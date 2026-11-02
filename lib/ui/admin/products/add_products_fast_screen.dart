import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/color_naming.dart';
import '../../../core/lang.dart';
import '../../../core/warehouse_context.dart';
import '../../../data/models/category_attributes.dart';
import '../../../data/models/models.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';
import '../../shared/color_picker_sheet.dart';
import '../../shared/h_scroll_chips.dart';
import '../../shared/mandatory_warehouse_picker.dart';
import '../../shared/prompt_text_dialog.dart';
import 'category_attributes_editor.dart';
import 'restock_screen.dart';

/// Жылдам товар қосу — бір экранда бірнеше тауарды жол-жолмен қосу.
/// Жоғарыда БІР рет ортақ: категория + кому + жеткізілім күні + әдепкі баға.
/// Әр «+» — жаңа жол. Әр жолда: атауы, бренд, тип, түс(тер) + айырмашылық белгісі,
/// баға, размер·сан (қолмен теру + пресеттер). Фото жоқ (кейін карточкадан).
class AddProductsFastScreen extends StatefulWidget {
  const AddProductsFastScreen({super.key});

  @override
  State<AddProductsFastScreen> createState() => _AddProductsFastScreenState();
}

/// Жолдағы бір түс-нұсқа. Түс — қарапайым таңдау/шешу: бір түс бір-ақ рет
/// (дубль жоқ). Екі ақ тауар (табаны әртүрлі) = екі бөлек жол/тауар, атауы
/// әртүрлі. Ескі `variant_note` деректері өзгермейді, тек енді енгізілмейді.
class _ColorPick {
  final String color;
  final String hex; // ерекше түстің HEX коды ('' = стандарт палитра)
  // Жылдам код (0062) — сатушының өз саны, офлайн іздеуге. Әр нұсқа жеке
  // тауар болғандықтан коды да жеке.
  final quickCtrl = TextEditingController();
  _ColorPick(this.color, {this.hex = ''});
  void dispose() {
    quickCtrl.dispose();
  }
}

/// Бір товар-жолдың күйі.
class _FastRow {
  final nameCtrl = TextEditingController();
  final brandCtrl = TextEditingController();
  final purchaseCtrl = TextEditingController();
  final sellingCtrl = TextEditingController();
  String? type; // вид
  final List<_ColorPick> colors = [];
  // Түссіз категорияда (кітап, азық-түлік…) түс жоқ — жол бір тауар, жылдам
  // коды осында.
  final quickCtrl = TextEditingController();
  // Категория сипаттамалары (0085) — жолдың барлық түс нұсқаларына ортақ.
  Map<String, dynamic> attrs = {};
  final Map<String, TextEditingController> sizeCtrls = {}; // размер → сан
  bool saved = false;

  // ── «Мұндай тауар бар» ұсынысы (0062) ──────────────────────────────────
  //  Жылдам режимде де қажет: бұрын ұсыныс ТЕК қарапайым қосу формасында
  //  болатын, ал тауарды көбіне осы жерден енгізеді. Нәтижесінде әкелінген
  //  партия жаңа тауар болып жазылып, қоймада бір модель екі карточкаға
  //  бөлініп кететін.
  List<ProductModel> similar = const [];
  bool similarDismissed = false;
  Timer? similarDebounce;

  int qtyOf(String s) => int.tryParse(sizeCtrls[s]?.text ?? '') ?? 0;
  int get total =>
      sizeCtrls.values.fold(0, (a, c) => a + (int.tryParse(c.text) ?? 0));

  /// Размер тізімін жаңасына сәйкестендіру (ескі мәндер сақталады).
  void syncSizes(List<String> sizes) {
    final old = {for (final e in sizeCtrls.entries) e.key: e.value.text};
    for (final c in sizeCtrls.values) {
      c.dispose();
    }
    sizeCtrls.clear();
    for (final s in sizes) {
      sizeCtrls[s] = TextEditingController(text: old[s] ?? '');
    }
  }

  void dispose() {
    similarDebounce?.cancel();
    nameCtrl.dispose();
    brandCtrl.dispose();
    purchaseCtrl.dispose();
    sellingCtrl.dispose();
    quickCtrl.dispose();
    for (final c in colors) {
      c.dispose();
    }
    for (final c in sizeCtrls.values) {
      c.dispose();
    }
  }
}

class _AddProductsFastScreenState extends State<AddProductsFastScreen> {
  final _firestoreService = FirestoreService();

  String? _categoryKey;
  String? _targetGroup;
  DateTime _dateArrived = DateTime.now();
  final _defPurchaseCtrl = TextEditingController();
  final _defSellingCtrl = TextEditingController();

  final List<_FastRow> _rows = [];
  List<String> _brandSuggestions = [];
  List<String> _typeSuggestions = []; // бұрын қолданылған тип/түрлер
  bool _isLoading = false;
  int _savingIndex = 0;

  // Сатушының сақталған размер-пресеттері (қарапайым товар қосумен ОРТАҚ кілт).
  static const String _kPresetsPref = 'qty_presets_v2';
  List<Map<String, dynamic>> _customPresets = [];

