import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qoima/core/app_user.dart';
import 'package:qoima/core/locale_context.dart';
import 'package:qoima/data/models/report_model.dart';
import 'package:qoima/data/models/story_model.dart';
import 'package:qoima/data/services/stories_service.dart';
import 'package:qoima/ui/client/report_sheet.dart';
import 'package:qoima/ui/client/stories/story_viewer_screen.dart';
import 'package:qoima/ui/superadmin/reports_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_backend.dart';

final _backend = FakeBackend();
final _t0 = DateTime.utc(2026, 11, 2, 10);

Map<String, dynamic> _row(String id, String store, String caption) => {
      'id': id,
      'store_uid': store,
      'image_url': 'https://example.invalid/$id.jpg',
      'caption': caption,
      'created_at': _t0.subtract(const Duration(minutes: 5)).toIso8601String(),
      'expires_at': _t0.add(const Duration(hours: 20)).toIso8601String(),
    };

StoryModel _story(String id, String store, String caption) =>
    StoryModel.fromMap(_row(id, store, caption));

/// Желісіз «сурет»: бірден дайын (таймер басталады).
Widget _fakeImage(BuildContext context, String url, VoidCallback onReady) {
  WidgetsBinding.instance.addPostFrameCallback((_) => onReady());
  return const ColoredBox(color: Colors.grey);
}

void _signIn(String uid, String role, {String ownerUid = ''}) => AppUser().set(
    uid: uid,
    ownerUid: ownerUid.isEmpty ? uid : ownerUid,
    name: 'Айгерім',
    email: '',
    phone: '+77010000000',
    role: role);

Widget _app(Widget home) => ChangeNotifierProvider<AppUser>.value(
      value: AppUser.current,
      child: MaterialApp(home: home),
    );

