import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' hide ConnectionState;
import 'package:livekit_client/livekit_client.dart' as lk show ConnectionState;
import 'package:provider/provider.dart';

import '../../core/lang.dart';
import '../../data/models/batch_model.dart';
import '../../data/models/cart_item_model.dart';
import '../../data/models/live_models.dart';
import '../../data/models/product_model.dart';
import '../../data/models/store_model.dart';
import '../../data/services/client_service.dart';
import '../../data/services/live_service.dart';
import '../../theme/qoima_design.dart';
import '../client/client_product_detail.dart';
import '../client/client_shell.dart';
import '../client/store_public_screen.dart';
import 'live_navigation.dart';
import 'live_widgets.dart';

/// Көрерменнің толық экранды эфир беті: видео, чат, лайк, бекітілген тауар.
///
/// LiveKit токені `livekit-token` edge fn-нен алынады (viewer grant: тек
/// subscribe). Чат/лайк/себет сигналы — SQL RPC арқылы, ал бекітілген тауар
/// мен чат realtime ағындарымен келеді.
class LiveViewerScreen extends StatefulWidget {
  final LiveSession session;
  const LiveViewerScreen({super.key, required this.session});

  @override
  State<LiveViewerScreen> createState() => _LiveViewerScreenState();
}

class _LiveViewerScreenState extends State<LiveViewerScreen> {
  final _svc = LiveService();
  final _client = ClientService();
  final _chatCtrl = TextEditingController();
  final _hearts = GlobalKey<LiveHeartsState>();

  late LiveSession _session = widget.session;
  List<LiveMessage> _messages = const [];
  List<LiveProduct> _shelf = const [];
  final Map<String, ProductModel> _products = {};
  StoreModel? _store;

  StreamSubscription<LiveSession?>? _sessionSub;
  StreamSubscription<List<LiveMessage>>? _msgSub;
  StreamSubscription<List<LiveProduct>>? _shelfSub;

  Room? _room;
  EventsListener<RoomEvent>? _roomListener;
  bool _connecting = true;
  String? _connectError;
  bool _ended = false;
  bool _releasing = false;

  // Лайк: жергілікті жүректер + сервер санағышы.
  int _lastLikes = 0;
  int _pendingOwnLikes = 0;
  DateTime _lastLikeCall = DateTime.fromMillisecondsSinceEpoch(0);

