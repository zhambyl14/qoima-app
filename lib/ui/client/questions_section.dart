import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/lang.dart';
import '../../data/models/product_model.dart';
import '../../data/models/product_question_model.dart';
import '../../data/models/store_model.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';
import '../auth/login_screen.dart';
import 'report_sheet.dart';

/// Тауар бойынша «Вопросы и ответы» секциясы (Wildberries үлгісі, детальдің
/// ішінде). Оқу — барлығына (guest те). Сұрақ қою — кез келген
/// авторизацияланған клиентке (сатып алу міндетті емес — сатып алғанға
/// ДЕЙІН сұрау үшін). Жауап беруші — тек дүкен иесі/сатушысы.
class QuestionsSection extends StatefulWidget {
  final ProductModel product;
  final StoreModel store;
  const QuestionsSection(
      {super.key, required this.product, required this.store});

  @override
  State<QuestionsSection> createState() => _QuestionsSectionState();
}

class _QuestionsSectionState extends State<QuestionsSection> {
  final _service = ClientService();
  List<ProductQuestionModel> _questions = [];
  bool _loading = true;
  bool _expanded = false;

  static const int _collapsedCount = 2;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _service.getProductQuestions(widget.product.id);
      if (mounted) setState(() { _questions = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAskSheet({ProductQuestionModel? existing}) async {
    final user = context.read<AppUser>();
    if (user.uid.isEmpty) {
      final goLogin = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: cSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(tr('Нужен вход', 'Кіру қажет'),
              style: manrope(16, FontWeight.w800, color: cInk)),
          content: Text(
              tr('Чтобы задать вопрос, войдите в аккаунт.',
                  'Сұрақ қою үшін аккаунтқа кіріңіз.'),
              style: manrope(14, FontWeight.w500, color: cInk2)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Отмена', 'Болдырмау'),
                    style: manrope(14, FontWeight.w600, color: cInk2))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('Войти', 'Кіру'),
                    style: manrope(14, FontWeight.w700, color: cGreen))),
          ],
        ),
      );
      if (goLogin == true && context.mounted) {
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      }
      return;
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AskQuestionSheet(
        product: widget.product,
        store: widget.store,
        clientName: user.name,
        existing: existing,
      ),
    );
    if (saved == true && mounted) {
      _load();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(existing != null
            ? tr('Вопрос изменён', 'Сұрақ өзгертілді')
            : tr('Вопрос отправлен', 'Сұрақ жіберілді')),
        backgroundColor: cGreen,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _deleteMyQuestion(ProductQuestionModel q) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(tr('Удалить вопрос?', 'Сұрақты өшіру керек пе?'),
            style: manrope(16, FontWeight.w800, color: cInk)),
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
    if (ok != true) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.deleteMyQuestion(q.id);
      _load();
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
    final myUid = context.watch<AppUser>().uid;
    final shown =
        _expanded ? _questions : _questions.take(_collapsedCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        QSecLabel(tr('Вопросы и ответы', 'Сұрақ-жауап')),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
                child: CircularProgressIndicator(
                    color: cGreen, strokeWidth: 2)),
          )
        else ...[
          if (_questions.isEmpty)
            QCard(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Icon(Icons.help_outline_rounded,
                    color: cInk3, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                      tr('Вопросов пока нет — задайте первым',
                          'Сұрақ әзірге жоқ — бірінші болып сұраңыз'),
                      style: manrope(13, FontWeight.w600, color: cInk3)),
                ),
              ]),
            )
          else
            QCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(children: [
                for (int i = 0; i < shown.length; i++) ...[
                  _QuestionTile(
                    question: shown[i],
                    isMine: shown[i].clientUid == myUid,
                    onReport: () => showReportSheet(
                      context,
                      targetType: 'question',
                      targetId: shown[i].id,
                      targetName:
                          '${widget.product.name} — ${shown[i].clientName}',
                      adminUid: widget.store.adminUid,
                      storeName: widget.store.storeName,
                    ),
                    onEdit: () => _openAskSheet(existing: shown[i]),
                    onDelete: () => _deleteMyQuestion(shown[i]),
                  ),
                  if (i < shown.length - 1) Container(height: 1, color: cLine),
                ],
              ]),
            ),
          if (_questions.length > _collapsedCount)
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    _expanded
                        ? tr('Свернуть', 'Жасыру')
                        : tr('Показать все (${_questions.length})',
                            'Барлығын көрсету (${_questions.length})'),
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
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _openAskSheet,
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
                  const Icon(Icons.help_outline_rounded,
                      color: cGreenDeep, size: 17),
                  const SizedBox(width: 8),
                  Text(tr('Задать вопрос', 'Сұрақ қою'),
                      style: manrope(14, FontWeight.w700, color: cGreenDeep)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _QuestionTile extends StatelessWidget {
  final ProductQuestionModel question;
  final bool isMine;
  final VoidCallback onReport;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _QuestionTile({
    required this.question,
    required this.isMine,
    required this.onReport,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name = question.clientName.trim().isEmpty
        ? tr('Покупатель', 'Сатып алушы')
        : question.clientName.trim();
    final date = DateFormat('dd.MM.yyyy').format(question.createdAt.toLocal());
    final canEdit = isMine && !question.hasAnswer;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.person_outline_rounded, size: 16, color: cInk3),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$name · $date',
                    style: manrope(11.5, FontWeight.w600, color: cInk3)),
                const SizedBox(height: 3),
                Text(question.question,
                    style: manrope(13.5, FontWeight.w600, color: cInk)
                        .copyWith(height: 1.4)),
              ],
            ),
          ),
          if (canEdit) ...[
            GestureDetector(
              onTap: onEdit,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.edit_outlined, size: 17, color: cInk3),
              ),
            ),
            GestureDetector(
              onTap: onDelete,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.delete_outline_rounded, size: 17, color: cInk3),
              ),
            ),
          ] else if (!isMine)
            GestureDetector(
              onTap: onReport,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.flag_outlined, size: 17, color: cInk3),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        if (question.hasAnswer)
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
              Text(question.answer,
                  style: manrope(12.5, FontWeight.w500, color: cInk2)
                      .copyWith(height: 1.4)),
            ]),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: cAmber.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(tr('Ожидает ответа', 'Жауап күтілуде'),
                style: manrope(10, FontWeight.w800, color: cAmber)),
          ),
      ]),
    );
  }
}