  static const Map<String, List<String>> _sizesByCat = {
    'Мужские': ['39', '40', '41', '42', '43', '44', '45', '46'],
    'Женские': ['35', '36', '37', '38', '39', '40', '41'],
    'Унисекс': ['36', '37', '38', '39', '40', '41', '42', '43', '44'],
    'Детские': ['28', '29', '30', '31', '32', '33', '34', '35', '36'],
  };

  static const Map<String, List<String>> _typesByCategory = kTypesByCategory;
  static const List<String> _targetGroups = kProductTargetGroups;
  static const Map<String, String> _targetGroupIcons = {
    'Мужские': '👨',
    'Женские': '👩',
    'Унисекс': '👫',
    'Детские': '🧸',
  };

  bool get _isShoes => _categoryKey == 'shoes';
  bool get _needsAudience =>
      _categoryKey != null && categoryByKey(_categoryKey).hasAudience;
  // Түс тек түсіне қарап таңдалатын категорияда (category_attributes.dart).
  bool get _needsColor => visibilityFor(_categoryKey).needsColor;

  @override
  void initState() {
    super.initState();
    _loadBrandsTypes();
    _loadPresets();
    _rows.add(_FastRow());
  }

  // Бренд/тип ұсыныстары ВИД ТОВАРҒА (categoryKey) байланысты — категория
  // таңдалғанда сол виддің брендтері мен типтерін ғана көрсетеміз.
  Future<void> _loadBrandsTypes() async {
    final brands =
        await _firestoreService.distinctBrands(categoryKey: _categoryKey);
    final types =
        await _firestoreService.distinctTypes(categoryKey: _categoryKey);
    if (mounted) {
      setState(() {
        _brandSuggestions = brands;
        _typeSuggestions = types;
      });
    }
  }

