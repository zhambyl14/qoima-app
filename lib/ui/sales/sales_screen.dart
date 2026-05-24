import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/l10n_ext.dart';
import '../../core/warehouse_context.dart';
import '../../data/models/models.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/app_theme.dart';
import 'make_sale_screen.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final _service = FirestoreService();
  DateTime _month = DateTime.now();

  List<SaleModel> _filterMonth(List<SaleModel> all) => all
      .where((s) => s.saleDate.month == _month.month && s.saleDate.year == _month.year)
      .toList();

  // Саттушы: тек өз сатылымдарын көреді
  List<SaleModel> _filterSeller(List<SaleModel> all) => AppUser.isAdmin
      ? all
      : all.where((s) => s.sellerId == AppUser.uid).toList();

  void _showHistorySheet(List<SaleModel> all, List<ProductModel> products,
      List<WarehouseModel> warehouses) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, ctrl) => _HistorySheet(
          sales: _filterSeller(all),
          products: products,
          warehouses: warehouses,
          scrollCtrl: ctrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final warehouses = context.watch<WarehouseContext>().all;
    return Scaffold(
      backgroundColor: AppTheme.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const MakeSaleScreen())),
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add_shopping_cart_rounded, color: Colors.white),
        label: Text(context.l10n.makeSale, style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.w700)),
      ),
      body: StreamBuilder<List<SaleModel>>(
        stream: _service.watchSalesHistory(),
        builder: (_, salesSnap) {
          final allSales = salesSnap.data ?? [];
          return StreamBuilder<List<ProductModel>>(
            stream: _service.watchProducts(),
            builder: (_, prodSnap) {
              final products = prodSnap.data ?? [];
              final monthSales = _filterSeller(_filterMonth(allSales));
              final total = monthSales.fold<double>(0, (s, e) => s + e.totalPrice);

              return CustomScrollView(slivers: [
                // ── Header ─────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                          colors: [Color(0xFF1E3A8A), Color(0xFF2D4FB5)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight),
                    ),
                    child: SafeArea(bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 16, 20),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(context.l10n.salesTitle,
                                  style: const TextStyle(color: Colors.white, fontSize: 26,
                                      fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                              Text(
                                AppUser.isAdmin ? context.l10n.overviewSub : context.l10n.makeSaleHint,
                                style: const TextStyle(color: Colors.white60, fontSize: 13),
                              ),
                            ]),
                          ),
                          // Тарих батырмасы
                          GestureDetector(
                            onTap: () => _showHistorySheet(allSales, products, warehouses),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.3))),
                              child: Row(children: [
                                const Icon(Icons.history_rounded, color: Colors.white, size: 16),
                                const SizedBox(width: 4),
                                Text(context.l10n.history, style: const TextStyle(color: Colors.white,
                                    fontWeight: FontWeight.w600, fontSize: 13)),
                              ]),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),

                // ── Body ───────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: _SalesBody(
                    sales: monthSales,
                    total: total,
                    month: _month,
                    showRevenue: AppUser.isAdmin,
                    products: products,
                    warehouses: warehouses,
                    onMonthTap: _pickMonth,
                  ),
                ),
              ]);
            },
          );
        },
      ),
    );
  }

  Future<void> _pickMonth() async {
    DateTime temp = _month;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(context.l10n.selectMonth, style: const TextStyle(
            fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
        content: StatefulBuilder(builder: (_, setS) => SizedBox(
          width: 280,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              IconButton(icon: const Icon(Icons.chevron_left, color: AppTheme.primary),
                  onPressed: () => setS(() => temp = DateTime(temp.year - 1, temp.month))),
              Text('${temp.year}', style: const TextStyle(fontWeight: FontWeight.w700,
                  fontSize: 17, color: AppTheme.textPrimary)),
              IconButton(icon: const Icon(Icons.chevron_right, color: AppTheme.primary),
                  onPressed: () => setS(() => temp = DateTime(temp.year + 1, temp.month))),
            ]),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4, childAspectRatio: 1.4,
                  crossAxisSpacing: 6, mainAxisSpacing: 6),
              itemCount: 12,
              itemBuilder: (_, i) {
                final sel = temp.month == i + 1;
                final mn = context.monthAbbreviations;
                return GestureDetector(
                  onTap: () => setS(() => temp = DateTime(temp.year, i + 1)),
                  child: Container(
                    decoration: BoxDecoration(
                        color: sel ? AppTheme.primary : AppTheme.background,
                        borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Text(mn[i], style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : AppTheme.textSecondary)))));
              },
            ),
          ]),
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text(context.l10n.cancel,
                  style: const TextStyle(color: AppTheme.textSecondary))),
          ElevatedButton(
            onPressed: () { setState(() => _month = temp); Navigator.pop(ctx); },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text(context.l10n.apply)),
        ],
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────
class _SalesBody extends StatelessWidget {
  final List<SaleModel> sales;
  final List<ProductModel> products;
  final List<WarehouseModel> warehouses;
  final double total;
  final DateTime month;
  final bool showRevenue;
  final VoidCallback onMonthTap;

