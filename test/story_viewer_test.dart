import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qoima/core/locale_context.dart';
import 'package:qoima/data/models/story_model.dart';
import 'package:qoima/data/services/stories_service.dart';
import 'package:qoima/ui/client/stories/story_viewer_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_backend.dart';

/// Желісіз сервис: дүкен бойынша дайын стористер, «көрілді» белгілері жадыда.
class _FakeStories extends StoriesService {
  _FakeStories(this.byStore);
  final Map<String, List<StoryModel>> byStore;
  final seen = <String, DateTime>{};
  final loads = <String>[];
  Object? failWith;

  @override
  Future<List<StoryModel>> storiesForStore(String storeUid) async {
    loads.add(storeUid);
    if (failWith != null) throw failWith!;
    return byStore[storeUid] ?? const [];
  }

  @override
  Future<void> markSeen(String storeUid, DateTime at) async {
    seen[storeUid] = at;
  }
}

/// Желісіз «сурет»: бірден дайын (таймер басталады).
Widget _fakeImage(BuildContext context, String url, VoidCallback onReady) {
  WidgetsBinding.instance.addPostFrameCallback((_) => onReady());
  return ColoredBox(color: Colors.grey, child: Center(child: Text(url)));
}

final _t0 = DateTime.utc(2026, 11, 2, 10);

StoryModel _story(String id,
        {String store = 's1', int hoursLeft = 20, String caption = ''}) =>
    StoryModel(
      id: id,
      storeUid: store,
      imageUrl: 'https://example.invalid/$id.jpg',
      caption: caption,
      createdAt: _t0.subtract(Duration(minutes: int.parse(id.substring(1)))),
      expiresAt: _t0.add(Duration(hours: hoursLeft)),
    );

/// Viewer-ді «бұрынғы экран» үстінен ашады (pop нәтижесін тексеру үшін).
class _Host extends StatefulWidget {
  final Widget Function() viewer;
  const _Host(this.viewer);
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  Object? result = 'не жабылды';
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          Text('result:$result', key: const ValueKey('result')),
          TextButton(
            onPressed: () async {
              final r = await Navigator.of(context).push<String>(
                  MaterialPageRoute(builder: (_) => widget.viewer()));
              setState(() => result = r ?? 'null');
            },
            child: const Text('open'),
          ),
        ]),
      );
}

Future<void> _open(WidgetTester t, Widget Function() viewer) async {
  t.view.physicalSize = const Size(400, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MaterialApp(home: _Host(viewer)));
  await t.tap(find.text('open'));
  await t.pump(); // route
  await t
      .pump(const Duration(milliseconds: 400)); // transition + post-frame open
  await t.pump(const Duration(milliseconds: 100)); // сурет қатесі → таймер
}

StoryViewerScreen _viewer(_FakeStories svc,
        {List<StoryViewerGroup>? groups,
        bool showStore = false,
        DateTime Function()? now}) =>
    StoryViewerScreen(
      groups: groups ??
          [
            const StoryViewerGroup(storeUid: 's1', storeName: 'Aru'),
          ],
      showStoreButton: showStore,
      service: svc,
      imageBuilder: _fakeImage,
      now: now ?? () => _t0,
    );

double _progress(WidgetTester t) => t
    .widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('story-progress-current')))
    .value!;