Future<void> _pumpViewer(WidgetTester t, StoryViewerScreen viewer) async {
  t.view.physicalSize = const Size(400, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(_app(viewer));
  await t.pump(); // post-frame _open
  await t.pump(const Duration(milliseconds: 50));
  await t.pump(const Duration(milliseconds: 50));
}

StoryViewerScreen _viewer({
  required String store,
  List<StoryModel>? stories,
  StoriesService? service,
  StoryReportAction? onReport,
  List<StoryViewerGroup>? groups,
}) =>
    StoryViewerScreen(
      groups: groups ??
          [
            StoryViewerGroup(
                storeUid: store,
                storeName: 'Aru Shoes',
                stories: stories ?? [_story('st1', store, 'Жаңа коллекция')]),
          ],
      service: service ?? StoriesService(hiddenStoreIds: () async => {}),
      imageBuilder: _fakeImage,
      now: () => _t0,
      onReport: onReport,
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await initFakeSupabase(_backend);
  });

  setUp(() {
    LocaleContext.currentLang = 'ru';
    SharedPreferences.setMockInitialValues({});
    _backend.calls.clear();
    _backend.bodies.clear();
    _backend.errors.clear();
    _backend.replies.clear();
    _backend.handler = null;
  });

  group('canReportStory', () {
    test('дүкен иесі өз сторисіне — жоқ', () {
      expect(
          canReportStory(
              storeUid: 's1',
              viewerUid: 's1',
              viewerOwnerUid: 's1',
              viewerRole: 'admin'),
          isFalse);
    });

    test('осы дүкеннің сатушысы — жоқ', () {
      expect(
          canReportStory(
              storeUid: 's1',
              viewerUid: 'seller-1',
              viewerOwnerUid: 's1',
              viewerRole: 'seller'),
          isFalse);
    });

    test('клиент, гость, басқа дүкен иесі/сатушысы, модератор — бар', () {
      bool can(String uid, String owner, String role) => canReportStory(
          storeUid: 's1',
          viewerUid: uid,
          viewerOwnerUid: owner,
          viewerRole: role);
      expect(can('c1', 'c1', 'client'), isTrue);
      expect(can('', '', ''), isTrue); // гость — парақ кіруді сұрайды
      expect(can('s2', 's2', 'admin'), isTrue);
      expect(can('seller-2', 's2', 'seller'), isTrue);
      expect(can('sa', 'sa', 'superadmin'), isTrue);
    });

    test('дүкен белгісіз — жоқ', () {
      expect(
          canReportStory(
              storeUid: '',
              viewerUid: 'c1',
              viewerOwnerUid: 'c1',
              viewerRole: 'client'),
          isFalse);
    });
  });

  group('reportErrorText', () {
    test('сервер кілттері қысқа мәтінге айналады', () {
      expect(
          reportErrorText(const PostgrestException(
              message: 'already_reported', code: 'P0001')),
          contains('уже отправили'));
      expect(
          reportErrorText(const PostgrestException(
              message: 'duplicate key value violates unique constraint '
                  '"content_reports_story_once"',
              code: '23505')),
          contains('уже отправили'));
      expect(
          reportErrorText(const PostgrestException(
              message: 'story_unavailable', code: 'P0001')),
          contains('недоступна'));
      expect(
          reportErrorText(const PostgrestException(
              message: 'cannot_report_own', code: 'P0001')),
          contains('свой магазин'));
      expect(reportErrorText(Exception('socket closed')), isNull);
    });

    test('қазақша мәтін де бар', () {
      LocaleContext.currentLang = 'kk';
      expect(
          reportErrorText(const PostgrestException(
              message: 'already_reported', code: 'P0001')),
          contains('бұрын жіберілген'));
    });
  });

  group('көрермендегі шағым батырмасы', () {
    testWidgets('клиентке көрінеді', (t) async {
      _signIn('client-1', 'client');
      await _pumpViewer(t, _viewer(store: 's1'));
      expect(find.text('Жаңа коллекция'), findsOneWidget);
      expect(find.byKey(const ValueKey('story-report')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('дүкен иесіне өз сторисінде — жоқ', (t) async {
      _signIn('s1', 'admin');
      await _pumpViewer(t, _viewer(store: 's1'));
      expect(find.text('Жаңа коллекция'), findsOneWidget);
      expect(find.byKey(const ValueKey('story-report')), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('осы дүкеннің сатушысына — жоқ, басқа дүкенде — бар',
        (t) async {
      _signIn('seller-1', 'seller', ownerUid: 's1');
      await _pumpViewer(t, _viewer(store: 's1'));
      expect(find.byKey(const ValueKey('story-report')), findsNothing);
      await t.pumpWidget(const SizedBox());

      await _pumpViewer(t, _viewer(store: 's2'));
      expect(find.byKey(const ValueKey('story-report')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('басса — сторис кідіреді, парақ жабылғанда жалғасады',
        (t) async {
      _signIn('client-1', 'client');
      final done = Completer<void>();
      StoryModel? reported;
      StoryViewerGroup? reportedGroup;
      await _pumpViewer(
          t,
          _viewer(
            store: 's1',
            onReport: (ctx, story, group) {
              reported = story;
              reportedGroup = group;
              return done.future;
            },
          ));
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.byKey(const ValueKey('story-report')));
      await t.pump();
      expect(reported?.id, 'st1');
      expect(reportedGroup?.storeUid, 's1');

      double progress() => t
          .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('story-progress-current')))
          .value!;
      final before = progress();
      await t.pump(const Duration(seconds: 2));
      expect(progress(), before, reason: 'парақ ашық тұрғанда таймер тоқтаулы');

      done.complete();
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await t.pump(const Duration(milliseconds: 500));
      expect(progress(), greaterThan(before));
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('нақты парақ: story түрімен content_reports-қа жазады',
        (t) async {
      _signIn('client-1', 'client');
      await _pumpViewer(t, _viewer(store: 's1'));
      await t.tap(find.byKey(const ValueKey('story-report')));
      await t.pumpAndSettle();
      expect(find.text('Пожаловаться'), findsWidgets);
      expect(find.text('Сторис · Жаңа коллекция'), findsOneWidget);

      await t.tap(find.text('Оскорбительный контент'));
      await t.pump();
      await t.tap(find.text('Отправить жалобу'));
      // pumpAndSettle емес: парақ жабылған соң сторис қайта жүреді де, 5 с
      // өткенде көрермен өзі жабылады (snackbar-мен бірге).
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }

      final body = _backend.bodies['content_reports']!;
      expect(body['target_type'], 'story');
      expect(body['target_id'], 'st1');
      expect(body['admin_uid'], 's1');
      expect(body['reason'], 'offensive');
      expect(find.textContaining('Жалоба отправлена'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('қайта шағым: түсінікті хабар, парақ жабылады', (t) async {
      _signIn('client-1', 'client');
      _backend.errors['content_reports'] = 'already_reported';
      await _pumpViewer(t, _viewer(store: 's1'));
      await t.tap(find.byKey(const ValueKey('story-report')));
      await t.pumpAndSettle();
      await t.tap(find.text('Другое'));
      await t.pump();
      await t.tap(find.text('Отправить жалобу'));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('Вы уже отправили жалобу. Мы её рассмотрим.'),
          findsOneWidget);
      expect(find.text('Отправить жалобу'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('жасырылған дүкен сүзгісі', () {
    late SupabaseClient client;
    setUp(() {
      client = SupabaseClient('http://localhost:54321', 'test-anon-key',
          httpClient: _backend,
          authOptions: const AuthClientOptions(autoRefreshToken: false));
      _backend.handler = (name, body) => name == 'stories_for_store'
          ? [_row('x-${body['p_store']}', body['p_store'] as String, 'cap')]
          : null;
    });

    test('жасырылған дүкен → бос, басқасы → тізім', () async {
      final svc =
          StoriesService(client: client, hiddenStoreIds: () async => {'s1'});
      expect(await svc.storiesForViewer('s1'), isEmpty);
      final other = await svc.storiesForViewer('s2');
      expect(other.map((s) => s.id), ['x-s2']);
    });

    test('жасыру тізімі жүктелмесе — сторис бәрібір көрінеді', () async {
      final svc = StoriesService(
          client: client,
          hiddenStoreIds: () async => throw Exception('offline'));
      expect((await svc.storiesForViewer('s1')).length, 1);
    });

    test('storiesForStore (дүкен иесінің экраны) сүзілмейді', () async {
      final svc =
          StoriesService(client: client, hiddenStoreIds: () async => {'s1'});
      expect((await svc.storiesForStore('s1')).length, 1);
    });

    testWidgets('басты беттен: жасырылған дүкен өткізіліп, келесісі ашылады',
        (t) async {
      _signIn('client-1', 'client');
      final svc =
          StoriesService(client: client, hiddenStoreIds: () async => {'s1'});
      await _pumpViewer(
          t,
          _viewer(
            store: 's1',
            service: svc,
            groups: const [
              StoryViewerGroup(storeUid: 's1', storeName: 'Hidden'),
              StoryViewerGroup(storeUid: 's2', storeName: 'Visible'),
            ],
          ));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Hidden'), findsNothing);
      expect(find.text('Visible'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('модератор: сторис шағымының карточкасы', () {
    ReportModel report(String type, {String image = ''}) =>
        ReportModel.fromMap({
          'id': 'r1',
          'reporter_uid': 'c1',
          'reporter_name': 'Айгерім',
          'target_type': type,
          'target_id': 'st1',
          'target_name': 'Жаңа коллекция',
          'target_image': image,
          'admin_uid': 's1',
          'store_name': 'Aru Shoes',
          'reason': 'offensive',
          'status': 'new',
          'created_at': '2026-11-02T10:00:00Z',
        });

    Future<List<String>> pumpCard(WidgetTester t, ReportModel r) async {
      final taps = <String>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ReportCard(
            report: r,
            onResolve: () => taps.add('resolve'),
            onDismiss: () => taps.add('dismiss'),
            onDeleteReview: () => taps.add('review'),
            onDeleteStory: () => taps.add('story'),
            onBlockStore: () => taps.add('block'),
          ),
        ),
      ));
      await t.pump();
      return taps;
    }

    test('модель: target_image + «Сторис» белгісі', () {
      final r = report('story', image: 'https://example.invalid/a.jpg');
      expect(r.isStory, isTrue);
      expect(r.targetImage, 'https://example.invalid/a.jpg');
      expect(reportTargetLabel('story'), 'Сторис');
      // Ескі жол (0086-ға дейін) — сурет жоқ.
      expect(ReportModel.fromMap({'target_type': 'product'}).targetImage, '');
    });

    testWidgets('сурет, дүкен, себеп және «Удалить сторис»', (t) async {
      final taps = await pumpCard(
          t, report('story', image: 'https://example.invalid/a.jpg'));
      expect(find.byKey(const ValueKey('report-thumb')), findsOneWidget);
      expect(find.text('Сторис · Оскорбительный контент'), findsOneWidget);
      expect(find.text('Aru Shoes'), findsOneWidget);
      expect(find.text('Блок магазина'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('report-delete-story')));
      expect(taps, ['story']);
    });

    testWidgets('тауар шағымында сурет пен «Удалить сторис» жоқ', (t) async {
      await pumpCard(t, report('product'));
      expect(find.byKey(const ValueKey('report-thumb')), findsNothing);
      expect(find.byKey(const ValueKey('report-delete-story')), findsNothing);
    });
  });
}
