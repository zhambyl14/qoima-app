import 'package:flutter/material.dart';
import '../../../data/models/batch_model.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/store_discount_model.dart';
import '../../../data/repositories/my_store_repository.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';
import 'admin_my_store_discount_add_screen.dart';

class AdminMyStoreDiscountsScreen extends StatelessWidget {
  const AdminMyStoreDiscountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = MyStoreRepository();
    final service = FirestoreService();
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        StreamBuilder<List<StoreDiscountModel>>(
          stream: repo.watchDiscounts(),
          builder: (_, snap) {
            final active = (snap.data ?? []).where((d) => d.isActive).length;
            return QGradientHeader(
              compact: true,
              title: 'Скидки',
              subtitle: '$active активных акций',
              showBack: true,
              action: QHeaderBtn(Icons.add_rounded,
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AdminMyStoreDiscountAddScreen()))),
            );
          },
        ),
        Expanded(
          child: StreamBuilder<List<StoreDiscountModel>>(
            stream: repo.watchDiscounts(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: cGreen));
              }
              final list = snap.data ?? [];
              final active = list.where((d) => d.isActive).toList();
              final inactive = list.where((d) => !d.isActive).toList();

              if (list.isEmpty) {
                return _Empty(onAdd: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AdminMyStoreDiscountAddScreen())));
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  ...active.map((d) => _DiscountCard(d, repo: repo, service: service)),
                  ...inactive.map((d) => _DiscountCard(d, repo: repo, service: service)),
                  const SizedBox(height: 8),
                  _AddBtn(onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AdminMyStoreDiscountAddScreen()))),
                ],
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ── Campaign card (expandable) ────────────────────────────────────────────────

class _DiscountCard extends StatefulWidget {
  final StoreDiscountModel d;
  final MyStoreRepository repo;
  final FirestoreService service;
  const _DiscountCard(this.d, {required this.repo, required this.service});

  @override
  State<_DiscountCard> createState() => _DiscountCardState();
}

class _DiscountCardState extends State<_DiscountCard> {
  bool _expanded = false;
  bool _loading = false;
  List<ProductModel> _products = [];
  // Local mirror of targetProductIds — updated immediately on add/remove.
  late List<String> _ids;

  @override
  void initState() {
    super.initState();
    _ids = List.from(widget.d.targetProductIds);
  }

  @override
  void didUpdateWidget(_DiscountCard old) {
    super.didUpdateWidget(old);
    // Sync from Firestore stream only if we're not mid-edit.
    if (old.d.targetProductIds.length != widget.d.targetProductIds.length) {
      _ids = List.from(widget.d.targetProductIds);
      if (_expanded) _refresh();
    }
  }

  void _toggleExpand() {
    setState(() => _expanded = !_expanded);
    if (_expanded && _products.isEmpty) _refresh();
  }

