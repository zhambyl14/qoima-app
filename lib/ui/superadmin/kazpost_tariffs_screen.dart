import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error_text.dart';
import '../../core/feature_flags.dart';
import '../../core/kz_cities.dart';
import '../../core/lang.dart';
import '../../data/services/kazpost_service.dart';
import '../../theme/qoima_design.dart';
import '../shared/h_scroll_chips.dart';

/// Модератор: Казпочта бағалары және функцияны қосу (0081).
///
/// Баға ережесі серверде (`kazpost_fee_for`):
///   кестеде жол бар → is_active болса сол баға, әйтпесе бағыт ЖАБЫҚ;
///   жол жоқ → әдепкі баға; ол да бос болса бағыт ЖАБЫҚ.
/// Экрандағы жол екі күймен (баға + қосқыш) осыған дәл түсіріледі, қараңыз:
/// [_RowEdit.toRoute].
class KazpostTariffsScreen extends StatefulWidget {
  const KazpostTariffsScreen({super.key});

  @override
  State<KazpostTariffsScreen> createState() => _KazpostTariffsScreenState();
}

/// Бір бағыттың экрандағы күйі және сервердегі нұсқасы (dirty тексерісі үшін).
class _RowEdit {
  final TextEditingController price;
  bool open;
  String _basePrice;
  bool _baseOpen;

  _RowEdit._(this.price, this.open, this._basePrice, this._baseOpen);

  factory _RowEdit.from(KazpostRoute? stored) {
    final text = stored == null ||
            // Әдепкі бағаны жабу үшін сақталған жол (баға 0, қосқыш өшік).
            (stored.price == 0 && !stored.isActive)
        ? ''
        : stored.price.toStringAsFixed(0);
    final isOpen = stored?.isActive ?? true;
    return _RowEdit._(TextEditingController(text: text), isOpen, text, isOpen);
  }

  /// Бос = баға жоқ. Жабық бағыттағы 0 да «баға жоқ» — сақтаған соң солай оқылады.
  String get normalized {
    final n = int.tryParse(price.text.trim());
    if (n == null || (n == 0 && !open)) return '';
    return '$n';
  }

  bool get dirty => normalized != _basePrice || open != _baseOpen;

  /// Ашық бағыттағы 0 — тегін почта, ал почтаға дүкен өз қалтасынан төлейді.
  /// Мұндайды кездейсоқ сақтатпаймыз: бағаны жою немесе бағытты жабу керек.
  bool get isFreeByMistake =>
      open && price.text.trim().isNotEmpty && normalized == '0';

  void rebase() {
    _basePrice = normalized;
    _baseOpen = open;
  }

  /// null = жолды өшіру (бағытқа әдепкі баға жүреді). Әдепкі баға болса да
  /// жабық тұруы үшін сақталған жол керек, сондықтан баға жоқ кезде 0 жазамыз.
  KazpostRoute? toRoute(String from, String to) {
    final n = normalized;
    if (n.isEmpty && open) return null;
    return KazpostRoute(
      fromCity: from,
      toCity: to,
      price: n.isEmpty ? 0 : double.parse(n),
      isActive: open,
    );
  }
}

class _KazpostTariffsScreenState extends State<KazpostTariffsScreen> {
  final _service = KazpostService();
  final _defaultCtrl = TextEditingController();

  bool _loading = true;
  Object? _error;

  /// Сервердегі шындық. Экрандағы өзгеріс сақталғанға дейін мұнда түспейді.
  Map<String, KazpostRoute> _routes = {};
  double? _defaultFee;
  bool _flagOn = false;
  bool _flagBusy = false;
  bool _defaultSaving = false;

  String? _city;
  Map<String, _RowEdit> _rows = {};
  bool _saving = false;

