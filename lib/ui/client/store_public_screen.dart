import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/lang.dart';
import '../../data/models/batch_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/store_model.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';
import '../shared/skeletons.dart';
import 'client_product_card.dart';
import 'client_product_detail.dart';
import 'report_sheet.dart';

/// Дүкеннің публичті парақшасы: ақпарат + ТЕК осы дүкеннің тауарлары.
///
/// Тауар детальіндегі дүкен карточкасынан ашылады. Әрекеттер (⋮):
/// «Пожаловаться на магазин» және «Скрыть магазин» (клиент сатушыны өзі үшін
/// блоктайды — App Store Guideline 1.2 талабы).
///
/// [previewMode] — дүкен иесі өз витринасын клиент көзімен көреді:
/// шағым/жасыру/сатып алу әрекеттері жасырылады.
class StorePublicScreen extends StatefulWidget {
  final StoreModel store;
  final bool previewMode;
  const StorePublicScreen(
      {super.key, required this.store, this.previewMode = false});

  @override
  State<StorePublicScreen> createState() => _StorePublicScreenState();
}

class _StorePublicScreenState extends State<StorePublicScreen> {
  final _service = ClientService();
  final _searchCtrl = TextEditingController();

  List<({ProductModel product, List<BatchModel> batches})> _pairs = [];
  bool _loading = true;
  bool _hidden = false; // клиент осы дүкенді жасырған ба
  String _query = '';

