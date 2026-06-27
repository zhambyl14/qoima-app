import 'package:flutter/material.dart';
import '../../../core/app_user.dart';
import '../../../core/l10n_ext.dart';
import '../../../data/models/models.dart';
import '../../../data/services/return_service.dart';
import '../../../theme/qoima_design.dart';

/// Seller-side offline return: browse recent sales → select items → pick refund method.
class SellerMakeOfflineReturnScreen extends StatefulWidget {
  const SellerMakeOfflineReturnScreen({super.key});

  @override
  State<SellerMakeOfflineReturnScreen> createState() =>
      _SellerMakeOfflineReturnScreenState();
}

class _SellerMakeOfflineReturnScreenState
    extends State<SellerMakeOfflineReturnScreen> {
  int _step = 0; // 0=find, 1=items+reason, 2=refund

  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _loading = true;
  List<SaleModel> _allSales = [];
  SaleModel? _selectedSale;

  final Map<String, ({ReturnItem item, bool selected})> _itemMap = {};
  ReturnReason _reason = ReturnReason.sizeNotFit;
  RefundMethod _refundMethod = RefundMethod.cash;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSales() async {
    setState(() => _loading = true);
    try {
      final results = await ReturnService().findRecentSales(
        adminUid: AppUser.current.ownerUid,
        days: 14,
      );
      if (mounted) setState(() => _allSales = results);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<SaleModel> get _filteredSales {
    if (_searchQuery.isEmpty) return _allSales;
    final q = _searchQuery.toUpperCase();
    return _allSales.where((s) {
      return s.id.toUpperCase().contains(q) ||
          s.receiptNumber.toUpperCase().contains(q) ||
          s.productName.toUpperCase().contains(q);
    }).toList();
  }

  void _selectSale(SaleModel sale) {
    _itemMap.clear();
    // Бір дананың бағасы = сатылым сомасы ÷ жалпы дана саны.
    // (Бұрын fold-тың бастапқы мәні 1 болғандықтан, баға екі есе төмен шығатын.)
    final totalQty = sale.quantity > 0
        ? sale.quantity
        : sale.sizesSold.values.fold(0, (s, v) => s + v);
    final perUnit = totalQty > 0 ? sale.totalPrice / totalQty : sale.totalPrice;
    for (final entry in sale.sizesSold.entries) {
      if (entry.value <= 0) continue;
      _itemMap[entry.key] = (
        item: ReturnItem(
          productId: sale.productId,
          productTitle: sale.productName,
          batchId: sale.batchId,
          size: entry.key,
          quantity: entry.value,
          pricePerUnit: perUnit,
        ),
        selected: true,
      );
    }
    setState(() {
      _selectedSale = sale;
      // Қайтару әдісі = төлем әдісі (таңдау жоқ — отчёт бұзылмауы үшін).
      _refundMethod = refundMethodForPayment(sale.paymentMethod);
      _step = 1;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final items = _itemMap.values
        .where((e) => e.selected)
        .map((e) => e.item)
        .toList();
    if (items.isEmpty) return;

    setState(() => _submitting = true);
    try {
      await ReturnService().createOfflineReturn(
        adminUid: AppUser.current.ownerUid,
        sourceSale: _selectedSale!,
        items: items,
        reason: _reason,
        method: _refundMethod,
        sellerId: AppUser.current.uid,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.l10n.returnRefundSuccess),
          backgroundColor: cGreen,
          behavior: SnackBarBehavior.floating,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        Container(
          decoration: const BoxDecoration(gradient: kGrad),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
              child: Row(children: [
                GestureDetector(
                  onTap: () {
                    if (_step > 0) {
                      setState(() => _step--);
                    } else {
                      Navigator.pop(context);
                    }
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Офлайн возврат',
                          style: manrope(21, FontWeight.w800,
                              color: Colors.white, letterSpacing: -0.5)),
                      Text(
                        _step == 0
                            ? context.l10n.returnOfflineFindReceipt
                            : _step == 1
                                ? context.l10n.returnOfflineSelectItems
                                : context.l10n.returnOfflineRefundMethod,
                        style: manrope(13, FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.75)),
                      ),
                    ],
                  ),
                ),
                // Step indicator
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${_step + 1}/3',
                      style: manrope(12, FontWeight.w700,
                          color: Colors.white)),
                ),
              ]),
            ),
          ),
        ),
        Expanded(
          child: _step == 0
              ? _FindStep(
                  searchCtrl: _searchCtrl,
                  searchQuery: _searchQuery,
                  loading: _loading,
                  sales: _filteredSales,
                  onQueryChanged: (q) =>
                      setState(() => _searchQuery = q),
                  onRefresh: _loadSales,
                  onSelect: _selectSale,
                )
              : _step == 1
                  ? _ItemsStep(
                      itemMap: _itemMap,
                      reason: _reason,
                      onItemToggled: (k, v) =>
                          setState(() => _itemMap[k] = v),
                      onReasonChanged: (r) =>
                          setState(() => _reason = r),
                      onNext: () => setState(() => _step = 2),
                    )
                  : _RefundStep(
                      method: _refundMethod,
                      onSubmit: _submit,
                      submitting: _submitting,
                    ),
        ),
      ]),
    );
  }
}