  const _SalesBody({
    required this.sales, required this.products, required this.warehouses,
    required this.total, required this.month, required this.showRevenue,
    required this.onMonthTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Ай таңдау + жиынтық (тек Admin)
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Row(children: [
          // Ай picker chip
          GestureDetector(
            onTap: onMonthTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.border),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6, offset: const Offset(0, 2))]),
              child: Row(children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 14, color: AppTheme.primary),
                const SizedBox(width: 6),
                Text(_fmtShort(month, context), style: const TextStyle(
                    color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.primary, size: 16),
              ]),
            ),
          ),
          const Spacer(),
          if (showRevenue)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${_fmtNum(total)} ₸',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary)),
              Text('${sales.length} ${context.l10n.salesSuffix}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textHint)),
            ])
          else
            Text('Бүгінгі: ${sales.where((s) => _isToday(s.saleDate)).length} сат.',
                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600)),
        ]),
      ),

      // Тізім
      if (sales.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 60, bottom: 40),
          child: Column(children: [
            Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(context.l10n.noSalesThisMonth,
                style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500)),
          ]),
        )
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.l10n.operations, style: const TextStyle(fontSize: 15,
                fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            const SizedBox(height: 10),
            ...sales.map((s) {
              final prod = products.firstWhere((p) => p.id == s.productId,
                  orElse: () => ProductModel(id: '', name: context.l10n.productDeleted,
                      brand: '', type: '', material: '', category: '',
                      color: '', articul: '', status: '', images: []));
              String whName = '';
              if (s.warehouseId.isNotEmpty) {
                try { whName = warehouses.firstWhere((w) => w.id == s.warehouseId).name; }
                catch (_) {}
              }
              return _SaleCard(sale: s, product: prod, warehouseName: whName);
            }),
          ]),
        ),
    ]);
  }

  static bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  static String _fmtNum(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000)    return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }

  String _fmtShort(DateTime d, BuildContext ctx) => ctx.monthShort(d);
}

// ── Sale Card ─────────────────────────────────────────────────────────────────
class _SaleCard extends StatelessWidget {
  final SaleModel sale;
  final ProductModel product;
  final String warehouseName;
  const _SaleCard({required this.sale, required this.product, this.warehouseName = ''});

  @override
  Widget build(BuildContext context) {
    final d = sale.saleDate;
    final dateStr = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}';
    final timeStr = '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    final sizesText = sale.sizesSold.entries
        .where((e) => e.value > 0)
        .map((e) => 'Р.${e.key}×${e.value}')
        .join('  ');