  Future<void> _loadPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPresetsPref);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List).map((e) {
        final m = e as Map;
        return <String, dynamic>{
          'name': (m['name'] as String?) ?? '',
          'sizes': ((m['sizes'] as Map?) ?? {})
              .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        };
      }).toList();
      if (mounted) setState(() => _customPresets = list);
    } catch (_) {}
  }

  Future<void> _persistPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPresetsPref, jsonEncode(_customPresets));
    } catch (_) {}
  }

  @override
  void dispose() {
    _defPurchaseCtrl.dispose();
    _defSellingCtrl.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  // Қолмен қосылған «өз размерлері» — барлық жолға ортақ.
  final Set<String> _customSizes = {};

  List<String> _sizesForSelection() {
    if (_categoryKey == null) return [];
    if (_categoryKey == 'shoes') return _sizesByCat[_targetGroup] ?? [];
    return categoryByKey(_categoryKey).sizes;
  }

  // Базалық размерлер + қолмен қосылғандар.
  List<String> _allSizesList() {
    final base = _sizesForSelection();
    return [...base, ..._customSizes.where((s) => !base.contains(s))];
  }

  List<String> get _currentTypes =>
      _categoryKey != null ? (_typesByCategory[_categoryKey!] ?? []) : [];

  // Ұсынылатын типтер: категорияныкі + бұрын қолданылғандар (қайталанбай).
  List<String> get _typeOptions {
    final out = <String>[..._currentTypes];
    for (final t in _typeSuggestions) {
      if (!out.contains(t)) out.add(t);
    }
    return out;
  }

  void _recomputeSizes() {
    _customSizes.clear(); // категория ауысса — өз размерлері тазарады
    for (final r in _rows) {
      r.syncSizes(_allSizesList());
    }
  }

  void _addRow() {
    final r = _FastRow();
    if (_defPurchaseCtrl.text.trim().isNotEmpty) {
      r.purchaseCtrl.text = _defPurchaseCtrl.text.trim();
    }
    if (_defSellingCtrl.text.trim().isNotEmpty) {
      r.sellingCtrl.text = _defSellingCtrl.text.trim();
    }
    r.syncSizes(_allSizesList());
    setState(() => _rows.add(r));
  }

  void _removeRow(int i) {
    setState(() {
      _rows[i].dispose();
      _rows.removeAt(i);
      if (_rows.isEmpty) _rows.add(_FastRow()..syncSizes(_allSizesList()));
    });
  }

  /// Ерекше түс: HSV палитрадан таңдап, атын автоматты жазып, жолға қосамыз.
  Future<void> _addCustomColorToRow(_FastRow r) async {
    final color = await showCustomColorPicker(context);
    if (color == null || !mounted) return;
    final name = describeColorName(color);
    // Дәл сол түс әлдеқашан таңдалған болса — қайта қоспаймыз.
    if (r.colors.any((c) => c.color == name)) {
      _err(tr('Цвет «${trValue(name)}» уже выбран',
          '«${trValue(name)}» түсі әлдеқашан таңдалған'));
      return;
    }
    setState(() =>
        r.colors.add(_ColorPick(name, hex: colorToHex(color))));
  }

  /// «Өз размері» — барлық жолға қосылады.
  Future<void> _addCustomSize() async {
    final value = await promptTextDialog(
      context,
      title: tr('Свой размер', 'Өз өлшемі'),
      hint: tr('Например: 42 или XXL', 'Мысалы: 42 немесе XXL'),
    );
    final size = value?.trim() ?? '';
    if (size.isEmpty || !mounted) return;
    if (_allSizesList().contains(size)) return;
    setState(() {
      _customSizes.add(size);
      for (final r in _rows) {
        r.sizeCtrls.putIfAbsent(size, () => TextEditingController());
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateArrived,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('ru'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
              primary: cGreen, onPrimary: Colors.white, surface: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dateArrived = picked);
  }

  void _err(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: cRed,
      behavior: SnackBarBehavior.floating));

  // Сақталмаған деректер бар ма (кемінде бір жол толтырыла бастаған)?
  bool _hasUnsavedData() => _rows.any((r) =>
      !r.saved &&
      (r.nameCtrl.text.trim().isNotEmpty ||
          r.brandCtrl.text.trim().isNotEmpty ||
          r.colors.isNotEmpty ||
          r.attrs.isNotEmpty ||
          r.quickCtrl.text.trim().isNotEmpty ||
          r.total > 0));

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsavedData()) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Есть несохранённые товары', 'Сақталмаған тауарлар бар'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        content: Text(
            tr('Если продолжить, введённые данные будут потеряны.',
                'Жалғастырсаңыз, енгізілген деректер жоғалады.'),
            style: manrope(13.5, FontWeight.w500, color: cInk2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Остаться', 'Қалу'))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Продолжить', 'Жалғастыру'))),
        ],
      ),
    );
    return ok == true;
  }

  // ── Пресеттер ─────────────────────────────────────────────────────────────
  void _applyPresetToRow(_FastRow r, Map<String, int> preset) {
    setState(() {
      for (final e in r.sizeCtrls.entries) {
        e.value.text = (preset[e.key] ?? 0) > 0 ? '${preset[e.key]}' : '';
      }
    });
  }

  Future<void> _saveRowAsPreset(_FastRow r) async {
    final sizes = <String, int>{
      for (final e in r.sizeCtrls.entries)
        if ((int.tryParse(e.value.text) ?? 0) > 0)
          e.key: int.parse(e.value.text),
    };
    if (sizes.isEmpty) {
      _err(tr('Сначала укажите количество', 'Алдымен санды енгізіңіз'));
      return;
    }
    final total = sizes.values.fold(0, (a, b) => a + b);
    final name = await promptTextDialog(
      context,
      title: tr('Название пресета', 'Пресет атауы'),
      hint: tr('Мой пресет $total шт', 'Менің пресетім $total дана'),
      initial: tr('Пресет $total шт', 'Пресет $total дана'),
    );
    if (name == null) return;
    setState(() => _customPresets.add({'name': name, 'sizes': sizes}));
    _persistPresets();
  }

  Future<void> _promptCustomType(_FastRow r) async {
    final value = await promptTextDialog(
      context,
      title: tr('Свой тип товара', 'Өз тауар түрі'),
      hint: tr('Например: Мокасины', 'Мысалы: Мокасиндер'),
      initial: (r.type != null && !_typeOptions.contains(r.type)) ? r.type! : '',
    );
    if (value != null && mounted) setState(() => r.type = value);
  }

  // ── «Мұндай тауар бар» ұсынысы (0062) ─────────────────────────────────────

  /// Атау/бренд терілген сайын (кідіріспен) ұқсас тауарларды іздейміз.
  void _scheduleSimilar(_FastRow r) {
    r.similarDebounce?.cancel();
    r.similarDebounce =
        Timer(const Duration(milliseconds: 450), () => _searchSimilar(r));
  }

  Future<void> _searchSimilar(_FastRow r) async {
    final name = r.nameCtrl.text.trim();
    if (name.length < 3) {
      if (r.similar.isNotEmpty && mounted) {
        setState(() => r.similar = const []);
      }
      return;
    }
    try {
      final found = await _firestoreService.findSimilarProducts(
        name: name,
        brand: r.brandCtrl.text.trim(),
        categoryKey: _categoryKey ?? '',
        limit: 3,
      );
      if (mounted) setState(() => r.similar = found);
    } catch (_) {}
  }

  /// Ұқсас тауарды басқанда — «Повторный завоз» экранына ауысамыз.
  /// Жылдам форма сақталмайды, сондықтан АШЫҚ ескертеміз.
  Future<void> _openRestock(ProductModel p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Повторный завоз?', 'Қайта завоз ба?'),
            style: manrope(16, FontWeight.w800, color: cInk)),
        content: Text(
            tr('Откроем оформление новой партии для «${p.name}». Заполненные строки не сохранятся.',
                '«${p.name}» үшін жаңа партия рәсімдеуін ашамыз. Толтырылған жолдар сақталмайды.'),
            style: manrope(13.5, FontWeight.w500, color: cInk2, height: 1.4)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Отмена', 'Болдырмау'),
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cGreen, foregroundColor: Colors.white),
              child: Text(tr('Да, завоз', 'Иә, завоз'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => RestockScreen(product: p)));
  }

  /// Жол ішіндегі ұсыныс баннері (қарапайым қосу формасындағымен бір мағына,
  /// бірақ ықшам: жылдам режимде экран жолдарға толы).
  Widget _buildSimilarHint(_FastRow r) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: cAmberTint,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: cAmber.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.help_outline_rounded, color: cAmber, size: 15),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                  tr('Похожий товар уже есть. Это повторный завоз?',
                      'Ұқсас тауар бар. Бұл қайта завоз ба?'),
                  style: manrope(11.5, FontWeight.w800, color: cInk)),
            ),
            GestureDetector(
              onTap: () => setState(() => r.similarDismissed = true),
              child: const Icon(Icons.close_rounded, size: 15, color: cInk3),
            ),
          ]),
          const SizedBox(height: 7),
          ...r.similar.map((p) => GestureDetector(
                onTap: () => _openRestock(p),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(9)),
                  child: Row(children: [
                    SizedBox(
                      width: 34,
                      height: 34,
                      child: QShoeImage(
                        imageUrl: p.images.isNotEmpty ? p.images.first : null,
                        height: 34,
                        tone: p.id.hashCode % 5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          [
                            p.name,
                            if (p.color.isNotEmpty) trValue(p.color),
                            if (p.variantNote.isNotEmpty) p.variantNote,
                          ].join(' · '),
                          style: manrope(11.5, FontWeight.w700, color: cInk),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: cGreen,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(tr('Завоз', 'Завоз'),
                          style: manrope(10.5, FontWeight.w800,
                              color: Colors.white)),
                    ),
                  ]),
                ),
              )),
          Text(
              tr('Иначе сохраним как отдельный товар со своим артикулом.',
                  'Баспасаңыз, өз артикулы бар бөлек тауар болып сақталады.'),
              style: manrope(10.5, FontWeight.w600, color: cInk2)),
        ]),
      );

  /// Жолдың жылдам кодтары: түсті категорияда әр түстікі, түссізде — біреу.
  List<String> _rowCodes(_FastRow r) => [
        if (_needsColor)
          for (final cp in r.colors) cp.quickCtrl.text.trim()
        else
          r.quickCtrl.text.trim(),
      ];

  /// Енгізілген жылдам кодтарды дүкендегі басқа тауар иеленіп тұрған жоқ па.
  Future<bool> _quickCodesFree(List<_FastRow> rows) async {
    for (final r in rows) {
      for (final code in _rowCodes(r)) {
        if (code.isEmpty) continue;
        try {
          final taken = await _firestoreService.productWithQuickCode(code);
          if (taken != null) {
            _err(tr('Число «$code» уже занято: ${taken.name}',
                '«$code» коды бос емес: ${taken.name}'));
            return false;
          }
        } catch (_) {
          // Тексеру мүмкін болмады — DB-дегі unique индекс бәрібір қорғайды.
        }
      }
    }
    return true;
  }

  // ── Сақтау ────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (_isLoading) return;
    if (_categoryKey == null) {
      _err(tr('Выберите категорию', 'Категорияны таңдаңыз'));
      return;
    }
    if (_needsAudience && _targetGroup == null) {
      _err(tr('Выберите, кому', 'Кімге екенін таңдаңыз'));
      return;
    }
    final toSave = _rows
        .where((r) => !r.saved && r.nameCtrl.text.trim().isNotEmpty)
        .toList();
    if (toSave.isEmpty) {
      _err(tr('Добавьте хотя бы один товар', 'Кемінде бір тауар қосыңыз'));
      return;
    }
    for (var i = 0; i < toSave.length; i++) {
      final r = toSave[i];
      final n = i + 1;
      if (r.brandCtrl.text.trim().isEmpty) {
        _err(tr('Строка $n: бренд', '$n-жол: бренд'));
        return;
      }
      if (_needsColor && r.colors.isEmpty) {
        _err(tr('Строка $n: выберите цвет', '$n-жол: түс таңдаңыз'));
        return;
      }
      final missingAttr = missingRequiredAttributes(_categoryKey, r.attrs);
      if (missingAttr.isNotEmpty) {
        _err(tr('Строка $n: укажите «${missingAttr.first.label}»',
            '$n-жол: «${missingAttr.first.label}» көрсетіңіз'));
        return;
      }
      if ((double.tryParse(r.purchaseCtrl.text) ?? 0) <= 0) {
        _err(tr('Строка $n: закупочная цена', '$n-жол: сатып алу бағасы'));
        return;
      }
      if ((double.tryParse(r.sellingCtrl.text) ?? 0) <= 0) {
        _err(tr('Строка $n: цена продажи', '$n-жол: сату бағасы'));
        return;
      }
      if (r.total == 0) {
        _err(tr('Строка $n: количество по размерам', '$n-жол: размер бойынша сан'));
        return;
      }
    }

    // Жылдам кодтар форманың ІШІНДЕ қайталанбауы керек.
    final seenCodes = <String>{};
    for (final r in toSave) {
      for (final code in _rowCodes(r)) {
        if (code.isEmpty) continue;
        if (!seenCodes.add(code)) {
          _err(tr('Быстрое число «$code» повторяется — у каждого товара своё',
              '«$code» жылдам коды қайталанады — әр тауардың коды бөлек'));
          return;
        }
      }
    }

    setState(() => _isLoading = true);
    // Дүкенде бұл кодтар бос па (DB-дегі unique индексті алдын ала ұстаймыз).
    if (!await _quickCodesFree(toSave)) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (!mounted) return;
    if (!await ensureWarehouseSelected(context)) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (!mounted) return;
    final warehouseId = context.read<WarehouseContext>().current?.id ?? '';

    var savedProducts = 0;
    try {
      for (final r in _rows) {
        if (r.saved ||
            r.nameCtrl.text.trim().isEmpty ||
            (_needsColor && r.colors.isEmpty)) {
          continue;
        }
        setState(() => _savingIndex = savedProducts + 1);
        final sizesQty = <String, int>{
          for (final e in r.sizeCtrls.entries)
            if ((int.tryParse(e.value.text) ?? 0) > 0)
              e.key: int.parse(e.value.text),
        };
        final attributes = sanitizeAttributes(_categoryKey, r.attrs);
        // Жолдың әр түсі — жеке товар (ортақ размер/баға). Түссіз категорияда
        // жол = бір тауар, түсі '' (жасырын нұсқа, қосу формасымен бірдей).
        final variants = _needsColor
            ? [
                for (final cp in r.colors)
                  (color: cp.color, hex: cp.hex, quick: cp.quickCtrl.text.trim())
              ]
            : [(color: '', hex: '', quick: r.quickCtrl.text.trim())];
        for (final cp in variants) {
          final batch = BatchModel(
            id: '',
            dateArrived: _dateArrived,
            purchasePrice: double.tryParse(r.purchaseCtrl.text) ?? 0,
            sellingPrice: double.tryParse(r.sellingCtrl.text) ?? 0,
            sizesQuantity: Map.from(sizesQty),
          );
          // ⚠️ ӘРҚАШАН ЖАҢА ТАУАР. Бұрын мұнда findMatchingProduct тұратын да,
          // дәл сәйкестік табылса жол ескі карточкаға ПАРТИЯ болып жазылатын.
          // Повторный завоздың өз экраны бар; «товар қосу» — жаңа тауар.
          final product = ProductModel(
            id: '',
            name: r.nameCtrl.text.trim(),
            brand: r.brandCtrl.text.trim(),
            type: r.type ?? '',
            material: '',
            category: _targetGroup ?? '',
            categoryKey: _categoryKey ?? '',
            color: cp.color,
            customColorHex: cp.hex,
            articul: '',
            quickCode: cp.quick,
            status: ProductModel.statusInStock,
            images: const [],
            attributes: attributes,
          );
          await _firestoreService.addNewProduct(
            product: product,
            firstBatch: batch,
            dateArrived: _dateArrived,
            warehouseId: warehouseId,
          );
          savedProducts++;
        }
        r.saved = true;
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('$savedProducts товаров добавлено на склад!',
              '$savedProducts тауар қоймаға қосылды!')),
          backgroundColor: cGreen,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      _err(tr('Сохранено $savedProducts. Ошибка: $e\nНажмите «Сохранить» ещё раз.',
          '$savedProducts сақталды. Қате: $e\n«Сақтау» қайта басыңыз.'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final ready = _categoryKey != null && (!_needsAudience || _targetGroup != null);
    return PopScope(
      canPop: !_hasUnsavedData(),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
      backgroundColor: cBg,
      body: SafeArea(
        child: Column(children: [
          Container(
            decoration: const BoxDecoration(gradient: kGrad),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 20, 16),
              child: Row(children: [
                GestureDetector(
                  onTap: () async {
                    final navigator = Navigator.of(context);
                    if (await _confirmDiscard()) navigator.pop();
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.chevron_left_rounded,
                        color: Colors.white, size: 22),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Быстрое добавление', 'Жылдам қосу'),
                            style: manrope(21, FontWeight.w800,
                                color: Colors.white, letterSpacing: -0.5)),
                        Text(tr('Несколько товаров · без фото',
                            'Бірнеше тауар · фотосыз'),
                            style: manrope(12, FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.8))),
                      ]),
                ),
              ]),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [
                _buildSharedHeader(),
                const SizedBox(height: 16),
                if (ready) ...[
                  ...List.generate(
                      _rows.length, (i) => _buildRow(i, _rows[i])),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _addRow,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cGreenTint,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: cGreen.withValues(alpha: 0.4), width: 1.5),
                      ),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_rounded, color: cGreen),
                            const SizedBox(width: 8),
                            Text(tr('Ещё товар', 'Тағы тауар'),
                                style: manrope(14, FontWeight.w700,
                                    color: cGreen)),
                          ]),
                    ),
                  ),
                ] else
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: cAmberTint,
                        borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      const Icon(Icons.info_outline, color: cAmber, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                            tr('Сначала выберите категорию и «кому» выше',
                                'Алдымен жоғарыдан категория мен «кімге» таңдаңыз'),
                            style: manrope(12.5, FontWeight.w600,
                                color: const Color(0xFF7A4F00))),
                      ),
                    ]),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(color: Colors.white, boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, -3))
            ]),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading || !ready ? null : _save,
                style: ElevatedButton.styleFrom(
                    backgroundColor: cGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    elevation: 0),
                child: Text(
                    _isLoading
                        ? tr('Сохранение $_savingIndex…',
                            'Сақталуда $_savingIndex…')
                        : tr('Сохранить всё', 'Барлығын сақтау'),
                    style:
                        const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ),
        ]),
      ),
      ),
    );
  }

  Widget _buildSharedHeader() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cLine),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Общее для всех', 'Барлығына ортақ'),
            style: manrope(13, FontWeight.w800, color: cInk)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kCategories.map((c) {
            final on = _categoryKey == c.key;
            final tone = toneFor(c.tone);
            return GestureDetector(
              onTap: () async {
                if (c.key == _categoryKey) return;
                // Категория ауысса — размерлер/типтер тазарады. Деректер болса растату.
                if (!await _confirmDiscard()) return;
                if (!mounted) return;
                setState(() {
                  _categoryKey = c.key;
                  _targetGroup = null;
                  for (final r in _rows) {
                    r.type = null;
                    // Сипаттама кілттері категорияға тиесілі.
                    r.attrs = {};
                    // Түссіз категорияда таңдалған түстер мағынасыз.
                    if (!_needsColor) {
                      for (final cp in r.colors) {
                        cp.dispose();
                      }
                      r.colors.clear();
                    }
                  }
                  _recomputeSizes();
                });
                _loadBrandsTypes(); // осы виддің брендтері/типтері
              },
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
                decoration: BoxDecoration(
                  color: on ? tone.tint : Colors.white,
                  border: Border.all(color: on ? tone.deep : cLine, width: 1.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  CategoryIcon(
                      kind: c.iconKey, size: 15, color: on ? tone.deep : cInk3),
                  const SizedBox(width: 6),
                  Text(c.short,
                      style: manrope(12.5, FontWeight.w700,
                          color: on ? tone.deep : cInk2)),
                ]),
              ),
            );
          }).toList(),
        ),
        if (_needsAudience) ...[
          const SizedBox(height: 12),
          Text(tr('Кому', 'Кімге'),
              style: manrope(12, FontWeight.w700, color: cInk2)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _targetGroups.map((g) {
              final on = _targetGroup == g;
              return GestureDetector(
                onTap: () async {
                  if (g == _targetGroup) return;
                  // Аяқ киімде «кімге» размерлерді ауыстырады — деректер болса растату.
                  if (_isShoes && !await _confirmDiscard()) return;
                  if (!mounted) return;
                  setState(() {
                    _targetGroup = g;
                    if (_isShoes) _recomputeSizes();
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: on ? cGreenTint : Colors.white,
                    border:
                        Border.all(color: on ? cGreen : cLine, width: 1.5),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text('${_targetGroupIcons[g] ?? ''} ${trValue(g)}',
                      style: manrope(13, FontWeight.w700,
                          color: on ? cGreenDeep : cInk2)),
                ),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _pickDate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
                color: cBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cLine)),
            child: Row(children: [
              const Icon(Icons.calendar_today_outlined,
                  color: cGreen, size: 16),
              const SizedBox(width: 8),
              Text(
                  '${_dateArrived.day.toString().padLeft(2, '0')}.${_dateArrived.month.toString().padLeft(2, '0')}.${_dateArrived.year}',
                  style: manrope(13, FontWeight.w700, color: cInk)),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: _MiniNumberField(
              controller: _defPurchaseCtrl,
              label: tr('Закуп ₸ (по умолч.)', 'Сатып алу ₸ (әдепкі)'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _MiniNumberField(
              controller: _defSellingCtrl,
              label: tr('Продажа ₸ (по умолч.)', 'Сату ₸ (әдепкі)'),
            ),
          ),
        ]),
      ]),
    );
  }

  /// «Характеристики · 2/4» батырмасы. Міндетті өріс бос болса — қызғылт сары.
  Widget _buildAttrsButton(_FastRow r) {
    final defs = attributesFor(_categoryKey);
    final filled =
        defs.where((d) => normalizeAttrValue(d, r.attrs[d.key]) != null).length;
    final missing = missingRequiredAttributes(_categoryKey, r.attrs).isNotEmpty;
    return GestureDetector(
      onTap: () => _editRowAttrs(r),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: missing ? cAmberTint : cBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: missing ? cAmber.withValues(alpha: 0.5) : cLine),
        ),
        child: Row(children: [
          Icon(Icons.fact_check_outlined,
              size: 16, color: missing ? cAmberInk : cGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                missing
                    ? tr('Характеристики · есть обязательные',
                        'Сипаттамалары · міндеттісі бар')
                    : tr('Характеристики', 'Сипаттамалары'),
                style: manrope(12.5, FontWeight.w700,
                    color: missing ? cAmberInk : cInk)),
          ),
          Text('$filled/${defs.length}',
              style: manrope(12, FontWeight.w700, color: cInk3)),
          const Icon(Icons.chevron_right_rounded, size: 18, color: cInk3),
        ]),
      ),
    );
  }

  /// Сипаттамалар парақшасы (ортақ редактор). Әр өзгеріс жолға бірден жазылады.
  Future<void> _editRowAttrs(_FastRow r) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
              18, 14, 18, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                            color: cLine,
                            borderRadius: BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 14),
                  Text(tr('Характеристики', 'Сипаттамалары'),
                      style: manrope(16, FontWeight.w800, color: cInk)),
                  const SizedBox(height: 12),
                  CategoryAttributesEditor(
                    categoryKey: _categoryKey,
                    values: r.attrs,
                    framed: false,
                    showErrors: true,
                    onChanged: (v) {
                      setS(() => r.attrs = v);
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 18),
                  QPrimaryButton(
                    label: tr('Готово', 'Дайын'),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ]),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(int index, _FastRow r) {
    final sizes = _allSizesList();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cLine),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 24,
            height: 24,
            decoration:
                const BoxDecoration(color: cGreenTint, shape: BoxShape.circle),
            child: Center(
                child: Text('${index + 1}',
                    style: manrope(12, FontWeight.w800, color: cGreenDeep))),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                _needsColor
                    ? '${r.total} ${tr('шт', 'дана')} · ${r.colors.length} ${tr('цв', 'түс')}'
                    : '${r.total} ${tr('шт', 'дана')}',
                style: manrope(12.5, FontWeight.w700, color: cInk3)),
          ),
          if (_rows.length > 1)
            GestureDetector(
              onTap: () => _removeRow(index),
              child: const Icon(Icons.close_rounded, color: cInk3, size: 18),
            ),
        ]),
        const SizedBox(height: 10),
        _MiniTextField(
            controller: r.nameCtrl,
            hint: tr('Название *', 'Атауы *'),
            onChanged: (_) {
              setState(() {});
              _scheduleSimilar(r);
            }),
        const SizedBox(height: 8),
        _MiniTextField(
            controller: r.brandCtrl,
            hint: tr('Бренд *', 'Бренд *'),
            onChanged: (_) {
              setState(() {});
              _scheduleSimilar(r);
            }),
        if (_brandSuggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          HScrollChips(
            chips: _brandSuggestions
                .map((b) => HChip(
                    label: b,
                    selected: r.brandCtrl.text.trim() == b,
                    onTap: () {
                      setState(() => r.brandCtrl.text = b);
                      _scheduleSimilar(r);
                    }))
                .toList(),
          ),
        ],
        // «Мұндай тауар бар ма» — толтырып жатқанда бірден көрінеді.
        if (r.similar.isNotEmpty && !r.similarDismissed)
          _buildSimilarHint(r),
        // ── Тип товара ──────────────────────────────────────────────────
        const SizedBox(height: 10),
        Text(tr('Тип товара', 'Тауар түрі'),
            style: manrope(11.5, FontWeight.w700, color: cInk2)),
        const SizedBox(height: 6),
        HScrollChips(
          chips: [
            for (final t in _typeOptions)
              HChip(
                  label: trValue(t),
                  selected: r.type == t,
                  onTap: () => setState(() => r.type = r.type == t ? null : t)),
            if (r.type != null && !_typeOptions.contains(r.type))
              HChip(
                  label: r.type!,
                  selected: true,
                  onTap: () => setState(() => r.type = null)),
          ],
          trailing: HActionChip(
            label: tr('Свой', 'Өз нұсқасы'),
            icon: Icons.edit_outlined,
            onTap: () => _promptCustomType(r),
          ),
        ),
        // ── Сипаттамалар: ықшам батырма → парақша (экран ұзармасын) ─────
        if (attributesFor(_categoryKey).isNotEmpty) ...[
          const SizedBox(height: 10),
          _buildAttrsButton(r),
        ],
        // ── Түссіз категория: тек жылдам код ──────────────────────────
        if (!_needsColor) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Text(tr('Быстрый номер (необязательно)',
                  'Жылдам нөмір (міндетті емес)'),
                  style: manrope(11.5, FontWeight.w700, color: cInk2)),
            ),
            SizedBox(
              width: 110,
              child: _MiniTextField(
                controller: r.quickCtrl,
                hint: '№ 103',
                keyboardType: TextInputType.number,
              ),
            ),
          ]),
        ],
        // ── Түстер (міндетті; басу = таңдау, қайта басу = алып тастау) ────
        if (_needsColor) ...[
        const SizedBox(height: 10),
        Text(tr('Цвет(а) *', 'Түс(тер) *'),
            style: manrope(11.5, FontWeight.w700, color: cInk2)),
        const SizedBox(height: 6),
        HScrollChips(
          chips: ProductModel.colorOptions.map((opt) {
            final name = opt['name'] as String;
            final idx = r.colors.indexWhere((c) => c.color == name);
            return HChip(
              label: trValue(name),
              selected: idx >= 0,
              onTap: () => setState(() {
                if (idx >= 0) {
                  r.colors[idx].dispose();
                  r.colors.removeAt(idx);
                } else {
                  r.colors.add(_ColorPick(name));
                }
              }),
            );
          }).toList(),
          trailing: HActionChip(
            label: tr('Свой цвет', 'Өз түсі'),
            icon: Icons.palette_outlined,
            onTap: () => _addCustomColorToRow(r),
          ),
        ),
        if (r.colors.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...List.generate(r.colors.length, (ci) {
            final cp = r.colors[ci];
            final swatch = cp.hex.isNotEmpty
                ? (hexToColor(cp.hex) ?? cInk3)
                : (ProductModel.colorHex(cp.color) ?? cInk3);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                      color: swatch,
                      shape: BoxShape.circle,
                      border: Border.all(color: cLine)),
                ),
                const SizedBox(width: 8),
                SizedBox(
                    width: 64,
                    child: Text(trValue(cp.color),
                        style: manrope(12.5, FontWeight.w700, color: cInk),
                        overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 6),
                const Spacer(),
                // Жылдам код — сатушының өз саны (офлайн сату/іздеу үшін).
                SizedBox(
                  width: 90,
                  child: _MiniTextField(
                    controller: cp.quickCtrl,
                    hint: '№ 103',
                    keyboardType: TextInputType.number,
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() {
                    r.colors[ci].dispose();
                    r.colors.removeAt(ci);
                  }),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, size: 16, color: cInk3),
                  ),
                ),
              ]),
            );
          }),
        ],
        ],
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: _MiniNumberField(
                controller: r.purchaseCtrl, label: tr('Закуп ₸ *', 'Сатып алу ₸ *')),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _MiniNumberField(
                controller: r.sellingCtrl, label: tr('Продажа ₸ *', 'Сату ₸ *')),
          ),
        ]),
        // ── Размерлер: қолмен теру + пресеттер ──────────────────────────
        const SizedBox(height: 10),
        Row(children: [
          Text(tr('Размеры (впишите кол-во) *', 'Размерлер (санды жазыңыз) *'),
              style: manrope(11.5, FontWeight.w700, color: cInk2)),
          const Spacer(),
          GestureDetector(
            onTap: () => _saveRowAsPreset(r),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.bookmark_add_outlined, size: 14, color: cGreen),
              const SizedBox(width: 3),
              Text(tr('В пресет', 'Пресетке'),
                  style: manrope(11, FontWeight.w700, color: cGreen)),
            ]),
          ),
        ]),
        if (_customPresets.isNotEmpty) ...[
          const SizedBox(height: 6),
          HScrollChips(
            chips: _customPresets.map((p) {
              final s = (p['sizes'] as Map)
                  .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
              final total = s.values.fold(0, (a, b) => a + b);
              final label = (p['name'] as String?)?.isNotEmpty == true
                  ? p['name'] as String
                  : tr('$total шт', '$total дана');
              return HChip(
                  label: label,
                  selected: false,
                  onTap: () => _applyPresetToRow(r, s));
            }).toList(),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...sizes.map((s) => _SizeCell(
                  size: s,
                  controller: r.sizeCtrls[s] ?? TextEditingController(),
                  onChanged: () => setState(() {}),
                )),
            // + Свой размер (барлық жолға ортақ)
            GestureDetector(
              onTap: _addCustomSize,
              child: Container(
                width: 62,
                height: 56,
                decoration: BoxDecoration(
                  color: cGreenTint,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: cGreen.withValues(alpha: 0.4), width: 1.2),
                ),
                child: const Center(
                    child: Icon(Icons.add_rounded, color: cGreen, size: 22)),
              ),
            ),
          ],
        ),
      ]),
    );
  }
}

