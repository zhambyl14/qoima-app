import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../core/lang.dart';
import '../../data/models/live_models.dart';
import '../../data/models/product_model.dart';
import '../../data/models/store_model.dart';
import '../../data/services/live_service.dart';
import '../../theme/qoima_design.dart';
import 'live_moderation.dart';
import 'live_widgets.dart';

/// Хосттың толық экранды эфир беті: камера, чат, сөре, бекіту, аяқтау.
///
/// Room мен камера трегін [LiveSetupScreen] дайындап береді; бұл экран
/// олардың иесі — аяқталғанда/жабылғанда өзі disconnect + dispose жасайды.
class LiveHostScreen extends StatefulWidget {
  final StoreModel store;
  final LiveSession session;
  final Room room;
  final LocalVideoTrack camera;
  const LiveHostScreen({
    super.key,
    required this.store,
    required this.session,
    required this.room,
    required this.camera,
  });

  @override
  State<LiveHostScreen> createState() => _LiveHostScreenState();
}

class _LiveHostScreenState extends State<LiveHostScreen>
    with WidgetsBindingObserver {
  final _svc = LiveService();
  final _chatCtrl = TextEditingController();

  late LiveSession _session = widget.session;
  List<LiveMessage> _messages = const [];
  List<LiveProduct> _shelf = const [];
  Map<String, ProductModel> _products = {};

  StreamSubscription<LiveSession?>? _sessionSub;
  StreamSubscription<List<LiveMessage>>? _msgSub;
  StreamSubscription<List<LiveProduct>>? _shelfSub;
  EventsListener<RoomEvent>? _roomListener;
  Timer? _heartbeat;
  // Секундомер: тек уақыт жазуы қайта салынады (бүкіл экран емес).
  final _tick = ValueNotifier<int>(0);
  Timer? _clock;

  bool _micOn = true;
  bool _frontCamera = true;
  bool _reconnecting = false;
  bool _ending = false;
  bool _finished = false; // эфир аяқталды → қорытынды көрсетіледі
  bool _loadingProducts = false;
  bool _chatSending = false;

  // Қорытынды үшін өз көшірмеміз (stream жабылғаннан кейін де қалады).
  Duration _finalDuration = Duration.zero;
  int _finalPeak = 0;
  int _finalLikes = 0;
  int _finalCart = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionSub = _svc.watchSession(_session.id).listen((s) {
      if (!mounted || s == null) return;
      setState(() => _session = s);
      // Cron/басқа құрылғы эфирді жапса — біз де аяқтаймыз.
      if (!s.isLive && !_finished && !_ending) _finish();
    }, onError: (_) {});
    _msgSub = _svc.watchMessages(_session.id).listen((m) {
      if (mounted) setState(() => _messages = m);
    }, onError: (_) {});
    _shelfSub = _svc.watchSessionProducts(_session.id).listen((list) {
      if (!mounted) return;
      setState(() => _shelf = list);
      _loadMissingProducts();
    }, onError: (_) {});

    _roomListener = widget.room.createListener()
      ..on<RoomReconnectingEvent>((_) => _setReconnecting(true))
      ..on<RoomResumingEvent>((_) => _setReconnecting(true))
      ..on<RoomReconnectedEvent>((_) => _setReconnecting(false))
      ..on<RoomDisconnectedEvent>((_) => _onRoomDisconnected());

    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tick.value++);
    WidgetsBinding.instance.addPostFrameCallback((_) => _showKeepAwakeHint());
    _sendHeartbeat();
    _heartbeat =
        Timer.periodic(const Duration(seconds: 20), (_) => _sendHeartbeat());
  }

  /// Қолданба фонға кетіп қайтқанда бірден heartbeat жібереміз — әйтпесе
  /// келесі 20 с тактіге дейін cron эфирді жауып тастауы мүмкін. (Экран
  /// өшіп қалмауы үшін wakelock жоқ — қараңыз: _showKeepAwakeHint.)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sendHeartbeat();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionSub?.cancel();
    _msgSub?.cancel();
    _shelfSub?.cancel();
    _roomListener?.dispose();
    _heartbeat?.cancel();
    _clock?.cancel();
    _tick.dispose();
    _chatCtrl.dispose();
    // Экраннан басқа жолмен шықса (мысалы, маршрут жойылса) — эфирді
    // жетім қалдырмаймыз. Қолданба өлсе — cron 2 минутта жабады.
    if (!_finished) {
      unawaited(
          _svc.end(_session.id).then((_) => null).catchError((_) => null));
    }
    unawaited(_releaseMedia());
    super.dispose();
  }

  bool _released = false;

  Future<void> _releaseMedia() async {
    if (_released) return; // _finish() пен dispose() екеуі де шақырады
    _released = true;
    try {
      await widget.room.disconnect();
    } catch (_) {}
    try {
      await widget.camera.stop();
    } catch (_) {}
    try {
      await widget.room.dispose();
    } catch (_) {}
  }

  /// RoomDisconnectedEvent — ақырғы үзілу (қайта қосылу әрекеттері таусылды,
  /// сервер шығарды, бөлме жабылды). Эфирді «ілулі» қалдырмай, таза жабамыз.
  Future<void> _onRoomDisconnected() async {
    if (!mounted || _finished || _ending) return;
    _ending = true;
    _toast(tr('Соединение потеряно — эфир завершён',
        'Байланыс үзілді — эфир аяқталды'));
    try {
      final ended = await _svc.end(_session.id);
      if (ended != null) _session = ended;
    } catch (_) {
      // Серверге жетпесе — cron 2 минутта жабады.
    }
    if (mounted) _finish();
  }

  void _setReconnecting(bool v) {
    if (mounted && !_finished && v != _reconnecting) {
      setState(() => _reconnecting = v);
    }
  }

  // ── Heartbeat ─────────────────────────────────────────────────────────────
  Future<void> _sendHeartbeat() async {
    if (_finished || _ending) return;
    // Бөлме үзілсе heartbeat жібермейміз — cron өлі эфирді 2 минутта жабады.
    if (widget.room.connectionState.name != 'connected') return;
    try {
      final viewers = widget.room.remoteParticipants.length;
      final st = await _svc.heartbeat(_session.id, viewers);
      if (st != LiveSession.statusLive && mounted && !_finished && !_ending) {
        _finish();
      }
    } catch (_) {
      // Желі үзілді — келесі тактіде қайталаймыз; cron 2 минуттан соң жабады.
    }
  }

  // ── Тауарлар ──────────────────────────────────────────────────────────────
  Future<void> _loadMissingProducts() async {
    final missing = _shelf
        .map((e) => e.productId)
        .where((id) => !_products.containsKey(id))
        .toList();
    if (missing.isEmpty || _loadingProducts) return;
    _loadingProducts = true;
    try {
      final got = await _svc.getProductsByIds(missing);
      if (mounted) setState(() => _products = {..._products, ...got});
    } catch (_) {
    } finally {
      _loadingProducts = false;
    }
  }

  Future<void> _togglePin(String productId) async {
    final unpin = _session.currentProductId == productId;
    try {
      await _svc.pin(_session.id, unpin ? null : productId);
    } catch (e) {
      _toast(liveErrorText(e));
    }
  }

  /// Дүкеннің басқа тауарларын эфирге қосып, бірден бекіту.
  Future<void> _addProducts() async {
    final items = await showModalBottomSheet<List<LiveShelfItem>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _AddProductSheet(
        store: widget.store,
        taken: _shelf.map((e) => e.productId).toSet(),
      ),
    );
    if (items == null || items.isEmpty || !mounted) return;
    // Сервер тізімде жоқ тауарды live_pin_product арқылы өзі қосады;
    // соңғысы бекітулі қалады.
    for (final it in items) {
      try {
        await _svc.pin(_session.id, it.product.id);
      } catch (e) {
        _toast(liveErrorText(e));
        break;
      }
    }
  }

  // ── Чат ───────────────────────────────────────────────────────────────────
  Future<void> _sendChat() async {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty) return;
    if (_chatSending) return;
    _chatSending = true;
    // Мәтін тек сәтті жіберілгенде тазаланады — қате болса жоғалмайды.
    try {
      await _svc.sendMessage(_session.id, text);
      if (_chatCtrl.text.trim() == text) _chatCtrl.clear();
    } catch (e) {
      _toast(liveErrorText(e));
    }
    // Сервер шегі 1 хабарлама/2 с.
    await Future.delayed(const Duration(seconds: 2));
    _chatSending = false;
  }

  // ── Басқару ───────────────────────────────────────────────────────────────
  Future<void> _toggleMic() async {
    final next = !_micOn;
    try {
      await widget.room.localParticipant?.setMicrophoneEnabled(next);
      if (mounted) setState(() => _micOn = next);
    } catch (_) {
      _toast(tr('Не удалось переключить микрофон',
          'Микрофонды ауыстыру мүмкін болмады'));
    }
  }

  Future<void> _flipCamera() async {
    final next = _frontCamera ? CameraPosition.back : CameraPosition.front;
    try {
      await widget.camera.setCameraPosition(next);
      if (mounted) setState(() => _frontCamera = !_frontCamera);
    } catch (_) {
      _toast(tr(
          'Не удалось переключить камеру', 'Камераны ауыстыру мүмкін болмады'));
    }
  }

  Future<bool> _confirmEnd() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(tr('Завершить эфир?', 'Эфирді аяқтау керек пе?'),
            style: manrope(16, FontWeight.w800, color: cInk)),
        content: Text(
            tr('Зрители увидят, что эфир закончился.',
                'Көрермендер эфирдің аяқталғанын көреді.'),
            style: manrope(14, FontWeight.w500, color: cInk2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Продолжить', 'Жалғастыру'),
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Завершить', 'Аяқтау'),
                  style: manrope(14, FontWeight.w700, color: cRed))),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _endPressed() async {
    if (_ending || _finished) return;
    if (!await _confirmEnd() || !mounted) return;
    setState(() => _ending = true);
    try {
      final ended = await _endWithRetry();
      if (ended != null) _session = ended;
    } catch (e) {
      // Қайталаудан кейін де жетпесе, экранды жабамыз — cron эфирді өзі аяқтайды.
      _toast(liveErrorText(e));
    }
    if (mounted) _finish();
  }

  /// live_end желі қатесінде 3 рет қайталанады (1 с, 2 с үзіліспен): сервер
  /// эфирді жаппай қалса, көрермендер 2 минутқа дейін «тірі» көре береді.
  Future<LiveSession?> _endWithRetry() async {
    Object? last;
    for (var i = 0; i < 3; i++) {
      try {
        return await _svc.end(_session.id);
      } catch (e) {
        last = e;
        if (i < 2) await Future.delayed(Duration(seconds: i + 1));
      }
    }
    throw last!;
  }

  /// Қорытынды экранға өту: камера/микрофонды жауып, санағыштарды тіркеу.
  void _finish() {
    if (_finished) return;
    _heartbeat?.cancel();
    _clock?.cancel();
    final cart = _shelf.fold<int>(0, (s, e) => s + e.addToCartCount);
    setState(() {
      _finished = true;
      _ending = false;
      _finalDuration = _session.duration;
      _finalPeak = _session.peakViewers;
      _finalLikes = _session.likeCount;
      _finalCart = cart;
    });
    unawaited(_releaseMedia());
  }

  /// Wakelock-қа жаңа тәуелділік қосуға болмайды, сондықтан хостқа экранды
  /// өшірмеуді ескертеміз (экран ұйқыға кетсе, камера тоқтап, cron 2 минуттан
  /// кейін эфирді жабады).
  void _showKeepAwakeHint() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr(
          'Не блокируйте экран и не сворачивайте приложение во время эфира',
          'Эфир кезінде экранды құлыптамаңыз және қолданбаны жаппаңыз')),
      duration: const Duration(seconds: 6),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: cRed,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_finished) return _buildSummary();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endPressed();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(fit: StackFit.expand, children: [
          VideoTrackRenderer(widget.camera, fit: VideoViewFit.cover),
          // Жоғары/төмен қараңғы градиент: батырмалар кез келген кадрда оқылсын.
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
                  stops: [0, 0.18, 0.55, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(children: [
              _buildTopBar(),
              if (_reconnecting) _buildReconnectBanner(),
              const Spacer(),
              _buildChat(),
              const SizedBox(height: 8),
              _buildShelf(),
              const SizedBox(height: 8),
              _buildChatInput(),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildTopBar() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: Row(children: [
          const LiveBadge(),
          const SizedBox(width: 8),
          LiveViewersChip(count: _session.viewerCount),
          const SizedBox(width: 8),
          ValueListenableBuilder<int>(
            valueListenable: _tick,
            builder: (_, __, ___) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                  color: kLiveScrim,
                  borderRadius: BorderRadius.circular(kRPill)),
              child: Text(formatLiveDuration(_session.duration),
                  style: manrope(11.5, FontWeight.w700, color: Colors.white)),
            ),
          ),
          const SizedBox(width: 8),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.favorite_rounded, color: cRed, size: 14),
            const SizedBox(width: 3),
            Text('${_session.likeCount}',
                style: manrope(11.5, FontWeight.w700, color: Colors.white)),
          ]),
          const Spacer(),
          LiveRoundButton(
              icon: _micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
              onTap: _toggleMic,
              background: _micOn ? kLiveScrim : cRed),
          const SizedBox(width: 8),
          LiveRoundButton(icon: Icons.cameraswitch_rounded, onTap: _flipCamera),
          const SizedBox(width: 8),
          _ending
              ? const SizedBox(
                  width: 40,
                  height: 40,
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ))
              : LiveRoundButton(
                  icon: Icons.close_rounded,
                  onTap: _endPressed,
                  background: cRed),
        ]),
      );

  Widget _buildReconnectBanner() => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: cAmber, borderRadius: BorderRadius.circular(kRPill)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.black)),
          const SizedBox(width: 8),
          Text(
              tr('Связь прервалась — переподключение…',
                  'Байланыс үзілді — қайта қосылуда…'),
              style: manrope(12, FontWeight.w700, color: Colors.black)),
        ]),
      );

  Widget _buildChat() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: 0.78,
            child: LiveChatOverlay(
              messages: _messages,
              maxHeight: 190,
              onMessageLongPress: (m) => showLiveMessageActions(
                context,
                message: m,
                sessionId: _session.id,
                adminUid: widget.store.adminUid,
                storeName: widget.store.storeName,
                asHost: true,
              ),
            ),
          ),
        ),
      );

  /// Төменгі сөре: тауарға басу = бекіту/алып тастау. Жасыл жақтау = бекітулі,
  /// сары белгі = себетке қосылған саны.
  Widget _buildShelf() => SizedBox(
        height: 88,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            GestureDetector(
              onTap: _addProducts,
              child: Container(
                width: 70,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: kLiveScrim,
                  borderRadius: BorderRadius.circular(kR14),
                  border: Border.all(color: Colors.white38),
                ),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_rounded, color: Colors.white),
                      const SizedBox(height: 2),
                      Text(tr('Товар', 'Тауар'),
                          style: manrope(11, FontWeight.w700,
                              color: Colors.white)),
                    ]),
              ),
            ),
            for (final lp in _shelf) _shelfTile(lp),
          ],
        ),
      );

  Widget _shelfTile(LiveProduct lp) {
    final p = _products[lp.productId];
    final pinned = _session.currentProductId == lp.productId;
    final img = (p != null && p.images.isNotEmpty) ? p.images.first : '';
    return GestureDetector(
      onTap: () => _togglePin(lp.productId),
      child: Container(
        width: 70,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(kR14),
          border: Border.all(
              color: pinned ? cGreenBright : Colors.white24,
              width: pinned ? 2.5 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          if (img.isNotEmpty)
            Image.network(img,
                fit: BoxFit.cover,
                cacheWidth: 200,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          if (pinned)
            const Positioned(
              left: 4,
              top: 4,
              child:
                  Icon(Icons.push_pin_rounded, size: 16, color: cGreenBright),
            ),
          if (lp.addToCartCount > 0)
            Positioned(
              right: 3,
              bottom: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: cAmber, borderRadius: BorderRadius.circular(kRPill)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.shopping_bag_outlined,
                      size: 10, color: Colors.black),
                  const SizedBox(width: 2),
                  Text('${lp.addToCartCount}',
                      style: manrope(10, FontWeight.w800, color: Colors.black)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _buildChatInput() => Padding(
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
              ),
            ),
          ),
          const SizedBox(width: 8),
          LiveRoundButton(
              icon: Icons.send_rounded, onTap: _sendChat, background: cGreen),
        ]),
      );

  Widget _buildSummary() => PopScope(
        canPop: true,
        child: Scaffold(
          backgroundColor: cBg,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                const Spacer(),
                const Icon(Icons.check_circle_rounded, color: cGreen, size: 56),
                const SizedBox(height: 12),
                Text(tr('Эфир завершён', 'Эфир аяқталды'),
                    style: manrope(22, FontWeight.w800, color: cInk)),
                const SizedBox(height: 4),
                Text(_session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: manrope(14, FontWeight.w600, color: cInk2)),
                const SizedBox(height: 22),
                LiveSummaryCard(
                  duration: _finalDuration,
                  peakViewers: _finalPeak,
                  likes: _finalLikes,
                  cartAdds: _finalCart,
                ),
                const Spacer(),
                QPrimaryButton(
                  label: tr('Закрыть', 'Жабу'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ]),
            ),
          ),
        ),
      );
}

