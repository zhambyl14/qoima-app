import 'dart:async';
import 'dart:io' show File;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart' show ImagePicker, ImageSource;

import '../../core/lang.dart';
import '../../theme/qoima_design.dart';
import 'image_crop_screen.dart';

/// Дайын 1:1 фото + түпнұсқасы (қайта кадрлау түпнұсқадан басталуы үшін).
class CapturedPhoto {
  final Uint8List cropped;
  final Uint8List original;
  const CapturedPhoto({required this.cropped, required this.original});
}

/// Бір түсіру/таңдау нәтижесі. [overLimit] — лимитке сыймай қалғаны,
/// [failed] — оқылмаған файл (шақырушы иесіне хабарлайды).
class PhotoBatch {
  final List<CapturedPhoto> photos;
  final int overLimit;
  final int failed;
  const PhotoBatch(this.photos, {this.overLimit = 0, this.failed = 0});
}

/// Галереядан таңдап, бәрін авто-центр кеседі (міндетті кадрлау экранынсыз).
Future<PhotoBatch> pickGalleryPhotos({
  required int maxShots,
  int outputSize = kProductPhotoSize,
}) {
  return _pickViaSystem(ImageSource.gallery, maxShots, outputSize);
}

// image_picker-ден келетін түпнұсқа шегі: кадр бәрібір 1080 болады, ал 12 Мп
// файлды жадыда ұстап, әр кесуде декодтау баяу әрі қымбат. Қайта кадрлағанда
// жақындатуға жететін запас қалады.
const double _kPickerMaxSide = 2400;

Future<PhotoBatch> _pickViaSystem(
    ImageSource source, int maxShots, int outputSize) async {
  if (maxShots <= 0) return const PhotoBatch([]);
  final picker = ImagePicker();
  final List<XFile> picked;
  if (source == ImageSource.camera) {
    final XFile? shot;
    try {
      shot = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 90,
          maxWidth: _kPickerMaxSide,
          maxHeight: _kPickerMaxSide);
    } catch (_) {
      // Жүйелік камера да жоқ не рұқсат жоқ — галерея қалады.
      return _pickViaSystem(ImageSource.gallery, maxShots, outputSize);
    }
    picked = shot == null ? const [] : [shot];
  } else {
    picked = await picker.pickMultiImage(
        imageQuality: 90,
        maxWidth: _kPickerMaxSide,
        maxHeight: _kPickerMaxSide);
  }
  final photos = <CapturedPhoto>[];
  var failed = 0;
  for (final file in picked.take(maxShots)) {
    final raw = await file.readAsBytes();
    final cropped = await autoCenterCropAsync(raw, size: outputSize);
    if (cropped == null) {
      failed++;
    } else {
      photos.add(CapturedPhoto(cropped: cropped, original: raw));
    }
  }
  return PhotoBatch(photos,
      overLimit: picked.length > maxShots ? picked.length - maxShots : 0,
      failed: failed);
}

/// Экран кадрындағы шаршы: жоғарғы/төменгі панельдердің арасындағы аймақтың
/// ортасында. Таза функция — тестіленеді.
@visibleForTesting
Rect cameraFrameRect(Size screen,
    {required double top, required double bottom}) {
  final stageH = screen.height - top - bottom;
  final side = screen.width < stageH ? screen.width : stageH;
  return Rect.fromCenter(
    center: Offset(screen.width / 2, top + stageH / 2),
    width: side < 0 ? 0 : side,
    height: side < 0 ? 0 : side,
  );
}

/// Превью өлшемі: ҚЫСҚА қабырғасы кадрға ДӘЛ тең (шаршы ішіндегі BoxFit.cover).
/// Бүкіл экранды жапсақ, превью экраннан кең болып, кадр суреттің қысқа
/// қабырғасынан кіші аймақты көрсетер еді — сақталғаны көрінгенінен кең шығатын.
@visibleForTesting
Size cameraPreviewSize(double frameSide, double aspectRatio) {
  final a = aspectRatio <= 0 ? 1.0 : aspectRatio;
  return Size(frameSide, frameSide * (a < 1 ? 1 / a : a));
}

/// Рұқсат қатесі ме (Android/iOS кодтары әртүрлі).
@visibleForTesting
bool isCameraPermissionError(String code) {
  final c = code.toLowerCase();
  return c.contains('accessdenied') ||
      c.contains('accessrestricted') ||
      c.contains('permission');
}

