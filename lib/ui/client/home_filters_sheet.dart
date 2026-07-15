import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/lang.dart';
import '../../data/models/category_data.dart';
import '../../data/models/store_model.dart';
import '../../theme/qoima_design.dart';
import 'client_home_screen.dart' show ClientFilters;

/// Басты беттің фильтр sheet-і. Нәтиже: жаңа [ClientFilters] немесе null
/// (өзгеріссіз жабылды).
Future<ClientFilters?> showHomeFiltersSheet(
  BuildContext context, {
  required ClientFilters current,
  required List<StoreModel> stores,
}) =>
    showModalBottomSheet<ClientFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FiltersSheet(current: current, stores: stores),
    );

class _FiltersSheet extends StatefulWidget {
  final ClientFilters current;
  final List<StoreModel> stores;
  const _FiltersSheet({required this.current, required this.stores});

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late Set<String> _categoryKeys = {...widget.current.categoryKeys};
  late Set<String> _audiences = {...widget.current.categories};
  late String? _storeId = widget.current.storeId;
  late bool _onSale = widget.current.onSale;
  late String _sort = widget.current.sort;
  late final _minCtrl = TextEditingController(
      text: widget.current.minPrice?.toStringAsFixed(0) ?? '');
  late final _maxCtrl = TextEditingController(
      text: widget.current.maxPrice?.toStringAsFixed(0) ?? '');

  static const List<String> _audienceValues = [
    'Мужские',
    'Женские',
    'Унисекс',
    'Детские',
  ];

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _categoryKeys = {};
      _audiences = {};
      _storeId = null;
      _onSale = false;
      _sort = 'default';
      _minCtrl.clear();
      _maxCtrl.clear();
    });
  }

  void _apply() {
    final min = double.tryParse(_minCtrl.text.trim());
    final max = double.tryParse(_maxCtrl.text.trim());
    // Теріс/ауыстырылған аралықты жөндейміз (min > max → орындарын ауыстыру).
    double? lo = min, hi = max;
    if (lo != null && hi != null && lo > hi) {
      final t = lo;
      lo = hi;
      hi = t;
    }
    Navigator.pop(
      context,
      ClientFilters(
        categoryKeys: _categoryKeys,
        categories: _audiences,
        storeId: _storeId,
        minPrice: lo,
        maxPrice: hi,
        onSale: _onSale,
        sort: _sort,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxH = MediaQuery.of(context).size.height * 0.85;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(top: 12, bottom: 4),
          decoration: BoxDecoration(
              color: cLine, borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Row(children: [
            Expanded(
              child: Text(tr('Фильтры', 'Сүзгілер'),
                  style: manrope(18, FontWeight.w800, color: cInk)),
            ),
            GestureDetector(
              onTap: _reset,
              child: Text(tr('Сбросить', 'Тазалау'),
                  style: manrope(13.5, FontWeight.w700, color: cRed)),
            ),
          ]),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── Категория ─────────────────────────────────────────────
              QSecLabel(tr('Категория', 'Санат')),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kCategories.map((c) {
                  final sel = _categoryKeys.contains(c.key);
                  return _Chip(
                    label: c.short,
                    selected: sel,
                    onTap: () => setState(() =>
                        sel ? _categoryKeys.remove(c.key) : _categoryKeys.add(c.key)),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),

              // ── Кому ──────────────────────────────────────────────────
              QSecLabel(tr('Кому', 'Кімге')),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _audienceValues.map((a) {
                  final sel = _audiences.contains(a);
                  return _Chip(
                    label: trValue(a),
                    selected: sel,
                    onTap: () => setState(
                        () => sel ? _audiences.remove(a) : _audiences.add(a)),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),

              // ── Цена ──────────────────────────────────────────────────
              QSecLabel(tr('Цена, ₸', 'Баға, ₸')),
              Row(children: [
                Expanded(
                    child: _priceField(
                        _minCtrl, tr('от', 'бастап'))),
                const SizedBox(width: 10),
                Expanded(
                    child: _priceField(
                        _maxCtrl, tr('до', 'дейін'))),
              ]),
              const SizedBox(height: 18),

              // ── Скидка ────────────────────────────────────────────────
              GestureDetector(
                onTap: () => setState(() => _onSale = !_onSale),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _onSale ? cGreenTint : cBg,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                        color: _onSale ? cGreen : cLine, width: 1.5),
                  ),
                  child: Row(children: [
                    Icon(Icons.local_offer_outlined,
                        size: 18, color: _onSale ? cGreenDeep : cInk3),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(tr('Только со скидкой', 'Тек жеңілдікпен'),
                          style: manrope(14, FontWeight.w600,
                              color: _onSale ? cGreenDeep : cInk)),
                    ),
                    Icon(
                      _onSale
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: 20,
                      color: _onSale ? cGreen : cInk3,
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 18),

              // ── Магазин ───────────────────────────────────────────────
              if (widget.stores.isNotEmpty) ...[
                QSecLabel(tr('Магазин', 'Дүкен')),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Chip(
                      label: tr('Все', 'Барлығы'),
                      selected: _storeId == null,
                      onTap: () => setState(() => _storeId = null),
                    ),
                    ...widget.stores.map((s) => _Chip(
                          label: s.storeName,
                          selected: _storeId == s.adminUid,
                          onTap: () => setState(() => _storeId =
                              _storeId == s.adminUid ? null : s.adminUid),
                        )),
                  ],
                ),
                const SizedBox(height: 18),
              ],

              // ── Сортировка ────────────────────────────────────────────
              QSecLabel(tr('Сортировка', 'Сорттау')),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Chip(
                    label: tr('По умолчанию', 'Әдепкі'),
                    selected: _sort == 'default',
                    onTap: () => setState(() => _sort = 'default'),
                  ),
                  _Chip(
                    label: tr('Сначала дешевле', 'Арзанынан бастап'),
                    selected: _sort == 'price_asc',
                    onTap: () => setState(() => _sort = 'price_asc'),
                  ),
                  _Chip(
                    label: tr('Сначала дороже', 'Қымбатынан бастап'),
                    selected: _sort == 'price_desc',
                    onTap: () => setState(() => _sort = 'price_desc'),
                  ),
                  _Chip(
                    label: tr('По рейтингу', 'Рейтинг бойынша'),
                    selected: _sort == 'rating',
                    onTap: () => setState(() => _sort = 'rating'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ]),
          ),
        ),
        // ── Қолдану ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: QPrimaryButton(
            label: tr('Показать товары', 'Тауарларды көрсету'),
            onPressed: _apply,
            height: 52,
          ),
        ),
      ]),
    );
  }

  Widget _priceField(TextEditingController ctrl, String hint) => TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: manrope(14.5, FontWeight.w700, color: cInk),
        cursorColor: cGreen,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: manrope(14, FontWeight.w500, color: cInk3),
          filled: true,
          fillColor: cBg,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: cLine),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: cLine),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: cGreen, width: 1.5),
          ),
        ),
      );
}

// ── Chip ───────────────────────────────────────────────────────────────────────
class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? cGreenTint : cBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? cGreen : cLine, width: 1.5),
          ),
          child: Text(label,
              style: manrope(13, FontWeight.w700,
                  color: selected ? cGreenDeep : cInk)),
        ),
      );
}
