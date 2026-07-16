import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/lang.dart';
import '../../data/models/product_model.dart';
import '../../data/models/review_model.dart';
import '../../data/models/store_model.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';
import 'report_sheet.dart';

/// Жұлдызды рейтинг көрсеткіші (толық/жарты/бос жұлдыздар).
class RatingStars extends StatelessWidget {
  final double rating;
  final double size;
  const RatingStars({super.key, required this.rating, this.size = 15});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final IconData icon;
        if (rating >= i + 0.75) {
          icon = Icons.star_rounded;
        } else if (rating >= i + 0.25) {
          icon = Icons.star_half_rounded;
        } else {
          icon = Icons.star_outline_rounded;
        }
        return Icon(icon, size: size, color: const Color(0xFFF6A609));
      }),
    );
  }
}

/// Тауар пікірлері секциясы (детальдің ішінде).
///
/// Оқу — барлығына (guest те). Жазу — ТЕК осы тауарды сатып алған клиентке
/// (completed тапсырыс; RLS деңгейінде де қорғалған). Әр пікірге кез келген
/// басқа қолданушы шағымдана алады (Guideline 1.2).
class ReviewsSection extends StatefulWidget {
  final ProductModel product;
  final StoreModel store;
  const ReviewsSection(
      {super.key, required this.product, required this.store});

  @override
  State<ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends State<ReviewsSection> {
  final _service = ClientService();
  List<ReviewModel> _reviews = [];
  bool _loading = true;
  bool _canReview = false;
  bool _expanded = false;

  static const int _collapsedCount = 3;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = context.read<AppUser>();
      final results = await Future.wait([
        _service.getProductReviews(widget.product.id),
        // Тек клиент рөлі сатып ала алады — басқаларға RPC шақырмаймыз.
        user.isClient
            ? _service.canReviewProduct(widget.product.id)
            : Future.value(false),
      ]);
      if (!mounted) return;
      setState(() {
        _reviews = results[0] as List<ReviewModel>;
        _canReview = results[1] as bool;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _myUid => context.read<AppUser>().uid;

  ReviewModel? get _myReview {
    final uid = _myUid;
    if (uid.isEmpty) return null;
    for (final r in _reviews) {
      if (r.clientUid == uid) return r;
    }
    return null;
  }

  double get _avg => _reviews.isEmpty
      ? 0
      : _reviews.fold<int>(0, (s, r) => s + r.rating) / _reviews.length;

  Future<void> _openWriteSheet() async {
    final user = context.read<AppUser>();
    final existing = _myReview;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WriteReviewSheet(
        product: widget.product,
        store: widget.store,
        clientName: user.name,
        existing: existing,
      ),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final shown =
        _expanded ? _reviews : _reviews.take(_collapsedCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: QSecLabel(tr('Отзывы', 'Пікірлер'))),
          if (_reviews.isNotEmpty) ...[
            const Icon(Icons.star_rounded,
                size: 16, color: Color(0xFFF6A609)),
            const SizedBox(width: 3),
            Text(
              '${_avg.toStringAsFixed(1)} · ${_reviews.length}',
              style: manrope(13.5, FontWeight.w800, color: cInk),
            ),
          ],
        ]),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
                child: CircularProgressIndicator(
                    color: cGreen, strokeWidth: 2)),
          )
        else ...[
          if (_reviews.isEmpty)
            QCard(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Icon(Icons.rate_review_outlined,
                    color: cInk3, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Пока нет отзывов', 'Әзірге пікір жоқ'),
                          style:
                              manrope(13.5, FontWeight.w700, color: cInk)),
                      const SizedBox(height: 2),
                      Text(
                        tr('Отзывы могут оставлять только покупатели этого товара',
                            'Пікірді тек осы тауарды сатып алғандар қалдыра алады'),
                        style: manrope(12, FontWeight.w500, color: cInk3),
                      ),
                    ],
                  ),
                ),
              ]),
            )
          else
            QCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(children: [
                for (int i = 0; i < shown.length; i++) ...[
                  _ReviewTile(
                    review: shown[i],
                    isMine: shown[i].clientUid == _myUid,
                    onEdit: _openWriteSheet,
                    onReport: () => showReportSheet(
                      context,
                      targetType: 'review',
                      targetId: shown[i].id,
                      targetName:
                          '${widget.product.name} — ${shown[i].clientName}',
                      adminUid: widget.store.adminUid,
                      storeName: widget.store.storeName,
                    ),
                  ),
                  if (i < shown.length - 1)
                    Container(height: 1, color: cLine),
                ],
              ]),
            ),
          if (_reviews.length > _collapsedCount)
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    _expanded
                        ? tr('Свернуть', 'Жасыру')
                        : tr('Показать все (${_reviews.length})',
                            'Барлығын көрсету (${_reviews.length})'),
                    style: manrope(13.5, FontWeight.w700, color: cGreenDeep),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: cGreenDeep,
                  ),
                ]),
              ),
            ),
          if (_canReview) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _openWriteSheet,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: cGreenTint,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cGreen, width: 1.2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                        _myReview == null
                            ? Icons.edit_outlined
                            : Icons.edit_rounded,
                        color: cGreenDeep,
                        size: 17),
                    const SizedBox(width: 8),
                    Text(
                      _myReview == null
                          ? tr('Оставить отзыв', 'Пікір қалдыру')
                          : tr('Изменить мой отзыв', 'Пікірімді өзгерту'),
                      style:
                          manrope(14, FontWeight.w700, color: cGreenDeep),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

// ── Бір пікір жолы ────────────────────────────────────────────────────────────
class _ReviewTile extends StatelessWidget {
  final ReviewModel review;
  final bool isMine;
  final VoidCallback onEdit;
  final VoidCallback onReport;
  const _ReviewTile({
    required this.review,
    required this.isMine,
    required this.onEdit,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final name = review.clientName.trim().isEmpty
        ? tr('Покупатель', 'Сатып алушы')
        : review.clientName.trim();
    final initial = name.characters.first.toUpperCase();
    final date = DateFormat('dd.MM.yyyy').format(review.createdAt.toLocal());

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
                color: cGreenTint, shape: BoxShape.circle),
            child: Center(
                child: Text(initial,
                    style:
                        manrope(14, FontWeight.w800, color: cGreenDeep))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(name,
                        style: manrope(13.5, FontWeight.w700, color: cInk),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: cGreenTint,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(tr('Покупка', 'Сатып алу'),
                        style: manrope(9.5, FontWeight.w800,
                            color: cGreenDeep)),
                  ),
                ]),
                const SizedBox(height: 2),
                Row(children: [
                  RatingStars(rating: review.rating.toDouble(), size: 13),
                  const SizedBox(width: 6),
                  Text(date,
                      style:
                          manrope(11.5, FontWeight.w500, color: cInk3)),
                ]),
              ],
            ),
          ),
          // Өз пікірі — өңдеу; басқанікі — шағымдану.
          if (isMine)
            GestureDetector(
              onTap: onEdit,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.edit_outlined, size: 17, color: cInk3),
              ),
            )
          else
            GestureDetector(
              onTap: onReport,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.flag_outlined, size: 17, color: cInk3),
              ),
            ),
        ]),
        if (review.comment.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(review.comment,
              style: manrope(13, FontWeight.w500, color: cInk2)
                  .copyWith(height: 1.45)),
        ],
        // ── Дүкен жауабы ──────────────────────────────────────────────
        if (review.hasReply) ...[
          const SizedBox(height: 8),
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
                Text(tr('Ответ магазина', 'Дүкен жауабы'),
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
      ]),
    );
  }
}