/// Тауарды қатарынан түсіретін камера. Ысырма БІРДЕН түсіреді: растау да,
/// әр кадрдан кейінгі «Готово» да жоқ — иесі 4 фотоны қатарынан түсіре алады.
/// Кесу фонда жүреді, сондықтан ысырма күтпейді.
class MultiShotCameraScreen extends StatefulWidget {
  final int maxShots;
  final int outputSize;
  const MultiShotCameraScreen({
    super.key,
    required this.maxShots,
    this.outputSize = kProductPhotoSize,
  });

  /// Дайын 1:1 JPEG тізімі (бас тартылса — бос).
  static Future<List<Uint8List>> capture(
    BuildContext context, {
    required int maxShots,
    int outputSize = kProductPhotoSize,
  }) async {
    final batch = await captureWithOriginals(context,
        maxShots: maxShots, outputSize: outputSize);
    return [for (final p in batch.photos) p.cropped];
  }

  /// [capture] сияқты, бірақ түпнұсқасымен қоса. Веб пен камерасыз құрылғыда,
  /// плагин қате берсе — image_picker-ге ауысады.
  static Future<PhotoBatch> captureWithOriginals(
    BuildContext context, {
    required int maxShots,
    int outputSize = kProductPhotoSize,
  }) async {
    if (maxShots <= 0) return const PhotoBatch([]);
    if (kIsWeb) {
      return _pickViaSystem(ImageSource.camera, maxShots, outputSize);
    }
    final res = await Navigator.of(context, rootNavigator: true)
        .push<_CameraOutcome>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          MultiShotCameraScreen(maxShots: maxShots, outputSize: outputSize),
    ));
    final photos = res?.photos ?? const <CapturedPhoto>[];
    final fallback = res?.fallback;
    if (fallback == null) return PhotoBatch(photos);
    final more =
        await _pickViaSystem(fallback, maxShots - photos.length, outputSize);
    return PhotoBatch([...photos, ...more.photos],
        overLimit: more.overLimit, failed: more.failed);
  }

  @override
  State<MultiShotCameraScreen> createState() => _MultiShotCameraScreenState();
}

class _CameraOutcome {
  final List<CapturedPhoto> photos;
  final ImageSource? fallback;
  const _CameraOutcome(this.photos, {this.fallback});
}

class _Shot {
  final int id;
  final Uint8List original;
  final double? previewAspect;
  Uint8List? cropped;
  bool deleted = false;
  _Shot(this.id, this.original, this.previewAspect);
}

enum _CamState { starting, ready, denied, unavailable }