  static String _key(String from, String to) => '$from|$to';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _defaultCtrl.dispose();
    for (final r in _rows.values) {
      r.price.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Future.wait<Object?>([
        _service.getRoutes(),
        _service.getDefaultFee(),
        // app_settings-тен тікелей: FeatureFlags RPC құласа, қосқыш жалған OFF
        // көрсетпесін (платформа баптауларымен бірдей).
        Supabase.instance.client
            .from('app_settings')
            .select('value')
            .eq('key', 'feature_${FeatureFlags.kazpostDelivery}')
            .maybeSingle(),
      ]);
      final loadedRoutes = res[0] as List<KazpostRoute>;
      final loadedFee = res[1] as double?;
      final loadedFlag = res[2] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        _routes = {for (final r in loadedRoutes) _key(r.fromCity, r.toCity): r};
        _defaultFee = loadedFee;
        _defaultCtrl.text = _feeText(loadedFee);
        _flagOn = loadedFlag?['value']?.toString() == 'true';
        _openCity(_city ?? kzCities.first);
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

  static String _feeText(double? fee) =>
      fee == null ? '' : fee.toStringAsFixed(0);

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ));
  }

  bool get _rowsDirty => _rows.values.any((r) => r.dirty);
  bool get _defaultDirty => _defaultCtrl.text.trim() != _feeText(_defaultFee);

  /// Қосулы, бірақ ешбір бағаға жетпейді: клиент Казпочтаны ешқайда көрмейді.
  bool get _noPriceAnywhere =>
      _defaultFee == null && !_routes.values.any((r) => r.isActive);

  // ── Қала ───────────────────────────────────────────────────────────────────

  /// setState ішінен шақырылады.
  void _openCity(String city) {
    final old = _rows.values.map((r) => r.price).toList();
    _city = city;
    _rows = {
      for (final to in kzCities)
        if (to != city) to: _RowEdit.from(_routes[_key(city, to)]),
    };
    // Ескі TextField-тер осы кадрда әлі контроллерге жалғаулы.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in old) {
        c.dispose();
      }
    });
  }

  Future<void> _selectCity(String city) async {
    if (city == _city || _saving) return;
    if (_rowsDirty) {
      final leave = await _confirmDiscard(tr(
          'Цены из города ${trValue(_city!)} не сохранены.',
          '${trValue(_city!)} қаласынан шығатын бағалар сақталмады.'));
      if (!leave || !mounted) return;
    }
    setState(() => _openCity(city));
  }

  Future<bool> _confirmDiscard(String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title:
            Text(tr('Есть несохранённые изменения', 'Сақталмаған өзгеріс бар')),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Остаться', 'Қалу'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: cRed),
              child: Text(tr('Не сохранять', 'Сақтамау'))),
        ],
      ),
    );
    return ok == true;
  }

  // ── Жалауша ────────────────────────────────────────────────────────────────

  Future<void> _toggleFlag(bool on) async {
    HapticFeedback.selectionClick();
    final prev = _flagOn;
    setState(() {
      _flagOn = on;
      _flagBusy = true;
    });
    try {
      await FeatureFlags.instance.setFlag(FeatureFlags.kazpostDelivery, on);
      _snack(
          on
              ? tr('Доставка Казпочтой включена', 'Казпочтамен жеткізу қосылды')
              : tr('Доставка Казпочтой отключена',
                  'Казпочтамен жеткізу өшірілді'),
          on ? cGreen : cInk);
    } catch (e) {
      if (mounted) setState(() => _flagOn = prev);
      _snack(friendlyError(e), cRed);
    } finally {
      if (mounted) setState(() => _flagBusy = false);
    }
  }

  // ── Әдепкі баға ────────────────────────────────────────────────────────────

  Future<void> _saveDefault() async {
    final text = _defaultCtrl.text.trim();
    final fee = text.isEmpty ? null : double.parse(text);
    if (fee == 0) {
      _snack(_zeroPriceMessage(), cRed);
      return;
    }
    setState(() => _defaultSaving = true);
    try {
      await _service.setDefaultFee(fee);
      if (!mounted) return;
      setState(() {
        _defaultFee = fee;
        _defaultCtrl.text = _feeText(fee); // «0500» → «500»: dirty қалмасын
      });
      FocusScope.of(context).unfocus();
      _snack(tr('Цена по умолчанию сохранена', 'Әдепкі баға сақталды'), cGreen);
    } catch (e) {
      _snack(friendlyError(e), cRed);
    } finally {
      if (mounted) setState(() => _defaultSaving = false);
    }
  }

  // ── Бағыттар ───────────────────────────────────────────────────────────────

  String _zeroPriceMessage() => tr(
      'Цена 0 означает бесплатную почту за счёт магазина. Оставьте поле пустым или закройте направление.',
      '0 баға почта тегін, ақысын дүкен төлейді дегенді білдіреді. Өрісті бос қалдырыңыз немесе бағытты жабыңыз.');

  /// Бір қаланың өзгерген жолдарын сақтап, жергілікті күйді жаңартады.
  /// Ерекшелік лақтырады — хабарды шақырушы көрсетеді.
  Future<void> _writeForward(String city) async {
    final changed = _rows.entries.where((e) => e.value.dirty).toList();
    final routes = <KazpostRoute>[];
    final cleared = <String>[];
    for (final e in changed) {
      final route = e.value.toRoute(city, e.key);
      if (route == null) {
        cleared.add(e.key);
      } else {
        routes.add(route);
      }
    }
    await _service.saveRoutesFrom(city, routes, clearedToCities: cleared);
    for (final r in routes) {
      _routes[_key(city, r.toCity)] = r;
    }
    for (final to in cleared) {
      _routes.remove(_key(city, to));
    }
    for (final e in changed) {
      e.value.rebase();
    }
  }

  Future<void> _save() async {
    final city = _city;
    if (city == null || !_rowsDirty || _saving) return;
    if (_rows.values.any((r) => r.dirty && r.isFreeByMistake)) {
      _snack(_zeroPriceMessage(), cRed);
      return;
    }
    setState(() => _saving = true);
    try {
      await _writeForward(city);
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      _snack(tr('Цены сохранены', 'Бағалар сақталды'), cGreen);
    } catch (e) {
      _snack(friendlyError(e), cRed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _applyToAll() async {
    final value = await showDialog<int>(
      context: context,
      builder: (_) => const _PriceDialog(),
    );
    if (value == null || !mounted) return;
    setState(() {
      // Қосқышқа тимейміз: жабылған бағыт әдейі жабылған.
      for (final r in _rows.values) {
        r.price.text = '$value';
      }
    });
  }

  /// Кері бағыттар басқа қалаларға жатады (экранда жоқ), сондықтан «көшіру»
  /// бірден сақталады, экрандағы өзгерістер де бірге кетеді: тек кері жақ жазылып,
  /// тура жақ сақталмай қалса, екеуі айырылып кетер еді.
  Future<void> _copyToReverse() async {
    final city = _city;
    if (city == null || _saving) return;
    if (_rows.values.any((r) => r.isFreeByMistake)) {
      _snack(_zeroPriceMessage(), cRed);
      return;
    }
    final cityName = trValue(city);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Сделать обратные такими же?',
            'Кері бағыттарды да осындай ету керек пе?')),
        content: Text(tr(
            'Цены из города $cityName будут сохранены, и те же цены и статусы запишутся в обратные направления (в город $cityName из каждого города). Текущие обратные цены заменятся.',
            '$cityName қаласынан шығатын бағалар сақталады да, сол бағалар мен күйлер кері бағыттарға жазылады (әр қаладан $cityName қаласына). Қазіргі кері бағалар ауыстырылады.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Отмена', 'Бас тарту'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cGreen, foregroundColor: Colors.white),
              child: Text(tr('Да, записать', 'Иә, жазу'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await _writeForward(city);
      await Future.wait(_rows.entries.map((e) {
        final route = e.value.toRoute(e.key, city);
        return _service.saveRoutesFrom(
          e.key,
          route == null ? const [] : [route],
          clearedToCities: route == null ? [city] : const [],
        );
      }));
      _snack(
          tr('Обратные направления записаны', 'Кері бағыттар жазылды'), cGreen);
    } catch (e) {
      _snack(friendlyError(e), cRed);
    } finally {
      // Қала бойынша бөлек сұраныс: қате болса, бір бөлігі жазылып үлгерген
      // болуы мүмкін. Сондықтан қандай жағдайда да серверден қайта оқимыз.
      await _refreshRoutes();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refreshRoutes() async {
    try {
      final fresh = await _service.getRoutes();
      if (!mounted) return;
      setState(() =>
          _routes = {for (final r in fresh) _key(r.fromCity, r.toCity): r});
    } catch (_) {
      // Желі жоқ: қалалар чиптеріндегі сан ғана ескіреді, келесі ашқанда түзеледі.
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_rowsDirty && !_defaultDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final leave = await _confirmDiscard(tr(
            'Если выйти сейчас, изменения пропадут.',
            'Қазір шықсаңыз, өзгерістер жоғалады.'));
        if (leave && mounted) nav.pop();
      },
      child: Scaffold(
        backgroundColor: cBg,
        body: Column(children: [
          QGradientHeader(
            title: tr('Тарифы Казпочты', 'Казпочта тарифтері'),
            subtitle: tr('Цены задаёт модератор, по направлениям',
                'Бағаны модератор бағыт бойынша қояды'),
            showBack: true,
            compact: true,
          ),
          Expanded(child: _body()),
          if (!_loading && _error == null) _saveBar(),
        ]),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: cGreen, strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(friendlyError(_error),
                textAlign: TextAlign.center,
                style: manrope(13, FontWeight.w600, color: cInk3)),
            const SizedBox(height: 12),
            QSoftButton(label: tr('Повторить', 'Қайталау'), onPressed: _load),
          ]),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _flagCard(),
        const SizedBox(height: 14),
        _defaultCard(),
        const SizedBox(height: 22),
        _routesSection(),
      ],
    );
  }

  Widget _flagCard() {
    return QCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(tr('Доставка Казпочтой', 'Казпочтамен жеткізу'),
                style: manrope(14.5, FontWeight.w800, color: cInk)),
          ),
          Switch.adaptive(
            value: _flagOn,
            activeThumbColor: Colors.white,
            activeTrackColor: cGreen,
            onChanged: _flagBusy ? null : _toggleFlag,
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Text(
              tr('Покупатели из других городов увидят Казпочту в корзине.',
                  'Басқа қаладағы сатып алушылар Казпочтаны себетте көреді.'),
              style:
                  manrope(12.5, FontWeight.w500, color: cInk2, height: 1.35)),
        ),
        if (_flagOn && _noPriceAnywhere)
          Padding(
            padding: const EdgeInsets.only(top: 10, right: 6),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: cAmberTint,
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 15, color: cAmberInk),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                      tr('Цен пока нет: покупатели не увидят Казпочту, пока вы не зададите цену.',
                          'Баға әлі жоқ: баға қоймайынша сатып алушылар Казпочтаны көрмейді.'),
                      style: manrope(12, FontWeight.w600,
                          color: cAmberInk, height: 1.35)),
                ),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _defaultCard() {
    return QCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Цена по умолчанию', 'Әдепкі баға'),
            style: manrope(14.5, FontWeight.w800, color: cInk)),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Text(
              tr('Для направлений без своей цены. Пусто — такие направления закрыты.',
                  'Өз бағасы жоқ бағыттарға. Бос болса — ондай бағыттар жабық.'),
              style:
                  manrope(12.5, FontWeight.w500, color: cInk2, height: 1.35)),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: _priceField(
              controller: _defaultCtrl,
              hint: tr('Нет цены', 'Баға жоқ'),
              align: TextAlign.start,
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 44,
            child: _defaultSaving
                ? const Center(
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: cGreen)))
                : IconButton(
                    tooltip: tr('Сохранить', 'Сақтау'),
                    onPressed: _defaultDirty ? _saveDefault : null,
                    icon: const Icon(Icons.check_circle_rounded),
                    color: cGreen,
                  ),
          ),
        ]),
      ]),
    );
  }

  Widget _routesSection() {
    final city = _city;
    if (city == null) return const SizedBox.shrink();
    final cityName = trValue(city);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      QSecLabel(tr('Откуда', 'Қайдан')),
      HScrollChips(chips: [
        for (final c in kzCities)
          HChip(
            label: _chipLabel(c),
            selected: c == city,
            onTap: () => _selectCity(c),
          ),
      ]),
      const SizedBox(height: 10),
      Text(
          tr('Направления отдельные: Астана → Тараз и Тараз → Астана могут стоить по-разному. Здесь только цены из города $cityName.',
              'Бағыттар бөлек: Астана → Тараз бен Тараз → Астана әртүрлі болуы мүмкін. Мұнда тек $cityName қаласынан шығатын бағалар.'),
          style: manrope(12.5, FontWeight.w500, color: cInk2, height: 1.4)),
      const SizedBox(height: 12),
      QSoftButton(
        label: tr('Применить ко всем', 'Барлығына қолдану'),
        height: 42,
        tone: 'gray',
        icon: const Icon(Icons.format_list_numbered_rounded),
        onPressed: _saving ? null : _applyToAll,
      ),
      const SizedBox(height: 8),
      QSoftButton(
        label:
            tr('Сделать обратные такими же', 'Кері бағыттарды да осылай ету'),
        height: 42,
        tone: 'gray',
        icon: const Icon(Icons.swap_horiz_rounded),
        onPressed: _saving ? null : _copyToReverse,
      ),
      const SizedBox(height: 12),
      QCard(
        padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
        child: Column(children: [
          for (final (i, e) in _rows.entries.indexed) ...[
            if (i > 0) const Divider(height: 1, color: cLine),
            _routeRow(city, e.key, e.value),
          ],
        ]),
      ),
    ]);
  }

  /// Чипте қаланың сақталған бағыт саны: қай қала толтырылғаны бірден көрінеді.
  String _chipLabel(String city) {
    final n = _routes.values.where((r) => r.fromCity == city).length;
    return n == 0 ? trValue(city) : '${trValue(city)} · $n';
  }

  Widget _routeRow(String from, String to, _RowEdit row) {
    final hasPrice = row.price.text.trim().isNotEmpty;
    final defaultFee = _defaultFee;
    final ({String text, Color color}) state = !row.open
        ? (text: tr('Закрыто', 'Жабық'), color: cRed)
        : hasPrice
            ? (text: tr('Своя цена', 'Өз бағасы'), color: cGreenDeep)
            : defaultFee != null
                ? (text: tr('По умолчанию', 'Әдепкі'), color: cInk3)
                : (
                    text: tr('Закрыто: нет цены', 'Жабық: баға жоқ'),
                    color: cAmberInk
                  );
    final hint = !row.open || defaultFee == null
        ? tr('закрыто', 'жабық')
        : defaultFee.toStringAsFixed(0);

    return Padding(
      key: ValueKey(_key(from, to)),
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('→ ${trValue(to)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: manrope(13.5, FontWeight.w700, color: cInk)),
            Text(state.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: manrope(11, FontWeight.w700, color: state.color)),
          ]),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 88,
          child: _priceField(controller: row.price, hint: hint),
        ),
        Switch.adaptive(
          value: row.open,
          activeThumbColor: Colors.white,
          activeTrackColor: cGreen,
          onChanged: _saving ? null : (v) => setState(() => row.open = v),
        ),
      ]),
    );
  }

  Widget _priceField({
    required TextEditingController controller,
    required String hint,
    TextAlign align = TextAlign.center,
  }) {
    OutlineInputBorder line(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c));
    return TextField(
      controller: controller,
      enabled: !_saving,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: align,
      maxLength: 7,
      style: manrope(14, FontWeight.w700, color: cInk),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        isDense: true,
        counterText: '',
        hintText: hint,
        hintStyle: manrope(12.5, FontWeight.w500, color: cInk3),
        filled: true,
        fillColor: cBg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: line(cLine),
        enabledBorder: line(cLine),
        disabledBorder: line(cLine),
        focusedBorder: line(cGreen),
      ),
    );
  }

  Widget _saveBar() {
    final city = _city;
    if (city == null) return const SizedBox.shrink();
    return Container(
      decoration: const BoxDecoration(
        color: cSurface,
        border: Border(top: BorderSide(color: cLine)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: QPrimaryButton(
            label: tr('Сохранить цены из города ${trValue(city)}',
                '${trValue(city)} бағаларын сақтау'),
            height: 48,
            isLoading: _saving,
            onPressed: _rowsDirty ? _save : null,
          ),
        ),
      ),
    );
  }
}

/// «Барлығына қолдану» саны. Контроллерді диалог өзі ұстайды.
class _PriceDialog extends StatefulWidget {
  const _PriceDialog();

  @override
  State<_PriceDialog> createState() => _PriceDialogState();
}

class _PriceDialogState extends State<_PriceDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int get _value => int.tryParse(_ctrl.text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(tr('Применить ко всем', 'Барлығына қолдану')),
      content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                tr('Цена появится во всех строках. Закрытые направления останутся закрытыми.',
                    'Баға барлық жолға жазылады. Жабық бағыттар жабық күйінде қалады.'),
                style:
                    manrope(12.5, FontWeight.w500, color: cInk2, height: 1.35)),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 7,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: tr('Например, 2500', 'Мысалы, 2500'),
                suffixText: '₸',
                counterText: '',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Отмена', 'Бас тарту'))),
        ElevatedButton(
          onPressed: _value > 0 ? () => Navigator.pop(context, _value) : null,
          style: ElevatedButton.styleFrom(
              backgroundColor: cGreen, foregroundColor: Colors.white),
          child: Text(tr('Заполнить', 'Толтыру')),
        ),
      ],
    );
  }
}
