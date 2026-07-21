import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/color_naming.dart';
import '../../../core/lang.dart';
import '../../../core/warehouse_context.dart';
import '../../../data/models/models.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';
import '../../shared/color_picker_sheet.dart';
import '../../shared/h_scroll_chips.dart';
import '../../shared/mandatory_warehouse_picker.dart';
import '../../shared/prompt_text_dialog.dart';

/// Жылдам товар қосу — бір экранда бірнеше тауарды жол-жолмен қосу.
/// Жоғарыда БІР рет ортақ: категория + кому + жеткізілім күні + әдепкі баға.
/// Әр «+» — жаңа жол. Әр жолда: атауы, бренд, тип, түс(тер) + айырмашылық белгісі,
/// баға, размер·сан (қолмен теру + пресеттер). Фото жоқ (кейін карточкадан).
class AddProductsFastScreen extends StatefulWidget {
  const AddProductsFastScreen({super.key});

  @override
  State<AddProductsFastScreen> createState() => _AddProductsFastScreenState();
}

/// Жолдағы бір түс-нұсқа (түс + айырмашылық белгісі). Бірдей түсті екі рет
/// таңдауға болады — әрқайсысына белгі жазылады (мыс. «қара табан» / «қызыл табан»).
class _ColorPick {
  final String color;
  final String hex; // ерекше түстің HEX коды ('' = стандарт палитра)
  final noteCtrl = TextEditingController();
  _ColorPick(this.color, {this.hex = ''});
  void dispose() => noteCtrl.dispose();
}

/// Бір товар-жолдың күйі.
class _FastRow {
  final nameCtrl = TextEditingController();
  final brandCtrl = TextEditingController();
  final purchaseCtrl = TextEditingController();
  final sellingCtrl = TextEditingController();
  String? type; // вид
  final List<_ColorPick> colors = [];
  final Map<String, TextEditingController> sizeCtrls = {}; // размер → сан
  bool saved = false;

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
    nameCtrl.dispose();
    brandCtrl.dispose();
    purchaseCtrl.dispose();
    sellingCtrl.dispose();
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
    setState(() => r.colors
        .add(_ColorPick(describeColorName(color), hex: colorToHex(color))));
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

  // ── Сақтау ────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (_isLoading) return;
    if (_categoryKey == null) {
      _err(tr('Выберите категорию', 'Категорияны таңдаңыз'));
      return;
    }
    if (_targetGroup == null) {
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
      if (r.colors.isEmpty) {
        _err(tr('Строка $n: выберите цвет', '$n-жол: түс таңдаңыз'));
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

    setState(() => _isLoading = true);
    if (!await ensureWarehouseSelected(context)) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (!mounted) return;
    final warehouseId = context.read<WarehouseContext>().current?.id ?? '';

    var savedProducts = 0;
    try {
      for (final r in _rows) {
        if (r.saved || r.nameCtrl.text.trim().isEmpty || r.colors.isEmpty) {
          continue;
        }
        setState(() => _savingIndex = savedProducts + 1);
        final sizesQty = <String, int>{
          for (final e in r.sizeCtrls.entries)
            if ((int.tryParse(e.value.text) ?? 0) > 0)
              e.key: int.parse(e.value.text),
        };
        // Жолдың әр түсі — жеке товар (ортақ размер/баға).
        for (final cp in r.colors) {
          final batch = BatchModel(
            id: '',
            dateArrived: _dateArrived,
            purchasePrice: double.tryParse(r.purchaseCtrl.text) ?? 0,
            sellingPrice: double.tryParse(r.sellingCtrl.text) ?? 0,
            sizesQuantity: Map.from(sizesQty),
          );
          final note = cp.noteCtrl.text.trim();
          final existingId = await _firestoreService.findMatchingProduct(
            name: r.nameCtrl.text.trim(),
            brand: r.brandCtrl.text.trim(),
            type: r.type ?? '',
            material: '',
            category: _targetGroup ?? '',
            color: cp.color,
            variantNote: note,
          );
          if (existingId != null) {
            await _firestoreService.addNewBatchToProduct(
              productId: existingId,
              batch: batch,
              dateArrived: _dateArrived,
              warehouseId: warehouseId,
            );
          } else {
            final product = ProductModel(
              id: '',
              name: r.nameCtrl.text.trim(),
              brand: r.brandCtrl.text.trim(),
              type: r.type ?? '',
              material: '',
              category: _targetGroup ?? '',
              categoryKey: _categoryKey ?? '',
              color: cp.color,
              variantNote: note,
              customColorHex: cp.hex,
              articul: '',
              status: ProductModel.statusInStock,
              images: const [],
            );
            await _firestoreService.addNewProduct(
              product: product,
              firstBatch: batch,
              dateArrived: _dateArrived,
              warehouseId: warehouseId,
            );
          }
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
    final ready = _categoryKey != null && _targetGroup != null;
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
        if (_categoryKey != null) ...[
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
            child: Text('${r.total} ${tr('шт', 'дана')} · ${r.colors.length} ${tr('цв', 'түс')}',
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
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 8),
        _MiniTextField(
            controller: r.brandCtrl,
            hint: tr('Бренд *', 'Бренд *'),
            onChanged: (_) => setState(() {})),
        if (_brandSuggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          HScrollChips(
            chips: _brandSuggestions
                .map((b) => HChip(
                    label: b,
                    selected: r.brandCtrl.text.trim() == b,
                    onTap: () => setState(() => r.brandCtrl.text = b)))
                .toList(),
          ),
        ],
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
        // ── Түстер (міндетті; бірдей түсті екі рет таңдауға болады) ──────
        const SizedBox(height: 10),
        Text(tr('Цвет(а) *', 'Түс(тер) *'),
            style: manrope(11.5, FontWeight.w700, color: cInk2)),
        const SizedBox(height: 6),
        HScrollChips(
          chips: ProductModel.colorOptions.map((opt) {
            final name = opt['name'] as String;
            final cnt = r.colors.where((c) => c.color == name).length;
            return HChip(
              label: cnt > 0 ? '${trValue(name)} ×$cnt' : trValue(name),
              selected: cnt > 0,
              onTap: () => setState(() => r.colors.add(_ColorPick(name))),
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
                Expanded(
                  child: _MiniTextField(
                    controller: cp.noteCtrl,
                    hint: tr('Отличие (напр. чёрная подошва)',
                        'Айырмашылық (мыс. қара табан)'),
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
  const _MiniTextField(
      {required this.controller, required this.hint, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
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
