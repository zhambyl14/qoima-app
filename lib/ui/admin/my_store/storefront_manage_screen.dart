import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/lang.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/store_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';
import '../../client/store_public_screen.dart';

/// Дүкен иесі витринаны басқарады: қай тауар онлайн көрінеді, қайсысы жоқ.
///
/// Тауарды витринадан алу — ӨШІРУ ЕМЕС: қоймада есеп/офлайн сату үшін қалады,
/// тек клиентке көрсетілмейді (products.storefront_hidden). Жоғарыда «👁 Как
/// видит клиент» — нақты клиент көрінісінің алдын ала қарауы.
class StorefrontManageScreen extends StatefulWidget {
  final StoreModel? store;
  const StorefrontManageScreen({super.key, this.store});

  @override
  State<StorefrontManageScreen> createState() => _StorefrontManageScreenState();
}

class _StorefrontManageScreenState extends State<StorefrontManageScreen> {
  final _service = FirestoreService();
  final _searchCtrl = TextEditingController();
  String _q = '';
  int _tab = 0; // 0 Все · 1 В витрине · 2 Скрытые
  // Optimistic: серверлік realtime растауын күтпей switch бірден жылжиды.
  final Map<String, bool> _pending = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggle(ProductModel p, bool visible) async {
    // visible=true → витринада көрінсін → storefront_hidden=false.
    setState(() => _pending[p.id] = !visible);
    HapticFeedback.selectionClick();
    try {
      await _service.setStorefrontHidden(p.id, !visible);
    } catch (_) {
      if (!mounted) return;
      setState(() => _pending.remove(p.id));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Не удалось изменить. Проверьте интернет.',
            'Өзгерту сәтсіз. Интернетті тексеріңіз.')),
        backgroundColor: cRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  bool _isHidden(ProductModel p) => _pending[p.id] ?? p.storefrontHidden;

  List<ProductModel> _filter(List<ProductModel> all) {
    // Сатылған (толық) тауарларды тізбелемейміз — тек қолда барлар.
    var list = all
        .where((p) => p.status == ProductModel.statusInStock)
        .toList();
    if (_tab == 1) list = list.where((p) => !_isHidden(p)).toList();
    if (_tab == 2) list = list.where(_isHidden).toList();
    if (_q.isNotEmpty) {
      final q = _q.toLowerCase();
      list = list
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.brand.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: StreamBuilder<List<ProductModel>>(
        stream: _service.watchProducts(),
        builder: (context, snap) {
          final all = (snap.data ?? [])
              .where((p) => p.status == ProductModel.statusInStock)
              .toList();
          final hiddenCount = all.where(_isHidden).length;
          final visibleCount = all.length - hiddenCount;
          final list = _filter(snap.data ?? []);

          return SafeArea(
            bottom: false,
            child: Column(children: [
              // ── Header ─────────────────────────────────────────────────
              Container(
                decoration: const BoxDecoration(gradient: kGrad),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              width: 38,
                              height: 38,
                              margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.chevron_left_rounded,
                                  color: Colors.white, size: 24),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tr('Витрина магазина', 'Дүкен витринасы'),
                                    style: manrope(20, FontWeight.w800,
                                        color: Colors.white,
                                        letterSpacing: -0.4)),
                                Text(
                                    tr('$visibleCount в витрине · $hiddenCount скрыто',
                                        '$visibleCount витринада · $hiddenCount жасырын'),
                                    style: manrope(12.5, FontWeight.w500,
                                        color: Colors.white
                                            .withValues(alpha: 0.78))),
                              ],
                            ),
                          ),
                          // 👁 клиент көзімен алдын ала қарау
                          if (widget.store != null)
                            GestureDetector(
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => StorePublicScreen(
                                          store: widget.store!,
                                          previewMode: true))),
                              child: Container(
                                height: 38,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(children: [
                                  const Icon(Icons.visibility_outlined,
                                      color: Colors.white, size: 17),
                                  const SizedBox(width: 6),
                                  Text(tr('Просмотр', 'Қарау'),
                                      style: manrope(12.5, FontWeight.w700,
                                          color: Colors.white)),
                                ]),
                              ),
                            ),
                        ]),
                        const SizedBox(height: 14),
                        // Іздеу
                        Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: (v) => setState(() => _q = v),
                            style: manrope(14.5, FontWeight.w500,
                                color: Colors.white),
                            decoration: InputDecoration(
                              hintText: tr('Поиск товара…', 'Тауар іздеу…'),
                              hintStyle: manrope(14.5, FontWeight.w500,
                                  color: Colors.white.withValues(alpha: 0.8)),
                              prefixIcon: Icon(Icons.search_rounded,
                                  color: Colors.white.withValues(alpha: 0.8),
                                  size: 19),
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Табтар
                        Row(children: [
                          _Tab(
                              label: tr('Все (${all.length})',
                                  'Барлығы (${all.length})'),
                              active: _tab == 0,
                              onTap: () => setState(() => _tab = 0)),
                          const SizedBox(width: 8),
                          _Tab(
                              label: tr('В витрине ($visibleCount)',
                                  'Витринада ($visibleCount)'),
                              active: _tab == 1,
                              onTap: () => setState(() => _tab = 1)),
                          const SizedBox(width: 8),
                          _Tab(
                              label: tr('Скрытые ($hiddenCount)',
                                  'Жасырын ($hiddenCount)'),
                              active: _tab == 2,
                              onTap: () => setState(() => _tab = 2)),
                        ]),
                      ]),
                ),
              ),

              // ── Тізім ──────────────────────────────────────────────────
              Expanded(
                child: snap.connectionState == ConnectionState.waiting
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: cGreen, strokeWidth: 2))
                    : list.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.storefront_outlined,
                                    size: 52, color: cInk3),
                                const SizedBox(height: 12),
                                Text(
                                    _tab == 2
                                        ? tr('Скрытых товаров нет',
                                            'Жасырын тауар жоқ')
                                        : _q.isNotEmpty
                                            ? tr('Ничего не найдено',
                                                'Ештеңе табылмады')
                                            : tr('Товаров нет', 'Тауар жоқ'),
                                    style: manrope(15, FontWeight.w600,
                                        color: cInk2)),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                            itemCount: list.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) => _Row(
                              product: list[i],
                              hidden: _isHidden(list[i]),
                              onChanged: (visible) =>
                                  _toggle(list[i], visible),
                            ),
                          ),
              ),
            ]),
          );
        },
      ),
    );
  }
}

