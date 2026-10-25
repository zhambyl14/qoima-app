import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../core/app_user.dart';
import '../../core/feature_flags.dart';
import '../../core/lang.dart';
import '../../data/models/live_models.dart';
import '../../data/models/store_model.dart';
import '../../data/services/live_service.dart';
import '../../theme/qoima_design.dart';
import 'live_host_screen.dart';
import 'live_widgets.dart';

/// Дүкен иесі / сатушы үшін эфирге кіру нүктесі.
///
/// Тексерулер (UI деңгейінде; нағыз тексеру — SQL `live_start`-та):
/// функция қосулы ма, рөл admin/seller ме, жазылым «қатып» қалмаған ба,
/// дүкен жарияланған ба. Содан кейін эфир алдындағы баптау экраны ашылады.
Future<void> openLiveHost(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String ru, String kk, {bool error = false}) {
    messenger.showSnackBar(SnackBar(
      content: Text(tr(ru, kk)),
      backgroundColor: error ? cRed : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // Суперадмин өшірсе — жаңа эфир бастауға болмайды.
  await FeatureFlags.instance.refresh();
  if (!context.mounted) return;
  if (!FeatureFlags.instance.isOn(FeatureFlags.liveShopping)) {
    say('Функция временно отключена', 'Функция уақытша өшірулі');
    return;
  }

  final me = AppUser.current;
  if (!(me.isAdmin || me.isSeller)) {
    say('Эфир доступен только магазину', 'Эфир тек дүкенге қолжетімді',
        error: true);
    return;
  }
  if (me.subFrozen) {
    say('Подписка истекла — эфир недоступен',
        'Жазылым мерзімі өтті — эфир қолжетімсіз',
        error: true);
    return;
  }

  final svc = LiveService();
  StoreModel? store;
  LiveSession? running;
  try {
    store = await svc.getMyStore();
    if (store != null) {
      running = await svc.getLiveSessionForStore(store.adminUid);
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text(liveErrorText(e)),
      backgroundColor: cRed,
      behavior: SnackBarBehavior.floating,
    ));
    return;
  }
  if (!context.mounted) return;

  if (store == null || !store.isPublished || store.isBlocked) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(tr('Магазин не опубликован', 'Дүкен жарияланбаған'),
            style: manrope(16, FontWeight.w800, color: cInk)),
        content: Text(
            tr(
                'Эфир показывается покупателям только у опубликованного магазина. '
                    'Опубликуйте магазин в разделе «Мой магазин».',
                'Эфир тек жарияланған дүкенде сатып алушыларға көрінеді. '
                    '«Менің дүкенім» бөлімінде дүкенді жариялаңыз.'),
            style: manrope(14, FontWeight.w500, color: cInk2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('OK',
                  style: manrope(14, FontWeight.w700, color: cGreen))),
        ],
      ),
    );
    return;
  }

  // Басқа құрылғыда (не басқа қызметкерде) тірі эфир болса — ескертеміз:
  // жаңасын бастау ескісін жабады.
  if (running != null && running.isFreshLive) {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(tr('Эфир уже идёт', 'Эфир қазірдің өзінде жүріп жатыр'),
            style: manrope(16, FontWeight.w800, color: cInk)),
        content: Text(
            tr(
                'У магазина уже есть активный эфир. Если начать новый, '
                    'текущий будет завершён.',
                'Дүкенде белсенді эфир бар. Жаңасын бастасаңыз, '
                    'ағымдағысы аяқталады.'),
            style: manrope(14, FontWeight.w500, color: cInk2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Отмена', 'Болдырмау'),
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Начать новый', 'Жаңасын бастау'),
                  style: manrope(14, FontWeight.w700, color: cRed))),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
  }

  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => LiveSetupScreen(store: store!),
  ));
}

/// Эфир алдындағы баптау: камера превьюі, тақырып, тауарлар таңдауы.
class LiveSetupScreen extends StatefulWidget {
  final StoreModel store;
  const LiveSetupScreen({super.key, required this.store});

  @override
  State<LiveSetupScreen> createState() => _LiveSetupScreenState();
}

class _LiveSetupScreenState extends State<LiveSetupScreen> {
  final _svc = LiveService();
  final _titleCtrl = TextEditingController();

  LocalVideoTrack? _camera;
  String? _mediaError; // камера/микрофон рұқсаты жоқ болса мәтін
  bool _mediaLoading = true;

