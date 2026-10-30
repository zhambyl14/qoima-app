import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/error_text.dart';
import '../../../core/feature_flags.dart';
import '../../../core/lang.dart';
import '../../../data/models/return_policy.dart';
import '../../../data/models/store_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/return_service.dart';
import '../../../theme/qoima_design.dart';
import '../../client/return_notice_sheet.dart';

/// Дүкен иесі: «Қайтару ережесі» (0073, 0082).
/// • режим: шартпен қабылдаймын / қайтармаймын («қайтармаймын» тек модератор
///   рұқсатымен, сервер де бөгейді);
/// • мерзім, шарттар, еркін мәтін — бәрі set_store_return_policy RPC арқылы;
/// • клиент оны тауар қолға тигенде және қайтару формасында көреді;
/// • тауарға жеке белгіні қалай қою керегін түсіндіреді.
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

  String _mode = ReturnPolicy.modeAccept;
  int _days = 14;
  Set<String> _conditions = {};

  String _savedMode = ReturnPolicy.modeAccept;
  int _savedDays = 14;
  Set<String> _savedConditions = {};
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
        if (s != null) {
          _savedMode = s.returnPolicyMode;
          _savedDays = s.returnDays;
          _savedConditions = s.returnConditions
              .where(ReturnPolicy.conditionCodes.contains)
              .toSet();
          _savedNote = s.returnPolicyNote;
          _mode = _savedMode;
          _days = _savedDays;
          _conditions = {..._savedConditions};
          _noteCtrl.text = _savedNote;
        }
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

  /// Режим «Без возврата» қолжетімді ме (сервердің шартымен бірдей).
  bool get _canUseNone =>
      (_store?.allowNonReturnable ?? false) &&
      FeatureFlags.instance.isOn(FeatureFlags.nonReturnable);

  /// Рұқсат/жалауша кейін алынса, снапшот бәрібір 'accept' жазады. Экран да
  /// соны көрсетеді: иесі күшінде жоқ режимді күшінде деп ойламасын.
  String get _effectiveMode =>
      _mode == ReturnPolicy.modeNone && !_canUseNone
          ? ReturnPolicy.modeAccept
          : _mode;

  bool get _noReturns => _effectiveMode == ReturnPolicy.modeNone;

  List<String> get _orderedConditions => ReturnPolicy.conditionCodes
      .where(_conditions.contains)
      .toList(growable: false);

  // 'none' режимінде мерзім мен шарттарды сервер елемейді — оларды өзгерту
  // сақтауды қажет етпейді.
  bool get _dirty {
    if (_effectiveMode != _savedMode) return true;
    if (_noteCtrl.text.trim() != _savedNote.trim()) return true;
    if (_noReturns) return false;
    if (_days != _savedDays) return true;
    return _conditions.length != _savedConditions.length ||
        !_conditions.containsAll(_savedConditions);
  }

  Future<void> _save() async {
    if (_saving) return;
    final note = _noteCtrl.text.trim();
    final mode = _effectiveMode;
    final conditions = _orderedConditions;
    setState(() => _saving = true);
    try {
      await ReturnService().setStoreReturnPolicy(
        mode: mode,
        days: _days,
        conditions: conditions,
        note: note,
      );
      if (!mounted) return;
      HapticFeedback.selectionClick();
      setState(() {
        // Сервер 'none' кезінде мерзім мен шартты әдепкіге қайтарады.
        final none = mode == ReturnPolicy.modeNone;
        _mode = mode;
        _savedMode = mode;
        _savedDays = none ? 14 : _days;
        _savedConditions = none ? {} : conditions.toSet();
        _savedNote = note;
        _days = _savedDays;
        _conditions = {..._savedConditions};
      });
      _snack(tr('Условия сохранены', 'Шарттар сақталды'), cGreen);
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
                      builder: (_, __) => _body(),
                    ),
        ),
      ]),
    );
  }

  Widget _body() {
    // Сервер екі жалаушаның бірін талап етеді (set_store_return_policy).
    final flags = FeatureFlags.instance;
    final productFlag = flags.isOn(FeatureFlags.nonReturnable);
    final featureOn = flags.isOn(FeatureFlags.returnNotice) || productFlag;
    final editable = featureOn && !_saving;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        if (!featureOn && flags.isLoaded) ...[
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
        QSecLabel(tr('Как магазин работает с возвратом',
            'Дүкен қайтаруды қалай қабылдайды')),
        QCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _ModeTile(
              title: tr('Принимаю возврат на условиях',
                  'Қайтаруды шарттармен қабылдаймын'),
              selected: !_noReturns,
              onTap: editable
                  ? () => setState(() => _mode = ReturnPolicy.modeAccept)
                  : null,
            ),
            const SizedBox(height: 8),
            _ModeTile(
              title: tr('Без возврата', 'Қайтарусыз'),
              selected: _noReturns,
              onTap: editable && _canUseNone
                  ? () => setState(() => _mode = ReturnPolicy.modeNone)
                  : null,
              footnote: _canUseNone
                  ? null
                  : tr(
                      'Разрешение выдаёт модератор платформы — обратитесь в поддержку.',
                      'Рұқсатты платформа модераторы береді — қолдау қызметіне жазыңыз.'),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        if (!_noReturns) ...[
          QSecLabel(tr('Срок возврата', 'Қайтару мерзімі')),
          QCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                for (final d in ReturnPolicy.allowedDays) ...[
                  if (d != ReturnPolicy.allowedDays.first)
                    const SizedBox(width: 8),
                  Expanded(
                    child: _DayChip(
                      days: d,
                      selected: _days == d,
                      onTap: editable ? () => setState(() => _days = d) : null,
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 10),
              Text(
                  tr('14 дней — минимум по закону, поэтому срок можно только увеличить.',
                      '14 күн — заң бойынша ең аз мерзім, сондықтан оны тек ұзартуға болады.'),
                  style: manrope(12.5, FontWeight.w500, color: cInk3)),
            ]),
          ),
          const SizedBox(height: 16),
          QSecLabel(tr('Условия', 'Шарттар')),
          QCard(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Column(children: [
              for (final code in ReturnPolicy.conditionCodes)
                CheckboxListTile(
                  value: _conditions.contains(code),
                  onChanged: editable
                      ? (on) => setState(() => on == true
                          ? _conditions.add(code)
                          : _conditions.remove(code))
                      : null,
                  activeColor: cGreen,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(ReturnPolicy.conditionLabel(code),
                      style: manrope(13.5, FontWeight.w600)),
                ),
            ]),
          ),
          const SizedBox(height: 16),
        ],
        QSecLabel(tr('Примечание магазина', 'Дүкен ескертпесі')),
        QCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                tr('Покупатель увидит условия, когда заказ будет у него на руках, и в форме возврата.',
                    'Сатып алушы шарттарды тапсырыс қолына тигенде және қайтару формасында көреді.'),
                style: manrope(12.5, FontWeight.w500, color: cInk3)),
            const SizedBox(height: 10),
            TextField(
              controller: _noteCtrl,
              enabled: editable,
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
          ]),
        ),
        const SizedBox(height: 16),
        QSecLabel(tr('Так увидит покупатель', 'Сатып алушы осылай көреді')),
        QCard(
          child: ReturnPolicyBody(ReturnPolicy(
            mode: _effectiveMode,
            days: _days,
            conditions: _orderedConditions,
            note: _noteCtrl.text.trim(),
          )),
        ),
        const SizedBox(height: 16),
        QPrimaryButton(
          label: tr('Сохранить', 'Сақтау'),
          isLoading: _saving,
          onPressed: editable && _dirty ? _save : null,
          height: 48,
        ),
        // Тауарға жеке белгі тек осы жалауша қосулы болғанда бар.
        if (productFlag) ...[
          const SizedBox(height: 20),
          QSecLabel(tr('Как отметить товар', 'Тауарды қалай белгілеу')),
          _markProductCard(),
        ],
      ],
    );
  }

  Widget _markProductCard() {
    final allowed = _store!.allowNonReturnable;
    return QCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_noReturns) ...[
          Text(
              tr('Сейчас без возврата весь магазин, поэтому отдельные товары отмечать не нужно.',
                  'Қазір бүкіл дүкен қайтарусыз, сондықтан жекелеген тауарды белгілеудің қажеті жоқ.'),
              style: manrope(13, FontWeight.w600, color: cInk)),
          const SizedBox(height: 10),
        ] else
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
                tr('Можно принимать возврат в целом, но отметить отдельные товары как невозвратные.',
                    'Қайтаруды жалпы қабылдап, жекелеген тауарларды қайтарылмайтын деп белгілеуге болады.'),
                style: manrope(13, FontWeight.w500, color: cInk2)),
          ),
        _Step(
            n: 1,
            text: tr('Откройте «Товары» и создайте или отредактируйте товар.',
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
            tr('Если разрешение будет отозвано, отметки со всех ваших товаров снимаются, а магазин возвращается к приёму возвратов.',
                'Рұқсат қайтарылып алынса, барлық тауарыңыздан белгі алынады, ал дүкен қайтаруды қабылдау режиміне оралады.'),
            style: manrope(11.5, FontWeight.w500, color: cInk3)),
      ]),
    );
  }
}

class _ModeTile extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback? onTap;
  final String? footnote;
  const _ModeTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(
          selected
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_unchecked_rounded,
          color: selected && enabled ? cGreen : cInk3,
          size: 22,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: manrope(14.5, FontWeight.w700,
                    color: enabled || selected ? cInk : cInk3)),
            if (footnote != null) ...[
              const SizedBox(height: 3),
              Text(footnote!,
                  style: manrope(12.5, FontWeight.w500, color: cInk2)),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _DayChip extends StatelessWidget {
  final int days;
  final bool selected;
  final VoidCallback? onTap;
  const _DayChip(
      {required this.days, required this.selected, required this.onTap});

  // 21 день, бірақ 14 дней: мән ақ тізімнен келеді, тек соңғы цифр маңызды.
  String get _label {
    final word = days % 10 == 1 && days % 100 != 11 ? 'день' : 'дней';
    return tr('$days $word', '$days күн');
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? cGreenTint : cBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? cGreen : cLine, width: selected ? 1.5 : 1),
        ),
        child: Text(_label,
            style: manrope(13.5, FontWeight.w700,
                color: selected ? cGreenDeep : cInk2)),
      ),
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