// ── Бір тауар жолы (switch-пен) ───────────────────────────────────────────────
class _Row extends StatelessWidget {
  final ProductModel product;
  final bool hidden;
  final ValueChanged<bool> onChanged;
  const _Row(
      {required this.product,
      required this.hidden,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hidden ? cLine : cGreen.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        // Фото (жасырын болса — солғын)
        Opacity(
          opacity: hidden ? 0.5 : 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: product.images.isNotEmpty
                ? Image.network(product.images.first,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _ph())
                : _ph(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.brand.toUpperCase(),
                  style: manrope(9.5, FontWeight.w800, color: cGreen)
                      .copyWith(letterSpacing: 0.8)),
              const SizedBox(height: 1),
              Text(product.name,
                  style: manrope(14, FontWeight.w700, color: cInk),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hidden ? cLine2 : cGreenTint,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                      hidden
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 12,
                      color: hidden ? cInk3 : cGreenDeep),
                  const SizedBox(width: 4),
                  Text(
                      hidden
                          ? tr('Скрыт с витрины', 'Витринадан жасырын')
                          : tr('В витрине', 'Витринада'),
                      style: manrope(10.5, FontWeight.w700,
                          color: hidden ? cInk3 : cGreenDeep)),
                ]),
              ),
            ],
          ),
        ),
        Switch(
          value: !hidden,
          activeThumbColor: Colors.white,
          activeTrackColor: cGreen,
          onChanged: onChanged,
        ),
      ]),
    );
  }

  Widget _ph() => Container(
      width: 56,
      height: 56,
      color: const Color(0xFFEEF2FF),
      child: const Icon(Icons.inventory_2_outlined, color: cGreen, size: 24));
}

// ── Tab ────────────────────────────────────────────────────────────────────────
class _Tab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Tab(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: manrope(12, FontWeight.w700,
                color: active ? cGreenDeep : Colors.white)),
      ),
    );
  }
}
