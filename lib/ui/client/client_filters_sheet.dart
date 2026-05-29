import 'package:flutter/material.dart';
import '../../data/models/store_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/batch_model.dart';
import '../../theme/app_theme.dart';
import 'client_home_screen.dart';

class ClientFiltersSheet extends StatefulWidget {
  final List<({ProductModel product, List<BatchModel> batches})> pairs;
  final List<StoreModel> stores;
  final ClientFilters current;

  const ClientFiltersSheet({
    super.key,
    required this.pairs,
    required this.stores,
    required this.current,
  });

  @override
  State<ClientFiltersSheet> createState() => _ClientFiltersSheetState();
}

class _ClientFiltersSheetState extends State<ClientFiltersSheet> {
  late ClientFilters _f;

  // Derived option sets from the product catalogue
  late Set<String> _allTypes;
  late Set<String> _allBrands;
  late Set<String> _allSizes;
  late Set<String> _allColors;
  late Set<String> _allCategories;

  @override
  void initState() {
    super.initState();
    _f = widget.current;
    _allTypes = {};
    _allBrands = {};
    _allSizes = {};
    _allColors = {};
    _allCategories = {};
    for (final pair in widget.pairs) {
      final p = pair.product;
      if (p.type.isNotEmpty) _allTypes.add(p.type);
      if (p.brand.isNotEmpty) _allBrands.add(p.brand);
      if (p.color.isNotEmpty) _allColors.add(p.color);
      if (p.category.isNotEmpty) _allCategories.add(p.category);
      for (final b in pair.batches) {
        _allSizes.addAll(b.availableSizes.keys);
      }
    }
  }

  int get _resultCount {
    return widget.pairs.where((pair) {
      final p = pair.product;
      final b = pair.batches;
      if (_f.types.isNotEmpty && !_f.types.contains(p.type)) return false;
      if (_f.brands.isNotEmpty && !_f.brands.contains(p.brand)) return false;
      if (_f.colors.isNotEmpty && !_f.colors.contains(p.color)) return false;
      if (_f.categories.isNotEmpty && !_f.categories.contains(p.category)) {
        return false;
      }
      if (_f.sizes.isNotEmpty) {
        final has = b
            .any((bt) => _f.sizes.any((s) => bt.availableSizes.containsKey(s)));
        if (!has) return false;
      }
      if (_f.minPrice != null || _f.maxPrice != null) {
        final has = b.any((bt) =>
            (_f.minPrice == null || bt.sellingPrice >= _f.minPrice!) &&
            (_f.maxPrice == null || bt.sellingPrice <= _f.maxPrice!));
        if (!has) return false;
      }
      return true;
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final count = _resultCount;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(children: [
              const Text('Фильтры',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary)),
              const Spacer(),
              if (_f.activeCount > 0)
                TextButton(
                  onPressed: () => setState(() => _f = const ClientFilters()),
                  child: const Text('Сбросить',
                      style: TextStyle(color: AppTheme.danger, fontSize: 13)),
                ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              children: [
                // Store selector (multiple stores)
                if (widget.stores.length > 1) ...[
                  _SectionTitle('Магазин'),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _OptionChip(
                      label: 'Все магазины',
                      selected: _f.storeId == null,
                      onTap: () =>
                          setState(() => _f = _f.copyWith(storeId: null)),
                    ),
                    ...widget.stores.map((s) => _OptionChip(
                          label: s.storeName,
                          selected: _f.storeId == s.adminUid,
                          onTap: () => setState(
                              () => _f = _f.copyWith(storeId: s.adminUid)),
                        )),
                  ]),
                  const SizedBox(height: 20),
                ],

                // Types
                if (_allTypes.isNotEmpty) ...[
                  _SectionTitle('Тип'),
                  const SizedBox(height: 8),
                  Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _sortedList(_allTypes)
                          .map((v) => _OptionChip(
                                label: v,
                                selected: _f.types.contains(v),
                                onTap: () => setState(() {
                                  final s = Set<String>.from(_f.types);
                                  s.contains(v) ? s.remove(v) : s.add(v);
                                  _f = _f.copyWith(types: s);
                                }),
                              ))
                          .toList()),
                  const SizedBox(height: 20),
                ],

                // Brands
                if (_allBrands.isNotEmpty) ...[
                  _SectionTitle('Бренд'),
                  const SizedBox(height: 8),
                  Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _sortedList(_allBrands)
                          .map((v) => _OptionChip(
                                label: v,
                                selected: _f.brands.contains(v),
                                onTap: () => setState(() {
                                  final s = Set<String>.from(_f.brands);
                                  s.contains(v) ? s.remove(v) : s.add(v);
                                  _f = _f.copyWith(brands: s);
                                }),
                              ))
                          .toList()),
                  const SizedBox(height: 20),
                ],

                // Sizes — grid style
                if (_allSizes.isNotEmpty) ...[
                  _SectionTitle('Размер'),
                  const SizedBox(height: 8),
                  Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _sortedSizes(_allSizes)
                          .map((v) => _SizeChip(
                                label: v,
                                selected: _f.sizes.contains(v),
                                onTap: () => setState(() {
                                  final s = Set<String>.from(_f.sizes);
                                  s.contains(v) ? s.remove(v) : s.add(v);
                                  _f = _f.copyWith(sizes: s);
                                }),
                              ))
                          .toList()),
                  const SizedBox(height: 20),
                ],

                // Colors
                if (_allColors.isNotEmpty) ...[
                  _SectionTitle('Цвет'),
                  const SizedBox(height: 8),
                  Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _sortedList(_allColors)
                          .map((v) => _OptionChip(
                                label: v,
                                selected: _f.colors.contains(v),
                                onTap: () => setState(() {
                                  final s = Set<String>.from(_f.colors);
                                  s.contains(v) ? s.remove(v) : s.add(v);
                                  _f = _f.copyWith(colors: s);
                                }),
                              ))
                          .toList()),
                  const SizedBox(height: 20),
                ],