  List<LiveShelfItem> _items = const [];
  bool _itemsLoading = true;
  String? _itemsError;
  final Set<String> _selected = {};

  bool _starting = false;
  // Host экранына берілді ме — берілсе, превью трегін өзіміз жоймаймыз.
  bool _handedOver = false;

  static const _maxProducts = 50;

  @override
  void initState() {
    super.initState();
    _titleCtrl.text = widget.store.storeName;
    _initMedia();
    _loadItems();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    if (!_handedOver) {
      _camera?.stop();
      _camera?.dispose();
    }
    super.dispose();
  }

  /// Камера превьюі. Микрофон рұқсатын да осы жерде ерте сұраймыз — эфирді
  /// бастаған соң ғана бас тартылса, сессия бос ашылып қалады.
  Future<void> _initMedia() async {
    setState(() {
      _mediaLoading = true;
      _mediaError = null;
    });
    try {
      final cam = await LocalVideoTrack.createCameraTrack(
        const CameraCaptureOptions(cameraPosition: CameraPosition.front),
      );
      // Микрофон рұқсатын тексеру үшін уақытша трек жасап, бірден жабамыз.
      final probe = await LocalAudioTrack.create();
      await probe.stop();
      await probe.dispose();
      if (!mounted) {
        await cam.stop();
        await cam.dispose();
        return;
      }
      setState(() {
        _camera = cam;
        _mediaLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _mediaLoading = false;
        _mediaError = tr(
            'Нет доступа к камере или микрофону. Разрешите доступ в настройках телефона и повторите.',
            'Камераға не микрофонға рұқсат жоқ. Телефон баптауларынан рұқсат беріп, қайталаңыз.');
      });
    }
  }

  Future<void> _loadItems() async {
    try {
      final list = await _svc.getHostProducts(widget.store);
      if (!mounted) return;
      setState(() {
        _items = list;
        _itemsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _itemsLoading = false;
        _itemsError = liveErrorText(e);
      });
    }
  }

