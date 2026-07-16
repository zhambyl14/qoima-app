import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/lang.dart';
import '../../../data/models/review_model.dart';
import '../../../data/repositories/admin_reviews_repository.dart';
import '../../../theme/qoima_design.dart';
import '../../client/reviews_section.dart' show RatingStars;

/// Дүкен иесі — тауар пікірлері: көру, жауап беру/өзгерту/өшіру.
///
/// Пікірді өшіру/өзгерту иесіне БЕРІЛМЕЙДІ (рейтинг манипуляциясы —
/// App Store 5.6.3) — тек жауап. Заңсыз пікірге шағымды superadmin қарайды.
class AdminReviewsScreen extends StatefulWidget {
  const AdminReviewsScreen({super.key});

  @override
  State<AdminReviewsScreen> createState() => _AdminReviewsScreenState();
}

class _AdminReviewsScreenState extends State<AdminReviewsScreen> {
  final _repo = AdminReviewsRepository();
  late final Stream<List<ReviewModel>> _reviews = _repo.watchStoreReviews();
  Map<String, ({String name, String image})> _products = {};
  int _tab = 0; // 0 Все · 1 Без ответа · 2 С ответом

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final map = await _repo.productsBrief();
      if (mounted) setState(() => _products = map);
    } catch (_) {}
  }

  List<ReviewModel> _filter(List<ReviewModel> all) {
    switch (_tab) {
      case 1:
        return all.where((r) => !r.hasReply).toList();
      case 2:
        return all.where((r) => r.hasReply).toList();
      default:
        return all;
    }
  }

  Future<void> _openReplySheet(ReviewModel review) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReplySheet(
        review: review,
        productName: _products[review.productId]?.name ?? '',
        repo: _repo,
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Ответ сохранён', 'Жауап сақталды')),
        backgroundColor: cGreen,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: StreamBuilder<List<ReviewModel>>(
        stream: _reviews,
        builder: (context, snap) {
          final all = snap.data ?? [];
          final unanswered = all.where((r) => !r.hasReply).length;
          final avg = all.isEmpty
              ? 0.0
              : all.fold<int>(0, (s, r) => s + r.rating) / all.length;
          final list = _filter(all);

          return Column(children: [
            QGradientHeader(
              title: tr('Отзывы покупателей', 'Сатып алушы пікірлері'),
              subtitle: all.isEmpty
                  ? tr('Пока нет отзывов', 'Әзірге пікір жоқ')
                  : tr('★ ${avg.toStringAsFixed(1)} · ${all.length} отзывов',
                      '★ ${avg.toStringAsFixed(1)} · ${all.length} пікір'),
              compact: true,
              bottom: [
                const SizedBox(height: 14),
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _TabChip(
                          label: tr('Все (${all.length})',
                              'Барлығы (${all.length})'),
                          active: _tab == 0,
                          onTap: () => setState(() => _tab = 0)),
                      _TabChip(
                          label: tr('Без ответа ($unanswered)',
                              'Жауапсыз ($unanswered)'),
                          active: _tab == 1,
                          onTap: () => setState(() => _tab = 1)),
                      _TabChip(
                          label: tr('С ответом', 'Жауап берілген'),
                          active: _tab == 2,
                          onTap: () => setState(() => _tab = 2)),
                    ],
                  ),
                ),
              ],
            ),
            Expanded(
              child: snap.connectionState == ConnectionState.waiting
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: cGreen, strokeWidth: 2))
                  : list.isEmpty
                      ? _empty()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                          itemCount: list.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => _AdminReviewCard(
                            review: list[i],
                            product: _products[list[i].productId],
                            onReply: () => _openReplySheet(list[i]),
                          ),
                        ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                  color: cGreenTint, shape: BoxShape.circle),
              child: const Icon(Icons.rate_review_outlined,
                  color: cGreen, size: 34),
            ),
            const SizedBox(height: 14),
            Text(tr('Отзывов нет', 'Пікір жоқ'),
                style: manrope(16, FontWeight.w700, color: cInk)),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                  tr('Отзывы оставляют покупатели после получения заказа',
                      'Пікірді сатып алушылар тапсырысты алғаннан кейін қалдырады'),
                  textAlign: TextAlign.center,
                  style: manrope(13, FontWeight.w500, color: cInk3)),
            ),
          ],
        ),
      );
}

// ── Пікір карточкасы (админ көрінісі) ────────────────────────────────────────
class _AdminReviewCard extends StatelessWidget {
  final ReviewModel review;
  final ({String name, String image})? product;
  final VoidCallback onReply;
  const _AdminReviewCard(
      {required this.review, required this.product, required this.onReply});

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('dd.MM.yyyy').format(review.createdAt.toLocal());
    final clientName = review.clientName.trim().isEmpty
        ? tr('Покупатель', 'Сатып алушы')
        : review.clientName.trim();

