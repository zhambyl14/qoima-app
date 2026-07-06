import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/app_user.dart';
import '../../../core/warehouse_context.dart';
import '../../../data/models/models.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';

import '../../../core/lang.dart';

/// Ревизия: тауарды түгендеу — жетіспегенін «недостача» етіп жазу,
/// кейін «Списать» арқылы қоймадан шығару (sales_history, type='writeoff').
class RevisionScreen extends StatefulWidget {
  const RevisionScreen({super.key});
  @override
  State<RevisionScreen> createState() => _RevisionScreenState();
}

class _RevisionScreenState extends State<RevisionScreen>
    with SingleTickerProviderStateMixin {
  final _service = FirestoreService();
  late final TabController _tabCtrl = TabController(length: 2, vsync: this);
  late final Stream<List<RevisionModel>> _revisionsStream =
      _service.watchRevisions();

  // Товар ағыны қойма бойынша мемоизацияланады (build сайын қайта ашылмауы үшін).
  String? _cachedWhId;
  Stream<List<({ProductModel product, List<BatchModel> batches})>>?
      _cachedProductsStream;

  final _searchCtrl = TextEditingController();
  String _q = '';
  bool _busy = false;

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Stream<List<({ProductModel product, List<BatchModel> batches})>>
      _productsStream(String whId) {
    if (_cachedProductsStream == null || _cachedWhId != whId) {
      _cachedWhId = whId;
      _cachedProductsStream =
          _service.watchProductsWithBatches(warehouseId: whId);
    }
    return _cachedProductsStream!;
  }

  void _snack(String msg, {bool isError = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: isError ? cRed : cGreen,
        behavior: SnackBarBehavior.floating,
      ));

  // ── Недостача жасау парағы ─────────────────────────────────────────────────
  void _openShortageSheet(ProductModel product, List<BatchModel> batches,
      String warehouseId) {
    // Учёт бойынша қалдық: қойма партияларының размер қосындысы.
    final Map<String, int> stock = {};
    for (final b in batches) {
      b.sizesQuantity.forEach((k, v) {
        if (v > 0) stock[k] = (stock[k] ?? 0) + v;
      });
    }
    if (stock.isEmpty) {
      _snack(tr('По учёту остатка нет — списывать нечего', 'Есеп бойынша қалдық жоқ — списание қажет емес'),
          isError: true);
      return;
    }
    final sizes = stock.keys.toList()
      ..sort((a, b) =>
          (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
    final missing = <String, int>{};
    final noteCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final total = missing.values.fold(0, (a, b) => a + b);
        return Padding(
          padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom +
                  MediaQuery.of(ctx).padding.bottom +
                  24),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                    child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 14),
                Text(product.name,
                    style: manrope(16, FontWeight.w700, color: cInk)),
                const SizedBox(height: 2),
                Text(tr('Сколько не хватает по факту?', 'Іс жүзінде нешеу жетіспейді?'),
                    style: manrope(13, FontWeight.w500, color: cInk2)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: sizes.map((size) {
                    final max = stock[size]!;
                    final cur = missing[size] ?? 0;
                    final active = cur > 0;
                    return Container(
                      decoration: BoxDecoration(
                          color: active ? cRedTint : cBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: active
                                  ? cRed.withValues(alpha: 0.4)
                                  : cLine,
                              width: active ? 1.5 : 1)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        GestureDetector(
                            onTap: cur > 0
                                ? () => setS(() {
                                      if (cur - 1 <= 0) {
                                        missing.remove(size);
                                      } else {
                                        missing[size] = cur - 1;
                                      }
                                    })
                                : null,
                            child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                    color: cur > 0
                                        ? cRed.withValues(alpha: 0.8)
                                        : Colors.grey.shade100,
                                    borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(9),
                                        bottomLeft: Radius.circular(9))),
                                child: Icon(Icons.remove,
                                    size: 13,
                                    color: cur > 0
                                        ? Colors.white
                                        : Colors.grey.shade400))),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(size,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: active ? cRed : cInk)),
                              Text(tr('$cur из $max', '$cur / $max'),
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: active ? cRed : cInk3,
                                      fontWeight: active
                                          ? FontWeight.w700
                                          : FontWeight.w400)),
                            ],
                          ),
                        ),
                        GestureDetector(
                            onTap: cur < max
                                ? () => setS(() => missing[size] = cur + 1)
                                : null,
                            child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                    color: cur < max
                                        ? cRed
                                        : Colors.grey.shade100,
                                    borderRadius: const BorderRadius.only(
                                        topRight: Radius.circular(9),
                                        bottomRight: Radius.circular(9))),
                                child: Icon(Icons.add,
                                    size: 13,
                                    color: cur < max
                                        ? Colors.white
                                        : Colors.grey.shade400))),
                      ]),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: noteCtrl,
                  maxLength: 200,
                  style: manrope(14, FontWeight.w500, color: cInk),
                  decoration: InputDecoration(
                    labelText: tr('Комментарий (необязательно)', 'Пікір (міндетті емес)'),
                    counterText: '',
                    filled: true,
                    fillColor: cBg,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: cLine)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: cLine)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            const BorderSide(color: cGreen, width: 1.5)),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: total == 0
                        ? null
                        : () async {
                            try {
                              await _service.createRevision(
                                productId: product.id,
                                productName: product.name,
                                warehouseId: warehouseId,
                                sizesMissing: missing,
                                note: noteCtrl.text,
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              _snack(tr('Недостача создана · $total шт.', 'Жетіспеушілік жазылды · $total дана'));
                              _tabCtrl.animateTo(1);
                            } catch (e) {
                              _snack(
                                  e
                                      .toString()
                                      .replaceFirst('SaleException: ', ''),
                                  isError: true);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: cRed,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade200,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))),
                    child: Text(
                        total == 0
                            ? tr('Укажите недостачу', 'Жетіспеушілікті көрсетіңіз')
                            : tr('Создать недостачу · $total шт.', 'Жетіспеушілік жазу · $total дана'),
                        style: manrope(14.5, FontWeight.w700,
                            color: total == 0 ? cInk3 : Colors.white)),
                  ),
                ),
              ]),
        );
      }),
    );
  }

  // ── Списание (сомасын енгізу) ──────────────────────────────────────────────
  Future<void> _writeOff(RevisionModel rev) async {
    if (_busy) return;
    final amount = await _askWriteOffAmount(rev);
    if (amount == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _service.writeOffRevision(rev, amount: amount);
      HapticFeedback.mediumImpact();
      _snack(tr('Списано на ${amount.toStringAsFixed(0)} ₸ — прибыль владельца', '${amount.toStringAsFixed(0)} ₸ списание — иенің пайдасы'));
    } catch (e) {
      _snack(e.toString().replaceFirst('SaleException: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Списание сомасын (₸) сұрайтын парақ. Бос/0 → болдырмау.
  Future<double?> _askWriteOffAmount(RevisionModel rev) {
    final ctrl = TextEditingController();
    return showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final val = double.tryParse(ctrl.text.trim()) ?? 0;
        return Padding(
          padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom +
                  MediaQuery.of(ctx).padding.bottom +
                  24),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                    child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 14),
                Text(tr('Списать ${rev.quantity} шт.', '${rev.quantity} дана списание'),
                    style: manrope(16, FontWeight.w700, color: cInk)),
                const SizedBox(height: 2),
                Text(
                    tr('На какую сумму списываете? Она пойдёт в прибыль владельца в разделе «Продавцы».',
                        'Қандай сомаға списание жасайсыз? Ол «Сатушылар» бөлімінде иенің пайдасына түседі.'),
                    style: manrope(12.5, FontWeight.w500, color: cInk2)),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
                  ],
                  onChanged: (_) => setS(() {}),
                  style: manrope(20, FontWeight.w800, color: cInk),
                  decoration: InputDecoration(
                    hintText: '0',
                    suffixText: '₸',
                    filled: true,
                    fillColor: cBg,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: cLine)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: cLine)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: cGreen, width: 1.5)),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                    tr('Товар снимется с остатка склада, возврат по нему невозможен.',
                        'Тауар қойма қалдығынан шығады, оны қайтаруға болмайды.'),
                    style: manrope(11.5, FontWeight.w500, color: cInk3)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: val <= 0
                        ? null
                        : () => Navigator.pop(ctx, val),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: cRed,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade200,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))),
                    child: Text(
                        val <= 0
                            ? tr('Введите сумму', 'Соманы енгізіңіз')
                            : tr('Списать на ${val.toStringAsFixed(0)} ₸', '${val.toStringAsFixed(0)} ₸-ге списание'),
                        style: manrope(14.5, FontWeight.w700,
                            color: val <= 0 ? cInk3 : Colors.white)),
                  ),
                ),
              ]),
        );
      }),
    );
  }

  Future<void> _deleteRevision(RevisionModel rev) async {
    try {
      await _service.deleteRevision(rev.id);
      _snack(tr('Недостача отменена', 'Жетіспеушілік жазбасы өшірілді'));
    } catch (e) {
      _snack('$e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wCtx = context.watch<WarehouseContext>();
    final whId =
        wCtx.current?.id ?? context.read<AppUser>().assignedWarehouseId;
    final whName = wCtx.current?.name ?? '';

    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        // ── Header ───────────────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(gradient: kGrad),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
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
                            color: Colors.white, size: 22)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('Ревизия', 'Түгендеу'),
                              style: manrope(21, FontWeight.w800,
                                  color: Colors.white, letterSpacing: -0.4)),
                          Text(
                              whName.isEmpty
                                  ? tr('Недостачи и списание', 'Жетіспеушілік және списание')
                                  : tr('Склад: $whName', 'Қойма: $whName'),
                              style: manrope(13, FontWeight.w500,
                                  color:
                                      Colors.white.withValues(alpha: 0.78))),
                        ]),
                  ),
                ]),
                const SizedBox(height: 8),
                StreamBuilder<List<RevisionModel>>(
                  stream: _revisionsStream,
                  builder: (_, snap) {
                    final open =
                        (snap.data ?? []).where((r) => r.isOpen).length;
                    return TabBar(
                      controller: _tabCtrl,
                      indicatorColor: Colors.white,
                      labelColor: Colors.white,
                      unselectedLabelColor:
                          Colors.white.withValues(alpha: 0.65),
                      labelStyle:
                          manrope(13.5, FontWeight.w700, color: Colors.white),
                      unselectedLabelStyle: manrope(13.5, FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.65)),
                      tabs: [
                        Tab(text: tr('Товары', 'Тауарлар')),
                        Tab(
                            text: open > 0
                                ? tr('Недостачи ($open)', 'Жетіспеушілік ($open)')
                                : tr('Недостачи', 'Жетіспеушілік')),
                      ],
                    );
                  },
                ),
              ]),
            ),
          ),
        ),

        // ── Body ─────────────────────────────────────────────────────────
        Expanded(
          child: TabBarView(controller: _tabCtrl, children: [
            _buildProductsTab(whId),
            _buildRevisionsTab(),
          ]),
        ),
      ]),
    );
  }

  // ── Tab 0: тауарлар тізімі ─────────────────────────────────────────────────
  Widget _buildProductsTab(String whId) {
    return StreamBuilder<
        List<({ProductModel product, List<BatchModel> batches})>>(
      stream: _productsStream(whId),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: cGreen));
        }
        var items = (snap.data ?? [])
            .where((e) =>
                e.batches.any((b) => b.sizesQuantity.values.any((q) => q > 0)))
            .toList();
        if (_q.isNotEmpty) {
          final q = _q.toLowerCase();
          items = items
              .where((e) =>
                  e.product.name.toLowerCase().contains(q) ||
                  e.product.brand.toLowerCase().contains(q) ||
                  e.product.articul.toLowerCase().contains(q))
              .toList();
        }

        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cLine),
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _q = v.trim()),
                style: const TextStyle(fontSize: 14, color: cInk),
                decoration: InputDecoration(
                  hintText: tr('Название, бренд, артикул...', 'Атауы, бренд, артикул...'),
                  hintStyle: const TextStyle(color: cInk3, fontSize: 13),
                  prefixIcon:
                      const Icon(Icons.search_rounded, color: cInk3, size: 20),
                  suffixIcon: _q.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() => _q = '');
                          },
                          child: const Icon(Icons.close_rounded,
                              color: cInk3, size: 18))
                      : null,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
                ),
              ),
            ),
          ),
          if (items.isEmpty)
            Expanded(
              child: Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 52, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text(
                      _q.isNotEmpty
                          ? tr('«$_q» не найдено', '«$_q» табылмады')
                          : tr('На складе нет товаров с остатком', 'Қоймада қалдығы бар тауар жоқ'),
                      style: const TextStyle(fontSize: 14, color: cInk2)),
                ]),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final p = items[i].product;
                  final batches = items[i].batches;
                  final stockQty = batches.fold<int>(
                      0,
                      (s, b) =>
                          s +
                          b.sizesQuantity.values
                              .fold(0, (a, q) => a + (q > 0 ? q : 0)));
                  return GestureDetector(
                    onTap: () => _openShortageSheet(p, batches, whId),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cLine),
                        boxShadow: kShadowSm,
                      ),
                      child: Row(children: [
                        ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: p.images.isNotEmpty
                                ? Image.network(p.images.first,
                                    width: 46,
                                    height: 46,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _imgPlaceholder())
                                : _imgPlaceholder()),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.name,
                                    style: manrope(14, FontWeight.w700,
                                        color: cInk),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 2),
                                Text(
                                    '${p.articul}  ·  ${tr('по учёту $stockQty шт.', 'есепте $stockQty дана')}',
                                    style: manrope(12, FontWeight.w500,
                                        color: cInk3)),
                              ]),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                              color: cRedTint,
                              borderRadius: BorderRadius.circular(9)),
                          child: Text(tr('Недостача', 'Жетіспеушілік'),
                              style: manrope(11, FontWeight.w700,
                                  color: cRed)),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
        ]);
      },
    );
  }

  // ── Tab 1: недостача жазбалары ─────────────────────────────────────────────
  Widget _buildRevisionsTab() {
    return StreamBuilder<List<RevisionModel>>(
      stream: _revisionsStream,
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: cGreen));
        }
        final revisions = snap.data ?? [];
        if (revisions.isEmpty) {
          return Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.rule_rounded, size: 52, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text(tr('Недостач пока нет', 'Әзірге жетіспеушілік жоқ'),
                  style: const TextStyle(fontSize: 15, color: cInk2)),
              const SizedBox(height: 4),
              Text(
                  tr('Выберите товар во вкладке «Товары»', '«Тауарлар» қойындысынан тауар таңдаңыз'),
                  style: const TextStyle(fontSize: 12, color: cInk3)),
            ]),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          itemCount: revisions.length,
          itemBuilder: (_, i) => _RevisionCard(
            revision: revisions[i],
            busy: _busy,
            onWriteOff: () => _writeOff(revisions[i]),
            onDelete: () => _deleteRevision(revisions[i]),
          ),
        );
      },
    );
  }

  Widget _imgPlaceholder() => Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
          color: cGreenTint, borderRadius: BorderRadius.circular(10)),
      child: const Icon(Icons.inventory_2_outlined, color: cGreen, size: 20));
}

