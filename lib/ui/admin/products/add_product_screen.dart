import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/warehouse_context.dart';
import '../../../data/models/models.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/cloudinary_service.dart';
import '../../../theme/qoima_design.dart';
import '../../shared/mandatory_warehouse_picker.dart';
import '../../widgets/image_crop_screen.dart';

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

  String? _type;
  String? _material;
  String? _targetGroup; // кому: Мужские|Женские|Унисекс|Детские
  String? _categoryKey; // категория товара v2 (shoes|tshirt|...)
  String? _color;
  DateTime _dateArrived = DateTime.now();

  bool get _isShoes => _categoryKey == 'shoes';

  // Алдын ала квадратқа (1:1) қиылған фото bytes. Каталог біркелкі көріну үшін.
  final List<Uint8List> _imageBytes = [];
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

  Map<String, int> _sizesQuantity = {};

  // Тип товара (вид/модель) для каждой категории — источник истины для дропдауна.
  static const Map<String, List<String>> _typesByCategory = {
    'shoes': ['Туфли', 'Кеды', 'Кроссовки', 'Ботинки', 'Сланцы', 'Босоножки'],
    'tshirt': ['Футболка', 'Оверсайз', 'Поло', 'Базовая', 'С принтом'],
    'outer': ['Куртка', 'Пуховик', 'Ветровка', 'Пальто', 'Худи'],
    'caps': ['Кепка', 'Шапка', 'Панама', 'Бини'],
    'pants': ['Джинсы', 'Карго', 'Шорты', 'Спортивные'],
    'dress': ['Платье', 'Юбка', 'Сарафан'],
    'acc': ['Ремень', 'Сумка', 'Очки', 'Кошелек'],
    'sport': ['Спортивный костюм', 'Леггинсы', 'Топ', 'Шорты'],
  };

  // Кому — единый список для всех категорий.
  static const List<String> _targetGroups = [
    'Мужские',
    'Женские',
    'Унисекс',
    'Детские',
  ];
  static const Map<String, String> _targetGroupIcons = {
    'Мужские': '👨',
    'Женские': '👩',
    'Унисекс': '👫',
    'Детские': '🧸',
  };
  static const Map<String, List<String>> _materialsByCategory = {
    'shoes':  ['Кожа', 'Экокожа', 'Замша', 'Текстиль', 'Резина', 'Синтетика'],
    'tshirt': ['Хлопок', 'Полиэстер', 'Трикотаж', 'Вискоза', 'Лён', 'Синтетика'],
    'outer':  ['Нейлон', 'Полиэстер', 'Пух', 'Шерсть', 'Мембрана', 'Синтетика'],
    'caps':   ['Шерсть', 'Хлопок', 'Акрил', 'Вязка', 'Фетр'],
    'pants':  ['Хлопок', 'Деним', 'Полиэстер', 'Лён', 'Велюр', 'Синтетика'],
    'dress':  ['Хлопок', 'Шёлк', 'Трикотаж', 'Атлас', 'Вискоза', 'Синтетика'],
    'acc':    ['Кожа', 'Экокожа', 'Текстиль', 'Металл', 'Пластик'],
    'sport':  ['Полиэстер', 'Спандекс', 'Сетка', 'Нейлон', 'Синтетика'],
  };
  static const List<Map<String, dynamic>> _presets = [
    {
      'label': 'Үш размерден 1 жұп · содовойдан 2',
      'desc': 'Барлығы 10–14 жұп (категорияға қарай)',
      'kind': 'recommended',
    },
    {
      'label': '20 жұп · 4 размер тең',
      'desc': 'Әр размерден 5 жұп',
      'perSize': 5,
      'count': 4
    },
    {
      'label': '24 жұп · 4 размер',
      'desc': 'Әр размерден 6 жұп',
      'perSize': 6,
      'count': 4
    },
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _brandCtrl.dispose();
    _purchaseCtrl.dispose();
    _sellingCtrl.dispose();
    super.dispose();
  }

  /// Размеры для текущего выбора: для обуви зависят от пола (богаче), для
  /// остальных категорий берутся из CategoryData.
  List<String> _sizesForSelection() {
    if (_categoryKey == null) return [];
    if (_categoryKey == 'shoes') return _sizesByCat[_targetGroup] ?? [];
    return categoryByKey(_categoryKey).sizes;
  }

  void _recomputeSizes() {
    final sizes = _sizesForSelection();
    final old = _sizesQuantity;
    _sizesQuantity = {for (final s in sizes) s: old[s] ?? 0};
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

  void _applyPreset(Map<String, dynamic> preset) {
    final keys = _sizesQuantity.keys.toList();
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
    setState(() => _sizesQuantity = newMap);
  }

  int get _totalPairs => _sizesQuantity.values.fold(0, (a, b) => a + b);

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

  int get _remainingSlots => _maxImages - _imageBytes.length;

  Future<void> _pickFromGallery() async {
    Navigator.pop(context);
    if (_remainingSlots <= 0) {
      _err('Максимум $_maxImages фото');
      return;
    }
    final picked = await _imagePicker.pickMultiImage(imageQuality: 90);
    if (picked.isEmpty) return;
    await _processPicked(picked);
  }

  Future<void> _pickFromCamera() async {
    Navigator.pop(context);
    if (_remainingSlots <= 0) {
      _err('Максимум $_maxImages фото');
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
                toAdd.length > 1 ? 'Фото ${i + 1} из ${toAdd.length}' : null,
          ),
        ),
      );
      if (cropped != null && mounted) {
        setState(() => _imageBytes.add(cropped));
      }
    }
    if (overflow && mounted) _err('Добавлено только $_remainingSlots — лимит $_maxImages фото');
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
              title: const Text('Сфотографировать',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              subtitle: const Text('Камера телефона'),
              onTap: _pickFromCamera),
          ListTile(
              leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: cGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.photo_library_outlined,
                      color: cGreen)),
              title: const Text('Из галереи',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text('До $_remainingSlots фото сразу'),
              onTap: _pickFromGallery),
          const SizedBox(height: 8),
        ]),
      )),
    );
  }

  bool _validateStep() {
    if (_step == 0) {
      if (_categoryKey == null) {
        _err('Выберите тип товара');
        return false;
      }
      if (_nameCtrl.text.trim().isEmpty) {
        _err('Введите название товара');
        return false;
      }
      if (_brandCtrl.text.trim().isEmpty) {
        _err('Введите бренд');
        return false;
      }
      if (_currentTypes.isNotEmpty && _type == null) {
        _err('Выберите тип товара');
        return false;
      }
      if (_targetGroup == null) {
        _err('Выберите, кому предназначен товар');
        return false;
      }
      if (_color == null) {
        _err('Выберите цвет');
        return false;
      }
    }
    if (_step == 1) {
      if (_purchaseCtrl.text.isEmpty) {
        _err('Введите закупочную цену');
        return false;
      }
      if (_sellingCtrl.text.isEmpty) {
        _err('Введите цену продажи');
        return false;
      }
    }
    if (_step == 2) {
      if (_totalPairs == 0) {
        _err('Добавьте хотя бы 1 товар');
        return false;
      }
    }
    if (_step == 3) {
      if (_imageBytes.isEmpty) {
        _err('Добавьте хотя бы одно фото товара');
        return false;
      }
    }
    return true;
  }

  Future<void> _save() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    if (!await ensureWarehouseSelected(context)) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (!mounted) return;
    final warehouseId = context.read<WarehouseContext>().current?.id ?? '';
    try {
      // Бірдей товар бар-жоғын тексереміз
      final existingId = await _firestoreService.findMatchingProduct(
        name: _nameCtrl.text.trim(),
        brand: _brandCtrl.text.trim(),
        type: _type ?? '',
        material: _material ?? '',
        category: _targetGroup ?? '',
        color: _color ?? '',
      );

      final imageUrls = await _cloudinaryService.uploadBytesList(_imageBytes);
      final batchModel = BatchModel(
        id: '',
        dateArrived: _dateArrived,
        purchasePrice: double.tryParse(_purchaseCtrl.text) ?? 0,
        sellingPrice: double.tryParse(_sellingCtrl.text) ?? 0,
        sizesQuantity: Map.from(_sizesQuantity),
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
          await _firestoreService.updateProductImages(existingId, imageUrls);
        }
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Row(children: [
              Icon(Icons.add_box_outlined, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                  child:
                      Text('Новая партия добавлена к существующему товару!')),
            ]),
            backgroundColor: cGreen,
            behavior: SnackBarBehavior.floating,
          ));
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
          color: _color ?? '',
          articul: '',
          status: ProductModel.statusInStock,
          images: imageUrls,
        );
        await _firestoreService.addNewProduct(
          product: product,
          firstBatch: batchModel,
          dateArrived: _dateArrived,
          warehouseId: warehouseId,
        );
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Row(children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('Товар добавлен на склад!'),
            ]),
            backgroundColor: cGreen,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (e) {
      _err('Ошибка: $e');
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
    final steps = ['Товар', 'Цены', 'Размеры', 'Фото'];
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
                    child: Text('Новый товар',
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
                        _step < 3 ? 'Далее →' : 'Сохранить',
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
                      child: const Text('Назад',
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
                    child: Text(_step == 3 ? 'Сохранить товар' : 'Далее →',
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
            title: 'Информация о товаре',
            subtitle: 'Название, бренд и характеристики'),
        const SizedBox(height: 20),
        _Field(
            controller: _nameCtrl,
            label: 'Название товара',
            hint: 'Напр: Nike Air Max 270',
            icon: Icons.inventory_2_outlined),
        const SizedBox(height: 12),
        _Field(
            controller: _brandCtrl,
            label: 'Бренд',
            hint: 'Напр: Nike, Adidas, New Balance',
            icon: Icons.workspace_premium_outlined),
        const SizedBox(height: 16),
        const _Label('Категория товара *'),
        const SizedBox(height: 8),
        _buildCategoryTypePicker(),
        if (_categoryKey != null && _currentTypes.isNotEmpty) ...[
          const SizedBox(height: 16),
          const _Label('Тип товара *'),
          const SizedBox(height: 8),
          _buildTypeDropdown(),
        ],
        if (_categoryKey != null) ...[
          const SizedBox(height: 16),
          const _Label('Кому *'),
          const SizedBox(height: 8),
          _buildTargetGroupPicker(),
        ],
        const SizedBox(height: 16),
        const _Label('Цвет *'),
        const SizedBox(height: 10),
        _buildColorPicker(),
        if (_categoryKey != null && _currentMaterials.isNotEmpty) ...[
          const SizedBox(height: 16),
          const _Label('Материал (необязательно)'),
          const SizedBox(height: 8),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _currentMaterials
                  .map((m) => _SelectChip(
                      label: m,
                      selected: _material == m,
                      onTap: () =>
                          setState(() => _material = _material == m ? null : m)))
                  .toList()),
        ],
      ]);

  Widget _buildColorPicker() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: ProductModel.colorOptions.map((opt) {
        final name = opt['name'] as String;
        final hexValue = opt['hex'] as int;
        final color = Color(hexValue);
        final selected = _color == name;
        final isLight = color.computeLuminance() > 0.7;
        return GestureDetector(
          onTap: () => setState(() => _color = name),
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
              Text(name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? (isLight ? cInk : Colors.white)
                        : cInk2,
                  )),
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

  // Тип товара (вид/модель) — зависит от выбранной категории.
  Widget _buildTypeDropdown() {
    final types = _currentTypes;
    return DropdownButtonFormField<String>(
      initialValue: types.contains(_type) ? _type : null,
      isExpanded: true,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        hintText: 'Выберите тип',
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
      items: types
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: (v) => setState(() => _type = v),
    );
  }

  // Кому — единый список для всех категорий.
  Widget _buildTargetGroupPicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _targetGroups
          .map((g) => _SelectChip(
              label: '${_targetGroupIcons[g] ?? ''} $g',
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
          title: 'Ценообразование',
          subtitle: 'Закупочная и продажная цена'),
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
              const Text('Дата поставки',
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
              const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Закупочная цена',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: cInk)),
                    Text('Сколько заплатили за партию',
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
              const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Цена продажи',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: cInk)),
                    Text('По какой цене будете продавать',
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
              Text('Маржа с одного товара',
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
            Text('Размер $size',
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
            Text('шт.', style: manrope(13, FontWeight.w500, color: cInk3)),
            const SizedBox(height: 24),
            QPrimaryButton(
              label: 'Готово',
              onPressed: () {
                setState(() => _sizesQuantity[size] = tempQty);
                Navigator.pop(ctx);
              },
            ),
          ]),
        ),
      ),
    );
  }

  // ── Шаг 3: Размеры ────────────────────────────────────────────────────
  Widget _buildStepSizes() {
    if (_sizesQuantity.isEmpty) {
      return Center(
          child: Column(children: [
        const SizedBox(height: 40),
        const Icon(Icons.arrow_back, size: 48, color: cInk3),
        const SizedBox(height: 12),
        const Text('Вернитесь и выберите тип товара',
            style: TextStyle(color: cInk2, fontSize: 15)),
        const SizedBox(height: 16),
        ElevatedButton(
            onPressed: () => setState(() => _step = 0),
            child: const Text('← Шаг 1')),
      ]));
    }

    final keys = _sizesQuantity.keys.toList();
    final catLabel = _isShoes
        ? (_targetGroup ?? '')
        : categoryByKey(_categoryKey).name;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _StepHeader(
          icon: Icons.straighten_outlined,
          title: 'Размеры и количество',
          subtitle: '$catLabel · ${keys.length} размеров'),
      const SizedBox(height: 16),
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
            const Text('Итого в партии:',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const Spacer(),
            Text('$_totalPairs шт.',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20)),
          ])),
      const SizedBox(height: 14),
      const _Label('⚡ Быстрое заполнение'),
      const SizedBox(height: 8),
      SizedBox(
          height: 80,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: _presets.map((p) {
              final isRec = p['kind'] == 'recommended';
              return GestureDetector(
                  onTap: () => _applyPreset(p),
                  child: Container(
                      width: 160,
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: isRec
                              ? cGreen.withValues(alpha: 0.06)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: isRec
                                  ? cGreen.withValues(alpha: 0.4)
                                  : cGreen.withValues(alpha: 0.1))),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isRec)
                              Container(
                                  margin: const EdgeInsets.only(bottom: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: cGreen,
                                      borderRadius: BorderRadius.circular(4)),
                                  child: const Text('ҰСЫНЫЛАДЫ',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700))),
                            Text(p['label'] as String,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isRec
                                        ? cGreen
                                        : cGreen),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(p['desc'] as String,
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: cInk2)),
                          ])));
            }).toList(),
          )),
      const SizedBox(height: 14),
      Row(children: [
        const _Label('Размеры'),
        const Spacer(),
        GestureDetector(
            onTap: () =>
                setState(() => _sizesQuantity = {for (final k in keys) k: 0}),
            child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: cRedTint,
                    borderRadius: BorderRadius.circular(6)),
                child: const Text('Сбросить',
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
          final qty = _sizesQuantity[size] ?? 0;
          return GestureDetector(
            onTap: () => _showSizeInputSheet(size, qty),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
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
                  Text('$qty шт.',
                      style: manrope(11, FontWeight.w700,
                          color: qty > 0 ? cGreen : cInk3)),
                ],
              ),
            ),
          );
        },
      ),
    ]);
  }

  // ── Шаг 4: Фото ───────────────────────────────────────────────────────
  Widget _buildStepPhotos() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _StepHeader(
            icon: Icons.photo_library_outlined,
            title: 'Фотографии товара',
            subtitle: 'Минимум 1, максимум $_maxImages фото · авто-кадр 1:1'),
        const SizedBox(height: 20),
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
                      const Text('Добавить фото',
                          style: TextStyle(
                              color: cGreen,
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                      Text('Можно выбрать до $_remainingSlots сразу',
                          style: const TextStyle(color: cInk3, fontSize: 11)),
                    ])),
          ),
        if (_remainingSlots > 0) const SizedBox(height: 16),
        if (_imageBytes.isNotEmpty) ...[
          Text('Добавлено: ${_imageBytes.length} / $_maxImages фото',
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
            itemCount: _imageBytes.length,
            itemBuilder: (_, i) {
              return Stack(children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(_imageBytes[i],
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity)),
                Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                        onTap: () => setState(() => _imageBytes.removeAt(i)),
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
                          child: const Text('Главное',
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
              const Text('Итоговые данные товара',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: cInk)),
              const SizedBox(height: 12),
              _SummaryRow(
                  label: 'Название',
                  value: _nameCtrl.text.isEmpty ? '—' : _nameCtrl.text),
              _SummaryRow(
                  label: 'Бренд',
                  value: _brandCtrl.text.isEmpty ? '—' : _brandCtrl.text),
              _SummaryRow(
                  label: 'Категория',
                  value: _categoryKey == null
                      ? '—'
                      : categoryByKey(_categoryKey).name),
              _SummaryRow(label: 'Тип товара', value: _type ?? '—'),
              _SummaryRow(label: 'Кому', value: _targetGroup ?? '—'),
              _SummaryRow(label: 'Цвет', value: _color ?? '—'),
              _SummaryRow(
                  label: 'Дата поставки',
                  value:
                      '${_dateArrived.day.toString().padLeft(2, '0')}.${_dateArrived.month.toString().padLeft(2, '0')}.${_dateArrived.year}'),
              _SummaryRow(
                  label: 'Закуп / Продажа',
                  value: '${_purchaseCtrl.text} ₸ / ${_sellingCtrl.text} ₸'),
              _SummaryRow(label: 'Всего товаров', value: '$_totalPairs шт.'),
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