// ── Step 0: Browse recent sales ───────────────────────────────────────────────
class _FindStep extends StatelessWidget {
  final TextEditingController searchCtrl;
  final String searchQuery;
  final bool loading;
  final List<SaleModel> sales;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onRefresh;
  final ValueChanged<SaleModel> onSelect;

  const _FindStep({
    required this.searchCtrl,
    required this.searchQuery,
    required this.loading,
    required this.sales,
    required this.onQueryChanged,
    required this.onRefresh,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Search field
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Container(
          decoration: BoxDecoration(
            color: cSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cLine),
          ),
          child: TextField(
            controller: searchCtrl,
            onChanged: onQueryChanged,
            style: manrope(14.5, FontWeight.w500, color: cInk),
            decoration: InputDecoration(
              hintText: context.l10n.returnOfflineReceiptHint,
              hintStyle: manrope(14, FontWeight.w500, color: cInk3),
              prefixIcon:
                  const Icon(Icons.search_rounded, color: cInk3, size: 20),
              suffixIcon: searchQuery.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        searchCtrl.clear();
                        onQueryChanged('');
                      },
                      child: const Icon(Icons.close_rounded,
                          color: cInk3, size: 18),
                    )
                  : null,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
            ),
          ),
        ),
      ),

      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Row(children: [
          Text('Последние 14 дней',
              style: manrope(12, FontWeight.w600, color: cInk3)),
          const Spacer(),
          Text('${sales.length} продаж',
              style: manrope(12, FontWeight.w600, color: cInk3)),
        ]),
      ),

      if (loading)
        const Expanded(
          child:
              Center(child: CircularProgressIndicator(color: cGreen)),
        )
      else if (sales.isEmpty)
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.receipt_long_outlined,
                    size: 52, color: cInk3),
                const SizedBox(height: 12),
                Text(
                    searchQuery.isNotEmpty
                        ? 'По запросу «$searchQuery» ничего не найдено'
                        : 'Офлайн-продаж за последние 14 дней нет',
                    style: manrope(14, FontWeight.w500, color: cInk2),
                    textAlign: TextAlign.center),
                if (searchQuery.isEmpty) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded,
                        color: cGreen, size: 16),
                    label: Text('Обновить',
                        style: manrope(13, FontWeight.w600, color: cGreen)),
                  ),
                ],
              ],
            ),
          ),
        )
      else
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            itemCount: sales.length,
            itemBuilder: (_, i) =>
                _SaleCard(sale: sales[i], onTap: () => onSelect(sales[i])),
          ),
        ),
    ]);
  }
}

class _SaleCard extends StatelessWidget {
  final SaleModel sale;
  final VoidCallback onTap;
  const _SaleCard({required this.sale, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = sale.saleDate;
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    final timeStr =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cLine),
          boxShadow: kShadowSm,
        ),
        child: Row(children: [
          QIconTile(
            icon: const Icon(Icons.receipt_long_outlined,
                color: cGreen, size: 20),
            tone: 'green',
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sale.productName,
                    style: manrope(14, FontWeight.w700, color: cInk),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                  sale.receiptNumber.isNotEmpty
                      ? '${sale.receiptNumber}  ·  $dateStr $timeStr'
                      : '${sale.id}  ·  $dateStr $timeStr',
                  style: manrope(11.5, FontWeight.w500, color: cInk3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('${sale.totalPrice.toStringAsFixed(0)} ₸',
              style: manrope(14, FontWeight.w800, color: cInk)),
        ]),
      ),
    );
  }
}