                // Categories
                if (_allCategories.isNotEmpty) ...[
                  _SectionTitle('Категория'),
                  const SizedBox(height: 8),
                  Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _sortedList(_allCategories)
                          .map((v) => _OptionChip(
                                label: v,
                                selected: _f.categories.contains(v),
                                onTap: () => setState(() {
                                  final s = Set<String>.from(_f.categories);
                                  s.contains(v) ? s.remove(v) : s.add(v);
                                  _f = _f.copyWith(categories: s);
                                }),
                              ))
                          .toList()),
                  const SizedBox(height: 20),
                ],

                // Price range
                _SectionTitle('Цена (₸)'),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: _PriceField(
                    hint: 'От',
                    initial: _f.minPrice,
                    onChanged: (v) =>
                        setState(() => _f = _f.copyWith(minPrice: v)),
                  )),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _PriceField(
                    hint: 'До',
                    initial: _f.maxPrice,
                    onChanged: (v) =>
                        setState(() => _f = _f.copyWith(maxPrice: v)),
                  )),
                ]),
                const SizedBox(height: 24),
              ],
            ),
          ),
          // Bottom button
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, -4))
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, _f),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: Text(
                  count > 0 ? 'Показать $count товаров' : 'Нет результатов',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  List<String> _sortedList(Set<String> s) =>
      s.toList()..sort((a, b) => a.compareTo(b));

  List<String> _sortedSizes(Set<String> s) {
    final list = s.toList();
    list.sort((a, b) {
      final na = double.tryParse(a);
      final nb = double.tryParse(b);
      if (na != null && nb != null) return na.compareTo(nb);
      return a.compareTo(b);
    });
    return list;
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary));
}

class _OptionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _OptionChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : AppTheme.background,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: selected ? AppTheme.primary : AppTheme.border),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppTheme.textPrimary)),
        ),
      );
}

class _SizeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SizeChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 52,
          height: 42,
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : AppTheme.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected ? AppTheme.primary : AppTheme.border,
                width: selected ? 2 : 1),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppTheme.textPrimary)),
          ),
        ),
      );
}

class _PriceField extends StatefulWidget {
  final String hint;
  final double? initial;
  final void Function(double?) onChanged;
  const _PriceField(
      {required this.hint, this.initial, required this.onChanged});

  @override
  State<_PriceField> createState() => _PriceFieldState();
}

class _PriceFieldState extends State<_PriceField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: widget.initial != null ? widget.initial!.toStringAsFixed(0) : '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _ctrl,
        keyboardType: TextInputType.number,
        onChanged: (v) {
          final d = double.tryParse(v.trim());
          widget.onChanged(d);
        },
        decoration: InputDecoration(
          hintText: widget.hint,
          suffixText: '₸',
          filled: true,
          fillColor: AppTheme.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.border),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      );
}