  // Бекітілген тауар.
  String _pinnedId = '';
  int _pinSeq = 0; // жарыс жағдайынан қорғау (тез ауысқанда ескі жауап өтпесін)
  ProductModel? _pinned;
  List<BatchModel> _batches = const [];
  bool _batchesLoading = false;
  String? _selectedSize;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _lastLikes = _session.likeCount;
    _loadStore();
    _sessionSub =
        _svc.watchSession(_session.id).listen(_onSession, onError: (_) {});
    _msgSub = _svc.watchMessages(_session.id).listen((m) {
      if (mounted) setState(() => _messages = m);
    }, onError: (_) {});
    _shelfSub = _svc.watchSessionProducts(_session.id).listen((list) {
      if (!mounted) return;
      setState(() => _shelf = list);
      _loadShelfProducts();
    }, onError: (_) {});
    _onSession(_session);
    _connect();
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    _msgSub?.cancel();
    _shelfSub?.cancel();
    _chatCtrl.dispose();
    _roomListener?.dispose();
    unawaited(_releaseRoom());
    super.dispose();
  }

  Future<void> _releaseRoom() async {
    final room = _room;
    if (room == null || _releasing) return;
    _releasing = true;
    try {
      await room.disconnect();
    } catch (_) {}
    try {
      await room.dispose();
    } catch (_) {}
  }

  // ── Қосылу ────────────────────────────────────────────────────────────────
  Future<void> _connect() async {
    if (mounted) {
      setState(() {
        _connecting = true;
        _connectError = null;
      });
    }
    Room? room;
    try {
      // asViewer: қызметкер өз эфирін қарағанда хостпен identity қақтығыспасын.
      final token = await _svc.getToken(_session.id, asViewer: true);
      if (!mounted) return;
      room = Room(
        roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
      );
      _room = room;
      // Тек суретті өзгертетін оқиғалар ғана қайта салады (active speaker
      // сияқты жиі оқиғалар бүкіл экранды секундына бірнеше рет салмасын).
      _roomListener = room.createListener()
        ..on<TrackSubscribedEvent>((_) => _refresh())
        ..on<TrackUnsubscribedEvent>((_) => _refresh())
        ..on<TrackMutedEvent>((_) => _refresh())
        ..on<TrackUnmutedEvent>((_) => _refresh())
        ..on<RoomReconnectingEvent>((_) => _refresh())
        ..on<RoomReconnectedEvent>((_) => _refresh())
        ..on<ParticipantConnectedEvent>((_) => _refresh())
        ..on<ParticipantDisconnectedEvent>((_) => _refresh())
        ..on<RoomDisconnectedEvent>((_) => _onRoomDisconnected());
      await room.connect(token.url, token.token);
      if (!mounted) {
        // Қосылу кезінде экран жабылды — бөлме қалып қоймасын.
        try {
          await room.disconnect();
        } catch (_) {}
        try {
          await room.dispose();
        } catch (_) {}
        return;
      }
      setState(() => _connecting = false);
    } catch (e) {
      // Сәтсіз қосылған бөлмені тазалаймыз.
      if (room != null) {
        try {
          await room.disconnect();
          await room.dispose();
        } catch (_) {}
        if (identical(_room, room)) _room = null;
      }
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connectError = liveErrorText(e);
      });
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// Ақырғы үзілу (желі/сервер): эфир DB-да әлі 'live' болса да көрермен
  /// шексіз спиннерде қалмасын — «Повторить» батырмасы көрсетіледі.
  void _onRoomDisconnected() {
    if (!mounted || _ended || _releasing) return;
    setState(() {
      _connecting = false;
      _connectError = liveErrorText('internal');
    });
  }

  Future<void> _retry() async {
    _releasing = false;
    _roomListener?.dispose();
    _roomListener = null;
    await _releaseRoom();
    _room = null;
    _releasing = false;
    if (mounted) await _connect();
  }

  // ── Деректер ──────────────────────────────────────────────────────────────
  Future<void> _loadStore() async {
    try {
      final s = await _client.getStoreByAdminUid(_session.adminUid);
      if (mounted) setState(() => _store = s);
      // Дүкен келген соң бекітілген тауардың партияларын жүктей аламыз.
      if (s != null && _pinnedId.isNotEmpty && _batches.isEmpty) {
        _loadPinned(_pinnedId);
      }
    } catch (_) {}
  }

  Future<void> _loadShelfProducts() async {
    final missing = _shelf
        .map((e) => e.productId)
        .where((id) => !_products.containsKey(id))
        .toList();
    if (missing.isEmpty) return;
    try {
      final got = await _svc.getProductsByIds(missing);
      if (mounted) setState(() => _products.addAll(got));
    } catch (_) {}
  }

  void _onSession(LiveSession? s) {
    if (!mounted || s == null) return;
    final delta = s.likeCount - _lastLikes;
    _lastLikes = s.likeCount;
    if (delta > 0) {
      // Өз лайктарымыз жергілікті көрсетілген — қайталамаймыз.
      final mine = math.min(_pendingOwnLikes, delta);
      _pendingOwnLikes -= mine;
      final others = math.min(delta - mine, 6);
      if (others > 0) _hearts.currentState?.burst(others);
    }
    final becameEnded = !s.isLive && !_ended;
    setState(() {
      _session = s;
      if (becameEnded) _ended = true;
    });
    if (becameEnded) {
      _roomListener?.dispose();
      _roomListener = null;
      unawaited(_releaseRoom());
    }
    if (s.currentProductId != _pinnedId) {
      _pinnedId = s.currentProductId;
      _loadPinned(_pinnedId);
    }
  }

  /// Бекітілген тауарды + оның қолжетімді партияларын жүктеу.
  Future<void> _loadPinned(String productId) async {
    final seq = ++_pinSeq;
    if (productId.isEmpty) {
      setState(() {
        _pinned = null;
        _batches = const [];
        _selectedSize = null;
        _batchesLoading = false;
      });
      return;
    }
    setState(() {
      _pinned = _products[productId];
      _batches = const [];
      _selectedSize = null;
      _batchesLoading = true;
    });
    try {
      var p = _products[productId];
      if (p == null) {
        final got = await _svc.getProductsByIds([productId]);
        p = got[productId];
        if (p != null) _products[productId] = p;
      }
      final store = _store;
      if (store == null) {
        // _loadStore() аяқталғанда қайта шақырылады.
        if (mounted && seq == _pinSeq) setState(() => _pinned = p);
        return;
      }
      final batches = await _client.getProductBatches(
        store.adminUid,
        productId,
        store.visibleWarehouseIds,
        onlyAvailable: true,
      );
      if (!mounted || seq != _pinSeq) return;
      setState(() {
        _pinned = p;
        _batches = batches;
        _batchesLoading = false;
        final sizes = _availableSizes;
        if (sizes.length == 1) _selectedSize = sizes.first;
      });
    } catch (_) {
      if (mounted && seq == _pinSeq) setState(() => _batchesLoading = false);
    }
  }

  List<String> get _availableSizes {
    final seen = <String>{};
    for (final b in _batches) {
      b.availableSizes.forEach((size, avail) {
        if (avail > 0) seen.add(size);
      });
    }
    return seen.toList();
  }

  BatchModel? get _batchForSize {
    final size = _selectedSize;
    if (size == null) return null;
    for (final b in _batches) {
      if (b.availableForSize(size) > 0) return b;
    }
    return null;
  }

  BatchModel? get _priceBatch =>
      _batchForSize ?? (_batches.isNotEmpty ? _batches.first : null);

  // ── Әрекеттер ─────────────────────────────────────────────────────────────
  void _toast(String text, {bool error = true, SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? cRed : cGreen,
        behavior: SnackBarBehavior.floating,
        action: action,
      ));
  }

  Future<void> _addToCart() async {
    final p = _pinned;
    final store = _store;
    if (_adding || p == null || store == null) return;
    final batch = _batchForSize;
    if (batch == null) {
      _toast(tr('Выберите размер', 'Өлшемді таңдаңыз'), error: false);
      return;
    }
    setState(() => _adding = true);
    try {
      // Дүкен мекенжайы (өзі алып кету үшін) — detail экранындағыдай.
      var address = '';
      try {
        final wh =
            await _client.getWarehouseById(store.adminUid, batch.warehouseId);
        address = wh?.address ?? '';
      } catch (_) {}
      final hasDisc = hasActiveDiscount(batch);
      final item = CartItemModel(
        productId: p.id,
        productName: p.name,
        batchId: batch.id,
        size: _selectedSize!,
        qty: 1,
        price: effectivePrice(batch),
        originalPrice: hasDisc ? batch.sellingPrice : 0,
        adminUid: store.adminUid,
        storeName: store.storeName,
        imageUrl: p.images.isNotEmpty ? p.images.first : '',
        brand: p.brand,
        type: p.type,
        color: p.color,
        variantNote: p.variantNote,
        articul: p.articul,
        warehouseId: batch.warehouseId,
        warehouseAddress: address,
      );
      if (!mounted) return;
      context.read<CartProvider>().addItem(item);
      // Статистика + чаттағы «себетке қосты» жолы (қате болса үнсіз).
      unawaited(_svc.trackCart(_session.id, p.id).catchError((_) => false));
      _toast(
        tr('${p.name} добавлен в корзину', '${p.name} себетке қосылды'),
        error: false,
        action: SnackBarAction(
          label: tr('В корзину', 'Себетке'),
          textColor: Colors.white,
          onPressed: () => openCartTab(context),
        ),
      );
    } catch (e) {
      _toast(liveErrorText(e));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _sendChat() async {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty || _ended) return;
    _chatCtrl.clear();
    try {
      await _svc.sendMessage(_session.id, text);
    } catch (e) {
      _toast(liveErrorText(e));
    }
  }

  void _like() {
    if (_ended) return;
    _hearts.currentState?.burst(1);
    final now = DateTime.now();
    if (now.difference(_lastLikeCall) < const Duration(milliseconds: 300)) {
      return;
    }
    _lastLikeCall = now;
    // Өз лайкымызды тек RPC жіберілетін болғанда санаймыз; сервер шектеп
    // тастаса (false/қате) — кері қайтарамыз, әйтпесе санауыш өсіп кетеді.
    _pendingOwnLikes++;
    unawaited(_svc.like(_session.id).then((ok) {
      if (!ok && _pendingOwnLikes > 0) _pendingOwnLikes--;
    }).catchError((_) {
      if (_pendingOwnLikes > 0) _pendingOwnLikes--;
    }));
  }

  void _openStore() {
    final s = _store;
    if (s == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StorePublicScreen(store: s),
    ));
  }

  Future<void> _openProduct(ProductModel p) async {
    final s = _store;
    if (s == null) return;
    // «Купить сейчас» true қайтарады → себет табына өтеміз.
    final buy = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ClientProductDetail(product: p, store: s),
    ));
    if (buy == true && mounted) openCartTab(context);
  }

  Future<void> _showAllProducts() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        final items = [
          for (final lp in _shelf)
            if (_products[lp.productId] != null) _products[lp.productId]!,
        ];
        return SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.6,
          child: Column(children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: cLine, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            Text(tr('Товары в эфире', 'Эфирдегі тауарлар'),
                style: manrope(16, FontWeight.w800, color: cInk)),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(tr('Пока нет товаров', 'Әзірге тауар жоқ'),
                          style: manrope(13, FontWeight.w600, color: cInk3)))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final p = items[i];
                        final isPinned = p.id == _pinnedId;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(kR8),
                            child: p.images.isEmpty
                                ? const SizedBox(width: 48, height: 48)
                                : Image.network(p.images.first,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    cacheWidth: 120,
                                    errorBuilder: (_, __, ___) =>
                                        const SizedBox(width: 48, height: 48)),
                          ),
                          title: Text(p.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: manrope(14, FontWeight.w700, color: cInk)),
                          subtitle: isPinned
                              ? Text(
                                  tr('Показывается сейчас',
                                      'Қазір көрсетілуде'),
                                  style: manrope(12, FontWeight.w700,
                                      color: cGreen))
                              : null,
                          trailing: const Icon(Icons.chevron_right_rounded,
                              color: cInk3),
                          onTap: () {
                            Navigator.pop(ctx);
                            _openProduct(p);
                          },
                        );
                      },
                    ),
            ),
          ]),
        );
      },
    );
  }

  // ── Видео ─────────────────────────────────────────────────────────────────
  VideoTrack? _hostVideo() {
    final room = _room;
    if (room == null) return null;
    for (final part in room.remoteParticipants.values) {
      for (final pub in part.videoTrackPublications) {
        final t = pub.track;
        if (t != null && pub.subscribed && !pub.muted) return t;
      }
    }
    return null;
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final video = _ended ? null : _hostVideo();
    final reconnecting = !_ended &&
        _room != null &&
        (_room!.connectionState == lk.ConnectionState.reconnecting);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        _buildBackdrop(video),
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x99000000),
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0xB3000000),
                ],
                stops: [0, 0.18, 0.5, 1],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Column(children: [
            _buildTopBar(),
            if (reconnecting)
              _buildBanner(tr('Переподключение…', 'Қайта қосылуда…'),
                  loading: true),
            if (_connectError != null && !_ended) _buildError(),
            const Spacer(),
            if (!_ended) ...[
              _buildChatRow(),
              const SizedBox(height: 8),
              _buildPinnedCard(),
              _buildInputRow(),
            ],
          ]),
        ),
        if (_ended) _buildEndedOverlay(),
      ]),
    );
  }

  Widget _buildBackdrop(VideoTrack? video) {
    if (video != null) {
      return VideoTrackRenderer(video, fit: VideoViewFit.cover);
    }
    final cover = _session.coverUrl.isNotEmpty
        ? _session.coverUrl
        : (_store?.logoUrl ?? '');
    return Stack(fit: StackFit.expand, children: [
      if (cover.isNotEmpty)
        Opacity(
          opacity: 0.35,
          child: Image.network(cover,
              fit: BoxFit.cover,
              cacheWidth: 400,
              errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        ),
      if (_connecting || (_connectError == null && !_ended))
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 14),
            Text(
                _connecting
                    ? tr('Подключаемся к эфиру…', 'Эфирге қосылудамыз…')
                    : tr('Ждём трансляцию…', 'Трансляцияны күтудеміз…'),
                style: manrope(14, FontWeight.w600, color: Colors.white)),
          ]),
        ),
    ]);
  }

  Widget _buildTopBar() {
    final store = _store;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Row(children: [
        Expanded(
          child: GestureDetector(
            onTap: _openStore,
            child: Container(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
              decoration: BoxDecoration(
                  color: kLiveScrim,
                  borderRadius: BorderRadius.circular(kRPill)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: cGreenTint,
                  backgroundImage: (store != null && store.logoUrl.isNotEmpty)
                      ? NetworkImage(store.logoUrl)
                      : null,
                  child: (store == null || store.logoUrl.isEmpty)
                      ? const Icon(Icons.storefront_rounded,
                          size: 16, color: cGreen)
                      : null,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(store?.storeName ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: manrope(13, FontWeight.w800,
                                color: Colors.white)),
                        Text(_session.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: manrope(11, FontWeight.w500,
                                color: Colors.white70)),
                      ]),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (!_ended) ...[
          const LiveBadge(),
          const SizedBox(width: 6),
          LiveViewersChip(count: _session.viewerCount),
          const SizedBox(width: 8),
        ],
        LiveRoundButton(
            icon: Icons.close_rounded,
            onTap: () => Navigator.of(context).maybePop()),
      ]),
    );
  }

  Widget _buildBanner(String text, {bool loading = false}) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: cAmber, borderRadius: BorderRadius.circular(kRPill)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (loading) ...[
            const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.black)),
            const SizedBox(width: 8),
          ],
          Text(text, style: manrope(12, FontWeight.w700, color: Colors.black)),
        ]),
      );

  Widget _buildError() => Container(
        margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: kLiveScrim, borderRadius: BorderRadius.circular(kR16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_connectError!,
              textAlign: TextAlign.center,
              style: manrope(13, FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 10),
          QSoftButton(
              label: tr('Повторить', 'Қайталау'),
              onPressed: _retry,
              height: 40),
        ]),
      );

  Widget _buildChatRow() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: 0.85,
              child: LiveChatOverlay(messages: _messages, maxHeight: 190),
            ),
          ),
          LiveHearts(key: _hearts),
        ]),
      );

  Widget _buildPinnedCard() {
    final p = _pinned;
    if (_pinnedId.isEmpty || p == null) return const SizedBox.shrink();
    final pb = _priceBatch;
    final sizes = _availableSizes;
    final price = pb != null ? effectivePrice(pb) : 0.0;
    final hasDisc = pb != null && hasActiveDiscount(pb);
    final canBuy = !_batchesLoading && sizes.isNotEmpty;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.circular(kR16),
        boxShadow: kShadowSm,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          GestureDetector(
            onTap: () => _openProduct(p),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kR12),
              child: p.images.isEmpty
                  ? const SizedBox(width: 64, height: 64)
                  : Image.network(p.images.first,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      cacheWidth: 160,
                      errorBuilder: (_, __, ___) =>
                          const SizedBox(width: 64, height: 64)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => _openProduct(p),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: manrope(13.5, FontWeight.w800, color: cInk)),
                    const SizedBox(height: 3),
                    if (_batchesLoading)
                      const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: cGreen))
                    else if (pb != null)
                      Row(children: [
                        Text(money(price),
                            style: manrope(15, FontWeight.w800, color: cGreen)),
                        if (hasDisc) ...[
                          const SizedBox(width: 6),
                          Text(money(pb.sellingPrice),
                              style: manrope(12, FontWeight.w600, color: cInk3)
                                  .copyWith(
                                      decoration: TextDecoration.lineThrough)),
                        ],
                      ])
                    else
                      Text(tr('Нет в наличии', 'Қолда жоқ'),
                          style: manrope(12.5, FontWeight.w700, color: cRed)),
                  ]),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 108,
            child: QPrimaryButton(
              label: tr('В корзину', 'Себетке'),
              height: 44,
              isLoading: _adding,
              onPressed: canBuy ? _addToCart : null,
            ),
          ),
        ]),
        if (sizes.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: sizes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final s = sizes[i];
                final on = s == _selectedSize;
                return GestureDetector(
                  onTap: () => setState(() => _selectedSize = s),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: on ? cGreen : cLine2,
                      borderRadius: BorderRadius.circular(kRPill),
                      border: Border.all(color: on ? cGreen : cLine),
                    ),
                    child: Text(s,
                        style: manrope(13, FontWeight.w800,
                            color: on ? Colors.white : cInk)),
                  ),
                );
              },
            ),
          ),
        ],
      ]),
    );
  }

  Widget _buildInputRow() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _chatCtrl,
              maxLength: 300,
              maxLines: 1,
              onSubmitted: (_) => _sendChat(),
              style: manrope(14, FontWeight.w500, color: Colors.white),
              decoration: InputDecoration(
                counterText: '',
                isDense: true,
                hintText: tr('Написать в чат…', 'Чатқа жазу…'),
                hintStyle: manrope(14, FontWeight.w500, color: Colors.white60),
                filled: true,
                fillColor: kLiveScrim,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(kRPill),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 20),
                  onPressed: _sendChat,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          LiveRoundButton(
              icon: Icons.shopping_bag_outlined, onTap: _showAllProducts),
          const SizedBox(width: 8),
          LiveRoundButton(
              icon: Icons.favorite_rounded, onTap: _like, color: cRed),
        ]),
      );

  Widget _buildEndedOverlay() => Positioned.fill(
        child: Container(
          color: Colors.black.withValues(alpha: 0.78),
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.videocam_off_rounded,
                      color: Colors.white70, size: 48),
                  const SizedBox(height: 14),
                  Text(tr('Эфир завершён', 'Эфир аяқталды'),
                      style: manrope(22, FontWeight.w800, color: Colors.white)),
                  const SizedBox(height: 6),
                  Text(
                      tr('Спасибо, что были с нами!',
                          'Бізбен бірге болғаныңызға рахмет!'),
                      textAlign: TextAlign.center,
                      style:
                          manrope(14, FontWeight.w500, color: Colors.white70)),
                  const SizedBox(height: 22),
                  if (_store != null)
                    QPrimaryButton(
                      label: tr('Перейти в магазин', 'Дүкенге өту'),
                      onPressed: () {
                        Navigator.of(context).pushReplacement(MaterialPageRoute(
                          builder: (_) => StorePublicScreen(store: _store!),
                        ));
                      },
                    ),
                  const SizedBox(height: 10),
                  QSoftButton(
                    label: tr('Закрыть', 'Жабу'),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}