  Future<void> _refresh() async {
    if (_ids.isEmpty) { setState(() => _products = []); return; }
    setState(() => _loading = true);
    try {
      final results = await Future.wait(_ids.map((id) => widget.service.getProduct(id)));
      if (!mounted) return;
      setState(() {
        // Тек қоймада бар тауарлар көрсетіледі — сатылып кеткен товарлар жасырылады.
        _products = results
            .whereType<ProductModel>()
            .where((p) => p.status == ProductModel.statusInStock)
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  DiscountModel get _discountModel => DiscountModel(
    active: true,
    type: widget.d.type == DiscountType.fixed ? 'amount' : 'percent',
    value: widget.d.value,
    startsAt: widget.d.startsAt,
    endsAt: widget.d.endsAt,
  );

  Future<void> _toggle(bool on) async {
    if (on) {
      await widget.service.setDiscountBulk(productIds: _ids, discount: _discountModel);
    } else {
      await widget.service.removeDiscountBulk(_ids);
    }
    await widget.repo.toggleDiscount(widget.d.id, on);
  }

  Future<void> _delete() async {
    await widget.service.removeDiscountBulk(_ids);
    await widget.repo.deleteDiscount(widget.d.id);
  }

  Future<void> _removeProduct(String productId) async {
    setState(() {
      _ids.remove(productId);
      _products.removeWhere((p) => p.id == productId);
    });
    // Batch discount алдымен алынады, сосын campaign жаңартылады.
    if (widget.d.isActive) await widget.service.removeDiscountBulk([productId]);
    await widget.repo.removeProductFromDiscount(widget.d.id, productId);
  }

  Future<void> _addProduct(ProductModel product) async {
    setState(() {
      _ids.add(product.id);
      _products.add(product);
    });
    if (widget.d.isActive) {
      await widget.service.setDiscountBulk(productIds: [product.id], discount: _discountModel);
    }
    await widget.repo.addProductToDiscount(widget.d.id, product.id);
  }

  void _showAddSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddProductSheet(
        excludeIds: List.from(_ids),
        service: widget.service,
        onAdd: (p) { Navigator.pop(context); _addProduct(p); },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final urgent = d.daysLeft != null && d.daysLeft! <= 3;
    return Opacity(
      opacity: d.isActive ? 1.0 : 0.55,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: d.isActive ? cRed.withValues(alpha: 0.2) : cLine,
              width: d.isActive ? 1.5 : 1),
          boxShadow: kShadowSm,
        ),
        child: Column(children: [
          // ── Header ───────────────────────────────────────────────────────
          Row(children: [
            QIconTile(
              icon: Icon(Icons.percent_rounded, color: d.isActive ? cRed : cInk2, size: 20),
              tone: d.isActive ? 'red' : 'ink',
              size: 46,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.displayValue,
                    style: manrope(22, FontWeight.w800,
                        color: d.isActive ? cRed : cInk2, letterSpacing: -0.3)),
                Text(d.scopeLabel, style: manrope(12.5, FontWeight.w500, color: cInk3),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            Column(children: [
              QPill(d.isActive ? 'Активна' : 'Выключена',
                  tone: d.isActive ? 'red' : 'gray'),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => _toggle(!d.isActive),
                child: _SmallToggle(on: d.isActive),
              ),
            ]),
          ]),
          const SizedBox(height: 12),

          // ── Date / count row ─────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: urgent ? cAmberTint : cBg,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(children: [
              Icon(Icons.calendar_today_rounded, size: 15, color: urgent ? cAmber : cInk3),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  d.hasDateLimit && d.daysLeft != null
                      ? (d.daysLeft! > 0 ? 'Қалды ${d.daysLeft} күн' : 'Бүгін соңғы күн')
                      : 'Мерзімсіз',
                  style: manrope(12.5, FontWeight.w700,
                      color: urgent ? const Color(0xFF9A6A06) : cInk2),
                ),
              ),
              GestureDetector(
                onTap: _ids.isEmpty ? null : _toggleExpand,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${_ids.length} тауар',
                      style: manrope(12, FontWeight.w600,
                          color: _ids.isEmpty ? cInk3 : cGreen)),
                  if (_ids.isNotEmpty) ...[
                    const SizedBox(width: 2),
                    Icon(
                      _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 15,
                      color: cGreen,
                    ),
                  ],
                ]),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => _confirmDelete(context),
                child: const Icon(Icons.delete_outline_rounded, color: cRed, size: 18),
              ),
            ]),
          ),

          // ── Expandable product list ───────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(children: [
                      const Divider(height: 1, color: cLine),
                      const SizedBox(height: 10),
                      if (_loading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(color: cGreen, strokeWidth: 2),
                            ),
                          ),
                        )
                      else if (_products.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text('Барлық тауарлар сатылды немесе жасырылды',
                              style: manrope(12.5, FontWeight.w500, color: cInk3)),
                        )
                      else
                        ..._products.map((p) => _ProductRow(
                          p,
                          discount: d,
                          onRemove: () => _removeProduct(p.id),
                        )),
                      // ── Add product button ────────────────────────────────
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () => _showAddSheet(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: cGreen.withValues(alpha: 0.4),
                                width: 1.3),
                            color: cGreenTint,
                          ),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Icon(Icons.add_rounded, color: cGreen, size: 17),
                            const SizedBox(width: 6),
                            Text('Тауар қосу', style: manrope(13, FontWeight.w700, color: cGreen)),
                          ]),
                        ),
                      ),
                    ]),
                  )
                : const SizedBox.shrink(),
          ),
        ]),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Акцияны жою?', style: manrope(17, FontWeight.w700, color: cInk)),
        content: Text('«${widget.d.displayValue}» — ${widget.d.scopeLabel}.\nТауарлардағы скидка алынады.',
            style: manrope(14, FontWeight.w500, color: cInk2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Болдырмау', style: manrope(14, FontWeight.w600, color: cInk2))),
          TextButton(
              onPressed: () { Navigator.pop(ctx); _delete(); },
              child: Text('Жою', style: manrope(14, FontWeight.w600, color: cRed))),
        ],
      ),
    );
  }
}

// ── Add product bottom sheet ──────────────────────────────────────────────────

class _AddProductSheet extends StatefulWidget {
  final List<String> excludeIds;
  final FirestoreService service;
  final void Function(ProductModel) onAdd;
  const _AddProductSheet({
    required this.excludeIds,
    required this.service,
    required this.onAdd,
  });

  @override
  State<_AddProductSheet> createState() => _AddProductSheetState();
}