    return GestureDetector(
      onTap: () => _showDetail(context, dateStr, timeStr),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8, offset: const Offset(0, 2))]),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: product.images.isNotEmpty
                  ? Image.network(product.images.first, width: 48, height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _icon())
                  : _icon(),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700,
                  fontSize: 14, color: AppTheme.textPrimary),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('$dateStr · $timeStr', style: const TextStyle(
                  color: AppTheme.textHint, fontSize: 11)),
              if (sizesText.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(sizesText, style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 11)),
              ],
              if (sale.sellerName.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.badge_outlined, size: 11, color: AppTheme.textHint),
                  const SizedBox(width: 3),
                  Text(sale.sellerName, style: const TextStyle(
                      color: AppTheme.textHint, fontSize: 11)),
                ]),
              ],
              if (warehouseName.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.warehouse_outlined, size: 11, color: AppTheme.textHint),
                  const SizedBox(width: 3),
                  Text(warehouseName, style: const TextStyle(
                      color: AppTheme.textHint, fontSize: 11)),
                ]),
              ],
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (sale.discountPercent > 0)
                Text('${sale.basePrice.toStringAsFixed(0)} ₸',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textHint,
                        decoration: TextDecoration.lineThrough)),
              Text('${sale.totalPrice.toStringAsFixed(0)} ₸',
                  style: const TextStyle(fontWeight: FontWeight.w800,
                      fontSize: 16, color: AppTheme.success)),
              if (sale.discountPercent > 0)
                Text('-${sale.discountPercent.toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 11, color: AppTheme.warning,
                        fontWeight: FontWeight.w600)),
              Text('${sale.quantity} жұп',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textHint)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _icon() => Container(
      width: 48, height: 48,
      decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10)),
      child: const Icon(Icons.inventory_2_outlined, color: AppTheme.primary, size: 22));

  void _showDetail(BuildContext context, String dateStr, String timeStr) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(10),
              child: product.images.isNotEmpty
                  ? Image.network(product.images.first, width: 56, height: 56,
                      fit: BoxFit.cover, errorBuilder: (_, __, ___) => _detailIcon())
                  : _detailIcon()),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700,
                  fontSize: 16, color: AppTheme.textPrimary)),
              Text('${product.brand} · ${product.type}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            ])),
          ]),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 10),
          _InfoRow(label: 'Сату күні', value: '$dateStr · $timeStr'),
          if (sale.sellerName.isNotEmpty)
            _InfoRow(label: 'Саттушы', value: sale.sellerName),
          if (warehouseName.isNotEmpty)
            _InfoRow(label: 'Қойма', value: warehouseName),
          if (sale.discountPercent > 0) ...[
            _InfoRow(label: 'Скидка', value: '-${sale.discountPercent.toStringAsFixed(0)}% '
                '(−${sale.discountAmount.toStringAsFixed(0)} ₸)'),
          ],
          const SizedBox(height: 10),
          const Text('Сатылған размерлер:', style: TextStyle(
              fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 6,
            children: sale.sizesSold.entries.where((e) => e.value > 0)
                .map((e) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text('Р.${e.key} × ${e.value} жұп',
                      style: const TextStyle(fontWeight: FontWeight.w600,
                          color: AppTheme.primary, fontSize: 13))))
                .toList(),
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Барлығы:', style: TextStyle(
                fontSize: 15, color: AppTheme.textSecondary)),
            Text('${sale.totalPrice.toStringAsFixed(0)} ₸',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                    color: AppTheme.success)),
          ]),
        ]),
      ),
    );
  }

  Widget _detailIcon() => Container(
      width: 56, height: 56, color: AppTheme.primary.withValues(alpha: 0.08),
      child: const Icon(Icons.inventory_2_outlined, color: AppTheme.primary));
}

// ── History Sheet ─────────────────────────────────────────────────────────────
class _HistorySheet extends StatelessWidget {
  final List<SaleModel> sales;
  final List<ProductModel> products;
  final List<WarehouseModel> warehouses;
  final ScrollController scrollCtrl;
  const _HistorySheet({required this.sales, required this.products,
      required this.warehouses, required this.scrollCtrl});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Column(children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Операциялар тарихы', style: TextStyle(fontSize: 17,
                fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            const Spacer(),
            Text('${sales.length} жазба', style: const TextStyle(
                color: AppTheme.textHint, fontSize: 13)),
          ]),
          const SizedBox(height: 12),
          const Divider(height: 1),
        ]),
      ),
      Expanded(
        child: sales.isEmpty
            ? const Center(child: Text('Сатылым жоқ',
                style: TextStyle(color: AppTheme.textSecondary)))
            : ListView.builder(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: sales.length,
                itemBuilder: (_, i) {
                  final s = sales[i];
                  final prod = products.firstWhere((p) => p.id == s.productId,
                      orElse: () => ProductModel(id: '', name: 'Жойылды',
                          brand: '', type: '', material: '', category: '',
                          color: '', articul: '', status: '', images: []));
                  String whName = '';
                  if (s.warehouseId.isNotEmpty) {
                    try { whName = warehouses.firstWhere((w) => w.id == s.warehouseId).name; }
                    catch (_) {}
                  }
                  return _SaleCard(sale: s, product: prod, warehouseName: whName);
                },
              ),
      ),
    ]);
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
      const Spacer(),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600,
          fontSize: 13, color: AppTheme.textPrimary)),
    ]),
  );
}
