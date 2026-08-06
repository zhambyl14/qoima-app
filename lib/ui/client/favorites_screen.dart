import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:shimmer/shimmer.dart';
import '../../data/models/batch_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/store_model.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';
import 'client_product_detail.dart';

import '../../core/lang.dart';

/// Таңдаулылар тізімі.
///
/// Мінез-құлық: жүрекше басылған бойда жазба база жағында ӨШІРІЛЕДІ, бірақ
/// карточка экранда ҚАЛАДЫ (жүрекше бос контурға айналады) — клиент райынан
/// қайтып, қайта басып қоса алады. Экраннан шыққанда (немесе қайта ашқанда)
/// өшірілгендері тізімде БОЛМАЙДЫ.
///
/// «Нет в наличии» карточкаларда да жүрекше жұмыс істейді: бұрын бүкіл
/// карточка сұр (Opacity) қабатының ішінде тұрғандықтан батырма шағын әрі
/// нашар басылатын. Енді жүрекше — Opacity-ден ТЫС, өз алдына hit-target-і бар.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final _service = ClientService();
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  // Экранда көрінетін тізім (тәртібі сақталады).
  List<Map<String, dynamic>> _display = [];
  // Осы сессияда жүрекшесі алынған, бірақ әлі тізімде тұрған товарлар.
  final Set<String> _unliked = {};
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _sub = _service.watchFavorites().listen(
      (live) {
        if (!mounted) return;
        setState(() {
          _sync(live);
          _loading = false;
          _error = null;
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = e;
        });
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Ағымдағы базадағы тізімді экрандағы тізіммен біріктіреді: бұрынғы тәртіп
  /// сақталады, өшірілген (бірақ _unliked-та тұрған) жазбалар орнында қалады,
  /// жаңа қосылғандары басына түседі.
  void _sync(List<Map<String, dynamic>> live) {
    final liveById = {for (final e in live) e['id'] as String: e};
    final kept = <Map<String, dynamic>>[];
    final used = <String>{};
    for (final old in _display) {
      final id = old['id'] as String;
      if (liveById.containsKey(id)) {
        kept.add(liveById[id]!);
        used.add(id);
      } else if (_unliked.contains(id)) {
        kept.add(old); // өшірілген, бірақ сессия ішінде көрініп тұрады
        used.add(id);
      }
    }
    final fresh = live.where((e) => !used.contains(e['id'] as String)).toList();
    _display = [...fresh, ...kept];
  }

  Future<void> _toggle(Map<String, dynamic> item) async {
    final id = item['id'] as String? ?? '';
    if (id.isEmpty) return;
    HapticFeedback.lightImpact();
    final wasLiked = !_unliked.contains(id);
    // Оптимистік: UI бірден жауап береді, сәтсіз болса кері қайтарамыз.
    setState(() => wasLiked ? _unliked.add(id) : _unliked.remove(id));
    try {
      if (wasLiked) {
        await _service.removeFavorite(id);
      } else {
        await _service.addFavorite(
          productId: id,
          productName: item['productName'] as String? ?? '',
          imageUrl: item['imageUrl'] as String? ?? '',
          adminUid: item['adminUid'] as String? ?? '',
          storeName: item['storeName'] as String? ?? '',
          price: (item['price'] as num?)?.toDouble() ?? 0.0,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => wasLiked ? _unliked.remove(id) : _unliked.add(id));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Не удалось изменить избранное', 'Таңдаулыны өзгерту мүмкін болмады')),
        backgroundColor: cRed,
        behavior: SnackBarBehavior.floating,
      ));
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
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.chevron_left_rounded,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 10),
                Text(tr('Избранное', 'Таңдаулылар'),
                    style: manrope(20, FontWeight.w800, color: Colors.white)),
              ]),
            ),
          ),
        ),
        Expanded(child: _buildBody()),
      ]),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: cGreen));
    }
    if (_error != null && _display.isEmpty) {
      return Center(
        child: Text(tr('Не удалось загрузить', 'Жүктеу мүмкін болмады'),
            style: manrope(14, FontWeight.w600, color: cInk2)),
      );
    }
    if (_display.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.favorite_border_rounded,
              size: 60, color: cInk3.withValues(alpha: 0.35)),
          const SizedBox(height: 14),
          Text(tr('Список желаний пуст', 'Қалаулар тізімі бос'),
              style: manrope(16, FontWeight.w700, color: cInk2)),
          const SizedBox(height: 6),
          Text(tr('Нажмите ♡ на товаре чтобы добавить', 'Қосу үшін тауардағы ♡ басыңыз'),
              style: manrope(13, FontWeight.w500, color: cInk3)),
        ]),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: _display.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final item = _display[i];
        final id = item['id'] as String? ?? '';
        return _FavCard(
          key: ValueKey(id),
          item: item,
          service: _service,
          liked: !_unliked.contains(id),
          onToggle: () => _toggle(item),
        );
      },
    );
  }
}