    return QCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Тауар
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cGreenTint,
              borderRadius: BorderRadius.circular(11),
            ),
            clipBehavior: Clip.antiAlias,
            child: (product?.image.isNotEmpty ?? false)
                ? Image.network(product!.image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.inventory_2_outlined,
                        color: cGreenDeep,
                        size: 20))
                : const Icon(Icons.inventory_2_outlined,
                    color: cGreenDeep, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    product?.name.isNotEmpty ?? false
                        ? product!.name
                        : tr('Товар удалён', 'Тауар өшірілген'),
                    style: manrope(13.5, FontWeight.w800, color: cInk),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(children: [
                  RatingStars(rating: review.rating.toDouble(), size: 13),
                  const SizedBox(width: 6),
                  Text('$clientName · $date',
                      style: manrope(11.5, FontWeight.w500, color: cInk3)),
                ]),
              ],
            ),
          ),
          if (!review.hasReply)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: cAmber.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(tr('Без ответа', 'Жауапсыз'),
                  style: manrope(10, FontWeight.w800, color: cAmber)),
            ),
        ]),
        if (review.comment.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(review.comment,
              style: manrope(13, FontWeight.w500, color: cInk2)
                  .copyWith(height: 1.45)),
        ],
        // Бар жауап
        if (review.hasReply) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cGreenTint.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cGreen.withValues(alpha: 0.25)),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.storefront_rounded,
                    size: 14, color: cGreenDeep),
                const SizedBox(width: 5),
                Text(tr('Ваш ответ', 'Сіздің жауабыңыз'),
                    style:
                        manrope(11.5, FontWeight.w800, color: cGreenDeep)),
              ]),
              const SizedBox(height: 4),
              Text(review.sellerReply,
                  style: manrope(12.5, FontWeight.w500, color: cInk2)
                      .copyWith(height: 1.4)),
            ]),
          ),
        ],
        const SizedBox(height: 10),
        // Жауап беру / өзгерту
        GestureDetector(
          onTap: onReply,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: review.hasReply ? cBg : cGreenTint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: review.hasReply ? cLine : cGreen, width: 1.2),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(
                  review.hasReply
                      ? Icons.edit_outlined
                      : Icons.reply_rounded,
                  size: 16,
                  color: review.hasReply ? cInk2 : cGreenDeep),
              const SizedBox(width: 7),
              Text(
                  review.hasReply
                      ? tr('Изменить ответ', 'Жауапты өзгерту')
                      : tr('Ответить', 'Жауап беру'),
                  style: manrope(13, FontWeight.w700,
                      color: review.hasReply ? cInk2 : cGreenDeep)),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ── Жауап sheet-і ─────────────────────────────────────────────────────────────
class _ReplySheet extends StatefulWidget {
  final ReviewModel review;
  final String productName;
  final AdminReviewsRepository repo;
  const _ReplySheet(
      {required this.review, required this.productName, required this.repo});

  @override
  State<_ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends State<_ReplySheet> {
  late final _ctrl = TextEditingController(text: widget.review.sellerReply);
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save({bool clear = false}) async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await widget.repo
          .reply(widget.review.id, clear ? '' : _ctrl.text.trim());
      navigator.pop(true);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(
        content:
            Text(tr('Не удалось сохранить ответ', 'Жауап сақталмады')),
        backgroundColor: cRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomInset),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
                color: cLine, borderRadius: BorderRadius.circular(2)),
          ),
          Text(tr('Ответ на отзыв', 'Пікірге жауап'),
              style: manrope(17, FontWeight.w800, color: cInk)),
          if (widget.productName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(widget.productName,
                style: manrope(13, FontWeight.w500, color: cInk3),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 12),
          // Пікірдің өзі (контекст)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              RatingStars(rating: widget.review.rating.toDouble(), size: 14),
              if (widget.review.comment.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(widget.review.comment,
                    style: manrope(12.5, FontWeight.w500, color: cInk2)),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            maxLines: 4,
            maxLength: 1000,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            style: manrope(14, FontWeight.w500, color: cInk),
            cursorColor: cGreen,
            decoration: InputDecoration(
              hintText: tr('Напишите ответ покупателю…',
                  'Сатып алушыға жауап жазыңыз…'),
              hintStyle: manrope(13.5, FontWeight.w500, color: cInk3),
              filled: true,
              fillColor: cBg,
              counterStyle: manrope(11, FontWeight.w500, color: cInk3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: const BorderSide(color: cLine),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: const BorderSide(color: cLine),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: const BorderSide(color: cGreen, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          QPrimaryButton(
            label: _saving
                ? tr('Сохранение…', 'Сақталуда…')
                : tr('Сохранить ответ', 'Жауапты сақтау'),
            onPressed: (_saving ||
                    (_ctrl.text.trim().isEmpty &&
                        widget.review.sellerReply.isEmpty))
                ? null
                : _save,
            height: 52,
          ),
          if (widget.review.hasReply) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _saving ? null : () => _save(clear: true),
              child: Text(tr('Удалить ответ', 'Жауапты өшіру'),
                  style: manrope(13.5, FontWeight.w700, color: cRed)),
            ),
          ],
        ]),
      ),
    );
  }
}

// ── Tab chip ───────────────────────────────────────────────────────────────────
class _TabChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabChip(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? Colors.white
              : Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(label,
              style: manrope(12.5, FontWeight.w700,
                  color: active ? cGreenDeep : Colors.white)),
        ),
      ),
    );
  }
}
