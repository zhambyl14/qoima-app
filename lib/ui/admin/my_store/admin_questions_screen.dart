import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/lang.dart';
import '../../../data/models/product_question_model.dart';
import '../../../data/repositories/admin_questions_repository.dart';
import '../../../theme/qoima_design.dart';

/// Дүкен иесі — тауар сұрақтары: көру, жауап беру/өзгерту/өшіру
/// (Wildberries үлгісіндегі «Вопросы и ответы»). AdminReviewsScreen-мен
/// бірдей құрылым.
class AdminQuestionsScreen extends StatefulWidget {
  /// Push deep-link арқылы ашылғанда: тек осы өнімнің сұрақтарын көрсетеміз.
  final String? productId;
  const AdminQuestionsScreen({super.key, this.productId});

  @override
  State<AdminQuestionsScreen> createState() => _AdminQuestionsScreenState();
}

class _AdminQuestionsScreenState extends State<AdminQuestionsScreen> {
  final _repo = AdminQuestionsRepository();
  late final Stream<List<ProductQuestionModel>> _questions =
      _repo.watchStoreQuestions();
  Map<String, ({String name, String image})> _products = {};
  int _tab = 0; // 0 Все · 1 Без ответа · 2 С ответом
  // 0073: сұрақ-жауап режимі (superadmin 'qa_public' баптауы).
  bool _qaPublic = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    fetchQaIsPublic().then((v) {
      if (mounted) setState(() => _qaPublic = v);
    });
  }

  Future<void> _loadProducts() async {
    try {
      final map = await _repo.productsBrief();
      if (mounted) setState(() => _products = map);
    } catch (_) {}
  }

  List<ProductQuestionModel> _filter(List<ProductQuestionModel> all) {
    final byProduct = widget.productId == null
        ? all
        : all.where((q) => q.productId == widget.productId).toList();
    switch (_tab) {
      case 1:
        return byProduct.where((q) => !q.hasAnswer).toList();
      case 2:
        return byProduct.where((q) => q.hasAnswer).toList();
      default:
        return byProduct;
    }
  }

  Future<void> _openAnswerSheet(ProductQuestionModel question) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AnswerSheet(
        question: question,
        productName: _products[question.productId]?.name ?? '',
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

  Future<void> _deleteQuestion(ProductQuestionModel question) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(tr('Удалить вопрос?', 'Сұрақты өшіру керек пе?'),
            style: manrope(16, FontWeight.w800, color: cInk)),
        content: Text(
            tr('Например, если это спам или не относится к товару.',
                'Мысалы, ол спам болса немесе тауарға қатысы болмаса.'),
            style: manrope(13.5, FontWeight.w500, color: cInk2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Отмена', 'Болдырмау'),
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Удалить', 'Өшіру'),
                  style: manrope(14, FontWeight.w700, color: cRed))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.deleteQuestion(question.id);
      messenger.showSnackBar(SnackBar(
        content: Text(tr('Вопрос удалён', 'Сұрақ өшірілді')),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: Text(tr('Не удалось удалить вопрос', 'Сұрақ өшірілмеді')),
        backgroundColor: cRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: StreamBuilder<List<ProductQuestionModel>>(
        stream: _questions,
        builder: (context, snap) {
          final all = snap.data ?? [];
          final unanswered = all.where((q) => !q.hasAnswer).length;
          final list = _filter(all);

          return Column(children: [
            QGradientHeader(
              title: tr('Вопросы покупателей', 'Сатып алушы сұрақтары'),
              subtitle: all.isEmpty
                  ? tr('Пока нет вопросов', 'Әзірге сұрақ жоқ')
                  : tr('$unanswered без ответа из ${all.length}',
                      '${all.length} ішінен $unanswered жауапсыз'),
              compact: true,
              showBack: widget.productId != null,
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
            // 0073: режим туралы ескерту — сұрақты кімдер көретіні.
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                        _qaPublic
                            ? Icons.public_rounded
                            : Icons.lock_outline_rounded,
                        size: 15,
                        color: cInk3),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          _qaPublic
                              ? tr('Вопросы и ответы видны всем покупателям.',
                                  'Сұрақ-жауаптарды барлық сатып алушы көреді.')
                              : tr('Режим: личные вопросы. Ваш ответ видит только тот, кто спросил.',
                                  'Режим: жеке сұрақ. Жауабыңызды тек сұраған адам көреді.'),
                          style: manrope(12, FontWeight.w600, color: cInk3)),
                    ),
                  ]),
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
                          itemBuilder: (_, i) => _AdminQuestionCard(
                            question: list[i],
                            product: _products[list[i].productId],
                            onAnswer: () => _openAnswerSheet(list[i]),
                            onDelete: () => _deleteQuestion(list[i]),
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
              child: const Icon(Icons.help_outline_rounded,
                  color: cGreen, size: 34),
            ),
            const SizedBox(height: 14),
            Text(tr('Вопросов нет', 'Сұрақ жоқ'),
                style: manrope(16, FontWeight.w700, color: cInk)),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                  tr('Покупатели могут задать вопрос о товаре на его странице',
                      'Сатып алушылар тауар бетінде сұрақ қоя алады'),
                  textAlign: TextAlign.center,
                  style: manrope(13, FontWeight.w500, color: cInk3)),
            ),
          ],
        ),
      );
}

