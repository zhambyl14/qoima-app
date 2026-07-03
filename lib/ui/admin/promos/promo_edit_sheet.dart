import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/models/promo_model.dart';
import '../../../data/models/product_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';

/// Открывает лист создания/редактирования промокода.
Future<void> showPromoEditSheet(BuildContext context,
    {PromoModel? existing}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PromoEditSheet(existing: existing),
  );
}

class _PromoEditSheet extends StatefulWidget {
  final PromoModel? existing;
  const _PromoEditSheet({this.existing});

  @override
  State<_PromoEditSheet> createState() => _PromoEditSheetState();
}

class _PromoEditSheetState extends State<_PromoEditSheet> {
  final _service = FirestoreService();
  final _codeCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  final _maxUsesCtrl = TextEditingController();
  final _perUserCtrl = TextEditingController(text: '1');
  final _minOrderCtrl = TextEditingController();

  String _type = 'percent';
  String _scope = 'all';
  Set<String> _productIds = {};
  String _productQuery = '';
  bool _hasDateRange = false;
  DateTime? _startsAt;
  DateTime? _endsAt;
  bool _saving = false;
  bool _generating = false;

  List<ProductModel> _products = [];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _codeCtrl.text = e.code;
      _type = e.type;
      _valueCtrl.text = e.value.toStringAsFixed(0);
      _scope = e.scope;
      _productIds = e.productIds.toSet();
      _maxUsesCtrl.text = e.maxUses?.toString() ?? '';
      _perUserCtrl.text = e.perUserLimit?.toString() ?? '';
      _minOrderCtrl.text = e.minOrder > 0 ? e.minOrder.toStringAsFixed(0) : '';
      _startsAt = e.startsAt;
      _endsAt = e.endsAt;
      _hasDateRange = e.startsAt != null || e.endsAt != null;
    }
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final list = _service.cachedProducts ?? await _service.watchProducts().first;
      if (mounted) setState(() => _products = list);
    } catch (_) {}
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _valueCtrl.dispose();
    _maxUsesCtrl.dispose();
    _perUserCtrl.dispose();
    _minOrderCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final code = await _service.generateUniquePromoCode();
      if (mounted) _codeCtrl.text = code;
    } catch (_) {} finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _startsAt : _endsAt) ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2031),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startsAt = picked;
        } else {
          _endsAt = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        }
      });
    }
  }

  void _err(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: cRed,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _save() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    final value = double.tryParse(_valueCtrl.text.trim()) ?? 0;
    if (code.isEmpty) return _err('Введите код промокода');
    if (value <= 0) return _err('Введите размер скидки');
    if (_type == 'percent' && value > 100) {
      return _err('Процент не может быть больше 100');
    }
    if (_scope == 'products' && _productIds.isEmpty) {
      return _err('Выберите хотя бы один товар');
    }

    setState(() => _saving = true);
    try {
      final promo = (widget.existing ??
              PromoModel(id: '', code: code, type: _type, value: value))
          .copyWith(
        code: code,
        type: _type,
        value: value,
        scope: _scope,
        productIds: _scope == 'products' ? _productIds.toList() : [],
        maxUses: int.tryParse(_maxUsesCtrl.text.trim()),
        perUserLimit: int.tryParse(_perUserCtrl.text.trim()),
        minOrder: double.tryParse(_minOrderCtrl.text.trim()) ?? 0,
        startsAt: _hasDateRange ? _startsAt : null,
        endsAt: _hasDateRange ? _endsAt : null,
      );
      if (_isEdit) {
        await _service.updatePromo(promo);
      } else {
        await _service.createPromo(promo);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        _err(e.toString().replaceFirst('SaleException: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: cLine, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),
                Text(_isEdit ? 'Редактировать промокод' : 'Новый промокод',
                    style: manrope(18, FontWeight.w800, color: cInk)),
                const SizedBox(height: 18),

                // Code
                Text('Код', style: _lbl),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _codeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z0-9]')),
                        _UpperCaseFormatter(),
                      ],
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5),
                      decoration: const InputDecoration(hintText: 'LETO20'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _generating ? null : _generate,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cGreen,
                        side: const BorderSide(color: cGreen),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: _generating
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: cGreen))
                          : const Icon(Icons.casino_outlined, size: 18),
                      label: Text('Код',
                          style: manrope(13, FontWeight.w700, color: cGreen)),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),

                // Type + value
                Text('Тип и размер скидки', style: _lbl),
                const SizedBox(height: 8),
                Row(children: [
                  _TypeBtn(
                      label: '% Процент',
                      selected: _type == 'percent',
                      onTap: () => setState(() => _type = 'percent')),
                  const SizedBox(width: 10),
                  _TypeBtn(
                      label: '₸ Сумма',
                      selected: _type == 'amount',
                      onTap: () => setState(() => _type = 'amount')),
                ]),
                const SizedBox(height: 8),
                TextField(
                  controller: _valueCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    hintText: _type == 'percent' ? '20' : '5000',
                    suffixText: _type == 'percent' ? '%' : '₸',
                  ),
                ),
                const SizedBox(height: 14),

                // Scope
                Text('На какие товары', style: _lbl),
                const SizedBox(height: 8),
                Row(children: [
                  _TypeBtn(
                      label: 'На всё',
                      selected: _scope == 'all',
                      onTap: () => setState(() => _scope = 'all')),
                  const SizedBox(width: 10),
                  _TypeBtn(
                      label: 'Выбранные',
                      selected: _scope == 'products',
                      onTap: () => setState(() => _scope = 'products')),
                ]),
                if (_scope == 'products') ...[
                  const SizedBox(height: 10),
                  if (_products.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                          child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: cGreen))),
                    )
                  else ...[
                    // Поиск товара
                    TextField(
                      onChanged: (v) =>
                          setState(() => _productQuery = v.trim().toLowerCase()),
                      decoration: const InputDecoration(
                        hintText: 'Тауар іздеу (атауы, бренд, артикул)',
                        prefixIcon: Icon(Icons.search_rounded, color: cInk3),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (_productIds.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('Таңдалды: ${_productIds.length}',
                            style: manrope(12, FontWeight.w600, color: cGreen)),
                      ),
                    const SizedBox(height: 8),
                    Builder(builder: (_) {
                      final filtered = _productQuery.isEmpty
                          ? _products
                          : _products
                              .where((p) =>
                                  p.name.toLowerCase().contains(_productQuery) ||
                                  p.brand.toLowerCase().contains(_productQuery) ||
                                  p.articul.toLowerCase().contains(_productQuery))
                              .toList();
                      if (filtered.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text('Тауар табылмады',
                              style: manrope(13, FontWeight.w500, color: cInk3)),
                        );
                      }
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: filtered.map((p) {
                          final sel = _productIds.contains(p.id);
                          return GestureDetector(
                            onTap: () => setState(() {
                              if (sel) {
                                _productIds.remove(p.id);
                              } else {
                                _productIds.add(p.id);
                              }
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: sel ? cGreen : cSurface,
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: sel ? cGreen : cLine),
                              ),
                              child: Text(p.name,
                                  style: manrope(12.5, FontWeight.w600,
                                      color: sel ? Colors.white : cInk)),
                            ),
                          );
                        }).toList(),
                      );
                    }),
                  ],
                ],
                const SizedBox(height: 16),

                // Limits
                Text('Лимиты', style: _lbl),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: _NumField(
                        controller: _maxUsesCtrl,
                        label: 'Всего',
                        hint: '∞'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _NumField(
                        controller: _perUserCtrl,
                        label: 'На клиента',
                        hint: '∞'),
                  ),
                ]),
                const SizedBox(height: 10),
                _NumField(
                    controller: _minOrderCtrl,
                    label: 'Мин. сумма заказа (₸)',
                    hint: '0'),
                const SizedBox(height: 16),

                // Date range
                Row(children: [
                  Switch(
                    value: _hasDateRange,
                    activeTrackColor: cGreen,
                    onChanged: (v) => setState(() => _hasDateRange = v),
                  ),
                  const SizedBox(width: 8),
                  Text('Ограничить по времени',
                      style: manrope(13.5, FontWeight.w600, color: cInk)),
                ]),
                if (_hasDateRange) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                        child: _DateBtn(
                            label: 'С',
                            date: _startsAt,
                            onTap: () => _pickDate(isStart: true))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _DateBtn(
                            label: 'По',
                            date: _endsAt,
                            onTap: () => _pickDate(isStart: false))),
                  ]),
                ],
                const SizedBox(height: 22),
                QPrimaryButton(
                  label: _isEdit ? 'Сохранить' : 'Создать промокод',
                  isLoading: _saving,
                  onPressed: _saving ? null : _save,
                  height: 52,
                ),
              ]),
        ),
      ),
    );
  }

  TextStyle get _lbl => manrope(12.5, FontWeight.w600, color: cInk2);
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
          TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

class _TypeBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TypeBtn(
      {required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: selected ? cGreen : cSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? cGreen : cLine),
            ),
            child: Center(
              child: Text(label,
                  style: manrope(13, FontWeight.w700,
                      color: selected ? Colors.white : cInk2)),
            ),
          ),
        ),
      );
}

class _NumField extends StatelessWidget {
  final TextEditingController controller;
  final String label, hint;
  const _NumField(
      {required this.controller, required this.label, required this.hint});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: manrope(11.5, FontWeight.w500, color: cInk3)),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(hintText: hint),
          ),
        ],
      );
}

class _DateBtn extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  const _DateBtn(
      {required this.label, required this.date, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: cSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: date != null ? cGreen : cLine),
          ),
          child: Row(children: [
            Icon(Icons.calendar_today_outlined,
                size: 15, color: date != null ? cGreen : cInk3),
            const SizedBox(width: 6),
            Text(
              date != null
                  ? '${date!.day.toString().padLeft(2, '0')}.${date!.month.toString().padLeft(2, '0')}.${date!.year}'
                  : label,
              style: manrope(13, FontWeight.w600,
                  color: date != null ? cInk : cInk3),
            ),
          ]),
        ),
      );
}