  void _toggle(String productId) {
    setState(() {
      if (_selected.contains(productId)) {
        _selected.remove(productId);
      } else if (_selected.length < _maxProducts) {
        _selected.add(productId);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('Не больше 50 товаров', '50 тауардан көп болмайды')),
          behavior: SnackBarBehavior.floating,
        ));
      }
    });
  }

  void _toast(String text, {bool error = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? cRed : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _start() async {
    final cam = _camera;
    if (_starting || cam == null) return;
    setState(() => _starting = true);

    LiveSession? session;
    Room? room;
    try {
      // Тартиппен таңдалған тауарлар (тордағы реттілікпен).
      final ids = [
        for (final it in _items)
          if (_selected.contains(it.product.id)) it.product.id,
      ];
      // Мұқаба: бірінші таңдалған тауардың фотосы (https).
      String? cover;
      for (final it in _items) {
        if (_selected.contains(it.product.id) && it.product.images.isNotEmpty) {
          cover = it.product.images.first;
          break;
        }
      }
      session = await _svc.start(
        title: _titleCtrl.text.trim(),
        productIds: ids,
        coverUrl: cover,
      );
      final token = await _svc.getToken(session.id);
      if (!token.isHost) {
        throw LiveException('not_authorized', liveErrorText('not_authorized'));
      }

      room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: false,
          dynacast: true,
          defaultCameraCaptureOptions:
              CameraCaptureOptions(cameraPosition: CameraPosition.front),
        ),
      );
      await room.connect(token.url, token.token);
      await room.localParticipant!.publishVideoTrack(cam);
      await room.localParticipant!.setMicrophoneEnabled(true);

      if (!mounted) {
        await room.disconnect();
        await room.dispose();
        unawaited(_svc.end(session.id).catchError((_) => null));
        return;
      }
      _handedOver = true;
      final s = session;
      final r = room;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => LiveHostScreen(
          store: widget.store,
          session: s,
          room: r,
          camera: cam,
        ),
      ));
    } catch (e) {
      // Жартылай құрылған эфирді тазалаймыз (ілулі қалмасын).
      if (room != null) {
        try {
          await room.disconnect();
          await room.dispose();
        } catch (_) {}
      }
      if (session != null) {
        unawaited(_svc.end(session.id).catchError((_) => null));
      }
      _handedOver = false;
      if (mounted) {
        setState(() => _starting = false);
        _toast(liveErrorText(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canStart = !_starting && _camera != null && _mediaError == null;
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Прямой эфир', 'Тікелей эфир'),
          subtitle: tr('Подготовка', 'Дайындық'),
          showBack: true,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            children: [
              _buildPreview(),
              const SizedBox(height: 14),
              TextField(
                controller: _titleCtrl,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: tr('Название эфира', 'Эфир атауы'),
                  filled: true,
                  fillColor: cSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(kR14),
                    borderSide: const BorderSide(color: cLine),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: Text(tr('Товары в эфире', 'Эфирдегі тауарлар'),
                      style: manrope(15, FontWeight.w800, color: cInk)),
                ),
                Text('${_selected.length}/$_maxProducts',
                    style: manrope(13, FontWeight.w700, color: cInk3)),
              ]),
              const SizedBox(height: 4),
              Text(
                  tr('Можно добавить и позже, прямо во время эфира.',
                      'Кейін, эфир кезінде де қосуға болады.'),
                  style: manrope(12, FontWeight.w500, color: cInk3)),
              const SizedBox(height: 10),
              _buildGrid(),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: const BoxDecoration(
              color: cSurface,
              border: Border(top: BorderSide(color: cLine)),
            ),
            child: QPrimaryButton(
              label: tr('Начать эфир', 'Эфирді бастау'),
              isLoading: _starting,
              onPressed: canStart ? _start : null,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildPreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(kR20),
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: Container(
          color: Colors.black,
          child: _mediaLoading
              ? const Center(child: CircularProgressIndicator(color: cGreen))
              : _mediaError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.videocam_off_rounded,
                              color: Colors.white70, size: 42),
                          const SizedBox(height: 12),
                          Text(_mediaError!,
                              textAlign: TextAlign.center,
                              style: manrope(13, FontWeight.w600,
                                  color: Colors.white)),
                          const SizedBox(height: 14),
                          QSoftButton(
                            label: tr('Повторить', 'Қайталау'),
                            onPressed: _initMedia,
                            height: 42,
                          ),
                        ]),
                      ),
                    )
                  : Stack(fit: StackFit.expand, children: [
                      VideoTrackRenderer(_camera!, fit: VideoViewFit.cover),
                      const Positioned(
                          top: 10, left: 10, child: LiveBadge(compact: true)),
                    ]),
        ),
      ),
    );
  }

  Widget _buildGrid() {
    if (_itemsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Center(child: CircularProgressIndicator(color: cGreen)),
      );
    }
    if (_itemsError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(_itemsError!,
            style: manrope(13, FontWeight.w600, color: cRedInk)),
      );
    }
    if (_items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(kR16),
          border: Border.all(color: cLine),
        ),
        child: Text(
            tr(
                'Нет товаров в наличии на витрине. Эфир можно начать и без них — '
                    'товары добавятся по ходу.',
                'Витринада қолда бар тауар жоқ. Эфирді тауарсыз да бастауға болады — '
                    'тауарларды кейін қосасыз.'),
            style: manrope(13, FontWeight.w500, color: cInk2)),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.74,
      ),
      itemBuilder: (_, i) {
        final it = _items[i];
        final on = _selected.contains(it.product.id);
        return GestureDetector(
          onTap: () => _toggle(it.product.id),
          child: Container(
            decoration: BoxDecoration(
              color: cSurface,
              borderRadius: BorderRadius.circular(kR14),
              border: Border.all(color: on ? cGreen : cLine, width: on ? 2 : 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              Column(children: [
                Expanded(
                  child: SizedBox.expand(
                    child: Image.network(
                      it.product.images.first,
                      fit: BoxFit.cover,
                      cacheWidth: 260,
                      errorBuilder: (_, __, ___) =>
                          const ColoredBox(color: cLine2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 5),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(it.product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: manrope(11, FontWeight.w700, color: cInk)),
                        Text(money(it.price),
                            style: manrope(11, FontWeight.w800, color: cGreen)),
                      ]),
                ),
              ]),
              if (on)
                const Positioned(
                  top: 5,
                  right: 5,
                  child: CircleAvatar(
                    radius: 11,
                    backgroundColor: cGreen,
                    child: Icon(Icons.check_rounded,
                        size: 15, color: Colors.white),
                  ),
                ),
            ]),
          ),
        );
      },
    );
  }
}
