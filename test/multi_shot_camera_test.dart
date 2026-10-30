import 'dart:async';
import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as fonts;
import 'package:image/image.dart' as img;
import 'package:qoima/core/lang.dart';
import 'package:qoima/ui/widgets/multi_shot_camera_screen.dart';

class _FontManifest implements AssetManifest {
  const _FontManifest();
  @override
  List<String> listAssets() => const [
        'fake/Inter-Regular.ttf',
        'fake/Inter-Medium.ttf',
        'fake/Inter-SemiBold.ttf',
        'fake/Inter-Bold.ttf',
        'fake/Inter-ExtraBold.ttf',
      ];
  @override
  List<AssetMetadata>? getAssetVariants(String key) => null;
}

class _FakeCamera extends CameraPlatform {
  List<CameraDescription> cameras = const [
    CameraDescription(
        name: 'back',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90),
  ];
  Object? initError;
  Completer<void>? shutterGate; // берілсе, түсіру осыны күтеді
  int takeCount = 0;
  int createCount = 0;
  int initCount = 0;
  int disposeCount = 0;
  FlashMode? lastFlash;
  DeviceOrientation? locked;
  late final Uint8List jpeg = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 320, height: 180), quality: 80));

  @override
  Future<List<CameraDescription>> availableCameras() async => cameras;

  @override
  Future<int> createCameraWithSettings(
      CameraDescription cameraDescription, MediaSettings? mediaSettings) async {
    createCount++;
    return createCount;
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(CameraInitializedEvent(
          cameraId, 1920, 1080, ExposureMode.auto, true, FocusMode.auto, true));

  @override
  // Контроллер `.first` күтеді: бос стрим StateError береді, сондықтан ашық қалады.
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      StreamController<CameraErrorEvent>.broadcast().stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      StreamController<DeviceOrientationChangedEvent>.broadcast().stream;

  @override
  Future<void> initializeCamera(int cameraId,
      {ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown}) async {
    initCount++;
    final error = initError;
    if (error != null) throw error;
  }

  @override
  Future<void> lockCaptureOrientation(
      int cameraId, DeviceOrientation orientation) async {
    locked = orientation;
  }

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {
    lastFlash = mode;
  }

  @override
  Future<XFile> takePicture(int cameraId) async {
    takeCount++;
    await shutterGate?.future;
    return XFile.fromData(jpeg, name: 'shot.jpg');
  }

  @override
  Widget buildPreview(int cameraId) => const ColoredBox(color: Colors.teal);

  @override
  Future<void> dispose(int cameraId) async {
    disposeCount++;
  }
}

/// Нағыз isolate (compute) пен файл жұмысы бітуі үшін: FakeAsync-тен шығып күтеміз.
Future<void> _settle(WidgetTester tester,
    {bool Function()? until, int maxRounds = 200}) async {
  for (var i = 0; i < maxRounds; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
    if (until != null && until()) return;
  }
  if (until != null) fail('шарт орындалмады');
}

/// Экранды helper арқылы ашады; нәтиже [result]-қа түседі.
class _Host {
  PhotoBatch? result;
  bool get done => result != null;

  Future<void> open(WidgetTester tester, {int maxShots = 4}) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              result = await MultiShotCameraScreen.captureWithOriginals(context,
                  maxShots: maxShots);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _settle(tester, maxRounds: 3);
  }
}

Finder get _shutter => find.byWidgetPredicate((w) =>
    w is GestureDetector &&
    w.child is Opacity &&
    (w.child as Opacity).child is Container &&
    ((w.child as Opacity).child as Container).constraints?.maxWidth == 72);

Finder get _done => find.widgetWithText(ElevatedButton, tr('Готово', 'Дайын'));

/// Thumb ішіндегі ✕ (кадр панеліндегі жабу батырмасы емес).
Finder get _thumbDelete => find.byWidgetPredicate(
    (w) => w is Icon && w.icon == Icons.close_rounded && w.size == 13);

