import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/error_text.dart';
import '../../../core/feature_flags.dart';
import '../../../core/lang.dart';
import '../../../data/models/store_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/return_service.dart';
import '../../../theme/qoima_design.dart';

/// Дүкен иесі: «Қайтару ережесі» (0073).
/// • Superadmin «қайтарылмайтын тауар» белгісіне рұқсат бергенін көрсетеді;
/// • дүкеннің жалпы қайтару ескертпесін (≤500) модерациясыз өзгертеді
///   (set_store_return_note RPC);
/// • тауарға белгіні қалай қою керегін түсіндіреді.
class ReturnPolicySettingsScreen extends StatefulWidget {
  const ReturnPolicySettingsScreen({super.key});

  @override
  State<ReturnPolicySettingsScreen> createState() =>
      _ReturnPolicySettingsScreenState();
}

class _ReturnPolicySettingsScreenState
    extends State<ReturnPolicySettingsScreen> {
  static const _maxNote = 500;
  final _noteCtrl = TextEditingController();
  StoreModel? _store;
  bool _loading = true;
  Object? _error;
  bool _saving = false;
  String _savedNote = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await FirestoreService().getStore();
      if (!mounted) return;
      setState(() {
        _store = s;
        _savedNote = s?.returnPolicyNote ?? '';
        _noteCtrl.text = _savedNote;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  bool get _dirty => _noteCtrl.text.trim() != _savedNote;

  Future<void> _save() async {
    if (_saving) return;
    final note = _noteCtrl.text.trim();
    setState(() => _saving = true);
    try {
      await ReturnService().setStoreReturnNote(note);
      if (!mounted) return;
      HapticFeedback.selectionClick();
      setState(() => _savedNote = note);
      _snack(tr('Правило сохранено', 'Ереже сақталды'), cGreen);
    } catch (e) {
      _snack(policyErrorText(e), cRed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Правила возврата', 'Қайтару ережесі'),
          subtitle: tr('Условия возврата вашего магазина',
              'Дүкеніңіздің қайтару шарттары'),
          showBack: true,
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: cGreen, strokeWidth: 2))
              : _error != null || _store == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(
                              _error != null
                                  ? friendlyError(_error)
                                  : tr('Магазин не найден', 'Дүкен табылмады'),
                              textAlign: TextAlign.center,
                              style:
                                  manrope(14, FontWeight.w600, color: cInk3)),
                          const SizedBox(height: 12),
                          QSoftButton(
                              label: tr('Повторить', 'Қайталау'),
                              onPressed: _load),
                        ]),
                      ),
                    )
                  : ListenableBuilder(
                      listenable: FeatureFlags.instance,
                      builder: (_, __) => _body(FeatureFlags.instance
                          .isOn(FeatureFlags.nonReturnable)),
                    ),
        ),
      ]),
    );
  }

  Widget _body(bool featureOn) {
    final allowed = _store!.allowNonReturnable;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        if (!featureOn) ...[
          QCard(
            color: cAmberTint,
            padding: const EdgeInsets.all(14),
            child: Text(
                tr('Функция временно отключена платформой.',
                    'Функция платформа тарапынан уақытша өшірулі.'),
                style: manrope(13, FontWeight.w700, color: cAmberInk)),
          ),
          const SizedBox(height: 12),
        ],
        // Рұқсат күйі (тек superadmin өзгертеді).
        QCard(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            QIconTile(
              icon: Icon(
                  allowed ? Icons.verified_rounded : Icons.lock_outline_rounded,
                  color: allowed ? cGreenDeep : cInk3,
                  size: 22),
              tone: allowed ? 'green' : 'amber',
              size: 42,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        allowed
                            ? tr('Товары без возврата разрешены',
                                'Қайтарылмайтын тауарға рұқсат бар')
                            : tr('Товары без возврата не разрешены',
                                'Қайтарылмайтын тауарға рұқсат жоқ'),
                        style: manrope(14.5, FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                        allowed
                            ? tr(
                                'Вы можете отмечать отдельные товары как «не подлежит возврату».',
                                'Жекелеген тауарларды «қайтарылмайды» деп белгілей аласыз.')
                            : tr(
                                'Все ваши товары можно вернуть. Разрешение выдаёт модератор платформы — обратитесь в поддержку.',
                                'Барлық тауарыңыз қайтарылады. Рұқсатты платформа модераторы береді — қолдау қызметіне жазыңыз.'),
                        style: manrope(12.5, FontWeight.w500, color: cInk2)),
                  ]),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        QSecLabel(tr('Общее правило магазина', 'Дүкеннің жалпы ережесі')),
        QCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                tr('Покупатели увидят этот текст на карточке товара и в форме возврата.',
                    'Сатып алушылар бұл мәтінді тауар карточкасында және қайтару формасында көреді.'),
                style: manrope(12.5, FontWeight.w500, color: cInk3)),
            const SizedBox(height: 10),
            TextField(
              controller: _noteCtrl,
              enabled: featureOn && !_saving,
              maxLines: 4,
              minLines: 3,
              maxLength: _maxNote,
              onChanged: (_) => setState(() {}),
              style: manrope(14, FontWeight.w500),
              decoration: InputDecoration(
                hintText: tr(
                    'Например: нижнее бельё и косметика возврату не подлежат',
                    'Мысалы: іш киім мен косметика қайтарылмайды'),
                hintStyle: manrope(13.5, FontWeight.w500, color: cInk3),
                filled: true,
                fillColor: cBg,
                contentPadding: const EdgeInsets.all(14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: cLine)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: cLine)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: cGreen, width: 1.5)),
              ),
            ),
            const SizedBox(height: 6),
            QPrimaryButton(
              label: tr('Сохранить', 'Сақтау'),
              isLoading: _saving,
              onPressed: featureOn && _dirty && !_saving ? _save : null,
              height: 48,
            ),
          ]),
        ),
        const SizedBox(height: 16),
        QSecLabel(tr('Как отметить товар', 'Тауарды қалай белгілеу')),
        QCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Step(
                n: 1,
                text: tr(
                    'Откройте «Товары» и создайте или отредактируйте товар.',
                    '«Тауарлар» бөлімін ашып, тауар қосыңыз немесе өзгертіңіз.')),
            _Step(
                n: 2,
                text: allowed
                    ? tr(
                        'Включите переключатель «Не подлежит возврату» и при желании напишите причину (до 300 символов).',
                        '«Қайтарылмайды» ауыстырғышын қосып, қаласаңыз себебін жазыңыз (300 таңбаға дейін).')
                    : tr(
                        'Переключатель «Не подлежит возврату» появится после разрешения модератора.',
                        '«Қайтарылмайды» ауыстырғышы модератор рұқсат бергеннен кейін шығады.')),
            _Step(
                n: 3,
                text: tr(
                    'Покупатель увидит предупреждение и должен согласиться перед оформлением заказа. Условие фиксируется в заказе в момент покупки.',
                    'Сатып алушы ескертуді көреді және тапсырыс алдында келісуі керек. Шарт сатып алу сәтінде тапсырысқа жазылады.')),
            const SizedBox(height: 4),
            Text(
                tr('Если разрешение будет отозвано, отметки со всех ваших товаров снимаются.',
                    'Рұқсат қайтарылып алынса, барлық тауарыңыздан белгі алынады.'),
                style: manrope(11.5, FontWeight.w500, color: cInk3)),
          ]),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String text;
  const _Step({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration:
              const BoxDecoration(color: cGreenTint, shape: BoxShape.circle),
          child: Text('$n',
              style: manrope(11.5, FontWeight.w800, color: cGreenDeep)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: manrope(13, FontWeight.w500, color: cInk2)),
        ),
      ]),
    );
  }
}