// ── Сұрақ қою/өзгерту sheet-і ────────────────────────────────────────────────
class _AskQuestionSheet extends StatefulWidget {
  final ProductModel product;
  final StoreModel store;
  final String clientName;
  final ProductQuestionModel? existing;
  const _AskQuestionSheet({
    required this.product,
    required this.store,
    required this.clientName,
    this.existing,
  });

  @override
  State<_AskQuestionSheet> createState() => _AskQuestionSheetState();
}

class _AskQuestionSheetState extends State<_AskQuestionSheet> {
  final _service = ClientService();
  late final _ctrl =
      TextEditingController(text: widget.existing?.question ?? '');
  bool _saving = false;
  // SnackBar модалдық sheet-тің АРТЫНДА (негізгі беттің Scaffold-ында)
  // көрсетіледі де, sheet ашық тұрғанда көрінбей қалады — сол себепті
  // қатені осында, sheet ІШІНДЕ, мәтін ретінде көрсетеміз.
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_ctrl.text.trim().isEmpty || _saving) return;
    setState(() { _saving = true; _error = null; });
    final navigator = Navigator.of(context);
    try {
      final existing = widget.existing;
      if (existing != null) {
        await _service.updateMyQuestion(existing.id, _ctrl.text);
      } else {
        await _service.askProductQuestion(
          productId: widget.product.id,
          adminUid: widget.store.adminUid,
          clientName: widget.clientName,
          question: _ctrl.text,
        );
      }
      navigator.pop(true);
    } catch (e) {
      final msg = e.toString();
      final String text;
      if (msg.contains('question_rate_limit')) {
        text = tr('Слишком много вопросов за 24 часа. Попробуйте позже.',
            '24 сағатта тым көп сұрақ жаздыңыз. Кейінірек көріңіз.');
      } else if (msg.contains('duplicate key') ||
          msg.contains('23505') ||
          msg.contains('pending_uidx')) {
        text = tr(
            'У вас уже есть вопрос этому продавцу без ответа. Дождитесь ответа, затем спрашивайте снова.',
            'Сізде осы сатушыға жауап күтіп тұрған сұрағыңыз бар. Жауапты күтіп, содан кейін қайта сұраңыз.');
      } else {
        text = tr('Не удалось отправить вопрос', 'Сұрақ жіберілмеді');
      }
      if (mounted) setState(() { _saving = false; _error = text; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isEdit = widget.existing != null;
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
              isEdit
                  ? tr('Изменить вопрос', 'Сұрақты өзгерту')
                  : tr('Задать вопрос', 'Сұрақ қою'),
              style: manrope(17, FontWeight.w800, color: cInk)),
          const SizedBox(height: 4),
          Text(widget.product.name,
              style: manrope(13, FontWeight.w500, color: cInk3),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            maxLines: 4,
            maxLength: 500,
            autofocus: true,
            onChanged: (_) => setState(() => _error = null),
            style: manrope(14, FontWeight.w500, color: cInk),
            cursorColor: cGreen,
            decoration: InputDecoration(
              hintText: tr('Например: есть ли размер 42?',
                  'Мысалы: 42 өлшемі бар ма?'),
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
          if (_error != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.error_outline_rounded, size: 15, color: cRed),
              const SizedBox(width: 6),
              Expanded(
                child: Text(_error!,
                    style: manrope(12.5, FontWeight.w600, color: cRed)),
              ),
            ]),
          ],
          const SizedBox(height: 12),
          QPrimaryButton(
            label: _saving
                ? tr('Отправка...', 'Жіберілуде...')
                : isEdit
                    ? tr('Сохранить', 'Сақтау')
                    : tr('Отправить вопрос', 'Сұрақты жіберу'),
            onPressed: (_ctrl.text.trim().isNotEmpty && !_saving) ? _save : null,
            height: 52,
          ),
        ]),
      ),
    );
  }
}