class _AddProductSheetState extends State<_AddProductSheet> {
  final _searchCtrl = TextEditingController();
  List<ProductModel> _all = [];
  bool _loading = true;

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
      final products = widget.service.cachedProducts ??
          await widget.service.watchProducts().first;
      if (!mounted) return;
      setState(() {
        // Тек қоймада бар, кампанияда жоқ тауарлар ғана ұсынылады.
        _all = products
            .where((p) =>
                p.status == ProductModel.statusInStock &&
                !widget.excludeIds.contains(p.id))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ProductModel> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.brand.toLowerCase().contains(q) ||
            p.articul.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(18, 6, 18, bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(
          child: Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                color: cLine, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        Text('Акцияға тауар қосу',
            style: manrope(16, FontWeight.w800, color: cInk)),
        const SizedBox(height: 14),
        TextField(
          controller: _searchCtrl,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Тауар іздеу (атауы, бренд, артикул)',
            prefixIcon: Icon(Icons.search_rounded, color: cInk3),
          ),
        ),
        const SizedBox(height: 10),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(color: cGreen),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 340),
            child: _filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Тауар табылмады',
                        style: manrope(13.5, FontWeight.w500, color: cInk3),
                        textAlign: TextAlign.center),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final p = _filtered[i];
                      final img = p.images.isNotEmpty ? p.images.first : null;
                      return GestureDetector(
                        onTap: () => widget.onAdd(p),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: cBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: cLine),
                          ),
                          child: Row(children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 42, height: 42,
                                child: img != null
                                    ? Image.network(img, fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => _imgPlaceholder())
                                    : _imgPlaceholder(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.name,
                                        style: manrope(13.5, FontWeight.w700, color: cInk),
                                        maxLines: 1, overflow: TextOverflow.ellipsis),
                                    if (p.brand.isNotEmpty)
                                      Text(p.brand,
                                          style: manrope(11.5, FontWeight.w500, color: cInk3)),
                                  ]),
                            ),
                            const Icon(Icons.add_circle_outline_rounded,
                                color: cGreen, size: 22),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
      ]),
    );
  }

  Widget _imgPlaceholder() => Container(
    color: cBg,
    child: const Icon(Icons.inventory_2_outlined, size: 18, color: cInk3),
  );
}

// ── Product row in expanded card ──────────────────────────────────────────────

class _ProductRow extends StatelessWidget {
  final ProductModel product;
  final StoreDiscountModel discount;
  final VoidCallback onRemove;
  const _ProductRow(this.product, {required this.discount, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final img = product.images.isNotEmpty ? product.images.first : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            width: 44, height: 44,
            child: img != null
                ? Image.network(img, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _thumb())
                : _thumb(),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(product.name,
                style: manrope(13, FontWeight.w600, color: cInk),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(product.brand,
                style: manrope(11.5, FontWeight.w500, color: cInk3),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
              color: cRedTint, borderRadius: BorderRadius.circular(7)),
          child: Text(discount.displayValue,
              style: manrope(11.5, FontWeight.w700, color: cRed)),
        ),
        const SizedBox(width: 6),
        // Осы тауардан скидканы алу
        GestureDetector(
          onTap: onRemove,
          child: Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
                color: cRedTint, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.close_rounded, color: cRed, size: 15),
          ),
        ),
      ]),
    );
  }

  Widget _thumb() => Container(
    color: cBg,
    child: const Icon(Icons.inventory_2_outlined, size: 20, color: cInk3),
  );
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _SmallToggle extends StatelessWidget {
  final bool on;
  const _SmallToggle({required this.on});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40, height: 23, padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: on ? cGreen : cLine),
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
            width: 19, height: 19,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: Colors.white)),
      );
}

class _AddBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _AddBtn({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cRedTint,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cRed.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.add_rounded, color: cRed, size: 20),
            const SizedBox(width: 8),
            Text('Жаңа акция жасау',
                style: manrope(14, FontWeight.w700, color: cRed)),
          ]),
        ),
      );
}

class _Empty extends StatelessWidget {
  final VoidCallback onAdd;
  const _Empty({required this.onAdd});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.percent_rounded, size: 56, color: cInk3),
            const SizedBox(height: 12),
            Text('Акциялар жоқ',
                style: manrope(16, FontWeight.w700, color: cInk2)),
            const SizedBox(height: 6),
            Text('Тауарға, санатқа немесе қоймаға скидка қойыңыз',
                textAlign: TextAlign.center,
                style: manrope(13, FontWeight.w500, color: cInk3)),
            const SizedBox(height: 20),
            QPrimaryButton(label: 'Акция жасау', onPressed: onAdd, height: 46),
          ]),
        ),
      );
}