void main() {
  late _FakeCamera camera;

  setUpAll(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    // Тестте желі жоқ: google_fonts қаріпті «asset-тан» табады (бос байттар).
    fonts.assetManifest = const _FontManifest();
    binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (_) async => ByteData(4));
  });

  setUp(() {
    camera = _FakeCamera();
    CameraPlatform.instance = camera;
  });

  testWidgets('кадр: превьюдің қысқа қабырғасы кадрға тең, орталықтары бірдей',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _Host().open(tester);
    final preview = tester.getRect(find.byType(CameraPreview));
    final frame = cameraFrameRect(const Size(360, 780), top: 56, bottom: 176);
    expect(preview.width, frame.width);
    expect(preview.height, closeTo(frame.width * 16 / 9, 0.01));
    expect(preview.center.dx, closeTo(frame.center.dx, 0.01));
    expect(preview.center.dy, closeTo(frame.center.dy, 0.01));
    expect(camera.locked, DeviceOrientation.portraitUp);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ысырма: түсіру кезінде қос басу еленбейді, растау сұралмайды',
      (tester) async {
    await _Host().open(tester);
    camera.shutterGate = Completer<void>();
    await tester.tap(_shutter);
    await tester.pump();
    await tester.tap(_shutter);
    await tester.pump();
    expect(camera.takeCount, 1);

    camera.shutterGate!.complete();
    await _settle(tester,
        until: () => find.text('1 / 4').evaluate().isNotEmpty);
    // Экранда қалады: келесі кадрды бірден түсіруге болады.
    camera.shutterGate = null;
    await tester.tap(_shutter);
    await _settle(tester,
        until: () => find.text('2 / 4').evaluate().isNotEmpty);
    expect(camera.takeCount, 2);
    await tester.pumpWidget(const SizedBox());
    await _settle(tester, maxRounds: 10);
  });

  testWidgets('лимитке жеткенде кесу біткен соң өзі аяқталады (1:1, 1080)',
      (tester) async {
    final host = _Host();
    await host.open(tester, maxShots: 2);
    await tester.tap(_shutter);
    await _settle(tester,
        until: () => find.text('1 / 2').evaluate().isNotEmpty);
    await tester.tap(_shutter);
    await _settle(tester, until: () => host.done);

    final photos = host.result!.photos;
    expect(photos, hasLength(2));
    for (final p in photos) {
      final d = img.decodeJpg(p.cropped)!;
      expect((d.width, d.height), (1080, 1080));
      expect(identical(p.original, p.cropped), isFalse);
      expect(p.original, camera.jpeg);
    }
  });

  testWidgets('«Готово» бір фотодан бастап қосылады және нәтиже қайтарады',
      (tester) async {
    final host = _Host();
    await host.open(tester);
    expect(tester.widget<ElevatedButton>(_done).onPressed, isNull);

    await tester.tap(_shutter);
    await _settle(tester,
        until: () => find.text('1 / 4').evaluate().isNotEmpty);
    await tester.pump();
    expect(tester.widget<ElevatedButton>(_done).onPressed, isNotNull);

    await tester.tap(_done);
    await _settle(tester, until: () => host.done);
    expect(host.result!.photos, hasLength(1));
  });

  testWidgets('✕ кадрды өшіреді', (tester) async {
    final host = _Host();
    await host.open(tester);
    await tester.tap(_shutter);
    await _settle(tester,
        until: () => find.text('1 / 4').evaluate().isNotEmpty);
    await tester.tap(_thumbDelete);
    await tester.pump();
    expect(find.text('0 / 4'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(_done).onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
    await _settle(tester, maxRounds: 10);
  });

  testWidgets('артқа: фото бар болса сұрайды, «Остаться» экранда қалдырады',
      (tester) async {
    final host = _Host();
    await host.open(tester);
    await tester.tap(_shutter);
    await _settle(tester,
        until: () => find.text('1 / 4').evaluate().isNotEmpty);

    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await _settle(tester,
        until: () => find.text(tr('Остаться', 'Қалу')).evaluate().isNotEmpty);
    expect(
        find.text(tr('Удалить снятые фото?', 'Түсірілген фотолар өшсін бе?')),
        findsOneWidget);

    await tester.tap(find.text(tr('Остаться', 'Қалу')));
    await _settle(tester,
        until: () => find.text(tr('Остаться', 'Қалу')).evaluate().isEmpty);
    expect(find.text('1 / 4'), findsOneWidget);
    expect(host.done, isFalse);

    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await _settle(tester,
        until: () => find.text(tr('Выйти', 'Шығу')).evaluate().isNotEmpty);
    await tester.tap(find.text(tr('Выйти', 'Шығу')));
    await _settle(tester, until: () => host.done);
    expect(host.result!.photos, isEmpty);
  });

  testWidgets('рұқсат жоқ: түсінікті хабар + галерея; диалог қайта ашылмайды',
      (tester) async {
    camera.initError = CameraException('CameraAccessDenied', 'no permission');
    await _Host().open(tester);
    expect(find.text(tr('Нет доступа к камере', 'Камераға рұқсат жоқ')),
        findsOneWidget);
    expect(find.text(tr('Выбрать из галереи', 'Галереядан таңдау')),
        findsOneWidget);
    expect(camera.initCount, 1);

    // Рұқсат диалогы жабылды (фонға кетпеді): қайта сұрау циклі болмауы керек.
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester, maxRounds: 3);
    expect(camera.initCount, 1);

    // Баптауларға барып келді: енді қайта сынаймыз, рұқсат берілген.
    camera.initError = null;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester,
        until: () => find.byType(CameraPreview).evaluate().isNotEmpty);
    expect(camera.initCount, 2);
    await tester.pumpWidget(const SizedBox());
    await _settle(tester, maxRounds: 5);
  });

  testWidgets('камера жоқ: image_picker-ге ауысады', (tester) async {
    final calls = <String>[];
    const channel = MethodChannel('plugins.flutter.io/image_picker');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call.method);
      return null; // иесі бас тартты
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    camera.cameras = const [];
    final host = _Host();
    await host.open(tester);
    await _settle(tester, until: () => host.done);
    expect(calls, contains('pickImage'));
    expect(host.result!.photos, isEmpty);
  });

  testWidgets('плагин қатесі де image_picker-ге ауысады', (tester) async {
    final calls = <String>[];
    const channel = MethodChannel('plugins.flutter.io/image_picker');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    camera.initError = CameraException('cameraNotFound', 'broken');
    final host = _Host();
    await host.open(tester);
    await _settle(tester, until: () => host.done);
    expect(calls, contains('pickImage'));
  });

  testWidgets(
      'lifecycle: inactive босатады, resumed қайта ашады, фото сақталады',
      (tester) async {
    await _Host().open(tester);
    await tester.tap(_shutter);
    await _settle(tester,
        until: () => find.text('1 / 4').evaluate().isNotEmpty);
    expect(camera.createCount, 1);

    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byType(CameraPreview), findsNothing);
    await _settle(tester, maxRounds: 3);
    expect(camera.disposeCount, 1);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester,
        until: () => find.byType(CameraPreview).evaluate().isNotEmpty);
    expect(camera.createCount, 2);
    expect(find.text('1 / 4'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await _settle(tester, maxRounds: 5);
  });

  testWidgets('кесу жүріп жатқанда экран жабылса қате шықпайды',
      (tester) async {
    await _Host().open(tester);
    await tester.tap(_shutter);
    // Бірден жабамыз: compute әлі жұмыс істеп жатыр.
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pumpWidget(const SizedBox());
    await _settle(tester, maxRounds: 40);
    expect(tester.takeException(), isNull);
    expect(camera.disposeCount, 1);
  });

  testWidgets('жарқыл ауысады', (tester) async {
    await _Host().open(tester);
    expect(camera.lastFlash, FlashMode.off);
    await tester.tap(find.byIcon(Icons.flash_off_rounded));
    await _settle(tester,
        until: () => find.byIcon(Icons.flash_on_rounded).evaluate().isNotEmpty);
    expect(camera.lastFlash, FlashMode.always);
    await tester.pumpWidget(const SizedBox());
    await _settle(tester, maxRounds: 3);
  });
}
