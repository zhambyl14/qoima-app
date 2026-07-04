import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/warehouse_context.dart';
import '../../../data/models/batch_model.dart';
import '../../../data/models/category_data.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/store_discount_model.dart';
import '../../../data/models/warehouse_model.dart';
import '../../../data/repositories/my_store_repository.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';
import 'ms_widgets.dart';

import '../../../core/lang.dart';
class AdminMyStoreDiscountAddScreen extends StatefulWidget {
  const AdminMyStoreDiscountAddScreen({super.key});

  @override
  State<AdminMyStoreDiscountAddScreen> createState() =>
      _AdminMyStoreDiscountAddScreenState();
}

class _AdminMyStoreDiscountAddScreenState
    extends State<AdminMyStoreDiscountAddScreen> {
  final _service = FirestoreService();
  final _repo = MyStoreRepository();
  final _searchCtrl = TextEditingController();

  int _typeIdx = 0; // 0=percent, 1=fixed
  double _value = 10;
  int _scopeIdx = 0; // 0=product, 1=category, 2=warehouse
  bool _hasLimit = false;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _saving = false;

  // data
  List<ProductModel> _products = [];
  bool _loadingProducts = true;
  List<String> _visibleWarehouseIds = [];

  // selections
  ProductModel? _selectedProduct;
  String? _selectedCategoryKey;
  String? _selectedWarehouseId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final store = await _service.getStore();
      final products = _service.cachedProducts ??
          await _service.watchProducts().first;
      if (!mounted) return;
      setState(() {
        _products = products;
        _visibleWarehouseIds =
            List<String>.from(store?.visibleWarehouseIds ?? const []);
        _loadingProducts = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingProducts = false);
    }
  }

  double get _step => _typeIdx == 0 ? 5 : 500;
  double get _max => _typeIdx == 0 ? 100 : 9999999;
  void _inc() => setState(() => _value = (_value + _step).clamp(0, _max));
  void _dec() => setState(() => _value = (_value - _step).clamp(0, _max));

  List<WarehouseModel> _visibleWarehouses(BuildContext context) {
    final all = context.read<WarehouseContext>().all;
    if (_visibleWarehouseIds.isEmpty) return all;
    return all.where((w) => _visibleWarehouseIds.contains(w.id)).toList();
  }

  // categories present among products
  List<CategoryData> get _availableCategories {
    final keys = <String>{};
    for (final p in _products) {
      keys.add(p.effectiveCategoryKey);
    }
    return kCategories.where((c) => keys.contains(c.key)).toList();
  }

  bool get _canSave {
    if (_value <= 0) return false;
    switch (_scopeIdx) {
      case 0: return _selectedProduct != null;
      case 1: return _selectedCategoryKey != null;
      case 2: return _selectedWarehouseId != null;
      default: return false;
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _startDate : _endDate) ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2031),
    );
    if (picked == null) return;
    if (isStart) {
      setState(() => _startDate = picked);
    } else {
      setState(() =>
          _endDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59));
    }
  }

  Future<void> _onSave() async {
    if (!_canSave) return;
    // capture warehouse list before any async gap (no BuildContext after await)
    final whList = context.read<WarehouseContext>().all;
    setState(() => _saving = true);
    try {
      // 1. target product ids + scope label
      late final List<String> targets;
      late final String scopeId;
      late final String scopeLabel;
      late final DiscountScope scope;

      switch (_scopeIdx) {
        case 0:
          scope = DiscountScope.product;
          scopeId = _selectedProduct!.id;
          scopeLabel = _selectedProduct!.name;
          targets = [_selectedProduct!.id];
          break;
        case 1:
          scope = DiscountScope.category;
          final key = _selectedCategoryKey!;
          scopeId = key;
          targets = _products
              .where((p) => p.effectiveCategoryKey == key)
              .map((p) => p.id)
              .toList();
          scopeLabel =
              tr('${categoryByKey(key).name} · ${targets.length} товаров', '${categoryByKey(key).name} · ${targets.length} тауар');
          break;
        default:
          scope = DiscountScope.store;
          final whId = _selectedWarehouseId!;
          scopeId = whId;
          targets = await _service.productIdsInWarehouse(whId);
          final whName = whList
              .firstWhere((w) => w.id == whId,
                  orElse: () => WarehouseModel(
                      id: whId, name: tr('Склад', 'Қойма'), createdAt: DateTime.now()))
              .name;
          scopeLabel = tr('$whName · ${targets.length} товаров', '$whName · ${targets.length} тауар');
      }

      if (targets.isEmpty) {
        throw Exception(tr('В этой области товары не найдены', 'Бұл аяда тауар табылмады'));
      }

      // 2. apply real batch discount (auto-reverts after endsAt)
      final discount = DiscountModel(
        active: true,
        type: _typeIdx == 0 ? 'percent' : 'amount',
        value: _value,
        startsAt: _hasLimit ? _startDate : null,
        endsAt: _hasLimit ? _endDate : null,
      );
      await _service.setDiscountBulk(productIds: targets, discount: discount);

      // 3. record campaign for the My Store list
      final campaign = StoreDiscountModel(
        id: '',
        storeId: Supabase.instance.client.auth.currentUser!.id,
        type: _typeIdx == 0 ? DiscountType.percent : DiscountType.fixed,
        value: _value,
        scope: scope,
        scopeId: scopeId,
        scopeLabel: scopeLabel,
        targetProductIds: targets,
        hasDateLimit: _hasLimit,
        startsAt: _hasLimit ? _startDate : null,
        endsAt: _hasLimit ? _endDate : null,
        isActive: true,
        createdAt: DateTime.now(),
      );
      await _repo.addDiscount(campaign);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final suffix = _typeIdx == 0 ? '%' : ' ₸';
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Новая акция', 'Жаңа акция'),
          showBack: true,
          action: TextButton(
            onPressed: (_canSave && !_saving) ? _onSave : null,
            child: Text(tr('Сохранить', 'Сақтау'),
                style: manrope(14.5, FontWeight.w700, color: Colors.white)),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Type
              QSecLabel(tr('Тип скидки', 'Скидка түрі')),
              MSSeg(
                options: [tr('Процент %', 'Пайыз %'), tr('Сумма ₸', 'Сомма ₸')],
                active: _typeIdx,
                onChanged: (i) => setState(() {
                  _typeIdx = i;
                  _value = i == 0 ? 10 : 1000;
                }),
              ),
              const SizedBox(height: 16),

              // Counter
              QCard(
                child: Row(children: [
                  Expanded(child: Text(tr('Размер скидки', 'Скидка мөлшері'), style: manrope(14, FontWeight.w700, color: cInk))),
                  MSCounterBtn(icon: Icons.remove, bg: cBg, fg: cInk2, onTap: _dec),
                  const SizedBox(width: 14),
                  SizedBox(
                    width: 92,
                    child: Text('${_value.toStringAsFixed(0)}$suffix',
                        textAlign: TextAlign.center,
                        style: manrope(26, FontWeight.w800, color: cRed, letterSpacing: -0.5)),
                  ),
                  const SizedBox(width: 14),
                  MSCounterBtn(icon: Icons.add, bg: cRed, fg: Colors.white, onTap: _inc),
                ]),
              ),
              const SizedBox(height: 16),

              // Scope
              QSecLabel(tr('Область применения', 'Қолдану аясы')),
              MSSeg(
                options: [tr('Товар', 'Тауар'), tr('Категория', 'Санат'), tr('Склад', 'Қойма')],
                active: _scopeIdx,
                onChanged: (i) => setState(() => _scopeIdx = i),
              ),
              const SizedBox(height: 12),

              if (_loadingProducts)
                const Center(child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: cGreen)))
              else ...[
                if (_scopeIdx == 0) _buildProductPicker(),
                if (_scopeIdx == 1) _buildCategoryPicker(),
                if (_scopeIdx == 2) _buildWarehousePicker(context),
              ],
              const SizedBox(height: 16),

              // Date limit
              QSecLabel(tr('Срок', 'Мерзімі')),
              QCard(
                child: Column(children: [
                  Row(children: [
                    const Icon(Icons.calendar_today_rounded, color: cGreen, size: 20),
                    const SizedBox(width: 11),
                    Expanded(child: Text(tr('Ограничить по времени', 'Уақыт шектеу'), style: manrope(14, FontWeight.w700, color: cInk))),
                    MSToggle(on: _hasLimit, onTap: () => setState(() => _hasLimit = !_hasLimit)),
                  ]),
                  if (_hasLimit) ...[
                    const SizedBox(height: 13),
                    Row(children: [
                      Expanded(child: MSDateBtn(label: tr('С', 'Бастап'), date: _startDate, onTap: () => _pickDate(isStart: true))),
                      const SizedBox(width: 10),
                      Expanded(child: MSDateBtn(label: tr('По', 'Дейін'), date: _endDate, onTap: () => _pickDate(isStart: false))),
                    ]),
                    const SizedBox(height: 8),
                    Text(tr('После окончания срока цена вернётся автоматически', 'Мерзім біткен соң баға автоматты түрде қайтады'),
                        style: manrope(11.5, FontWeight.w500, color: cInk3)),
                  ],
                ]),
              ),
              const SizedBox(height: 24),

              QPrimaryButton(
                label: tr('Сохранить акцию', 'Акцияны сақтау'),
                isLoading: _saving,
                onPressed: (_canSave && !_saving) ? _onSave : null,
              ),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Product picker with search ────────────────────────────────────────────────
  Widget _buildProductPicker() {
    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _products
        : _products.where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.brand.toLowerCase().contains(q) ||
            p.articul.toLowerCase().contains(q)).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: _searchCtrl,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: tr('Поиск товара (название, бренд, артикул)', 'Тауар іздеу (атауы, бренд, артикул)'),
          prefixIcon: Icon(Icons.search_rounded, color: cInk3),
        ),
      ),
      const SizedBox(height: 10),
      if (_selectedProduct != null)
        _SelectedChip(
          label: _selectedProduct!.name,
          onClear: () => setState(() => _selectedProduct = null),
        ),
      if (_selectedProduct == null)
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: filtered.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(tr('Товары не найдены', 'Тауар табылмады'),
                      style: manrope(13, FontWeight.w500, color: cInk3)))
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final p = filtered[i];
                    return GestureDetector(
                      onTap: () => setState(() => _selectedProduct = p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: cSurface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: cLine),
                        ),
                        child: Row(children: [
                          Icon(CategoryIcon.iconFor(categoryByKey(p.effectiveCategoryKey).iconKey),
                              color: cInk3, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p.name, style: manrope(13.5, FontWeight.w700, color: cInk),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              if (p.brand.isNotEmpty)
                                Text(p.brand, style: manrope(11.5, FontWeight.w500, color: cInk3)),
                            ]),
                          ),
                          const Icon(Icons.add_circle_outline_rounded, color: cGreen, size: 20),
                        ]),
                      ),
                    );
                  },
                ),
        ),
    ]);
  }

  // ── Category picker ───────────────────────────────────────────────────────────
  Widget _buildCategoryPicker() {
    final cats = _availableCategories;
    if (cats.isEmpty) {
      return Text(tr('Категории не найдены', 'Санат табылмады'), style: manrope(13, FontWeight.w500, color: cInk3));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: cats.map((c) {
        final sel = _selectedCategoryKey == c.key;
        final count = _products.where((p) => p.effectiveCategoryKey == c.key).length;
        return GestureDetector(
          onTap: () => setState(() => _selectedCategoryKey = c.key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: sel ? cRed : cSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sel ? cRed : cLine),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              CategoryIcon(kind: c.iconKey, size: 16, color: sel ? Colors.white : cInk3),
              const SizedBox(width: 8),
              Text('${c.name} · $count',
                  style: manrope(13, FontWeight.w700, color: sel ? Colors.white : cInk)),
            ]),
          ),
        );
      }).toList(),
    );
  }

  // ── Warehouse picker ──────────────────────────────────────────────────────────
  Widget _buildWarehousePicker(BuildContext context) {
    final whs = _visibleWarehouses(context);
    if (whs.isEmpty) {
      return Text(tr('На витрине нет складов. Сначала добавьте склад в разделе «Склады витрины».', 'Витринада қойма жоқ. Алдымен «Витрина қоймалары» бөлімінен қойма қосыңыз.'),
          style: manrope(13, FontWeight.w500, color: cInk3));
    }
    return Column(
      children: whs.map((w) {
        final sel = _selectedWarehouseId == w.id;
        return GestureDetector(
          onTap: () => setState(() => _selectedWarehouseId = w.id),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: cSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: sel ? cRed : cLine, width: sel ? 2 : 1),
            ),
            child: Row(children: [
              Container(
                width: 20, height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: sel ? cRed : cLine, width: sel ? 5.5 : 1.5),
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.warehouse_outlined, color: cInk3, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(w.name, style: manrope(14, FontWeight.w700, color: sel ? cRed : cInk))),
            ]),
          ),
        );
      }).toList(),
    );
  }
}

class _SelectedChip extends StatelessWidget {
  final String label;
  final VoidCallback onClear;
  const _SelectedChip({required this.label, required this.onClear});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: cRedTint,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cRed.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.check_circle_rounded, color: cRed, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: manrope(13.5, FontWeight.w700, color: cInk),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
          GestureDetector(
            onTap: onClear,
            child: const Icon(Icons.close_rounded, color: cInk3, size: 18),
          ),
        ]),
      );
}

