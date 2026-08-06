import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/promo_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';
import 'promo_edit_sheet.dart';

import '../../../core/lang.dart';
import '../../../core/error_text.dart';
/// Админ-экран управления промокодами магазина — акциялар (скидки) бөлімі
/// секілді: әр промокод карточкасы ашылып, тауарларды суретімен қосуға/алуға
/// болады (см. admin_my_store_discounts_screen.dart — сол UX қайталанады).
class PromosScreen extends StatelessWidget {
  const PromosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = FirestoreService();
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Промокоды', 'Промокодтар'),
          subtitle: tr('Скидки по коду для клиентов', 'Клиенттерге код бойынша жеңілдік'),
          showBack: true,
        ),
        Expanded(
          child: StreamBuilder<List<PromoModel>>(
            stream: service.watchPromos(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: cGreen));
              }
              if (snap.hasError) {
                return _Empty(
                    icon: Icons.error_outline_rounded,
                    message: tr('Ошибка загрузки промокодов', 'Промокодтарды жүктеу қатесі'));
              }
              final promos = snap.data ?? [];
              if (promos.isEmpty) {
                return _Empty(
                    icon: Icons.local_activity_outlined,
                    message: tr('Пока нет промокодов.\nСоздайте первый.', 'Әзірге промокод жоқ.\nАлғашқысын жасаңыз.'));
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: promos.length,
                itemBuilder: (_, i) =>
                    _PromoCard(promo: promos[i], service: service),
              );
            },
          ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: cGreen,
        foregroundColor: Colors.white,
        onPressed: () => showPromoEditSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(tr('Создать', 'Жасау'), style: manrope(14, FontWeight.w700,
            color: Colors.white)),
      ),
    );
  }
}

// ── Promo card (expandable — акциялар карточкасы секілді) ────────────────────

class _PromoCard extends StatefulWidget {
  final PromoModel promo;
  final FirestoreService service;
  const _PromoCard({required this.promo, required this.service});

  @override
  State<_PromoCard> createState() => _PromoCardState();
}

class _PromoCardState extends State<_PromoCard> {
  bool _expanded = false;
  bool _loading = false;
  List<ProductModel> _products = [];
  // Firestore ағынын күтпей, қосу/алу бірден экранда көрінеді.
  late List<String> _ids;

  PromoModel get promo => widget.promo;
  FirestoreService get service => widget.service;

  @override
  void initState() {
    super.initState();
    _ids = List.from(promo.productIds);
  }

  @override
  void didUpdateWidget(_PromoCard old) {
    super.didUpdateWidget(old);
    if (old.promo.productIds.length != promo.productIds.length) {
      _ids = List.from(promo.productIds);
      if (_expanded) _refresh();
    }
  }

  void _toggleExpand() {
    setState(() => _expanded = !_expanded);
    if (_expanded && _products.isEmpty) _refresh();
  }

