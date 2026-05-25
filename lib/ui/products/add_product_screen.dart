import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/warehouse_context.dart';
import '../../data/models/models.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/cloudinary_service.dart';
import '../../theme/app_theme.dart';
import '../shared/mandatory_warehouse_picker.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});
  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _firestoreService  = FirestoreService();
  final _cloudinaryService = CloudinaryService();
  final _imagePicker       = ImagePicker();

  final _nameCtrl     = TextEditingController();
  final _brandCtrl    = TextEditingController();
  final _purchaseCtrl = TextEditingController();
  final _sellingCtrl  = TextEditingController();

  String? _type;
  String? _material;
  String? _category;
  String? _color;
  DateTime _dateArrived = DateTime.now();

  final List<XFile>        _images   = [];
  final Map<String, Uint8List> _previews = {};
  bool _isLoading = false;
  int  _step      = 0; // 0=Товар, 1=Цены, 2=Размеры, 3=Фото

  static const Map<String, List<String>> _sizesByCat = {
    'Мужские':            ['39','40','41','42','43','44','45','46'],
    'Женские':            ['35','36','37','38','39','40','41'],
    'Унисекс':            ['36','37','38','39','40','41','42','43','44'],
    'Детские (мальчики)': ['28','29','30','31','32','33','34','35','36'],
    'Детские (девочки)':  ['26','27','28','29','30','31','32','33','34'],
  };

  Map<String, int> _sizesQuantity = {};

  static const List<String> _types     = ['Туфли','Кеды','Кроссовки','Ботинки','Сланцы','Босоножки'];
  static const List<String> _materials = ['Кожа','Экокожа','Текстиль','Замша','Резина','Синтетика'];
  static const List<String> _categories = ['Мужские','Женские','Унисекс','Детские (мальчики)','Детские (девочки)'];

  static const List<Map<String, dynamic>> _presets = [
    {
      'label': 'Үш размерден 1 жұп · содовойдан 2',
      'desc':  'Барлығы 10–14 жұп (категорияға қарай)',
      'kind':  'recommended',
    },
    {'label': '20 жұп · 4 размер тең',  'desc': 'Әр размерден 5 жұп', 'perSize': 5, 'count': 4},
    {'label': '24 жұп · 4 размер',      'desc': 'Әр размерден 6 жұп', 'perSize': 6, 'count': 4},
  ];

  @override
  void dispose() {
    _nameCtrl.dispose(); _brandCtrl.dispose();
    _purchaseCtrl.dispose(); _sellingCtrl.dispose();
    super.dispose();
  }

  void _onCategoryChanged(String? cat) {
    setState(() {
      _category = cat;
      final sizes = _sizesByCat[cat] ?? [];
      _sizesQuantity = {for (final s in sizes) s: 0};
    });
  }

  void _applyPreset(Map<String, dynamic> preset) {
    final keys = _sizesQuantity.keys.toList();
    if (keys.isEmpty) return;
    final newMap = <String, int>{for (final k in keys) k: 0};

    if (preset['kind'] == 'recommended') {
      // Барлық размерге 1, ортаңғы 2 размерге 2 жұп
      for (final k in keys) { newMap[k] = 1; }
      final mid = keys.length ~/ 2;
      if (mid - 1 >= 0) { newMap[keys[mid - 1]] = 2; }
      if (mid < keys.length) { newMap[keys[mid]] = 2; }
    } else {
      final perSize = preset['perSize'] as int;
      final count   = (preset['count'] as int).clamp(0, keys.length);
      final mid     = (keys.length / 2).floor();
      final start   = (mid - count ~/ 2).clamp(0, keys.length - count);
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
            primary: AppTheme.primary,
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
  Future<void> _pickImage(ImageSource source) async {
    Navigator.pop(context);
    final picked = await _imagePicker.pickImage(source: source, imageQuality: 80);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() { _images.add(picked); _previews[picked.path] = bytes; });
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          ListTile(
            leading: Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.camera_alt_outlined, color: AppTheme.primary)),
            title: const Text('Сфотографировать',
                style: TextStyle(fontWeight: FontWeight.w500)),
            subtitle: const Text('Камера телефона'),
            onTap: () => _pickImage(ImageSource.camera)),
          ListTile(
            leading: Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.photo_library_outlined, color: AppTheme.primary)),
            title: const Text('Из галереи',
                style: TextStyle(fontWeight: FontWeight.w500)),
            subtitle: const Text('Выбрать существующее фото'),
            onTap: () => _pickImage(ImageSource.gallery)),
          const SizedBox(height: 8),
        ]),
      )),
    );
  }

  bool _validateStep() {
    if (_step == 0) {
      if (_nameCtrl.text.trim().isEmpty) { _err('Введите название товара'); return false; }
      if (_brandCtrl.text.trim().isEmpty) { _err('Введите бренд'); return false; }
      if (_type == null) { _err('Выберите тип обуви'); return false; }
      if (_category == null) { _err('Выберите категорию'); return false; }
      if (_color == null) { _err('Выберите цвет'); return false; }
    }
    if (_step == 1) {
      if (_purchaseCtrl.text.isEmpty) { _err('Введите закупочную цену'); return false; }
      if (_sellingCtrl.text.isEmpty) { _err('Введите цену продажи'); return false; }
    }
    if (_step == 2) {
      if (_totalPairs == 0) { _err('Добавьте хотя бы 1 пару'); return false; }
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
    final warehouseId =
        context.read<WarehouseContext>().current?.id ?? '';
    try {
      // Бірдей товар бар-жоғын тексереміз
      final existingId = await _firestoreService.findMatchingProduct(
        name:     _nameCtrl.text.trim(),
        brand:    _brandCtrl.text.trim(),
        type:     _type!,
        material: _material ?? '',
        category: _category!,
        color:    _color!,
      );

      final imageUrls = await _cloudinaryService.uploadMultiple(_images);
      final batchModel = BatchModel(
        id: '',
        dateArrived:   _dateArrived,
        purchasePrice: double.tryParse(_purchaseCtrl.text) ?? 0,
        sellingPrice:  double.tryParse(_sellingCtrl.text) ?? 0,
        sizesQuantity: Map.from(_sizesQuantity),
      );

      if (existingId != null) {
        // Бар карточкаға жаңа партия қосамыз
        await _firestoreService.addNewBatchToProduct(
          productId:   existingId,
          batch:       batchModel,
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
              Expanded(child: Text('Новая партия добавлена к существующему товару!')),
            ]),
            backgroundColor: AppTheme.primary,
            behavior: SnackBarBehavior.floating,
          ));
        }
      } else {
        // Жаңа карточка жасаймыз
        final product = ProductModel(
          id: '', name: _nameCtrl.text.trim(), brand: _brandCtrl.text.trim(),
          type: _type!, material: _material ?? '', category: _category!,
          color: _color!, articul: '', status: ProductModel.statusInStock,
          images: imageUrls,
        );
        await _firestoreService.addNewProduct(
          product:     product,
          firstBatch:  batchModel,
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
            backgroundColor: AppTheme.success,
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

  void _err(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: AppTheme.danger,
        behavior: SnackBarBehavior.floating));

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final steps = ['Товар', 'Цены', 'Размеры', 'Фото'];
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(child: Column(children: [
        // Header
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFF1E3A8A), Color(0xFF2D4FB5)],
                begin: Alignment.topLeft, end: Alignment.bottomRight)),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(children: [
            Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16))),
              const SizedBox(width: 12),
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Новый товар', style: TextStyle(color: Colors.white,
                    fontSize: 18, fontWeight: FontWeight.w700)),
                Text('Заполните данные о товаре',
                    style: TextStyle(color: Colors.white60, fontSize: 12)),
              ]),
              const Spacer(),
              if (_isLoading)
                const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            ]),
            const SizedBox(height: 16),
            Row(children: List.generate(steps.length, (i) {
              final done   = i < _step;
              final active = i == _step;
              return Expanded(child: Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () { if (i < _step) setState(() => _step = i); },
                  child: Column(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: active ? 32 : 26, height: active ? 32 : 26,
                      decoration: BoxDecoration(
                        color: done ? AppTheme.success
                            : active ? Colors.white
                            : Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: active ? null : Border.all(
                            color: Colors.white.withValues(alpha: 0.4), width: 1.5)),
                      child: Center(child: done
                          ? const Icon(Icons.check, color: Colors.white, size: 14)
                          : Text('${i+1}', style: TextStyle(
                              color: active ? AppTheme.primary : Colors.white,
                              fontSize: active ? 13 : 11,
                              fontWeight: FontWeight.w700)))),
                    const SizedBox(height: 4),
                    Text(steps[i], style: TextStyle(
                        color: active ? Colors.white : Colors.white.withValues(alpha: 0.5),
                        fontSize: 10,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
                  ]),
                )),
                if (i < steps.length - 1)
                  Container(height: 1.5, width: 20,
                      color: i < _step ? AppTheme.success : Colors.white.withValues(alpha: 0.25)),
              ]));
            })),
          ]),
        ),

        // Content
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: KeyedSubtree(key: ValueKey(_step), child: _buildStep()),
          ),
        )),

        // Bottom buttons
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12, offset: const Offset(0, -3))]),
          child: Row(children: [
            if (_step > 0)
              Expanded(flex: 1, child: OutlinedButton(
                onPressed: () => setState(() => _step--),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Назад',
                    style: TextStyle(color: AppTheme.textSecondary)))),
            if (_step > 0) const SizedBox(width: 12),
            Expanded(flex: 2, child: ElevatedButton(
              onPressed: _isLoading ? null : () {
                if (!_validateStep()) return;
                if (_step < 3) { setState(() => _step++); }
                else { _save(); }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14), elevation: 0),
              child: Text(_step == 3 ? 'Сохранить товар' : 'Далее →',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)))),
          ]),
        ),
      ])),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0: return _buildStepInfo();
      case 1: return _buildStepPrices();
      case 2: return _buildStepSizes();
      case 3: return _buildStepPhotos();
      default: return const SizedBox.shrink();
    }
  }

  // ── Шаг 1: Информация о товаре ────────────────────────────────────────
  Widget _buildStepInfo() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _StepHeader(icon: Icons.label_outline, title: 'Информация о товаре',
        subtitle: 'Название, бренд и характеристики'),
    const SizedBox(height: 20),

    _Field(controller: _nameCtrl, label: 'Название товара',
        hint: 'Напр: Nike Air Max 270', icon: Icons.inventory_2_outlined),
    const SizedBox(height: 12),
    _Field(controller: _brandCtrl, label: 'Бренд',
        hint: 'Напр: Nike, Adidas, New Balance',
        icon: Icons.workspace_premium_outlined),
    const SizedBox(height: 16),

    const _Label('Тип обуви'),
    const SizedBox(height: 8),
    Wrap(spacing: 8, runSpacing: 8,
      children: _types.map((t) => _SelectChip(
        label: t, selected: _type == t,
        onTap: () => setState(() => _type = t))).toList()),
    const SizedBox(height: 16),

    const _Label('Категория (определяет размеры)'),
    const SizedBox(height: 8),
    Wrap(spacing: 8, runSpacing: 8,
      children: _categories.map((c) {
        const icons = {
          'Мужские': '👨', 'Женские': '👩', 'Унисекс': '👫',
          'Детские (мальчики)': '👦', 'Детские (девочки)': '👧',
        };
        return _SelectChip(
          label: '${icons[c]} $c', selected: _category == c,
          onTap: () => _onCategoryChanged(c));
      }).toList()),
    const SizedBox(height: 16),

    const _Label('Цвет *'),
    const SizedBox(height: 10),
    _buildColorPicker(),
    const SizedBox(height: 16),

    const _Label('Материал (необязательно)'),
    const SizedBox(height: 8),
    Wrap(spacing: 8, runSpacing: 8,
      children: _materials.map((m) => _SelectChip(
        label: m, selected: _material == m,
        onTap: () => setState(() => _material = _material == m ? null : m))).toList()),
  ]);

  Widget _buildColorPicker() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: ProductModel.colorOptions.map((opt) {
        final name     = opt['name'] as String;
        final hexValue = opt['hex'] as int;
        final color    = Color(hexValue);
        final selected = _color == name;
        final isLight  = color.computeLuminance() > 0.7;
        return GestureDetector(
          onTap: () => setState(() => _color = name),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? color : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? color : AppTheme.border,
                width: selected ? 2 : 1,
              ),
              boxShadow: selected ? [BoxShadow(
                color: color.withValues(alpha: 0.35),
                blurRadius: 8, offset: const Offset(0, 3))] : [],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 14, height: 14,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isLight ? Colors.grey.shade300 : Colors.transparent,
                    width: 1),
                ),
              ),
              const SizedBox(width: 7),
              Text(name, style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected
                    ? (isLight ? AppTheme.textPrimary : Colors.white)
                    : AppTheme.textSecondary,
              )),
            ]),
          ),
        );
      }).toList(),
    );
  }

  // ── Шаг 2: Цены ───────────────────────────────────────────────────────
  Widget _buildStepPrices() {
    final purchase = double.tryParse(_purchaseCtrl.text) ?? 0;
    final selling  = double.tryParse(_sellingCtrl.text) ?? 0;
    final margin   = selling > 0 && purchase > 0
        ? ((selling - purchase) / purchase * 100) : 0.0;
    final profit   = selling - purchase;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _StepHeader(icon: Icons.monetization_on_outlined, title: 'Ценообразование',
          subtitle: 'Закупочная и продажная цена'),
      const SizedBox(height: 20),

      // Дата поставки
      GestureDetector(
        onTap: _pickDate,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border)),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.calendar_today_outlined,
                  color: AppTheme.primary, size: 18)),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Дата поставки',
                  style: TextStyle(fontSize: 12,
                      color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(
                '${_dateArrived.day.toString().padLeft(2, '0')}.${_dateArrived.month.toString().padLeft(2, '0')}.${_dateArrived.year}',
                style: const TextStyle(fontSize: 16,
                    fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            ]),
            const Spacer(),
            const Icon(Icons.edit_outlined, color: AppTheme.primary, size: 18),
          ]),
        ),
      ),
      const SizedBox(height: 12),

      // Закупочная
      Container(padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppTheme.dangerLight,
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.arrow_downward_rounded, color: AppTheme.danger, size: 18)),
            const SizedBox(width: 10),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Закупочная цена', style: TextStyle(fontWeight: FontWeight.w600,
                  fontSize: 14, color: AppTheme.textPrimary)),
              Text('Сколько заплатили за партию',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            ]),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _purchaseCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              hintText: '0', hintStyle: TextStyle(color: AppTheme.textHint, fontSize: 22),
              suffixText: '₸', suffixStyle: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
              border: InputBorder.none, filled: false, contentPadding: EdgeInsets.zero)),
        ])),
      const SizedBox(height: 12),

      // Цена продажи
      Container(padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppTheme.successLight,
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.arrow_upward_rounded, color: AppTheme.success, size: 18)),
            const SizedBox(width: 10),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Цена продажи', style: TextStyle(fontWeight: FontWeight.w600,
                  fontSize: 14, color: AppTheme.textPrimary)),
              Text('По какой цене будете продавать',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            ]),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _sellingCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              hintText: '0', hintStyle: TextStyle(color: AppTheme.textHint, fontSize: 22),
              suffixText: '₸', suffixStyle: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
              border: InputBorder.none, filled: false, contentPadding: EdgeInsets.zero)),
        ])),
      const SizedBox(height: 16),

      if (purchase > 0 && selling > 0)
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: profit >= 0 ? AppTheme.successLight : AppTheme.dangerLight,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: profit >= 0
                ? AppTheme.success.withValues(alpha: 0.3)
                : AppTheme.danger.withValues(alpha: 0.3))),
          child: Row(children: [
            Icon(profit >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                color: profit >= 0 ? AppTheme.success : AppTheme.danger, size: 24),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Маржа с одной пары',
                  style: TextStyle(fontSize: 12,
                      color: profit >= 0 ? AppTheme.success : AppTheme.danger)),
              Text('${profit >= 0 ? "+" : ""}${profit.toStringAsFixed(0)} ₸  '
                  '(${margin.toStringAsFixed(1)}%)',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                    color: profit >= 0 ? const Color(0xFF065F46) : AppTheme.danger)),
            ]),
          ]),
        ),
    ]);
  }

  // ── Шаг 3: Размеры ────────────────────────────────────────────────────
  Widget _buildStepSizes() {
    if (_category == null) {
      return Center(child: Column(children: [
        const SizedBox(height: 40),
        const Icon(Icons.arrow_back, size: 48, color: AppTheme.textHint),
        const SizedBox(height: 12),
        const Text('Вернитесь и выберите категорию',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: () => setState(() => _step = 0),
            child: const Text('← Шаг 1')),
      ]));
    }

    final keys = _sizesQuantity.keys.toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _StepHeader(icon: Icons.straighten_outlined, title: 'Размеры и количество',
          subtitle: '$_category · ${keys.length} размеров'),
      const SizedBox(height: 16),

      Container(padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF1E3A8A), Color(0xFF3B5FCC)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.inventory_2_outlined, color: Colors.white70, size: 20),
          const SizedBox(width: 10),
          const Text('Итого в партии:',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const Spacer(),
          Text('$_totalPairs пар', style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w800, fontSize: 20)),
        ])),
      const SizedBox(height: 14),

      const _Label('⚡ Быстрое заполнение'),
      const SizedBox(height: 8),
      SizedBox(height: 80, child: ListView(
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
                    ? AppTheme.success.withValues(alpha: 0.06)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isRec
                        ? AppTheme.success.withValues(alpha: 0.4)
                        : AppTheme.primary.withValues(alpha: 0.3))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isRec)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppTheme.success,
                          borderRadius: BorderRadius.circular(4)),
                      child: const Text('ҰСЫНЫЛАДЫ', style: TextStyle(
                          color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700))),
                  Text(p['label'] as String, style: TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isRec ? AppTheme.success : AppTheme.primary),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(p['desc'] as String, style: const TextStyle(
                      fontSize: 10, color: AppTheme.textSecondary)),
                ])));
        }).toList(),
      )),
      const SizedBox(height: 14),

      Row(children: [
        const _Label('Размеры'),
        const Spacer(),
        GestureDetector(
          onTap: () => setState(() => _sizesQuantity = {for (final k in keys) k: 0}),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: AppTheme.dangerLight,
                borderRadius: BorderRadius.circular(6)),
            child: const Text('Сбросить', style: TextStyle(fontSize: 11,
                color: AppTheme.danger, fontWeight: FontWeight.w600)))),
      ]),
      const SizedBox(height: 8),

      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, childAspectRatio: 2.8,
          crossAxisSpacing: 10, mainAxisSpacing: 10),
        itemCount: keys.length,
        itemBuilder: (_, i) {
          final size = keys[i];
          final qty  = _sizesQuantity[size] ?? 0;
          return Container(
            decoration: BoxDecoration(
              color: qty > 0 ? AppTheme.primary.withValues(alpha: 0.06) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: qty > 0 ? AppTheme.primary.withValues(alpha: 0.4) : AppTheme.border,
                width: qty > 0 ? 1.5 : 1)),
            child: Row(children: [
              const SizedBox(width: 10),
              Text(size, style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 14,
                color: qty > 0 ? AppTheme.primary : AppTheme.textSecondary)),
              const Spacer(),
              GestureDetector(
                onTap: () { if (qty > 0) setState(() => _sizesQuantity[size] = qty - 1); },
                child: Container(width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: qty > 0 ? AppTheme.primary : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(7)),
                  child: Icon(Icons.remove, size: 14,
                    color: qty > 0 ? Colors.white : Colors.grey.shade400))),
              SizedBox(width: 32, child: Text('$qty',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                  color: qty > 0 ? AppTheme.primary : AppTheme.textHint))),
              GestureDetector(
                onTap: () => setState(() => _sizesQuantity[size] = qty + 1),
                child: Container(width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.primary, borderRadius: BorderRadius.circular(7)),
                  child: const Icon(Icons.add, size: 14, color: Colors.white))),
              const SizedBox(width: 10),
            ]),
          );
        },
      ),
    ]);
  }

  // ── Шаг 4: Фото ───────────────────────────────────────────────────────
  Widget _buildStepPhotos() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _StepHeader(icon: Icons.photo_library_outlined, title: 'Фотографии товара',
        subtitle: 'Можно пропустить и добавить позже'),
    const SizedBox(height: 20),

    GestureDetector(
      onTap: _showImageOptions,
      child: Container(
        width: double.infinity, height: 100,
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3),
              style: BorderStyle.solid, width: 1.5)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.add_a_photo_outlined, size: 32,
              color: AppTheme.primary.withValues(alpha: 0.7)),
          const SizedBox(height: 8),
          const Text('Добавить фото', style: TextStyle(color: AppTheme.primary,
              fontWeight: FontWeight.w600, fontSize: 14)),
          const Text('Камера или галерея',
              style: TextStyle(color: AppTheme.textHint, fontSize: 11)),
        ])),
    ),
    const SizedBox(height: 16),

    if (_images.isNotEmpty) ...[
      Text('Добавлено: ${_images.length} фото',
          style: const TextStyle(fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary)),
      const SizedBox(height: 10),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1),
        itemCount: _images.length,
        itemBuilder: (_, i) {
          final preview = _previews[_images[i].path];
          return Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: preview != null
                  ? Image.memory(preview, fit: BoxFit.cover,
                      width: double.infinity, height: double.infinity)
                  : Container(color: AppTheme.background)),
            Positioned(top: 4, right: 4,
              child: GestureDetector(
                onTap: () => setState(() {
                  _previews.remove(_images[i].path);
                  _images.removeAt(i);
                }),
                child: Container(
                  decoration: const BoxDecoration(
                      color: Colors.red, shape: BoxShape.circle),
                  padding: const EdgeInsets.all(4),
                  child: const Icon(Icons.close, color: Colors.white, size: 14)))),
            if (i == 0)
              Positioned(bottom: 4, left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(4)),
                  child: const Text('Главное', style: TextStyle(color: Colors.white,
                      fontSize: 9, fontWeight: FontWeight.w700)))),
          ]);
        },
      ),
    ],

    const SizedBox(height: 20),
    Container(padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Итоговые данные товара',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 12),
        _SummaryRow(label: 'Название',
            value: _nameCtrl.text.isEmpty ? '—' : _nameCtrl.text),
        _SummaryRow(label: 'Бренд',
            value: _brandCtrl.text.isEmpty ? '—' : _brandCtrl.text),
        _SummaryRow(label: 'Категория', value: _category ?? '—'),
        _SummaryRow(label: 'Тип', value: _type ?? '—'),
        _SummaryRow(label: 'Цвет', value: _color ?? '—'),
        _SummaryRow(label: 'Дата поставки',
            value: '${_dateArrived.day.toString().padLeft(2,'0')}.${_dateArrived.month.toString().padLeft(2,'0')}.${_dateArrived.year}'),
        _SummaryRow(label: 'Закуп / Продажа',
            value: '${_purchaseCtrl.text} ₸ / ${_sellingCtrl.text} ₸'),
        _SummaryRow(label: 'Всего пар', value: '$_totalPairs шт.'),
      ])),
  ]);
}

// ─── Helper widgets ───────────────────────────────────────────────────────────
class _StepHeader extends StatelessWidget {
  final IconData icon; final String title, subtitle;
  const _StepHeader({required this.icon, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: AppTheme.primary, size: 22)),
    const SizedBox(width: 12),
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 17,
          fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
      Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
    ]),
  ]);
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary));
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label, hint;
  final IconData icon;
  const _Field({required this.controller, required this.label,
      required this.hint, required this.icon});
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary),
    decoration: InputDecoration(
      labelText: label, hintText: hint,
      prefixIcon: Icon(icon, color: AppTheme.primary, size: 20),
      filled: true, fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5))));
}

class _SelectChip extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap;
  const _SelectChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? AppTheme.primary : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.border,
            width: selected ? 1.5 : 1)),
      child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
          color: selected ? Colors.white : AppTheme.textSecondary))));
}

class _SummaryRow extends StatelessWidget {
  final String label, value;
  const _SummaryRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
      const Spacer(),
      Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary)),
    ]));
}