// ── Кіші өрістер ──────────────────────────────────────────────────────────────
class _MiniTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  const _MiniTextField(
      {required this.controller,
      required this.hint,
      this.onChanged,
      this.keyboardType});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: keyboardType,
      textCapitalization: TextCapitalization.sentences,
      style: manrope(14, FontWeight.w600, color: cInk),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: manrope(13.5, FontWeight.w500, color: cInk3),
        isDense: true,
        filled: true,
        fillColor: cBg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: cLine)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: cLine)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: cGreen, width: 1.5)),
      ),
    );
  }
}

class _MiniNumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  const _MiniNumberField({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
      style: manrope(14, FontWeight.w700, color: cInk),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: manrope(11.5, FontWeight.w600, color: cInk3),
        isDense: true,
        filled: true,
        fillColor: cBg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: cLine)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: cLine)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: cGreen, width: 1.5)),
      ),
    );
  }
}

// ── Размер ұяшығы: жоғарыда өлшем, астында қолмен теретін сан өрісі ──────────
class _SizeCell extends StatelessWidget {
  final String size;
  final TextEditingController controller;
  final VoidCallback onChanged;
  const _SizeCell(
      {required this.size, required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final active = (int.tryParse(controller.text) ?? 0) > 0;
    return Container(
      width: 62,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: active ? cGreenTint : cBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: active ? cGreen : cLine, width: 1.2),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(size,
            style: manrope(13, FontWeight.w800,
                color: active ? cGreenDeep : cInk)),
        SizedBox(
          height: 30,
          child: TextField(
            controller: controller,
            onChanged: (_) => onChanged(),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: manrope(14, FontWeight.w800,
                color: active ? cGreenDeep : cInk2),
            decoration: const InputDecoration(
              hintText: '0',
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
      ]),
    );
  }
}