  Future<void> _refresh() async {
    if (_ids.isEmpty) {
      setState(() => _products = []);
      return;
    }
    setState(() => _loading = true);
    try {
      final results = await Future.wait(_ids.map((id) => service.getProduct(id)));
      if (!mounted) return;
      setState(() {
        _products = results.whereType<ProductModel>().toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addProduct(ProductModel product) async {
    final newIds = [..._ids, product.id];
    setState(() {
      _ids = newIds;
      _products = [..._products, product];
    });
    try {
      await service.updatePromo(promo.copyWith(productIds: newIds));
    } catch (e) {
      if (mounted) {
        setState(() {
          _ids = List.from(_ids)..remove(product.id);
          _products = List.from(_products)..removeWhere((p) => p.id == product.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(friendlyError(e)),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _removeProduct(String productId) async {
    final oldIds = _ids;
    final oldProducts = _products;
    final newIds = List<String>.from(_ids)..remove(productId);
    setState(() {
      _ids = newIds;
      _products = _products.where((p) => p.id != productId).toList();
    });
    try {
      await service.updatePromo(promo.copyWith(productIds: newIds));
    } catch (e) {
      if (mounted) {
        setState(() {
          _ids = oldIds;
          _products = oldProducts;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(friendlyError(e)),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  void _showAddSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddPromoProductSheet(
        excludeIds: List.from(_ids),
        service: service,
        onAdd: (p) {
          Navigator.pop(context);
          _addProduct(p);
        },
      ),
    );
  }

  String get _discountLabel =>
      promo.isPercent ? '−${promo.value.toStringAsFixed(0)}%'
                      : '−${money(promo.value)}';

  ({String text, Color color}) get _status {
    if (!promo.active) return (text: tr('Выключен', 'Өшірулі'), color: cInk3);
    if (promo.isExpired) return (text: tr('Завершён', 'Аяқталды'), color: cRed);
    if (promo.isExhausted) return (text: tr('Исчерпан', 'Таусылды'), color: cRed);
    if (!promo.isStarted) return (text: tr('Запланирован', 'Жоспарланған'), color: cAmber);
    return (text: tr('Активен', 'Белсенді'), color: cGreen);
  }

  @override
  Widget build(BuildContext context) {
    final st = _status;
    final isProducts = promo.scope == 'products';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cLine),
        boxShadow: kShadowSm,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Код (моноширинный) + копировать
          Expanded(
            child: GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: promo.code));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(tr('Код ${promo.code} скопирован', '${promo.code} коды көшірілді')),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: cGreen,
                ));
              },
              child: Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cGreenTint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(promo.code,
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          letterSpacing: 1,
                          color: cGreenDeep)),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.copy_rounded, size: 14, color: cInk3),
              ]),
            ),
          ),
          // Вкл/выкл
          Switch(
            value: promo.active,
            activeTrackColor: cGreen,
            onChanged: (v) => service.setPromoActive(promo.id, v),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _Chip(_discountLabel, cRed),
          const Spacer(),
          Text(st.text,
              style: manrope(12.5, FontWeight.w700, color: st.color)),
        ]),
        const SizedBox(height: 10),
        // ── Область применения / товары с фото (акциялар секілді) ──────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: cBg,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(children: [
            Icon(isProducts ? Icons.inventory_2_outlined : Icons.storefront_outlined,
                size: 15, color: cInk3),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  isProducts ? tr('Выбранные товары', 'Таңдалған тауарлар') : tr('На все товары', 'Барлық тауарға'),
                  style: manrope(12.5, FontWeight.w600, color: cInk2)),
            ),
            if (isProducts)
              GestureDetector(
                onTap: _toggleExpand,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(tr('${_ids.length} товаров', '${_ids.length} тауар'),
                      style: manrope(12, FontWeight.w600,
                          color: _ids.isEmpty ? cInk3 : cGreen)),
                  const SizedBox(width: 2),
                  Icon(
                    _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 15,
                    color: cGreen,
                  ),
                ]),
              ),
          ]),
        ),
        // ── Ашылатын тауар тізімі (суретімен) ───────────────────────────────
        if (isProducts)
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(children: [
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
                          child: Text(tr('Товары не выбраны', 'Тауар таңдалмаған'),
                              style: manrope(12.5, FontWeight.w500, color: cInk3)),
                        )
                      else
                        ..._products.map((p) => _PromoProductRow(
                              p,
                              discountLabel: _discountLabel,
                              onRemove: () => _removeProduct(p.id),
                            )),
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
                            Text(tr('Добавить товар', 'Тауар қосу'), style: manrope(13, FontWeight.w700, color: cGreen)),
                          ]),
                        ),
                      ),
                    ]),
                  )
                : const SizedBox.shrink(),
          ),
        const SizedBox(height: 6),
        // Прогресс использований
        if (promo.maxUses != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: promo.maxUses! > 0
                  ? (promo.usedCount / promo.maxUses!).clamp(0.0, 1.0)
                  : 0,
              minHeight: 6,
              backgroundColor: cLine,
              valueColor: AlwaysStoppedAnimation(
                  promo.isExhausted ? cRed : cGreen),
            ),
          ),
          const SizedBox(height: 4),
          Text(tr('${promo.usedCount} / ${promo.maxUses} использований', '${promo.usedCount} / ${promo.maxUses} қолданылды'),
              style: manrope(11.5, FontWeight.w500, color: cInk3)),
        ] else
          Text(tr('${promo.usedCount} использований · без лимита', '${promo.usedCount} қолданылды · лимитсіз'),
              style: manrope(11.5, FontWeight.w500, color: cInk3)),
        const SizedBox(height: 6),
        Row(children: [
          if (promo.daysLeft != null)
            Text(tr('Осталось ${promo.daysLeft} дн.', 'Қалды ${promo.daysLeft} күн'),
                style: manrope(11.5, FontWeight.w500, color: cInk3)),
          const Spacer(),
          TextButton(
            onPressed: () => showPromoEditSheet(context, existing: promo),
            child: Text(tr('Изменить', 'Өзгерту'),
                style: manrope(12.5, FontWeight.w600, color: cGreen)),
          ),
          TextButton(
            onPressed: () => _confirmDelete(context),
            child: Text(tr('Удалить', 'Өшіру'),
                style: manrope(12.5, FontWeight.w600, color: cRed)),
          ),
        ]),
      ]),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(tr('Удалить промокод?', 'Промокодты өшіру керек пе?'),
            style: manrope(17, FontWeight.w700, color: cInk)),
        content: Text(tr('«${promo.code}» будет удалён безвозвратно.', '«${promo.code}» біржола өшіріледі.'),
            style: manrope(14, FontWeight.w500, color: cInk2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Отмена', 'Болдырмау'),
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await service.deletePromo(promo.id);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(friendlyError(e)),
                      backgroundColor: cRed,
                      behavior: SnackBarBehavior.floating,
                    ));
                  }
                }
              },
              child: Text(tr('Удалить', 'Өшіру'),
                  style: manrope(14, FontWeight.w600, color: cRed))),
        ],
      ),
    );
  }
}