/// Қай сторис көрсетіліп тұр (жазуы бойынша).
Finder _caption(String text) => find.text(text);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await initFakeSupabase(FakeBackend());
  });

  setUp(() => LocaleContext.currentLang = 'ru');

  testWidgets('жазу, дүкен аты көрінеді; 3 сегмент; ағымдағысы толады',
      (t) async {
    final svc = _FakeStories({
      's1': [
        _story('a1', caption: 'Бірінші'),
        _story('a2', caption: 'Екінші'),
        _story('a3', caption: 'Үшінші'),
      ]
    });
    await _open(t, () => _viewer(svc));
    expect(find.text('Aru'), findsOneWidget);
    expect(_caption('Бірінші'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
    expect(_progress(t), 0.0);
    await t.pump(const Duration(milliseconds: 2500));
    expect(_progress(t), closeTo(0.5, 0.05));
    // «көрілді» белгісі көрсетілген стористің уақытына жазылды
    expect(svc.seen['s1'], svc.byStore['s1']![0].createdAt);
    await t.pump(const Duration(seconds: 3)); // аяқтап қояйық: келесіге өтеді
    await t.pump();
  });

  testWidgets('5 секундтан кейін өздігінен келесіге өтеді, соңында жабылады',
      (t) async {
    final svc = _FakeStories({
      's1': [_story('a1', caption: 'Бірінші'), _story('a2', caption: 'Екінші')]
    });
    await _open(t, () => _viewer(svc));
    expect(_caption('Бірінші'), findsOneWidget);

    await t.pump(const Duration(milliseconds: 5100));
    await t
        .pump(const Duration(milliseconds: 100)); // жаңа сурет қатесі → таймер
    expect(_caption('Екінші'), findsOneWidget);
    expect(_progress(t), closeTo(0, 0.1));

    await t.pump(const Duration(milliseconds: 5100));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('result')), findsOneWidget);
    expect(find.text('result:null'), findsOneWidget);
  });

  testWidgets('оң жарты — келесі, сол жарты — алдыңғы', (t) async {
    final svc = _FakeStories({
      's1': [
        _story('a1', caption: 'Бірінші'),
        _story('a2', caption: 'Екінші'),
        _story('a3', caption: 'Үшінші'),
      ]
    });
    await _open(t, () => _viewer(svc));

    await t.tapAt(const Offset(350, 400)); // оң жарты
    await t.pump(const Duration(milliseconds: 100));
    expect(_caption('Екінші'), findsOneWidget);

    await t.tapAt(const Offset(350, 400));
    await t.pump(const Duration(milliseconds: 100));
    expect(_caption('Үшінші'), findsOneWidget);

    await t.tapAt(const Offset(50, 400)); // сол жарты
    await t.pump(const Duration(milliseconds: 100));
    expect(_caption('Екінші'), findsOneWidget);

    await t.tapAt(const Offset(50, 400));
    await t.pump(const Duration(milliseconds: 100));
    expect(_caption('Бірінші'), findsOneWidget);

    // Ең бірінші стористе «алдыңғы» — басынан қайта, жабылмайды.
    await t.tapAt(const Offset(50, 400));
    await t.pump(const Duration(milliseconds: 100));
    expect(_caption('Бірінші'), findsOneWidget);
    expect(find.text('result:не жабылды'), findsNothing); // viewer ашық
    expect(_progress(t), closeTo(0, 0.1));
  });

  testWidgets('соңғы стористе оң жақ басу — экран жабылады', (t) async {
    final svc = _FakeStories({
      's1': [_story('a1', caption: 'Жалғыз')]
    });
    await _open(t, () => _viewer(svc));
    await t.tapAt(const Offset(350, 400));
    await t.pumpAndSettle();
    expect(find.text('result:null'), findsOneWidget);
  });

  testWidgets('басып ұстау — кідіртеді, жіберсе — жалғасады', (t) async {
    final svc = _FakeStories({
      's1': [_story('a1', caption: 'Бірінші'), _story('a2')]
    });
    await _open(t, () => _viewer(svc));
    await t.pump(const Duration(seconds: 1));
    final before = _progress(t);
    expect(before, greaterThan(0.1));

    final g = await t.startGesture(const Offset(200, 400));
    // Кадрлар майда қадаммен: ұзақ басу таймері (500 мс) кадр арасында емес.
    for (var i = 0; i < 7; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final atPause = _progress(t);
    await t.pump(const Duration(seconds: 3));
    expect(_progress(t), closeTo(atPause, 0.001)); // тұрып қалды
    expect(_caption('Бірінші'), findsOneWidget);

    await g.up();
    await t.pump(); // тикер бірінші кадрда ғана іске қосылады
    await t.pump(const Duration(seconds: 1));
    expect(_progress(t), greaterThan(atPause + 0.1));
    await t.pump(const Duration(seconds: 5));
    await t.pump();
  });

  testWidgets('төмен сырғыту — жабады; X батырмасы да жабады', (t) async {
    final svc = _FakeStories({
      's1': [_story('a1', caption: 'Бірінші')]
    });
    await _open(t, () => _viewer(svc));
    await t.fling(find.text('Бірінші'), const Offset(0, 400), 1500);
    await t.pumpAndSettle();
    expect(find.text('result:null'), findsOneWidget);

    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.byKey(const ValueKey('story-close')));
    await t.pumpAndSettle();
    expect(find.text('result:null'), findsOneWidget);
  });

  testWidgets('0 сторис: құламайды, өздігінен жабылады', (t) async {
    final svc = _FakeStories({});
    await _open(t, () => _viewer(svc));
    await t.pumpAndSettle();
    expect(find.text('result:null'), findsOneWidget);
  });

  testWidgets('топтың өзі бос тізім: жабылады', (t) async {
    final svc = _FakeStories({});
    await _open(t, () => _viewer(svc, groups: const []));
    await t.pumpAndSettle();
    expect(find.text('result:null'), findsOneWidget);
  });

  testWidgets('мерзімі өткендер өткізіледі (экран ұзақ ашық тұрғанда)',
      (t) async {
    var now = _t0;
    final svc = _FakeStories({
      's1': [
        _story('a1', caption: 'Бірінші'),
        _story('a2', caption: 'Өтіп кетті', hoursLeft: 1),
        _story('a3', caption: 'Үшінші'),
      ]
    });
    await _open(t, () => _viewer(svc, now: () => now));
    // Бірінші көрінгенде сағат 2 сағат алға жылжыды: a2 мерзімі өтті.
    now = _t0.add(const Duration(hours: 2));
    await t.tapAt(const Offset(350, 400));
    await t.pump(const Duration(milliseconds: 100));
    expect(_caption('Өтіп кетті'), findsNothing);
    expect(_caption('Үшінші'), findsOneWidget);
  });

  testWidgets('ашылғанда мерзімі өткен сторис тізімнен түседі', (t) async {
    final svc = _FakeStories({
      's1': [
        _story('a1', caption: 'Ескі', hoursLeft: -1),
        _story('a2', caption: 'Жаңа'),
      ]
    });
    await _open(t, () => _viewer(svc));
    expect(_caption('Ескі'), findsNothing);
    expect(_caption('Жаңа'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('бірнеше дүкен: біріншісі біткен соң келесі дүкен жүктеледі',
      (t) async {
    final svc = _FakeStories({
      's1': [_story('a1', caption: 'A-бірінші')],
      's2': [_story('b1', store: 's2', caption: 'B-бірінші')],
    });
    await _open(
        t,
        () => _viewer(svc, groups: const [
              StoryViewerGroup(storeUid: 's1', storeName: 'Aru'),
              StoryViewerGroup(storeUid: 's2', storeName: 'Bota'),
            ]));
    expect(find.text('Aru'), findsOneWidget);
    await t.tapAt(const Offset(350, 400));
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Bota'), findsOneWidget);
    expect(_caption('B-бірінші'), findsOneWidget);
    expect(svc.loads, ['s1', 's2']);

    // Сол жарты — алдыңғы дүкенге қайту.
    await t.tapAt(const Offset(50, 400));
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Aru'), findsOneWidget);
  });

  testWidgets('бос дүкен өткізіледі, келесісіне өтеді', (t) async {
    final svc = _FakeStories({
      's2': [_story('b1', store: 's2', caption: 'B-бірінші')],
    });
    await _open(
        t,
        () => _viewer(svc, groups: const [
              StoryViewerGroup(storeUid: 's1', storeName: 'Aru'),
              StoryViewerGroup(storeUid: 's2', storeName: 'Bota'),
            ]));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Bota'), findsOneWidget);
  });

  testWidgets('«Дүкенге өту» — дүкен uid-імен жабылады', (t) async {
    final svc = _FakeStories({
      's1': [_story('a1')]
    });
    await _open(t, () => _viewer(svc, showStore: true));
    await t.tap(find.byKey(const ValueKey('story-open-store')));
    await t.pumpAndSettle();
    expect(find.text('result:s1'), findsOneWidget);
  });

  testWidgets('дүкен бетінен ашылса «Дүкенге өту» жоқ', (t) async {
    final svc = _FakeStories({
      's1': [_story('a1')]
    });
    await _open(t, () => _viewer(svc));
    expect(find.byKey(const ValueKey('story-open-store')), findsNothing);
  });

  testWidgets(
      'жүктеу қатесі: қате мәтіні + «Повторить», қайталағанда жұмыс істейді',
      (t) async {
    final svc = _FakeStories({
      's1': [_story('a1', caption: 'Бірінші')]
    })
      ..failWith = Exception('boom');
    await _open(t, () => _viewer(svc));
    expect(find.text('Повторить'), findsOneWidget);
    svc.failWith = null;
    await t.tap(find.text('Повторить'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(_caption('Бірінші'), findsOneWidget);
  });

  group('storyAgo', () {
    test('минуттар / сағаттар / жаңа ғана', () {
      LocaleContext.currentLang = 'ru';
      expect(storyAgo(_t0, _t0), 'только что');
      expect(storyAgo(_t0.subtract(const Duration(minutes: 7)), _t0),
          '7 мин назад');
      expect(
          storyAgo(_t0.subtract(const Duration(hours: 3)), _t0), '3 ч назад');
      LocaleContext.currentLang = 'kk';
      expect(
          storyAgo(_t0.subtract(const Duration(hours: 3)), _t0), '3 сағ бұрын');
    });
  });
}