// ── Сұрақ карточкасы (админ көрінісі) ────────────────────────────────────────
class _AdminQuestionCard extends StatelessWidget {
  final ProductQuestionModel question;
  final ({String name, String image})? product;
  final VoidCallback onAnswer;
  final VoidCallback onDelete;
  const _AdminQuestionCard(
      {required this.question,
      required this.product,
      required this.onAnswer,
      required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final date =
        DateFormat('dd.MM.yyyy').format(question.createdAt.toLocal());
    final clientName = question.clientName.trim().isEmpty
        ? tr('Покупатель', 'Сатып алушы')
        : question.clientName.trim();

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
                Text('$clientName · $date',
                    style: manrope(11.5, FontWeight.w500, color: cInk3)),
              ],
            ),
          ),
          if (!question.hasAnswer)
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
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onDelete,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.delete_outline_rounded, size: 18, color: cInk3),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Text(question.question,
            style: manrope(13, FontWeight.w500, color: cInk2)
                .copyWith(height: 1.45)),
        if (question.hasAnswer) ...[
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
              Text(question.answer,
                  style: manrope(12.5, FontWeight.w500, color: cInk2)
                      .copyWith(height: 1.4)),
            ]),
          ),
        ],
        const SizedBox(height: 10),
        GestureDetector(
          onTap: onAnswer,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: question.hasAnswer ? cBg : cGreenTint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: question.hasAnswer ? cLine : cGreen, width: 1.2),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(
                  question.hasAnswer
                      ? Icons.edit_outlined
                      : Icons.reply_rounded,
                  size: 16,
                  color: question.hasAnswer ? cInk2 : cGreenDeep),
              const SizedBox(width: 7),
              Text(
                  question.hasAnswer
                      ? tr('Изменить ответ', 'Жауапты өзгерту')
                      : tr('Ответить', 'Жауап беру'),
                  style: manrope(13, FontWeight.w700,
                      color: question.hasAnswer ? cInk2 : cGreenDeep)),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ── Жауап sheet-і ─────────────────────────────────────────────────────────────
class _AnswerSheet extends StatefulWidget {
  final ProductQuestionModel question;
  final String productName;
  final AdminQuestionsRepository repo;
  const _AnswerSheet(
      {required this.question, required this.productName, required this.repo});

  @override
  State<_AnswerSheet> createState() => _AnswerSheetState();
}

class _AnswerSheetState extends State<_AnswerSheet> {
  late final _ctrl = TextEditingController(text: widget.question.answer);
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
          .answer(widget.question.id, clear ? '' : _ctrl.text.trim());
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
          Text(tr('Ответ на вопрос', 'Сұраққа жауап'),
              style: manrope(17, FontWeight.w800, color: cInk)),
          if (widget.productName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(widget.productName,
                style: manrope(13, FontWeight.w500, color: cInk3),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 12),
          // Сұрақтың өзі (контекст)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(widget.question.question,
                style: manrope(12.5, FontWeight.w500, color: cInk2)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            maxLines: 4,
            maxLength: 500,
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
                        widget.question.answer.isEmpty))
                ? null
                : _save,
            height: 52,
          ),
          if (widget.question.hasAnswer) ...[
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