// ── Тауар жолы (суретімен) — акциялардағы _ProductRow секілді ────────────────

class _PromoProductRow extends StatelessWidget {
  final ProductModel product;
  final String discountLabel;
  final VoidCallback onRemove;
  const _PromoProductRow(this.product,
      {required this.discountLabel, required this.onRemove});

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
              color: cGreenTint, borderRadius: BorderRadius.circular(7)),
          child: Text(discountLabel,
              style: manrope(11.5, FontWeight.w700, color: cGreenDeep)),
        ),
        const SizedBox(width: 6),
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
      child: const Icon(Icons.inventory_2_outlined, size: 20, color: cInk3));
}

// ── Тауар қосу sheet (суретімен, іздеумен) ────────────────────────────────────

class _AddPromoProductSheet extends StatefulWidget {
  final List<String> excludeIds;
  final FirestoreService service;
  final void Function(ProductModel) onAdd;
  const _AddPromoProductSheet({
    required this.excludeIds,
    required this.service,
    required this.onAdd,
  });

  @override
  State<_AddPromoProductSheet> createState() => _AddPromoProductSheetState();
}

class _AddPromoProductSheetState extends State<_AddPromoProductSheet> {
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
        _all = products
            .where((p) => !widget.excludeIds.contains(p.id))
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
        Text(tr('Добавить товар в промокод', 'Промокодқа тауар қосу'),
            style: manrope(16, FontWeight.w800, color: cInk)),
        const SizedBox(height: 14),
        TextField(
          controller: _searchCtrl,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: tr('Поиск товара (название, бренд, артикул)', 'Тауар іздеу (атауы, бренд, артикул)'),
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
                    child: Text(tr('Товары не найдены', 'Тауар табылмады'),
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
      child: const Icon(Icons.inventory_2_outlined, size: 18, color: cInk3));
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: manrope(12, FontWeight.w700, color: color)),
      );
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String message;
  const _Empty({required this.icon, required this.message});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 56, color: cInk3),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: manrope(15, FontWeight.w500, color: cInk2)),
        ]),
      );
}