class _MultiShotCameraScreenState extends State<MultiShotCameraScreen>
    with WidgetsBindingObserver {
  static const double _kTopBar = 56;
  static const double _kBottomPanel = 176;

  CameraController? _controller;
  CameraDescription? _camera;
  _CamState _state = _CamState.starting;
  bool _initInFlight = false;
  // Қолданба шынымен фонға кетті ме (баптауларға барып келді). Рұқсат диалогы
  // тек inactive береді: оған қайта бастасақ, диалог шексіз қайталанар еді.
  bool _sawBackground = false;

  final List<_Shot> _shots = [];
  int _shotSeq = 0;
  bool _capturing = false;
  bool _finishRequested = false;
  bool _closed = false;
  bool _blink = false;
  FlashMode _flash = FlashMode.off;
  // Кесу кезекпен: арзан телефонда 4 isolate қатар декодтаса, жады жетпей қалады.
  Future<void> _cropQueue = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  // ── Камераны іске қосу ────────────────────────────────────────────────────
  Future<CameraDescription?> _findBackCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return null;
    return cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first);
  }

  Future<void> _start() async {
    if (_initInFlight) return;
    _initInFlight = true;
    if (mounted && _state != _CamState.starting) {
      setState(() => _state = _CamState.starting);
    }
    CameraController? c;
    try {
      _camera ??= await _findBackCamera();
      final camera = _camera;
      if (camera == null) {
        _initInFlight = false;
        _onUnavailable();
        return;
      }
      c = CameraController(camera, ResolutionPreset.veryHigh,
          enableAudio: false);
      await c.initialize();
      // Қолданба тік режимде ғана. Бекітпесек, телефонды бұрғанда превью қисаяды
      // да, кадрда көрінгені сақталғанына сәйкес келмей қалады.
      try {
        await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {}
      try {
        await c.setFlashMode(_flash);
      } catch (_) {
        _flash = FlashMode.off;
      }
      _initInFlight = false;
      if (!mounted) {
        unawaited(c.dispose());
        return;
      }
      // Іске қосылып жатқанда қолданба кетіп қалса — камераны ұстамаймыз,
      // resumed келгенде қайта ашылады.
      final life = WidgetsBinding.instance.lifecycleState;
      if (life != null && life != AppLifecycleState.resumed) {
        unawaited(c.dispose());
        setState(() => _state = _CamState.starting);
        return;
      }
      setState(() {
        _controller = c;
        _state = _CamState.ready;
      });
    } on CameraException catch (e) {
      _initInFlight = false;
      if (c != null) unawaited(c.dispose().catchError((_) {}));
      if (!mounted) return;
      if (isCameraPermissionError(e.code)) {
        setState(() => _state = _CamState.denied);
      } else {
        _onUnavailable();
      }
    } catch (_) {
      // MissingPluginException/UnimplementedError: бұл платформада плагин жоқ.
      _initInFlight = false;
      if (c != null) unawaited(c.dispose().catchError((_) {}));
      if (mounted) _onUnavailable();
    }
  }

  void _onUnavailable() {
    if (!mounted) return;
    if (_shots.isEmpty) {
      _close(fallback: ImageSource.camera);
    } else {
      // Түсірілгендер жоғалмасын: экранда қалып, «Готово» арқылы алынады.
      setState(() => _state = _CamState.unavailable);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
        final c = _controller;
        if (c == null) return; // инициализация/рұқсат диалогы кезінде тимейміз
        setState(() {
          _controller = null;
          _state = _CamState.starting;
        });
        c.dispose();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _sawBackground = true;
      case AppLifecycleState.resumed:
        final retry = _sawBackground &&
            (_state == _CamState.denied || _state == _CamState.unavailable);
        _sawBackground = false;
        if (_controller == null &&
            !_initInFlight &&
            (_state == _CamState.starting || retry)) {
          _start();
        }
      case AppLifecycleState.detached:
        break;
    }
  }

  // ── Түсіру ────────────────────────────────────────────────────────────────
  Future<void> _shoot() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (_capturing || _finishRequested) return; // қос басу еленбейді
    if (_shots.length >= widget.maxShots) return;
    _capturing = true;
    HapticFeedback.lightImpact();
    setState(() => _blink = true);
    final aspect = c.value.aspectRatio;
    try {
      final file = await c.takePicture();
      final raw = await file.readAsBytes();
      _deleteTemp(file);
      if (mounted) _addShot(raw, aspect);
    } catch (_) {
      if (mounted) {
        _snack(tr('Не удалось сделать снимок, попробуйте ещё раз',
            'Суретке түсіру мүмкін болмады, қайта көріңіз'));
      }
    } finally {
      _capturing = false;
      if (mounted) {
        setState(() => _blink = false);
        _maybeFinish();
      }
    }
  }

  // Плагин әр кадрды кэш папкасына жазады; байттар жадыда, файл енді керек емес.
  void _deleteTemp(XFile file) {
    if (kIsWeb) return;
    unawaited(File(file.path).delete().catchError((_) => File(file.path)));
  }

  void _addShot(Uint8List raw, double aspect) {
    final shot = _Shot(_shotSeq++, raw, aspect);
    setState(() => _shots.add(shot));
    _cropQueue = _cropQueue.then((_) => _cropOne(shot));
  }

  Future<void> _cropOne(_Shot shot) async {
    if (!mounted || shot.deleted) return;
    Uint8List? out;
    try {
      out = await autoCenterCropAsync(shot.original,
          size: widget.outputSize, previewAspect: shot.previewAspect);
    } catch (_) {}
    // Экран жабылып кетсе нәтиже жай тасталады.
    if (!mounted || shot.deleted) return;
    if (out == null) {
      setState(() => _shots.remove(shot));
      _snack(tr('Не удалось обработать снимок, снимите ещё раз',
          'Суретті өңдеу мүмкін болмады, қайта түсіріңіз'));
    } else {
      setState(() => shot.cropped = out);
    }
    _maybeFinish();
  }

  void _deleteShot(_Shot shot) {
    if (_finishRequested) return;
    shot.deleted = true;
    setState(() => _shots.remove(shot));
  }

  // ── Аяқтау ────────────────────────────────────────────────────────────────
  void _maybeFinish() {
    if (_closed || !mounted) return;
    if (_shots.isEmpty) {
      if (_finishRequested) setState(() => _finishRequested = false);
      return;
    }
    if (_capturing || _shots.any((s) => s.cropped == null)) return;
    if (_finishRequested || _shots.length >= widget.maxShots) _close();
  }

  void _onDone() {
    if (_shots.isEmpty) return;
    setState(() => _finishRequested = true);
    _maybeFinish();
  }

  void _close({ImageSource? fallback}) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(_CameraOutcome([
      for (final s in _shots)
        if (s.cropped != null)
          CapturedPhoto(cropped: s.cropped!, original: s.original),
    ], fallback: fallback));
  }

  Future<void> _onBack() async {
    if (_shots.isEmpty) {
      _closed = true;
      Navigator.of(context).pop();
      return;
    }
    final n = _shots.length;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Удалить снятые фото?', 'Түсірілген фотолар өшсін бе?'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        content: Text(
            tr('Снято: $n. Если выйти сейчас, они не сохранятся.',
                'Түсірілді: $n. Қазір шықсаңыз, олар сақталмайды.'),
            style: manrope(13.5, FontWeight.w500, color: cInk2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Остаться', 'Қалу'))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Выйти', 'Шығу'))),
        ],
      ),
    );
    if (leave != true || !mounted || _closed) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  Future<void> _toggleFlash() async {
    final c = _controller;
    if (c == null) return;
    final next = _flash == FlashMode.off ? FlashMode.always : FlashMode.off;
    try {
      await c.setFlashMode(next);
      if (mounted) setState(() => _flash = next);
    } catch (_) {
      _snack(tr(
          'На этом устройстве вспышка недоступна', 'Бұл құрылғыда жарқыл жоқ'));
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: cRed,
        behavior: SnackBarBehavior.floating,
      ));
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        canPop: _shots.isEmpty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _onBack();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: LayoutBuilder(builder: (context, box) {
            final pad = MediaQuery.paddingOf(context);
            final frame = cameraFrameRect(box.biggest,
                top: pad.top + _kTopBar, bottom: pad.bottom + _kBottomPanel);
            return Stack(clipBehavior: Clip.hardEdge, children: [
              ..._buildStage(frame),
              Positioned(
                  top: pad.top, left: 0, right: 0, child: _buildTopBar()),
              Positioned(
                  bottom: pad.bottom,
                  left: 0,
                  right: 0,
                  child: _buildBottomPanel()),
            ]);
          }),
        ),
      ),
    );
  }

  List<Widget> _buildStage(Rect frame) {
    final c = _controller;
    if (_state == _CamState.denied || _state == _CamState.unavailable) {
      return [Positioned.fromRect(rect: frame, child: _buildMessage())];
    }
    if (_state != _CamState.ready || c == null || !c.value.isInitialized) {
      return [
        Positioned.fromRect(
          rect: frame,
          child: const Center(
              child: CircularProgressIndicator(color: cGreen, strokeWidth: 2)),
        ),
      ];
    }
    final size = cameraPreviewSize(frame.width, c.value.aspectRatio);
    return [
      Positioned.fromRect(
        rect: Rect.fromCenter(
            center: frame.center, width: size.width, height: size.height),
        child: CameraPreview(c),
      ),
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(painter: _FramePainter(frame)),
        ),
      ),
      // Ысырма басылғанын көзбен де көрсетеміз (растау экраны жоқ).
      Positioned.fromRect(
        rect: frame,
        child: IgnorePointer(
          child: AnimatedOpacity(
            opacity: _blink ? 0.55 : 0,
            duration: const Duration(milliseconds: 90),
            child: const ColoredBox(color: Colors.black),
          ),
        ),
      ),
    ];
  }

  Widget _buildMessage() {
    final denied = _state == _CamState.denied;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(
            denied
                ? Icons.no_photography_outlined
                : Icons.videocam_off_outlined,
            color: Colors.white70,
            size: 40),
        const SizedBox(height: 12),
        Text(
            denied
                ? tr('Нет доступа к камере', 'Камераға рұқсат жоқ')
                : tr('Камера недоступна', 'Камера қолжетімсіз'),
            textAlign: TextAlign.center,
            style: manrope(16, FontWeight.w800, color: Colors.white)),
        const SizedBox(height: 6),
        Text(
            denied
                ? tr(
                    'Разрешите камеру для Qoima в настройках телефона или выберите фото из галереи.',
                    'Телефон баптауларында Qoima-ға камераны рұқсат етіңіз немесе фотоны галереядан таңдаңыз.')
                : tr(
                    'Выберите фото из галереи.', 'Фотоны галереядан таңдаңыз.'),
            textAlign: TextAlign.center,
            style: manrope(13, FontWeight.w500, color: Colors.white70)),
        const SizedBox(height: 16),
        QPrimaryButton(
          label: tr('Выбрать из галереи', 'Галереядан таңдау'),
          onPressed: () => _close(fallback: ImageSource.gallery),
        ),
      ]),
    );
  }

  Widget _buildTopBar() {
    final flashOn = _flash != FlashMode.off;
    return SizedBox(
      height: _kTopBar,
      child: Row(children: [
        IconButton(
          onPressed: _onBack,
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
        ),
        Expanded(
          child: Text('${_shots.length} / ${widget.maxShots}',
              textAlign: TextAlign.center,
              style: manrope(16, FontWeight.w800, color: Colors.white)),
        ),
        if (_state == _CamState.ready)
          IconButton(
            onPressed: _toggleFlash,
            tooltip: tr('Вспышка', 'Жарқыл'),
            icon: Icon(
                flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                color: flashOn ? cAmber : Colors.white,
                size: 24),
          )
        else
          const SizedBox(width: 48),
      ]),
    );
  }

  Widget _buildBottomPanel() {
    final atLimit = _shots.length >= widget.maxShots;
    final canShoot = _state == _CamState.ready && !atLimit && !_finishRequested;
    final working =
        (_finishRequested || atLimit) && _shots.any((s) => s.cropped == null);
    return SizedBox(
      height: _kBottomPanel,
      child: Column(children: [
        SizedBox(
          height: 76,
          child: Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < widget.maxShots; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: i < _shots.length
                        ? _buildThumb(_shots[i])
                        : _buildEmptySlot(),
                  ),
              ]),
            ),
          ),
        ),
        Expanded(
          child: Row(children: [
            const Expanded(child: SizedBox.shrink()),
            GestureDetector(
              onTap: canShoot ? _shoot : null,
              child: Opacity(
                opacity: canShoot ? 1 : 0.35,
                child: Container(
                  width: 72,
                  height: 72,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: ElevatedButton(
                  onPressed:
                      (_shots.isEmpty || _finishRequested) ? null : _onDone,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        Colors.white.withValues(alpha: 0.14),
                    disabledForegroundColor:
                        Colors.white.withValues(alpha: 0.5),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: working
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text(tr('Готово', 'Дайын'),
                          style: manrope(14, FontWeight.w700,
                              color: _shots.isEmpty
                                  ? Colors.white.withValues(alpha: 0.5)
                                  : Colors.white)),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildEmptySlot() => Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
      );

  Widget _buildThumb(_Shot shot) {
    return SizedBox(
      key: ValueKey(shot.id),
      width: 60,
      height: 60,
      child: Stack(fit: StackFit.expand, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          // Кесу біткенше түпнұсқа көрсетіледі: шетін cover бәрібір жасырады.
          child: Image.memory(shot.cropped ?? shot.original,
              fit: BoxFit.cover, cacheWidth: 180, gaplessPlayback: true),
        ),
        if (shot.cropped == null)
          const Center(
            child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2)),
          ),
        Positioned(
          top: 0,
          right: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _deleteShot(shot),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                    color: Colors.black87, shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 13),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Кадрдан тыс аймақты күңгірттейді: нені сақтайтынымыз бірден көрінеді.
class _FramePainter extends CustomPainter {
  final Rect frame;
  const _FramePainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRect(frame),
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );
    canvas.drawRect(
      frame,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.frame != frame;
}
