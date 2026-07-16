import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/warehouse_context.dart';
import '../../../data/models/models.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/cloudinary_service.dart';
import '../../../theme/qoima_design.dart';
import '../../shared/mandatory_warehouse_picker.dart';
import '../../shared/prompt_text_dialog.dart';
import '../../widgets/image_crop_screen.dart';

import '../../../core/lang.dart';
class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});
  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _firestoreService = FirestoreService();
  final _cloudinaryService = CloudinaryService();
  final _imagePicker = ImagePicker();

  final _nameCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _purchaseCtrl = TextEditingController();
  final _sellingCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();

  String? _type;
  String? _material;
  String? _targetGroup; // кому: Мужские|Женские|Унисекс|Детские
  String? _categoryKey; // категория товара v2 (shoes|tshirt|...)
  String? _season; // Лето|Зима|Осень|Весна (необязательно)
  DateTime _dateArrived = DateTime.now();

  bool get _isShoes => _categoryKey == 'shoes';

  // ── Түс варианттары ────────────────────────────────────────────────────
  // Бір модель — бірнеше түс: әр түс жеке товар-вариант болып сақталады
  // (клиентте name+brand+type бойынша бір карточкаға топталады). Атау, бренд,
  // категория, бағ. — ортақ; размерлер мен фото — әр түске бөлек.
  final List<String> _selectedColors = [];
  final Map<String, Map<String, int>> _variantSizes = {};
  final Map<String, List<Uint8List>> _variantImages = {};
  // Сақтау кезінде сәтті өткен түстер — қате шығып қайта басқанда
  // қайталанып (дубль партия) кетпес үшін өткізіп жібереміз.
  final Set<String> _savedColors = {};
  String? _activeColor; // Размеры/Фото қадамдарындағы белсенді түс табы
  int _savingIndex = 0; // «Сохранение i/N» прогресі

  Map<String, int> get _activeSizes => _variantSizes[_activeColor] ?? {};
  List<Uint8List> get _activeImages => _variantImages[_activeColor] ?? [];

  int _variantTotal(String color) =>
      (_variantSizes[color] ?? {}).values.fold(0, (a, b) => a + b);
  int get _grandTotal =>
      _selectedColors.fold(0, (s, c) => s + _variantTotal(c));

  static const int _maxImages = 4;
  static const int _cropSize = 1080; // тіркелген размер — админ өзгерте алмайды
  bool _isLoading = false;
  int _step = 0; // 0=Товар, 1=Цены, 2=Размеры, 3=Фото

  static const Map<String, List<String>> _sizesByCat = {
    'Мужские': ['39', '40', '41', '42', '43', '44', '45', '46'],
    'Женские': ['35', '36', '37', '38', '39', '40', '41'],
    'Унисекс': ['36', '37', '38', '39', '40', '41', '42', '43', '44'],
    'Детские': ['28', '29', '30', '31', '32', '33', '34', '35', '36'],
  };

  // Қолмен қосылған размерлер — БАРЛЫҚ түс варианттарына ортақ кілт.
  final Set<String> _customSizes = {};

  // ── Өз пресеттері (жылдам толтыру) — құрылғыда сақталады ──────────────
  // Әр элемент: {'perSize': шт/размер, 'count': неше размер}.
  List<Map<String, int>> _customPresets = [];
  static const String _kPresetsPref = 'qty_presets_v1';

  // Тип/материал по категориям и список «Кому» — общие константы каталога
  // (см. category_data.dart), используются и в редактировании товара.
  static const Map<String, List<String>> _typesByCategory = kTypesByCategory;
  static const List<String> _targetGroups = kProductTargetGroups;
  static const Map<String, String> _targetGroupIcons = {
    'Мужские': '👨',
    'Женские': '👩',
    'Унисекс': '👫',
    'Детские': '🧸',
  };
  static const Map<String, List<String>> _materialsByCategory =
      kMaterialsByCategory;
  static const List<Map<String, dynamic>> _presets = [
    {
      'labelRu': 'По 1 паре с трёх размеров · 2 с ходовых',
      'labelKk': 'Үш размерден 1 жұп · содовойдан 2',
      'descRu': 'Всего 10–14 пар (по категории)',
      'descKk': 'Барлығы 10–14 жұп (категорияға қарай)',
      'kind': 'recommended',
    },
    {
      'labelRu': '20 пар · 4 размера поровну',
      'labelKk': '20 жұп · 4 размер тең',
      'descRu': 'По 5 пар с размера',
      'descKk': 'Әр размерден 5 жұп',
      'perSize': 5,
      'count': 4
    },
    {
      'labelRu': '24 пары · 4 размера',
      'labelKk': '24 жұп · 4 размер',
      'descRu': 'По 6 пар с размера',
      'descKk': 'Әр размерден 6 жұп',
      'perSize': 6,
      'count': 4
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadCustomPresets();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _brandCtrl.dispose();
    _purchaseCtrl.dispose();
    _sellingCtrl.dispose();
    _descCtrl.dispose();
    _countryCtrl.dispose();
    super.dispose();
  }

  // ── Өз пресеттері: жүктеу/сақтау (SharedPreferences) ───────────────────
  Future<void> _loadCustomPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPresetsPref);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List)
          .map((e) => {
                'perSize': ((e as Map)['perSize'] as num).toInt(),
                'count': (e['count'] as num).toInt(),
              })
          .toList();
      if (mounted) setState(() => _customPresets = list);
    } catch (_) {}
  }

  Future<void> _persistCustomPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPresetsPref, jsonEncode(_customPresets));
    } catch (_) {}
  }

  /// Размеры для текущего выбора: для обуви зависят от пола (богаче), для
  /// остальных категорий берутся из CategoryData.
  List<String> _sizesForSelection() {
    if (_categoryKey == null) return [];
    if (_categoryKey == 'shoes') return _sizesByCat[_targetGroup] ?? [];
    return categoryByKey(_categoryKey).sizes;
  }

  /// Категория/«кому» өзгергенде әр түс вариантының размер картасын жаңа
  /// тізіммен қайта құрамыз (енгізілген сандар мүмкіндігінше сақталады).
  void _recomputeSizes() {
    final sizes = _sizesForSelection();
    _customSizes.clear();
    for (final color in _selectedColors) {
      final old = _variantSizes[color] ?? {};
      _variantSizes[color] = {for (final s in sizes) s: old[s] ?? 0};
    }
  }

  /// Түсті таңдау/алып тастау. Әр таңдалған түс — жеке вариант.
  void _toggleColor(String name) {
    setState(() {
      if (_selectedColors.contains(name)) {
        _selectedColors.remove(name);
        _variantSizes.remove(name);
        _variantImages.remove(name);
        if (_activeColor == name) {
          _activeColor =
              _selectedColors.isNotEmpty ? _selectedColors.first : null;
        }
      } else {
        _selectedColors.add(name);
        _variantSizes[name] = {
          for (final s in _sizesForSelection()) s: 0,
          for (final s in _customSizes) s: 0,
        };
        _variantImages[name] = [];
        _activeColor ??= name;
      }
    });
  }

  List<String> get _currentMaterials =>
      _categoryKey != null ? (_materialsByCategory[_categoryKey!] ?? []) : [];

  List<String> get _currentTypes =>
      _categoryKey != null ? (_typesByCategory[_categoryKey!] ?? []) : [];

  void _onCategoryKeyChanged(String key) {
    setState(() {
      _categoryKey = key;
      _type = null; // тип зависит от категории
      _targetGroup = null;
      _material = null;
      _recomputeSizes();
    });
  }

  void _onTargetGroupChanged(String group) {
    setState(() {
      _targetGroup = group;
      if (_isShoes) _recomputeSizes(); // у обуви размеры зависят от «кому»
    });
  }

  /// Пресетті БЕЛСЕНДІ түс вариантына қолданады.
  void _applyPreset(Map<String, dynamic> preset) {
    final color = _activeColor;
    if (color == null) return;
    final keys = (_variantSizes[color] ?? {}).keys.toList();
    if (keys.isEmpty) return;
    final newMap = <String, int>{for (final k in keys) k: 0};

    if (preset['kind'] == 'recommended') {
      // Барлық размерге 1, ортаңғы 2 размерге 2 жұп
      for (final k in keys) {
        newMap[k] = 1;
      }
      final mid = keys.length ~/ 2;
      if (mid - 1 >= 0) {
        newMap[keys[mid - 1]] = 2;
      }
      if (mid < keys.length) {
        newMap[keys[mid]] = 2;
      }
    } else {
      final perSize = preset['perSize'] as int;
      final count = (preset['count'] as int).clamp(0, keys.length);
      final mid = (keys.length / 2).floor();
      final start = (mid - count ~/ 2).clamp(0, keys.length - count);
      for (var i = start; i < start + count; i++) {
        newMap[keys[i]] = perSize;
      }
    }
    setState(() => _variantSizes[color] = newMap);
  }

  /// Басқа (толтырылған) варианттан белсендіге размерлерді көшіру.
  void _copySizesFrom(String donor) {
    final color = _activeColor;
    if (color == null || donor == color) return;
    setState(() =>
        _variantSizes[color] = Map<String, int>.from(_variantSizes[donor] ?? {}));
  }

  int get _totalPairs => _activeSizes.values.fold(0, (a, b) => a + b);

  // ── Дата таңдау ───────────────────────────────────────────────────────
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
            primary: cGreen,
            onPrimary: Colors.white,
            surface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dateArrived = picked);
  }

  // ── Фото ──────────────────────────────────────────────────────────────
  // Кадрды (1:1, _cropSize) қолданушы ImageCropScreen-де өзі таңдайды:
  // жылжытып/масштабтап шеттерін не төбесін кесе алады.

  // Белсенді түс вариантының бос фото орындары.
  int get _remainingSlots => _maxImages - _activeImages.length;

  Future<void> _pickFromGallery() async {
    Navigator.pop(context);
    if (_remainingSlots <= 0) {
      _err(tr('Максимум $_maxImages фото', 'Ең көбі $_maxImages фото'));
      return;
    }
    final picked = await _imagePicker.pickMultiImage(imageQuality: 90);
    if (picked.isEmpty) return;
    await _processPicked(picked);
  }

  Future<void> _pickFromCamera() async {
    Navigator.pop(context);
    if (_remainingSlots <= 0) {
      _err(tr('Максимум $_maxImages фото', 'Ең көбі $_maxImages фото'));
      return;
    }
    final shot = await _imagePicker.pickImage(
        source: ImageSource.camera, imageQuality: 90);
    if (shot == null) return;
    await _processPicked([shot]);
  }

  Future<void> _processPicked(List<XFile> picked) async {
    // Тек бос орын санынша аламыз
    final toAdd = picked.take(_remainingSlots).toList();
    final overflow = picked.length > _remainingSlots;
    for (var i = 0; i < toAdd.length; i++) {
      final raw = await toAdd[i].readAsBytes();
      if (!mounted) return;
      // Қолмен кадрлау (1:1): бас тартылса — сол сурет өткізіледі.
      final cropped = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(
          builder: (_) => ImageCropScreen(
            raw: raw,
            outputSize: _cropSize,
            title:
                toAdd.length > 1 ? tr('Фото ${i + 1} из ${toAdd.length}', 'Фото ${i + 1} / ${toAdd.length}') : null,
          ),
        ),
      );
      if (cropped != null && mounted && _activeColor != null) {
        setState(() => _variantImages[_activeColor!]!.add(cropped));
      }
    }
    if (overflow && mounted) _err(tr('Добавлено только $_remainingSlots — лимит $_maxImages фото', 'Тек $_remainingSlots қосылды — лимит $_maxImages фото'));
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
          child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          ListTile(
              leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: cGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.camera_alt_outlined,
                      color: cGreen)),
              title: Text(tr('Сфотографировать', 'Суретке түсіру'),
                  style: TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text(tr('Камера телефона', 'Телефон камерасы')),
              onTap: _pickFromCamera),
          ListTile(
              leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: cGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.photo_library_outlined,
                      color: cGreen)),
              title: Text(tr('Из галереи', 'Галереядан'),
                  style: TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text(tr('До $_remainingSlots фото сразу', 'Бірден $_remainingSlots фотоға дейін')),
              onTap: _pickFromGallery),
          const SizedBox(height: 8),
        ]),
      )),
    );
  }

  bool _validateStep() {
    if (_step == 0) {
      if (_categoryKey == null) {
        _err(tr('Выберите тип товара', 'Тауар түрін таңдаңыз'));
        return false;
      }
      if (_nameCtrl.text.trim().isEmpty) {
        _err(tr('Введите название товара', 'Тауар атауын енгізіңіз'));
        return false;
      }
      if (_brandCtrl.text.trim().isEmpty) {
        _err(tr('Введите бренд', 'Брендті енгізіңіз'));
        return false;
      }
      if (_currentTypes.isNotEmpty && _type == null) {
        _err(tr('Выберите тип товара', 'Тауар түрін таңдаңыз'));
        return false;
      }
      if (_targetGroup == null) {
        _err(tr('Выберите, кому предназначен товар', 'Тауар кімге арналғанын таңдаңыз'));
        return false;
      }
      if (_selectedColors.isEmpty) {
        _err(tr('Выберите хотя бы один цвет', 'Кемінде бір түс таңдаңыз'));
        return false;
      }
    }
    if (_step == 1) {
      if (_purchaseCtrl.text.isEmpty) {
        _err(tr('Введите закупочную цену', 'Сатып алу бағасын енгізіңіз'));
        return false;
      }
      if (_sellingCtrl.text.isEmpty) {
        _err(tr('Введите цену продажи', 'Сату бағасын енгізіңіз'));
        return false;
      }
    }
    if (_step == 2) {
      // Әр түс вариантында кемінде 1 тауар болуы керек.
      for (final color in _selectedColors) {
        if (_variantTotal(color) == 0) {
          setState(() => _activeColor = color);
          _err(tr('Укажите количество для цвета «${trValue(color)}»',
              '«${trValue(color)}» түсіне сан енгізіңіз'));
          return false;
        }
      }
    }
    if (_step == 3) {
      // Әр түс вариантына кемінде 1 фото.
      for (final color in _selectedColors) {
        if ((_variantImages[color] ?? []).isEmpty) {
          setState(() => _activeColor = color);
          _err(tr('Добавьте фото для цвета «${trValue(color)}»',
              '«${trValue(color)}» түсіне фото қосыңыз'));
          return false;
        }
      }
    }
    return true;
  }

  /// Барлық түс варианттарын кезекпен сақтайды. Әр түс — жеке товар
  /// (бар болса — жаңа партия). Қате шыққанда сәтті өткендер _savedColors-та
  /// қалады — «Сохранить» қайта басылғанда дубль жасалмайды.
  Future<void> _save() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    if (!await ensureWarehouseSelected(context)) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (!mounted) return;
    final warehouseId = context.read<WarehouseContext>().current?.id ?? '';
    final totalN = _selectedColors.length;
    String currentColor = '';
    try {
      for (final color in _selectedColors) {
        if (_savedColors.contains(color)) continue;
        currentColor = color;
        if (mounted) {
          setState(() => _savingIndex = _savedColors.length + 1);
        }

        // Бірдей товар (осы түспен) бар-жоғын тексереміз
        final existingId = await _firestoreService.findMatchingProduct(
          name: _nameCtrl.text.trim(),
          brand: _brandCtrl.text.trim(),
          type: _type ?? '',
          material: _material ?? '',
          category: _targetGroup ?? '',
          color: color,
        );

        final imageUrls = await _cloudinaryService
            .uploadBytesList(_variantImages[color] ?? []);
        final batchModel = BatchModel(
          id: '',
          dateArrived: _dateArrived,
          purchasePrice: double.tryParse(_purchaseCtrl.text) ?? 0,
          sellingPrice: double.tryParse(_sellingCtrl.text) ?? 0,
          sizesQuantity: Map.from(_variantSizes[color] ?? {}),
        );

        if (existingId != null) {
          // Бар карточкаға жаңа партия қосамыз
          await _firestoreService.addNewBatchToProduct(
            productId: existingId,
            batch: batchModel,
            dateArrived: _dateArrived,
            warehouseId: warehouseId,
          );
          if (imageUrls.isNotEmpty) {
            final oldImages = await _firestoreService.updateProductImages(
                existingId, imageUrls);
            // Ескі суреттер енді ешбір жерде қолданылмайды (DB жаңасымен
            // алмастырылды) — Cloudinary-де жетім қалмауы үшін тазалаймыз.
            final orphaned =
                oldImages.where((u) => !imageUrls.contains(u)).toList();
            if (orphaned.isNotEmpty) {
              await _cloudinaryService.deleteMany(orphaned);
            }
          }
        } else {
          // Жаңа карточка жасаймыз
          final product = ProductModel(
            id: '',
            name: _nameCtrl.text.trim(),
            brand: _brandCtrl.text.trim(),
            type: _type ?? '',
            material: _material ?? '',
            category: _targetGroup ?? '',
            categoryKey: _categoryKey ?? '',
            color: color,
            articul: '',
            status: ProductModel.statusInStock,
            images: imageUrls,
            description: _descCtrl.text.trim(),
            country: _countryCtrl.text.trim(),
            season: _season ?? '',
          );
          await _firestoreService.addNewProduct(
            product: product,
            firstBatch: batchModel,
            dateArrived: _dateArrived,
            warehouseId: warehouseId,
          );
        }
        _savedColors.add(color);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(totalN == 1
                  ? tr('Товар добавлен на склад!', 'Тауар қоймаға қосылды!')
                  : tr('$totalN цветовых варианта добавлены на склад!',
                      '$totalN түс варианты қоймаға қосылды!')),
            ),
          ]),
          backgroundColor: cGreen,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      final saved = _savedColors.length;
      _err(tr(
          'Ошибка при сохранении «${trValue(currentColor)}»: $e\nСохранено $saved из $totalN. Нажмите «Сохранить» ещё раз — готовые цвета не продублируются.',
          '«${trValue(currentColor)}» сақтау қатесі: $e\n$totalN ішінен $saved сақталды. «Сақтау» қайта басыңыз — дайын түстер қайталанбайды.'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _err(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: cRed,
      behavior: SnackBarBehavior.floating));

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final steps = [tr('Товар', 'Тауар'), tr('Цены', 'Бағалар'), tr('Размеры', 'Өлшемдер'), 'Фото'];
    return Scaffold(
      backgroundColor: cBg,
      body: SafeArea(
          child: Column(children: [
        // Header
        Container(
          decoration: const BoxDecoration(gradient: kGrad),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
              child: Column(children: [
                Row(children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
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
                    child: Text(tr('Новый товар', 'Жаңа тауар'),
                        style: manrope(23, FontWeight.w800,
                            color: Colors.white, letterSpacing: -0.5)),
                  ),
                  if (_isLoading)
                    const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                  else
                    GestureDetector(
                      onTap: () {
                        if (!_validateStep()) return;
                        if (_step < 3) {
                          setState(() => _step++);
                        } else {
                          _save();
                        }
                      },
                      child: Text(
                        _step < 3 ? tr('Далее →', 'Әрі қарай →') : tr('Сохранить', 'Сақтау'),
                        style: manrope(14.5, FontWeight.w700,
                            color: Colors.white),
                      ),
                    ),
                ]),
                const SizedBox(height: 14),
                Row(
                    children: List.generate(steps.length, (i) {
              final done = i < _step;
              final active = i == _step;
              return Expanded(
                  child: Row(children: [
                Expanded(
                    child: GestureDetector(
                  onTap: () {
                    if (i < _step) setState(() => _step = i);
                  },
                  child: Column(children: [
                    AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: active ? 32 : 26,
                        height: active ? 32 : 26,
                        decoration: BoxDecoration(
                            color: done
                                ? cGreen
                                : active
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                            border: active
                                ? null
                                : Border.all(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    width: 1.5)),
                        child: Center(
                            child: done
                                ? const Icon(Icons.check,
                                    color: Colors.white, size: 14)
                                : Text('${i + 1}',
                                    style: TextStyle(
                                        color: active
                                            ? cGreen
                                            : Colors.white,
                                        fontSize: active ? 13 : 11,
                                        fontWeight: FontWeight.w700)))),
                    const SizedBox(height: 4),
                    Text(steps[i],
                        style: TextStyle(
                            color: active
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.5),
                            fontSize: 10,
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w400)),
                  ]),
                )),
                if (i < steps.length - 1)
                  Container(
                      height: 1.5,
                      width: 20,
                      color: i < _step
                          ? cGreen
                          : Colors.white.withValues(alpha: 0.25)),
              ]));
            })),
          ]),
            ),
          ),
        ),

        // Content
        Expanded(
            child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: KeyedSubtree(key: ValueKey(_step), child: _buildStep()),
          ),
        )),

        // Bottom buttons
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(color: Colors.white, boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, -3))
          ]),
          child: Row(children: [
            if (_step > 0)
              Expanded(
                  flex: 1,
                  child: OutlinedButton(
                      onPressed: () => setState(() => _step--),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: cLine),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: Text(tr('Назад', 'Артқа'),
                          style: TextStyle(color: cInk2)))),
            if (_step > 0) const SizedBox(width: 12),
            Expanded(
                flex: 2,
                child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            if (!_validateStep()) return;
                            if (_step < 3) {
                              setState(() => _step++);
                            } else {
                              _save();
                            }
                          },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: cGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0),
                    child: Text(
                        _isLoading && _step == 3
                            ? (_selectedColors.length > 1
                                ? tr('Сохранение $_savingIndex/${_selectedColors.length}…',
                                    'Сақталуда $_savingIndex/${_selectedColors.length}…')
                                : tr('Сохранение…', 'Сақталуда…'))
                            : _step == 3
                                ? (_selectedColors.length > 1
                                    ? tr('Сохранить ${_selectedColors.length} варианта',
                                        '${_selectedColors.length} вариантты сақтау')
                                    : tr('Сохранить товар', 'Тауарды сақтау'))
                                : tr('Далее →', 'Әрі қарай →'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)))),
          ]),
        ),
      ])),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _buildStepInfo();
      case 1:
        return _buildStepPrices();
      case 2:
        return _buildStepSizes();
      case 3:
        return _buildStepPhotos();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Шаг 1: Информация о товаре ────────────────────────────────────────
  Widget _buildStepInfo() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _StepHeader(
            icon: Icons.label_outline,
            title: tr('Информация о товаре', 'Тауар туралы ақпарат'),
            subtitle: tr('Название, бренд и характеристики', 'Атауы, бренді және сипаттамалары')),
        const SizedBox(height: 20),
        _Field(
            controller: _nameCtrl,
            label: tr('Название товара', 'Тауар атауы'),
            hint: tr('Напр: Nike Air Max 270', 'Мыс: Nike Air Max 270'),
            icon: Icons.inventory_2_outlined),
        const SizedBox(height: 12),
        _Field(
            controller: _brandCtrl,
            label: 'Бренд',
            hint: tr('Напр: Nike, Adidas, New Balance', 'Мыс: Nike, Adidas, New Balance'),
            icon: Icons.workspace_premium_outlined),
        const SizedBox(height: 16),
        _Label(tr('Категория товара *', 'Тауар категориясы *')),
        const SizedBox(height: 8),
        _buildCategoryTypePicker(),
        if (_categoryKey != null && _currentTypes.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Label(tr('Тип товара *', 'Тауар түрі *')),
          const SizedBox(height: 8),
          _buildTypeDropdown(),
        ],
        if (_categoryKey != null) ...[
          const SizedBox(height: 16),
          _Label(tr('Кому *', 'Кімге *')),
          const SizedBox(height: 8),
          _buildTargetGroupPicker(),
        ],
        const SizedBox(height: 16),
        _Label(tr('Цвет *', 'Түсі *')),
        const SizedBox(height: 10),
        _buildColorPicker(),
        if (_categoryKey != null && _currentMaterials.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Label(tr('Материал (необязательно)', 'Материал (міндетті емес)')),
          const SizedBox(height: 8),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Списка может не хватать — своё значение тоже показываем.
                ...[
                  ..._currentMaterials,
                  if (_material != null &&
                      !_currentMaterials.contains(_material))
                    _material!,
                ].map((m) => _SelectChip(
                    label: trValue(m),
                    selected: _material == m,
                    onTap: () =>
                        setState(() => _material = _material == m ? null : m))),
                _SelectChip(
                    label: tr('✏️ Свой', '✏️ Өз нұсқасы'),
                    selected: false,
                    onTap: _promptCustomMaterial),
              ]),
        ],
        const SizedBox(height: 16),
        _Label(tr('Сезон (необязательно)', 'Сезон (міндетті емес)')),
        const SizedBox(height: 8),
        Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kSeasons
                .map((s) => _SelectChip(
                    label: '${_seasonIcons[s] ?? ''} ${trValue(s)}',
                    selected: _season == s,
                    onTap: () =>
                        setState(() => _season = _season == s ? null : s)))
                .toList()),
        const SizedBox(height: 16),
        _Field(
            controller: _countryCtrl,
            label: tr('Страна производства (необязательно)', 'Өндірілген ел (міндетті емес)'),
            hint: tr('Напр: Вьетнам, Китай, Турция', 'Мыс: Вьетнам, Қытай, Түркия'),
            icon: Icons.public_outlined),
        const SizedBox(height: 12),
        TextFormField(
            controller: _descCtrl,
            maxLines: 4,
            minLines: 3,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 15, color: cInk),
            decoration: InputDecoration(
                labelText: tr('Описание (необязательно)', 'Сипаттама (міндетті емес)'),
                alignLabelWithHint: true,
                hintText: tr('Расскажите о товаре: посадка, особенности, с чем носить…', 'Тауар туралы айтыңыз: пішімі, ерекшеліктері, немен киюге болады…'),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: cLine)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: cLine)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: cGreen, width: 1.5)))),
      ]);

  static const Map<String, String> _seasonIcons = {
    'Лето': '☀️',
    'Зима': '❄️',
    'Осень': '🍂',
    'Весна': '🌱',
  };

  Future<void> _promptCustomMaterial() async {
    final value = await promptTextDialog(
      context,
      title: tr('Свой материал', 'Өз материалы'),
      hint: tr('Например: Нубук', 'Мысалы: Нубук'),
      initial: _currentMaterials.contains(_material) ? '' : (_material ?? ''),
    );
    if (value != null && mounted) setState(() => _material = value);
  }

  Widget _buildColorPicker() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Көп түс таңдауға болады — әр түс жеке вариант болып сақталады.
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: cBlueTint,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          const Icon(Icons.palette_outlined, size: 16, color: cBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _selectedColors.length <= 1
                  ? tr('Можно выбрать несколько цветов — каждый станет отдельным вариантом с своими размерами и фото',
                      'Бірнеше түс таңдауға болады — әрқайсысы өз размерлері мен фотосы бар жеке вариант болады')
                  : tr('Выбрано ${_selectedColors.length} цвета — размеры и фото укажете для каждого',
                      '${_selectedColors.length} түс таңдалды — размерлер мен фотоны әрқайсысына бөлек енгізесіз'),
              style: manrope(11.5, FontWeight.w600, color: cBlue),
            ),
          ),
        ]),
      ),
      _buildColorWrap(),
    ]);
  }

  Widget _buildColorWrap() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: ProductModel.colorOptions.map((opt) {
        final name = opt['name'] as String;
        final hexValue = opt['hex'] as int;
        final color = Color(hexValue);
        final selected = _selectedColors.contains(name);
        final isLight = color.computeLuminance() > 0.7;
        return GestureDetector(
          onTap: () => _toggleColor(name),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? color : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? color : cLine,
                width: selected ? 2 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                          color: color.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3))
                    ]
                  : [],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color:
                          isLight ? Colors.grey.shade300 : Colors.transparent,
                      width: 1),
                ),
              ),
              const SizedBox(width: 7),
              Text(trValue(name),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? (isLight ? cInk : Colors.white)
                        : cInk2,
                  )),
              if (selected) ...[
                const SizedBox(width: 5),
                Icon(Icons.check_rounded,
                    size: 14, color: isLight ? cInk : Colors.white),
              ],
            ]),
          ),
        );
      }).toList(),
    );
  }

  // Выбор типа товара (8 категорий)
  Widget _buildCategoryTypePicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kCategories.map((c) {
        final isOn = _categoryKey == c.key;
        final tone = toneFor(c.tone);
        return GestureDetector(
          onTap: () => _onCategoryKeyChanged(c.key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.fromLTRB(10, 8, 13, 8),
            decoration: BoxDecoration(
              color: isOn ? tone.tint : Colors.white,
              border: Border.all(
                  color: isOn ? tone.deep : cLine, width: 1.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              CategoryIcon(
                  kind: c.iconKey,
                  size: 15,
                  color: isOn ? tone.deep : cInk3),
              const SizedBox(width: 6),
              Text(c.short,
                  style: manrope(12.5, FontWeight.w700,
                      color: isOn ? tone.deep : cInk2)),
            ]),
          ),
        );
      }).toList(),
    );
  }

  // Сентинель пункта «Свой вариант» в дропдауне типа.
  static const String _customTypeOption = '__custom__';
  // Дропдаун ішкі state-ін жаңарту үшін (сентинель таңдалғаннан кейін
  // initialValue қайта қолданылсын деп key өзгертіледі).
  int _typeFieldNonce = 0;

  Future<void> _promptCustomType() async {
    final value = await promptTextDialog(
      context,
      title: tr('Свой тип товара', 'Өз тауар түрі'),
      hint: tr('Например: Мокасины', 'Мысалы: Мокасиндер'),
      initial: _currentTypes.contains(_type) ? '' : (_type ?? ''),
    );
    if (!mounted) return;
    setState(() {
      _typeFieldNonce++;
      if (value != null) _type = value;
    });
  }

  // Тип товара (вид/модель) — зависит от выбранной категории.
  // Списка может не хватать — пункт «Свой вариант» позволяет вписать своё.
  Widget _buildTypeDropdown() {
    final types = [
      ..._currentTypes,
      if (_type != null && _type!.isNotEmpty && !_currentTypes.contains(_type))
        _type!,
    ];
    return DropdownButtonFormField<String>(
      key: ValueKey('type-$_typeFieldNonce-$_type'),
      initialValue: types.contains(_type) ? _type : null,
      isExpanded: true,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        hintText: tr('Выберите тип', 'Түрін таңдаңыз'),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: cLine)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: cLine)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: cGreen, width: 1.5)),
      ),
      items: [
        ...types.map(
            (e) => DropdownMenuItem(value: e, child: Text(trValue(e)))),
        DropdownMenuItem(
          value: _customTypeOption,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.edit_outlined, size: 16, color: cGreen),
            const SizedBox(width: 6),
            Text(tr('Свой вариант…', 'Өз нұсқасы…'),
                style: const TextStyle(
                    color: cGreen, fontWeight: FontWeight.w600)),
          ]),
        ),
      ],
      onChanged: (v) {
        if (v == _customTypeOption) {
          _promptCustomType();
        } else {
          setState(() => _type = v);
        }
      },
    );
  }

  // Кому — единый список для всех категорий.
  Widget _buildTargetGroupPicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _targetGroups
          .map((g) => _SelectChip(
              label: '${_targetGroupIcons[g] ?? ''} ${trValue(g)}',
              selected: _targetGroup == g,
              onTap: () => _onTargetGroupChanged(g)))
          .toList(),
    );
  }

  // ── Шаг 2: Цены ───────────────────────────────────────────────────────
  Widget _buildStepPrices() {
    final purchase = double.tryParse(_purchaseCtrl.text) ?? 0;
    final selling = double.tryParse(_sellingCtrl.text) ?? 0;
    final margin = selling > 0 && purchase > 0
        ? ((selling - purchase) / purchase * 100)
        : 0.0;
    final profit = selling - purchase;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _StepHeader(
          icon: Icons.monetization_on_outlined,
          title: tr('Ценообразование', 'Баға белгілеу'),
          subtitle: tr('Закупочная и продажная цена', 'Сатып алу және сату бағасы')),
      const SizedBox(height: 20),

      // Дата поставки
      GestureDetector(
        onTap: _pickDate,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cLine)),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: cGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.calendar_today_outlined,
                    color: cGreen, size: 18)),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Дата поставки', 'Жеткізілім күні'),
                  style: TextStyle(
                      fontSize: 12,
                      color: cInk2,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(
                  '${_dateArrived.day.toString().padLeft(2, '0')}.${_dateArrived.month.toString().padLeft(2, '0')}.${_dateArrived.year}',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: cInk)),
            ]),
            const Spacer(),
            const Icon(Icons.edit_outlined, color: cGreen, size: 18),
          ]),
        ),
      ),
      const SizedBox(height: 12),

      // Закупочная
      Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cLine)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: cRedTint,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.arrow_downward_rounded,
                      color: cRed, size: 18)),
              const SizedBox(width: 10),
              Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Закупочная цена', 'Сатып алу бағасы'),
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: cInk)),
                    Text(tr('Сколько заплатили за партию', 'Партияға қанша төледіңіз'),
                        style: TextStyle(
                            fontSize: 11, color: cInk2)),
                  ]),
            ]),
            const SizedBox(height: 12),
            TextField(
                controller: _purchaseCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                ],
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: cInk),
                decoration: const InputDecoration(
                    hintText: '0',
                    hintStyle:
                        TextStyle(color: cInk3, fontSize: 22),
                    suffixText: '₸',
                    suffixStyle:
                        TextStyle(fontSize: 18, color: cInk2),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero)),
          ])),
      const SizedBox(height: 12),

      // Цена продажи
      Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cLine)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: cGreenTint,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.arrow_upward_rounded,
                      color: cGreen, size: 18)),
              const SizedBox(width: 10),
              Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Цена продажи', 'Сату бағасы'),
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: cInk)),
                    Text(tr('По какой цене будете продавать', 'Қандай бағамен сатасыз'),
                        style: TextStyle(
                            fontSize: 11, color: cInk2)),
                  ]),
            ]),
            const SizedBox(height: 12),
            TextField(
                controller: _sellingCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                ],
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: cInk),
                decoration: const InputDecoration(
                    hintText: '0',
                    hintStyle:
                        TextStyle(color: cInk3, fontSize: 22),
                    suffixText: '₸',
                    suffixStyle:
                        TextStyle(fontSize: 18, color: cInk2),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero)),
          ])),
      const SizedBox(height: 16),

      if (purchase > 0 && selling > 0)
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: profit >= 0 ? cGreenTint : cRedTint,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: profit >= 0
                      ? cGreen.withValues(alpha: 0.3)
                      : cRed.withValues(alpha: 0.2))),
          child: Row(children: [
            Icon(
                profit >= 0
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                color: profit >= 0 ? cGreen : cRed,
                size: 24),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Маржа с одного товара', 'Бір тауардан маржа'),
                  style: TextStyle(
                      fontSize: 12,
                      color: profit >= 0 ? cGreen : cRed)),
              Text(
                  '${profit >= 0 ? "+" : ""}${profit.toStringAsFixed(0)} ₸  '
                  '(${margin.toStringAsFixed(1)}%)',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: profit >= 0
                          ? const Color(0xFF065F46)
                          : cRed)),
            ]),
          ]),
        ),
    ]);
  }

  void _addCustomSize() {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Свой размер', 'Өз өлшемі'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: tr('Например: 42', 'Мысалы: 42'),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Отмена', 'Бас тарту'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cGreen, foregroundColor: Colors.white),
            onPressed: () {
              final size = ctrl.text.trim();
              Navigator.pop(ctx);
              if (size.isEmpty) return;
              if (_activeSizes.containsKey(size)) {
                _showSizeInputSheet(size, _activeSizes[size] ?? 0);
                return;
              }
              // Өз размері БАРЛЫҚ түс варианттарына қосылады (кілт ортақ).
              setState(() {
                _customSizes.add(size);
                for (final c in _selectedColors) {
                  _variantSizes[c] = {...?_variantSizes[c], size: 0};
                }
              });
              _showSizeInputSheet(size, 0);
            },
            child: Text(tr('Добавить', 'Қосу')),
          ),
        ],
      ),
    );
  }

  void _showSizeInputSheet(String size, int currentQty) {
    int tempQty = currentQty;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                    color: cLine, borderRadius: BorderRadius.circular(2))),
            Text(tr('Размер ${trValue(size)}', 'Өлшем ${trValue(size)}'),
                style: manrope(17, FontWeight.w700, color: cInk)),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              GestureDetector(
                onTap: () { if (tempQty > 0) setS(() => tempQty--); },
                child: Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                        color: tempQty > 0 ? cGreenTint : cLine2,
                        borderRadius: BorderRadius.circular(14)),
                    child: Icon(Icons.remove_rounded,
                        color: tempQty > 0 ? cGreen : cInk3, size: 22)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Text('$tempQty',
                    style: manrope(34, FontWeight.w800, color: cInk,
                        letterSpacing: -1)),
              ),
              GestureDetector(
                onTap: () => setS(() => tempQty++),
                child: Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                        color: cGreen,
                        borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.add_rounded,
                        color: Colors.white, size: 22)),
              ),
            ]),
            const SizedBox(height: 8),
            Text(tr('шт.', 'дана'), style: manrope(13, FontWeight.w500, color: cInk3)),
            const SizedBox(height: 24),
            QPrimaryButton(
              label: tr('Готово', 'Дайын'),
              onPressed: () {
                final color = _activeColor;
                if (color != null) {
                  setState(() => _variantSizes[color]![size] = tempQty);
                }
                Navigator.pop(ctx);
              },
            ),
          ]),
        ),
      ),
    );
  }

  // ── Түс табтары (Размеры/Фото қадамдары; >1 түс болғанда) ─────────────
  Widget _buildColorTabs({required bool photosStep}) {
    if (_selectedColors.length <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        height: 42,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: _selectedColors.map((name) {
            final active = name == _activeColor;
            final dot = ProductModel.colorHex(name) ?? const Color(0xFFBDBDBD);
            final count = photosStep
                ? (_variantImages[name] ?? []).length
                : _variantTotal(name);
            final done = count > 0;
            return GestureDetector(
              onTap: () => setState(() => _activeColor = name),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: active ? cGreenTint : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: active ? cGreen : cLine, width: 1.5),
                ),
                child: Row(children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color(0xFFE0E0E0), width: 1),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(trValue(name),
                      style: manrope(12.5, FontWeight.w700,
                          color: active ? cGreenDeep : cInk2)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: done ? cGreen : cRedTint,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      photosStep
                          ? (done ? '$count 📷' : '0')
                          : (done ? tr('$count шт', '$count дана') : '0'),
                      style: manrope(10, FontWeight.w800,
                          color: done ? Colors.white : cRed),
                    ),
                  ),
                ]),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Өз пресетін қосу диалогы ──────────────────────────────────────────
  Future<void> _promptAddPreset() async {
    final perCtrl = TextEditingController();
    final cntCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Свой пресет', 'Өз пресеті'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              tr('Быстрое заполнение: сколько штук на размер и на сколько размеров (от середины сетки).',
                  'Жылдам толтыру: әр размерге неше дана және неше размерге (тор ортасынан).'),
              style: manrope(12.5, FontWeight.w500, color: cInk2)),
          const SizedBox(height: 14),
          TextField(
            controller: perCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: tr('Штук на размер', 'Әр размерге дана'),
              hintText: tr('Напр: 6', 'Мыс: 6'),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: cntCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: tr('Сколько размеров', 'Неше размер'),
              hintText: tr('Напр: 4', 'Мыс: 4'),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Отмена', 'Бас тарту'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cGreen, foregroundColor: Colors.white),
            onPressed: () {
              final per = int.tryParse(perCtrl.text.trim()) ?? 0;
              final cnt = int.tryParse(cntCtrl.text.trim()) ?? 0;
              Navigator.pop(ctx);
              if (per < 1 || cnt < 1) return;
              setState(() =>
                  _customPresets.add({'perSize': per, 'count': cnt}));
              _persistCustomPresets();
            },
            child: Text(tr('Сохранить', 'Сақтау')),
          ),
        ],
      ),
    );
  }

  // Пресет карточкасы (ені бірдей; custom-да ✕ өшіру батырмасы бар).
  Widget _presetCard({
    required String label,
    required String desc,
    required VoidCallback onTap,
    bool recommended = false,
    VoidCallback? onDelete,
  }) {
    return Stack(clipBehavior: Clip.none, children: [
      GestureDetector(
          onTap: onTap,
          child: Container(
              width: 160,
              height: 76,
              margin: const EdgeInsets.only(right: 10, top: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: recommended
                      ? cGreen.withValues(alpha: 0.06)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: recommended
                          ? cGreen.withValues(alpha: 0.4)
                          : cGreen.withValues(alpha: 0.1))),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (recommended)
                      Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: cGreen,
                              borderRadius: BorderRadius.circular(4)),
                          child: Text(tr('РЕКОМЕНДУЕТСЯ', 'ҰСЫНЫЛАДЫ'),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700))),
                    Text(label,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cGreen),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(desc,
                        style:
                            const TextStyle(fontSize: 10, color: cInk2)),
                  ]))),
      if (onDelete != null)
        Positioned(
          top: -2,
          right: 4,
          child: GestureDetector(
            onTap: onDelete,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration:
                  const BoxDecoration(color: cRed, shape: BoxShape.circle),
              child: const Icon(Icons.close, color: Colors.white, size: 10),
            ),
          ),
        ),
    ]);
  }

  // ── Шаг 3: Размеры ────────────────────────────────────────────────────
  Widget _buildStepSizes() {
    if (_selectedColors.isEmpty || _activeColor == null) {
      return Center(
          child: Column(children: [
        const SizedBox(height: 40),
        const Icon(Icons.arrow_back, size: 48, color: cInk3),
        const SizedBox(height: 12),
        Text(tr('Вернитесь и выберите тип товара и цвет', 'Артқа оралып, тауар түрі мен түсін таңдаңыз'),
            style: const TextStyle(color: cInk2, fontSize: 15)),
        const SizedBox(height: 16),
        ElevatedButton(
            onPressed: () => setState(() => _step = 0),
            child: Text(tr('← Шаг 1', '← 1-қадам'))),
      ]));
    }

    final activeColor = _activeColor!;
    final keys = _activeSizes.keys.toList();
    final catLabel = _isShoes
        ? (_targetGroup ?? '')
        : categoryByKey(_categoryKey).name;
    final multi = _selectedColors.length > 1;
    // Көшіруге болатын донор: белсенді бос, басқасында сан бар.
    String? donor;
    if (multi && _variantTotal(activeColor) == 0) {
      for (final c in _selectedColors) {
        if (c != activeColor && _variantTotal(c) > 0) {
          donor = c;
          break;
        }
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _StepHeader(
          icon: Icons.straighten_outlined,
          title: tr('Размеры и количество', 'Өлшемдер мен саны'),
          subtitle: tr('$catLabel · ${keys.length} размеров', '$catLabel · ${keys.length} өлшем')),
      const SizedBox(height: 16),
      // Түс табтары (әр түстің өз размерлері)
      _buildColorTabs(photosStep: false),
      Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF00A862), Color(0xFF3B5FCC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            const Icon(Icons.inventory_2_outlined,
                color: Colors.white70, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                  multi
                      ? tr('${trValue(activeColor)}:', '${trValue(activeColor)}:')
                      : tr('Итого в партии:', 'Партияда барлығы:'),
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
            Text(tr('$_totalPairs шт.', '$_totalPairs дана'),
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20)),
            if (multi) ...[
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                    tr('Всего: $_grandTotal', 'Барлығы: $_grandTotal'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
              ),
            ],
          ])),
      // Донордан көшіру (уақыт үнемдеу: размерлер жиі бірдей болады)
      if (donor != null) ...[
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => _copySizesFrom(donor!),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: cBlueTint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cBlue.withValues(alpha: 0.3)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.copy_rounded, size: 15, color: cBlue),
              const SizedBox(width: 8),
              Text(
                  tr('Скопировать размеры с «${trValue(donor)}»',
                      '«${trValue(donor)}» размерлерін көшіру'),
                  style: manrope(13, FontWeight.w700, color: cBlue)),
            ]),
          ),
        ),
      ],
      const SizedBox(height: 14),
      _Label(tr('⚡ Быстрое заполнение', '⚡ Жылдам толтыру')),
      const SizedBox(height: 8),
      SizedBox(
          height: 84,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              ..._presets.map((p) => _presetCard(
                    label: tr(p['labelRu'] as String, p['labelKk'] as String),
                    desc: tr(p['descRu'] as String, p['descKk'] as String),
                    recommended: p['kind'] == 'recommended',
                    onTap: () => _applyPreset(p),
                  )),
              // Өз пресеттері (өшіруге болады)
              ...List.generate(_customPresets.length, (i) {
                final p = _customPresets[i];
                final per = p['perSize']!;
                final cnt = p['count']!;
                return _presetCard(
                  label: tr('${per * cnt} шт · $cnt размера',
                      '${per * cnt} дана · $cnt размер'),
                  desc: tr('По $per шт с размера', 'Әр размерден $per дана'),
                  onTap: () => _applyPreset({'perSize': per, 'count': cnt}),
                  onDelete: () {
                    setState(() => _customPresets.removeAt(i));
                    _persistCustomPresets();
                  },
                );
              }),
              // «+ Свой пресет»
              GestureDetector(
                onTap: _promptAddPreset,
                child: Container(
                    width: 110,
                    height: 76,
                    margin: const EdgeInsets.only(right: 10, top: 4),
                    decoration: BoxDecoration(
                        color: cGreenTint,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: cGreen.withValues(alpha: 0.35),
                            width: 1.2)),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_rounded,
                              color: cGreen, size: 22),
                          const SizedBox(height: 4),
                          Text(tr('Свой пресет', 'Өз пресеті'),
                              style: manrope(11, FontWeight.w700,
                                  color: cGreen)),
                        ])),
              ),
            ],
          )),
      const SizedBox(height: 14),
      Row(children: [
        _Label(tr('Размеры', 'Өлшемдер')),
        const Spacer(),
        GestureDetector(
            onTap: _addCustomSize,
            child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: cGreenTint,
                    borderRadius: BorderRadius.circular(6)),
                child: Text(tr('+ Свой размер', '+ Өз өлшемі'),
                    style: TextStyle(
                        fontSize: 11,
                        color: cGreen,
                        fontWeight: FontWeight.w600)))),
        GestureDetector(
            onTap: () => setState(() =>
                _variantSizes[activeColor] = {for (final k in keys) k: 0}),
            child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: cRedTint,
                    borderRadius: BorderRadius.circular(6)),
                child: Text(tr('Сбросить', 'Тазарту'),
                    style: TextStyle(
                        fontSize: 11,
                        color: cRed,
                        fontWeight: FontWeight.w600)))),
      ]),
      const SizedBox(height: 8),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisExtent: 56,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8),
        itemCount: keys.length,
        itemBuilder: (_, i) {
          final size = keys[i];
          final qty = _activeSizes[size] ?? 0;
          final isCustom = _customSizes.contains(size);
          return Stack(clipBehavior: Clip.none, children: [
            GestureDetector(
              onTap: () => _showSizeInputSheet(size, qty),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                    color: qty > 0 ? cGreenTint : cSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: qty > 0 ? cGreen : cLine,
                        width: 1.5)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(size,
                        style: manrope(15, FontWeight.w800, color: cInk)),
                    Text(tr('$qty шт.', '$qty дана'),
                        style: manrope(11, FontWeight.w700,
                            color: qty > 0 ? cGreen : cInk3)),
                  ],
                ),
              ),
            ),
            if (isCustom)
              Positioned(
                top: -6,
                right: -6,
                child: GestureDetector(
                  onTap: () => setState(() {
                    // Ортақ кілт — барлық варианттан өшіреміз.
                    _customSizes.remove(size);
                    for (final c in _selectedColors) {
                      _variantSizes[c]?.remove(size);
                    }
                  }),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        color: cRed, shape: BoxShape.circle),
                    child: const Icon(Icons.close,
                        color: Colors.white, size: 11),
                  ),
                ),
              ),
          ]);
        },
      ),
    ]);
  }

  // ── Шаг 4: Фото ───────────────────────────────────────────────────────
  Widget _buildStepPhotos() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _StepHeader(
            icon: Icons.photo_library_outlined,
            title: tr('Фотографии товара', 'Тауар фотосуреттері'),
            subtitle: _selectedColors.length > 1
                ? tr('Для каждого цвета · до $_maxImages фото · кадр 1:1',
                    'Әр түске бөлек · $_maxImages фотоға дейін · кадр 1:1')
                : tr('Минимум 1, максимум $_maxImages фото · авто-кадр 1:1', 'Кемінде 1, ең көбі $_maxImages фото · авто-кадр 1:1')),
        const SizedBox(height: 20),
        // Түс табтары (әр түстің өз фотолары)
        _buildColorTabs(photosStep: true),
        if (_remainingSlots > 0)
          GestureDetector(
            onTap: _showImageOptions,
            child: Container(
                width: double.infinity,
                height: 100,
                decoration: BoxDecoration(
                    color: cGreenTint,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: cGreen.withValues(alpha: 0.3),
                        width: 1.5)),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_a_photo_outlined,
                          size: 32, color: cGreen),
                      const SizedBox(height: 8),
                      Text(tr('Добавить фото', 'Фото қосу'),
                          style: TextStyle(
                              color: cGreen,
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                      Text(tr('Можно выбрать до $_remainingSlots сразу', 'Бірден $_remainingSlots дейін таңдауға болады'),
                          style: const TextStyle(color: cInk3, fontSize: 11)),
                    ])),
          ),
        if (_remainingSlots > 0) const SizedBox(height: 16),
        if (_activeImages.isNotEmpty) ...[
          Text(
              _selectedColors.length > 1
                  ? tr('${trValue(_activeColor ?? '')}: ${_activeImages.length} / $_maxImages фото',
                      '${trValue(_activeColor ?? '')}: ${_activeImages.length} / $_maxImages фото')
                  : tr('Добавлено: ${_activeImages.length} / $_maxImages фото', 'Қосылды: ${_activeImages.length} / $_maxImages фото'),
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: cInk)),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1),
            itemCount: _activeImages.length,
            itemBuilder: (_, i) {
              return Stack(children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(_activeImages[i],
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity)),
                Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                        onTap: () => setState(() =>
                            _variantImages[_activeColor]?.removeAt(i)),
                        child: Container(
                            decoration: const BoxDecoration(
                                color: Colors.red, shape: BoxShape.circle),
                            padding: const EdgeInsets.all(4),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 14)))),
                if (i == 0)
                  Positioned(
                      bottom: 4,
                      left: 4,
                      child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: cGreen,
                              borderRadius: BorderRadius.circular(4)),
                          child: Text(tr('Главное', 'Басты'),
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700)))),
              ]);
            },
          ),
        ],
        const SizedBox(height: 20),
        Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cLine)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Итоговые данные товара', 'Тауардың қорытынды деректері'),
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: cInk)),
              const SizedBox(height: 12),
              _SummaryRow(
                  label: tr('Название', 'Атауы'),
                  value: _nameCtrl.text.isEmpty ? '—' : _nameCtrl.text),
              _SummaryRow(
                  label: 'Бренд',
                  value: _brandCtrl.text.isEmpty ? '—' : _brandCtrl.text),
              _SummaryRow(
                  label: 'Категория',
                  value: _categoryKey == null
                      ? '—'
                      : categoryByKey(_categoryKey).name),
              _SummaryRow(label: tr('Тип товара', 'Тауар түрі'), value: _type == null ? '—' : trValue(_type!)),
              _SummaryRow(label: tr('Кому', 'Кімге'), value: _targetGroup == null ? '—' : trValue(_targetGroup!)),
              _SummaryRow(
                  label: _selectedColors.length > 1 ? tr('Цвета', 'Түстері') : tr('Цвет', 'Түсі'),
                  value: _selectedColors.isEmpty
                      ? '—'
                      : _selectedColors.map(trValue).join(', ')),
              _SummaryRow(
                  label: tr('Дата поставки', 'Жеткізілім күні'),
                  value:
                      '${_dateArrived.day.toString().padLeft(2, '0')}.${_dateArrived.month.toString().padLeft(2, '0')}.${_dateArrived.year}'),
              _SummaryRow(
                  label: tr('Закуп / Продажа', 'Сатып алу / Сату'),
                  value: '${_purchaseCtrl.text} ₸ / ${_sellingCtrl.text} ₸'),
              // Әр түстің саны бөлек көрсетіледі (көп түс болғанда)
              if (_selectedColors.length > 1)
                ..._selectedColors.map((c) => _SummaryRow(
                    label: '· ${trValue(c)}',
                    value: tr('${_variantTotal(c)} шт. · ${(_variantImages[c] ?? []).length} фото',
                        '${_variantTotal(c)} дана · ${(_variantImages[c] ?? []).length} фото'))),
              _SummaryRow(label: tr('Всего товаров', 'Барлық тауар'), value: tr('$_grandTotal шт.', '$_grandTotal дана')),
            ])),
      ]);
}

// ─── Helper widgets ───────────────────────────────────────────────────────────
class _StepHeader extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  const _StepHeader(
      {required this.icon, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: cGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: cGreen, size: 22)),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: cInk)),
          Text(subtitle,
              style:
                  const TextStyle(fontSize: 12, color: cInk2)),
        ]),
      ]);
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: cInk2));
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label, hint;
  final IconData icon;
  const _Field(
      {required this.controller,
      required this.label,
      required this.hint,
      required this.icon});
  @override
  Widget build(BuildContext context) => TextFormField(
      controller: controller,
      style: const TextStyle(fontSize: 15, color: cInk),
      decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: cGreen, size: 20),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: cLine)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: cLine)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: cGreen, width: 1.5))));
}

class _SelectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SelectChip(
      {required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
              color: selected ? cGreen : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: selected ? cGreen : cLine,
                  width: selected ? 1.5 : 1)),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : cInk2))));
}

class _SummaryRow extends StatelessWidget {
  final String label, value;
  const _SummaryRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Text(label,
            style:
                const TextStyle(fontSize: 13, color: cInk2)),
        const Spacer(),
        Text(value,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cInk)),
      ]));
}