class _FavCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final ClientService service;
  final bool liked;
  final VoidCallback onToggle;
  const _FavCard({
    super.key,
    required this.item,
    required this.service,
    required this.liked,
    required this.onToggle,
  });

  @override
  State<_FavCard> createState() => _FavCardState();
}

class _FavCardState extends State<_FavCard> {
  ProductModel? _product;
  StoreModel? _store;
  List<BatchModel> _batches = [];
  bool _loading = true;
  bool _available = false;

  String get _adminUid => widget.item['adminUid'] as String? ?? '';
  String get _productId => widget.item['id'] as String? ?? '';

  // Ағымдағы (тірі) баға — скидка белсенді болса соны ескереді. Батч әлі
  // жүктелмесе/жоқ болса — таңдаулыға қосылған сәттегі сақталған баға.
  BatchModel? get _priceBatch => _batches.isNotEmpty ? _batches.first : null;
  bool get _hasDiscount =>
      _priceBatch != null && hasActiveDiscount(_priceBatch!);
  double get _basePrice =>
      _priceBatch?.sellingPrice ?? (widget.item['price'] as num?)?.toDouble() ?? 0.0;
  double get _livePrice =>
      _priceBatch != null ? effectivePrice(_priceBatch!) : _basePrice;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  // Товардың әлі сатылымда (қолжетімді) екенін тексереміз: статус + бос batch.
  Future<void> _resolve() async {
    try {
      final product = await widget.service.getProductById(_adminUid, _productId);
      final store = product == null
          ? null
          : await widget.service.getStoreByAdminUid(_adminUid);
      var available = false;
      var batches = <BatchModel>[];
      if (product != null &&
          store != null &&
          store.isPublished &&
          !store.isBlocked &&
          product.status == ProductModel.statusInStock) {
        batches = await widget.service.getProductBatches(
            _adminUid, _productId, store.visibleWarehouseIds,
            onlyAvailable: true);
        available = batches.isNotEmpty;
      }
      if (!mounted) return;
      setState(() {
        _product = product;
        _store = store;
        _batches = batches;
        _available = available;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open() {
    if (!_available || _product == null || _store == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ClientProductDetail(product: _product!, store: _store!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.item['productName'] as String? ?? '';
    final store = widget.item['storeName'] as String? ?? '';
    final img = widget.item['imageUrl'] as String? ?? '';
    final dimmed = !_loading && !_available; // сатылымда емес → сұр, басылмайды

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cLine),
        boxShadow: kShadowSm,
      ),
      child: Row(children: [
        // Тауар бөлігі — «нет в наличии» болса сұр әрі басылмайды.
        Expanded(
          child: GestureDetector(
            onTap: dimmed || _loading ? null : _open,
            behavior: HitTestBehavior.opaque,
            child: Opacity(
              opacity: dimmed ? 0.55 : 1,
              child: Row(children: [
                Stack(children: [
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: QShoeImage(
                        imageUrl: img.isNotEmpty ? img : null,
                        height: 72,
                        tone: _productId.hashCode % 5,
                      ),
                    ),
                  ),
                  if (dimmed)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: cInk.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: manrope(14, FontWeight.w700,
                                color: dimmed ? cInk3 : cInk),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(store,
                            style: manrope(12, FontWeight.w500, color: cInk3)),
                        const SizedBox(height: 4),
                        if (dimmed)
                          Text(tr('Нет в наличии', 'Қолда жоқ'),
                              style: manrope(13, FontWeight.w700, color: cInk3))
                        else if (_loading)
                          // Батч (скидка бар-жоғы) жүктелгенше баға мүлде
                          // көрсетілмейді — әйтпесе алдымен қате (ескі
                          // сақталған) баға жыпылықтап, содан кейін скидка
                          // бағасына "секіріп" ауысады (керегі жоқ дірілдеу).
                          Shimmer.fromColors(
                            baseColor: cLine,
                            highlightColor: cLine2,
                            child: Container(
                              width: 64,
                              height: 15,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          )
                        else ...[
                          if (_hasDiscount)
                            Text(money(_basePrice),
                                style: manrope(11.5, FontWeight.w600, color: cInk3)
                                    .copyWith(decoration: TextDecoration.lineThrough)),
                          Text(money(_livePrice),
                              style: manrope(15, FontWeight.w800,
                                  color: _hasDiscount ? cRed : cGreen)),
                        ],
                      ]),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Жүрекше — сұр қабаттан тыс, кең hit-target (44×44).
        GestureDetector(
          onTap: widget.onToggle,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: AnimatedScale(
                scale: widget.liked ? 1.0 : 0.88,
                duration: const Duration(milliseconds: 140),
                child: Icon(
                  widget.liked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: widget.liked ? cRed.withValues(alpha: 0.85) : cInk3,
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