/// Эфир кезінде қосымша тауар таңдау парақшасы (дүкеннің қолдағы тауарлары,
/// әлі эфирде жоқтары).
class _AddProductSheet extends StatefulWidget {
  final StoreModel store;
  final Set<String> taken;
  const _AddProductSheet({required this.store, required this.taken});

  @override
  State<_AddProductSheet> createState() => _AddProductSheetState();
}

class _AddProductSheetState extends State<_AddProductSheet> {
  final _svc = LiveService();
  List<LiveShelfItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _svc.getHostProducts(widget.store).then((list) {
      if (mounted) {
        setState(() => _items =
            list.where((e) => !widget.taken.contains(e.product.id)).toList());
      }
    }).catchError((Object e) {
      if (mounted) setState(() => _error = liveErrorText(e));
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height * 0.6;
    return SizedBox(
      height: h,
      child: Column(children: [
        const SizedBox(height: 10),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
              color: cLine, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 12),
        Text(tr('Добавить товар в эфир', 'Эфирге тауар қосу'),
            style: manrope(16, FontWeight.w800, color: cInk)),
        const SizedBox(height: 8),
        Expanded(
          child: _error != null
              ? Center(
                  child: Text(_error!,
                      style: manrope(13, FontWeight.w600, color: cRedInk)))
              : _items == null
                  ? const Center(
                      child: CircularProgressIndicator(color: cGreen))
                  : _items!.isEmpty
                      ? Center(
                          child: Text(
                              tr('Больше нет товаров', 'Басқа тауар жоқ'),
                              style:
                                  manrope(13, FontWeight.w600, color: cInk3)))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          itemCount: _items!.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final it = _items![i];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(kR8),
                                child: Image.network(it.product.images.first,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    cacheWidth: 120,
                                    errorBuilder: (_, __, ___) =>
                                        const SizedBox(width: 48, height: 48)),
                              ),
                              title: Text(it.product.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: manrope(14, FontWeight.w700,
                                      color: cInk)),
                              subtitle: Text(money(it.price),
                                  style: manrope(12, FontWeight.w700,
                                      color: cGreen)),
                              trailing: const Icon(Icons.add_circle_rounded,
                                  color: cGreen),
                              onTap: () => Navigator.pop(context, [it]),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}