  StoreModel get store => widget.store;

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
      final results = await Future.wait([
        _service.getStoreProductsWithBatches(
            store.adminUid, store.visibleWarehouseIds),
        _service.getHiddenStoreIds(),
      ]);
      if (!mounted) return;
      setState(() {
        _pairs = results[0]
            as List<({ProductModel product, List<BatchModel> batches})>;
        _hidden = (results[1] as Set<String>).contains(store.adminUid);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openProduct(
      ProductModel p, List<ProductModel> variants) async {
    final buyNow = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ClientProductDetail(
          product: p,
          store: store,
          allVariants: variants,
          openedFromStore: true,
          previewMode: widget.previewMode,
        ),
      ),
    );
    // «Купить сейчас» сигналын шақырушыға (home/catalog) жеткіземіз.
    if (buyNow == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _toggleHide() async {
    final user = context.read<AppUser>();
    final messenger = ScaffoldMessenger.of(context);
    if (user.uid.isEmpty) {
      messenger.showSnackBar(SnackBar(
        content: Text(tr('Войдите, чтобы скрыть магазин',
            'Дүкенді жасыру үшін кіріңіз')),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    try {
      if (_hidden) {
        await _service.unhideStore(store.adminUid);
        if (!mounted) return;
        setState(() => _hidden = false);
        messenger.showSnackBar(SnackBar(
          content: Text(tr('Магазин снова виден', 'Дүкен қайта көрінеді')),
          backgroundColor: cGreen,
          behavior: SnackBarBehavior.floating,
        ));
      } else {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: cSurface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
            title: Text(tr('Скрыть магазин?', 'Дүкенді жасыру керек пе?'),
                style: manrope(16, FontWeight.w800, color: cInk)),
            content: Text(
              tr('Товары «${store.storeName}» больше не будут показываться вам. Отменить можно в Профиль → Скрытые магазины.',
                  '«${store.storeName}» тауарлары сізге енді көрсетілмейді. Профиль → Жасырылған дүкендер бөлімінен қайтара аласыз.'),
              style: manrope(13.5, FontWeight.w500, color: cInk2),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(tr('Отмена', 'Болдырмау'),
                      style: manrope(14, FontWeight.w600, color: cInk2))),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(tr('Скрыть', 'Жасыру'),
                      style: manrope(14, FontWeight.w700, color: cRed))),
            ],
          ),
        );
        if (ok != true) return;
        await _service.hideStore(store.adminUid, store.storeName);
        if (!mounted) return;
        setState(() => _hidden = true);
        messenger.showSnackBar(SnackBar(
          content: Text(
              tr('Магазин скрыт', 'Дүкен жасырылды')),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: Text(tr('Не удалось выполнить действие', 'Әрекет орындалмады')),
        backgroundColor: cRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _report() => showReportSheet(
        context,
        targetType: 'store',
        targetId: store.adminUid,
        targetName: store.storeName,
        adminUid: store.adminUid,
        storeName: store.storeName,
      );

  @override
  Widget build(BuildContext context) {
    final groups = groupProducts(_pairs.map((e) => e.product).toList());
    final filtered = _query.isEmpty
        ? groups
        : groups.where((g) => productGroupMatches(g, _query)).toList();
    final cards = expandVariantCards(filtered);
    final batchesById = {for (final pr in _pairs) pr.product.id: pr.batches};
    final storeById = {
      for (final pr in _pairs) pr.product.id: store as StoreModel?
    };

    return Scaffold(
      backgroundColor: cBg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          // ── Header ───────────────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(gradient: kGrad),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 16),
              child: Column(children: [
                Row(children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.chevron_left_rounded,
                          color: Colors.white, size: 24),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(store.storeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: manrope(20, FontWeight.w800,
                            color: Colors.white, letterSpacing: -0.4)),
                  ),
                  // ⋮ — шағымдану / жасыру (preview-де жасырын)
                  if (widget.previewMode)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(tr('Предпросмотр', 'Алдын ала қарау'),
                          style: manrope(11.5, FontWeight.w700,
                              color: Colors.white)),
                    )
                  else
                  PopupMenuButton<String>(
                    icon: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.more_vert_rounded,
                          color: Colors.white, size: 20),
                    ),
                    color: cSurface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    onSelected: (v) {
                      if (v == 'report') _report();
                      if (v == 'hide') _toggleHide();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'report',
                        child: Row(children: [
                          const Icon(Icons.flag_outlined,
                              size: 18, color: cRed),
                          const SizedBox(width: 10),
                          Text(tr('Пожаловаться', 'Шағымдану'),
                              style: manrope(13.5, FontWeight.w600,
                                  color: cInk)),
                        ]),
                      ),
                      PopupMenuItem(
                        value: 'hide',
                        child: Row(children: [
                          Icon(
                              _hidden
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 18,
                              color: cInk2),
                          const SizedBox(width: 10),
                          Text(
                              _hidden
                                  ? tr('Показать магазин', 'Дүкенді көрсету')
                                  : tr('Скрыть магазин', 'Дүкенді жасыру'),
                              style: manrope(13.5, FontWeight.w600,
                                  color: cInk)),
                        ]),
                      ),
                    ],
                  ),
                ]),
              ]),
            ),
          ),

          // ── Body ─────────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const CatalogGridSkeleton()
                : CustomScrollView(slivers: [
                    // Дүкен ақпараты
                    SliverToBoxAdapter(child: _buildStoreInfo()),
                    // Іздеу
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: _buildSearchField(),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                        child: Text(
                          tr('Товары магазина (${cards.length})',
                              'Дүкен тауарлары (${cards.length})'),
                          style:
                              manrope(15.5, FontWeight.w800, color: cInk),
                        ),
                      ),
                    ),
                    if (cards.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: ClientEmptyState(
                            icon: Icons.inventory_2_outlined,
                            message: _query.isEmpty
                                ? tr('Товаров пока нет', 'Әзірге тауар жоқ')
                                : tr('«$_query» не найдено',
                                    '«$_query» табылмады'),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.72,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => ProductGroupCard(
                              key: ValueKey(cards[i]
                                  .group
                                  .variants[cards[i].index]
                                  .id),
                              group: cards[i].group,
                              initialIndex: cards[i].index,
                              batchesByProductId: batchesById,
                              storeByProductId: storeById,
                              tone: i % 5,
                              onTap: _openProduct,
                              quickAddEnabled: !widget.previewMode,
                            ),
                            childCount: cards.length,
                          ),
                        ),
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildStoreInfo() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: QCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            // Логотип
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: cGreenTint,
                borderRadius: BorderRadius.circular(15),
              ),
              clipBehavior: Clip.antiAlias,
              child: store.logoUrl.isNotEmpty
                  ? Image.network(store.logoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.storefront_rounded,
                          color: cGreenDeep,
                          size: 26))
                  : const Icon(Icons.storefront_rounded,
                      color: cGreenDeep, size: 26),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(store.storeName,
                      style: manrope(16, FontWeight.w800, color: cInk)),
                  if (store.category.isNotEmpty)
                    Text(trValue(store.category),
                        style:
                            manrope(12.5, FontWeight.w600, color: cGreenDeep)),
                ],
              ),
            ),
            if (_hidden)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cLine2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(tr('Скрыт', 'Жасырылған'),
                    style: manrope(10.5, FontWeight.w800, color: cInk2)),
              ),
          ]),
          if (store.description.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(store.description,
                style: manrope(13, FontWeight.w500, color: cInk2)
                    .copyWith(height: 1.45)),
          ],
          const SizedBox(height: 12),
          if (store.city.isNotEmpty)
            _infoRow(Icons.location_city_rounded, trValue(store.city)),
          if (store.address.isNotEmpty)
            _infoRow(Icons.place_outlined, store.address),
          if (store.phone.isNotEmpty)
            _infoRow(Icons.phone_outlined, store.phone),
        ]),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          Icon(icon, size: 16, color: cInk3),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: manrope(13, FontWeight.w600, color: cInk2)),
          ),
        ]),
      );

  Widget _buildSearchField() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cLine),
      ),
      child: Row(children: [
        const SizedBox(width: 12),
        const Icon(Icons.search_rounded, color: cInk3, size: 19),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            cursorColor: cGreen,
            textAlignVertical: TextAlignVertical.center,
            onChanged: (q) => setState(() => _query = q.trim()),
            style: manrope(14.5, FontWeight.w600, color: cInk),
            decoration: InputDecoration(
              hintText:
                  tr('Поиск в магазине...', 'Дүкеннен іздеу...'),
              hintStyle: manrope(14.5, FontWeight.w500, color: cInk3),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              suffixIcon: _query.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                      child: const Icon(Icons.close_rounded,
                          color: cInk3, size: 18))
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
      ]),
    );
  }
}