// ── Step 1: Items + reason ────────────────────────────────────────────────────
class _ItemsStep extends StatelessWidget {
  final Map<String, ({ReturnItem item, bool selected})> itemMap;
  final ReturnReason reason;
  final void Function(String, ({ReturnItem item, bool selected})) onItemToggled;
  final ValueChanged<ReturnReason> onReasonChanged;
  final VoidCallback onNext;

  const _ItemsStep({
    required this.itemMap,
    required this.reason,
    required this.onItemToggled,
    required this.onReasonChanged,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final hasSelection = itemMap.values.any((e) => e.selected);
    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          children: [
            Text(context.l10n.returnSelectItemsHint,
                style: manrope(13, FontWeight.w600, color: cInk3)),
            const SizedBox(height: 10),
            ...itemMap.entries.map((e) {
              final entry = e.value;
              return GestureDetector(
                onTap: () => onItemToggled(
                    e.key, (item: entry.item, selected: !entry.selected)),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: entry.selected ? cGreenTint : cSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: entry.selected ? cGreen : cLine,
                        width: entry.selected ? 1.5 : 1),
                  ),
                  child: Row(children: [
                    Icon(
                      entry.selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: entry.selected ? cGreen : cInk3,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.item.productTitle,
                              style: manrope(13.5, FontWeight.w700,
                                  color: cInk),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(
                              'Р.${entry.item.size}  ×${entry.item.quantity}',
                              style: manrope(12, FontWeight.w500,
                                  color: cInk3)),
                        ],
                      ),
                    ),
                    Text('${entry.item.subtotal.toStringAsFixed(0)} ₸',
                        style: manrope(13.5, FontWeight.w700, color: cInk)),
                  ]),
                ),
              );
            }),
            const SizedBox(height: 14),
            Text(context.l10n.returnReasonLabel,
                style: manrope(13, FontWeight.w600, color: cInk3)),
            const SizedBox(height: 8),
            ...ReturnReason.values.map((r) => GestureDetector(
                  onTap: () => onReasonChanged(r),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: reason == r ? cGreenTint : cSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: reason == r ? cGreen : cLine,
                          width: reason == r ? 1.5 : 1),
                    ),
                    child: Row(children: [
                      Icon(
                        reason == r
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: reason == r ? cGreen : cInk3,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(r.label(context),
                          style: manrope(13.5, FontWeight.w600,
                              color: reason == r ? cGreenDeep : cInk)),
                    ]),
                  ),
                )),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: hasSelection ? onNext : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: cGreen,
              foregroundColor: Colors.white,
              disabledBackgroundColor: cLine,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: Text('Далее',
                style: manrope(15, FontWeight.w700, color: Colors.white)),
          ),
        ),
      ),
    ]);
  }
}

// ── Step 2: Refund method (төлем әдісіне тең — таңдау жоқ) ─────────────────────
class _RefundStep extends StatelessWidget {
  final RefundMethod method;
  final VoidCallback onSubmit;
  final bool submitting;

  const _RefundStep({
    required this.method,
    required this.onSubmit,
    required this.submitting,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          children: [
            Text(context.l10n.returnRefundMethodLabel,
                style: manrope(13, FontWeight.w600, color: cInk3)),
            const SizedBox(height: 10),
            // Қайтару әдісі төлем әдісіне тең — өзгертуге болмайды.
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cGreenTint,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cGreen, width: 1.5),
              ),
              child: Row(children: [
                Icon(
                  method == RefundMethod.cash
                      ? Icons.payments_outlined
                      : Icons.credit_card_rounded,
                  color: cGreen,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(method.label(context),
                          style: manrope(15, FontWeight.w700,
                              color: cGreenDeep)),
                      Text('Төлем әдісіне сәйкес',
                          style:
                              manrope(12, FontWeight.w500, color: cInk3)),
                    ],
                  ),
                ),
                const Icon(Icons.lock_outline_rounded,
                    color: cInk3, size: 18),
              ]),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: submitting ? null : onSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: cGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Text(context.l10n.returnCompleteRefund,
                    style:
                        manrope(15, FontWeight.w700, color: Colors.white)),
          ),
        ),
      ),
    ]);
  }
}