// ── Недостача карточкасы ──────────────────────────────────────────────────────
class _RevisionCard extends StatelessWidget {
  final RevisionModel revision;
  final bool busy;
  final VoidCallback onWriteOff;
  final VoidCallback onDelete;

  const _RevisionCard({
    required this.revision,
    required this.busy,
    required this.onWriteOff,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final r = revision;
    final d = r.createdAt;
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: r.isOpen ? cRed.withValues(alpha: 0.45) : cLine,
            width: r.isOpen ? 1.5 : 1),
        boxShadow: kShadowSm,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          QIconTile(
            icon: Icon(
                r.isOpen
                    ? Icons.report_problem_outlined
                    : Icons.remove_shopping_cart_outlined,
                color: r.isOpen ? cAmber : cRed,
                size: 19),
            tone: r.isOpen ? 'amber' : 'red',
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.productName,
                  style: manrope(14, FontWeight.w700, color: cInk),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                  '$dateStr${r.createdByName.isNotEmpty ? ' · ${r.createdByName}' : ''}',
                  style: manrope(11.5, FontWeight.w500, color: cInk3)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
                color: r.isOpen ? cAmberTint : cRedTint,
                borderRadius: BorderRadius.circular(8)),
            child: Text(
                r.isOpen
                    ? tr('Недостача', 'Жетіспеушілік')
                    : tr('Списано', 'Списание жасалды'),
                style: manrope(11, FontWeight.w700,
                    color: r.isOpen ? cAmber : cRed)),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: r.sizesMissing.entries
              .where((e) => e.value > 0)
              .map((e) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                        color: cRedTint,
                        borderRadius: BorderRadius.circular(7)),
                    child: Text(tr('Р.${e.key} × ${e.value}', 'Ө.${e.key} × ${e.value}'),
                        style: manrope(11.5, FontWeight.w700, color: cRed)),
                  ))
              .toList(),
        ),
        if (r.note.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(r.note, style: manrope(12, FontWeight.w500, color: cInk2)),
        ],
        if (r.isOpen) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 42,
                child: ElevatedButton.icon(
                  onPressed: busy ? null : onWriteOff,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: cRed,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  icon: const Icon(Icons.remove_circle_outline_rounded,
                      size: 17),
                  label: Text(tr('Списать · ${r.quantity} шт.', 'Списание · ${r.quantity} дана'),
                      style: manrope(13.5, FontWeight.w700,
                          color: Colors.white)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: busy ? null : onDelete,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                    color: cBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cLine)),
                child:
                    const Icon(Icons.delete_outline_rounded, color: cInk3, size: 19),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}