// ── Пікір жазу/өңдеу sheet-і ─────────────────────────────────────────────────
class _WriteReviewSheet extends StatefulWidget {
  final ProductModel product;
  final StoreModel store;
  final String clientName;
  final ReviewModel? existing;
  const _WriteReviewSheet({
    required this.product,
    required this.store,
    required this.clientName,
    this.existing,
  });

  @override
  State<_WriteReviewSheet> createState() => _WriteReviewSheetState();
}

class _WriteReviewSheetState extends State<_WriteReviewSheet> {
  final _service = ClientService();
  late int _rating = widget.existing?.rating ?? 0;
  late final _commentCtrl =
      TextEditingController(text: widget.existing?.comment ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_rating < 1 || _saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await _service.submitReview(
        productId: widget.product.id,
        adminUid: widget.store.adminUid,
        clientName: widget.clientName,
        rating: _rating,
        comment: _commentCtrl.text,
      );
      navigator.pop(true);
      messenger.showSnackBar(SnackBar(
        content: Text(tr('Спасибо за отзыв!', 'Пікіріңізге рахмет!')),
        backgroundColor: cGreen,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(
        content: Text(tr(
            'Не удалось сохранить отзыв. Отзыв доступен только покупателям.',
            'Пікір сақталмады. Пікір тек сатып алушыларға қолжетімді.')),
        backgroundColor: cRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _delete() async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await _service.deleteMyReview(widget.product.id);
      navigator.pop(true);
      messenger.showSnackBar(SnackBar(
        content: Text(tr('Отзыв удалён', 'Пікір өшірілді')),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {
      if (mounted) setState(() => _saving = false);
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
          Text(
            widget.existing == null
                ? tr('Ваш отзыв', 'Сіздің пікіріңіз')
                : tr('Изменить отзыв', 'Пікірді өзгерту'),
            style: manrope(17, FontWeight.w800, color: cInk),
          ),
          const SizedBox(height: 4),
          Text(widget.product.name,
              style: manrope(13, FontWeight.w500, color: cInk3),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 16),
          // Жұлдыз таңдау
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final filled = i < _rating;
              return GestureDetector(
                onTap: () => setState(() => _rating = i + 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 38,
                    color: filled ? const Color(0xFFF6A609) : cInk3,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _commentCtrl,
            maxLines: 4,
            maxLength: 1000,
            style: manrope(14, FontWeight.w500, color: cInk),
            cursorColor: cGreen,
            decoration: InputDecoration(
              hintText: tr('Поделитесь впечатлениями (необязательно)',
                  'Әсеріңізбен бөлісіңіз (міндетті емес)'),
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
                ? tr('Сохранение...', 'Сақталуда...')
                : tr('Сохранить отзыв', 'Пікірді сақтау'),
            onPressed: (_rating >= 1 && !_saving) ? _save : null,
            height: 52,
          ),
          if (widget.existing != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _saving ? null : _delete,
              child: Text(tr('Удалить отзыв', 'Пікірді өшіру'),
                  style: manrope(13.5, FontWeight.w700, color: cRed)),
            ),
          ],
        ]),
      ),
    );
  }
}
