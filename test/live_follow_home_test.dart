import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qoima/core/app_user.dart';
import 'package:qoima/core/feature_flags.dart';
import 'package:qoima/core/locale_context.dart';
import 'package:qoima/core/push_navigation.dart';
import 'package:qoima/data/services/follow_service.dart';
import 'package:qoima/l10n/app_localizations.dart';
import 'package:qoima/ui/client/stories/stories_strip.dart';
import 'package:qoima/ui/client/stories/story_viewer_screen.dart';
import 'package:qoima/ui/client/store_public_screen.dart';
import 'package:qoima/ui/live/live_all_screen.dart';
import 'package:qoima/ui/live/live_now_row.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_backend.dart';

final _backend = FakeBackend();
late SupabaseClient _client;

FollowService _follow() =>
    FollowService(client: _client, currentUid: () => 'client-1');

Future<void> _flags(Map<String, bool> flags) async {
  _backend.replies['feature_flags'] = flags;
  await FeatureFlags.instance.refresh();
}

Map<String, dynamic> _live(String id, String title,
        {required bool followed, int viewers = 0, String store = 'Aru'}) =>
    {
      'id': id,
      'admin_uid': 'store-$id',
      'host_uid': 'host',
      'title': title,
      'cover_url': '',
      'status': 'live',
      'room_name': 'room-$id',
      'viewer_count': viewers,
      'started_at': '2026-11-02T10:00:00Z',
      'store_name': store,
      'store_logo_url': '',
      'followed': followed,
    };

Widget _app(Widget child,
        {GlobalKey<NavigatorState>? navKey, bool scroll = true}) =>
    ChangeNotifierProvider<AppUser>.value(
      value: AppUser.current,
      child: MaterialApp(
        navigatorKey: navKey,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: scroll
            ? Scaffold(body: SingleChildScrollView(child: child))
            : child,
      ),
    );

Future<void> _settle(WidgetTester t) async {
  // LiveBadge мәңгі анимацияланады → pumpAndSettle қолдануға болмайды.
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(600, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void _signIn() => AppUser().set(
    uid: 'client-1',
    ownerUid: 'client-1',
    name: 'Клиент',
    email: '',
    role: 'client');

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await initFakeSupabase(_backend);
    _client = Supabase.instance.client;
  });

  setUp(() async {
    LocaleContext.currentLang = 'ru';
    SharedPreferences.setMockInitialValues({});
    _backend.calls.clear();
    _backend.bodies.clear();
    _backend.errors.clear();
    _backend.gates.clear();
    _backend.replies.clear();
    _signIn();
    await _flags({
      FeatureFlags.liveShopping: true,
      FeatureFlags.storeFollow: true,
    });
  });

  group('басты бет: LiveNowRow', () {
    testWidgets('жазылу қосулы: тек жазылғандар, сервер ретімен, «Все эфиры»',
        (t) async {
      _backend.replies['live_sessions_for_home'] = [
        _live('a', 'Эфир A', followed: true, viewers: 3),
        _live('b', 'Эфир B', followed: true, viewers: 9),
        _live('c', 'Эфир C', followed: false, viewers: 99),
      ];
      await t.pumpWidget(_app(LiveNowRow(follow: _follow())));
      await _settle(t);

      expect(find.text('Эфиры ваших магазинов'), findsOneWidget);
      expect(find.text('Эфир A'), findsOneWidget);
      expect(find.text('Эфир B'), findsOneWidget);
      expect(find.text('Эфир C'),
          findsNothing); // жазылмаған дүкен — басты бетте жоқ
      // Сервер реті сақталады: A алдымен.
      expect(t.getTopLeft(find.text('Эфир A')).dx,
          lessThan(t.getTopLeft(find.text('Эфир B')).dx));
      expect(find.byKey(const ValueKey('live-all-link')), findsOneWidget);
      // Ескі getLiveSessions (live_sessions кестесі) шақырылмайды.
      expect(_backend.count('live_sessions'), 0);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('жазылған жоқ: бөлім мүлде көрінбейді', (t) async {
      _backend.replies['live_sessions_for_home'] = [
        _live('c', 'Эфир C', followed: false, viewers: 99),
      ];
      await t.pumpWidget(_app(LiveNowRow(follow: _follow())));
      await _settle(t);
      expect(find.text('Эфиры ваших магазинов'), findsNothing);
      expect(find.text('Эфир C'), findsNothing);
      expect(find.byKey(const ValueKey('live-all-link')), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('«Все эфиры» → барлық эфир тізімі (жазылғандар алдымен)',
        (t) async {
      _tall(t);
      _backend.replies['live_sessions_for_home'] = [
        _live('a', 'Эфир A', followed: true),
        _live('c', 'Эфир C', followed: false),
      ];
      await t.pumpWidget(_app(LiveNowRow(follow: _follow())));
      await _settle(t);
      await t.tap(find.byKey(const ValueKey('live-all-link')));
      await _settle(t);

      expect(find.byType(LiveAllScreen), findsOneWidget);
      expect(find.text('Ваши подписки'), findsOneWidget);
      expect(find.text('Другие эфиры'), findsOneWidget);
      expect(find.text('Эфир A'), findsWidgets);
      expect(find.text('Эфир C'), findsOneWidget);
      expect(t.getTopLeft(find.text('Эфир A').last).dy,
          lessThan(t.getTopLeft(find.text('Эфир C')).dy));
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('жазылу ӨШІК: бұрынғы мінез — барлық эфир, ескі сұраныс',
        (t) async {
      await _flags({
        FeatureFlags.liveShopping: true,
        FeatureFlags.storeFollow: false,
      });
      _backend.replies['live_sessions'] = [
        {
          'id': 'x',
          'admin_uid': 'store-x',
          'host_uid': 'h',
          'title': 'Ескі эфир',
          'status': 'live',
          'room_name': 'r',
          'started_at': '2026-11-02T10:00:00Z',
        }
      ];
      _backend.replies['stores'] = [
        {'admin_uid': 'store-x', 'store_name': 'Xmag', 'is_published': true}
      ];
      await t.pumpWidget(_app(LiveNowRow(follow: _follow())));
      await _settle(t);

      expect(find.text('Сейчас в эфире'), findsOneWidget);
      expect(find.text('Ескі эфир'), findsOneWidget);
      expect(find.text('Xmag'), findsOneWidget);
      expect(find.byKey(const ValueKey('live-all-link')), findsNothing);
      expect(_backend.count('live_sessions_for_home'), 0);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('live_shopping өшік: ештеңе көрсетілмейді, сұраныс жоқ',
        (t) async {
      await _flags({
        FeatureFlags.liveShopping: false,
        FeatureFlags.storeFollow: true,
      });
      _backend.replies['live_sessions_for_home'] = [
        _live('a', 'Эфир A', followed: true),
      ];
      await t.pumpWidget(_app(LiveNowRow(follow: _follow())));
      await _settle(t);
      expect(find.text('Эфир A'), findsNothing);
      expect(_backend.count('live_sessions_for_home'), 0);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('гость: сұраныс жоқ', (t) async {
      AppUser().clear();
      _backend.replies['live_sessions_for_home'] = [
        _live('a', 'Эфир A', followed: true),
      ];
      await t.pumpWidget(_app(LiveNowRow(follow: _follow())));
      await _settle(t);
      expect(find.text('Эфир A'), findsNothing);
      expect(_backend.count('live_sessions_for_home'), 0);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('LiveAllScreen', () {
    testWidgets('барлық эфир тізімделеді, бос күй, төмен тарту жаңартады',
        (t) async {
      _tall(t);
      _backend.replies['live_sessions_for_home'] = [
        _live('a', 'Эфир A', followed: true),
        _live('b', 'Эфир B', followed: false),
        _live('c', 'Эфир C', followed: false),
      ];
      await t.pumpWidget(_app(LiveAllScreen(follow: _follow()), scroll: false));
      await _settle(t);
      expect(find.text('Эфир A'), findsOneWidget);
      expect(find.text('Эфир B'), findsOneWidget);
      expect(find.text('Эфир C'), findsOneWidget);
      expect(_backend.bodies['live_sessions_for_home'], {'p_limit': 100});
      expect(_backend.count('live_sessions_for_home'), 1);

      await t.drag(find.byType(CustomScrollView), const Offset(0, 1000));
      await _settle(t);
      await t.pump(const Duration(seconds: 1));
      expect(_backend.count('live_sessions_for_home'), 2);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('эфир жоқ: түсінікті бос күй', (t) async {
      _backend.replies['live_sessions_for_home'] = <Object>[];
      await t.pumpWidget(_app(LiveAllScreen(follow: _follow()), scroll: false));
      await _settle(t);
      expect(find.text('Сейчас нет прямых эфиров'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('қате: «Повторить» көрінеді, қайталағанда тізім шығады',
        (t) async {
      _backend.errors['live_sessions_for_home'] = 'boom';
      await t.pumpWidget(_app(LiveAllScreen(follow: _follow()), scroll: false));
      await _settle(t);
      expect(find.text('Эфир A'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      _backend.errors.clear();
      _backend.replies['live_sessions_for_home'] = [
        _live('a', 'Эфир A', followed: false),
      ];
      // Повторить батырмасы (AppErrorView).
      await t.tap(find.byType(ElevatedButton).first, warnIfMissed: false);
      await _settle(t);
      expect(find.text('Эфир A'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('аяқталған эфирді басса — «Эфир завершён» (бар көрермен)',
        (t) async {
      _tall(t);
      _backend.replies['live_sessions_for_home'] = [
        _live('a', 'Эфир A', followed: true),
      ];
      // getSession: аяқталған эфир (жалғыз объект).
      _backend.replies['live_sessions'] = {
        ..._live('a', 'Эфир A', followed: true),
        'status': 'ended',
      };
      await t.pumpWidget(_app(LiveAllScreen(follow: _follow()), scroll: false));
      await _settle(t);
      await t.tap(find.text('Эфир A'));
      await _settle(t);
      expect(find.text('Эфир завершён'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('гость: кіру нұсқауы, сұраныс жоқ', (t) async {
      AppUser().clear();
      await t.pumpWidget(_app(LiveAllScreen(follow: _follow()), scroll: false));
      await _settle(t);
      expect(find.text('Войдите, чтобы смотреть эфиры'), findsOneWidget);
      expect(_backend.count('live_sessions_for_home'), 0);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('басты бет: StoriesStrip', () {
    Map<String, dynamic> group(String uid, String name, String latest) => {
          'store_uid': uid,
          'store_name': name,
          'logo_url': '',
          'story_count': 2,
          'latest_at': latest,
          'oldest_at': '2026-11-02T08:00:00Z',
        };

    testWidgets('көрілмегені алдымен, көрілгені сұр', (t) async {
      await _flags({
        FeatureFlags.storeFollow: true,
        FeatureFlags.stories: true,
      });
      _backend.replies['stories_for_stores'] = [
        group('s-new', 'NewShop', '2026-11-02T12:00:00Z'),
        group('s-seen', 'SeenShop', '2026-11-02T11:00:00Z'),
        group('s-old', 'OldShop', '2026-11-02T09:00:00Z'),
      ];
      // SeenShop-тың ең жаңа стористі көрілген; OldShop көрілмеген.
      SharedPreferences.setMockInitialValues({
        'story_seen_s-seen':
            DateTime.utc(2026, 11, 2, 11).millisecondsSinceEpoch,
        'story_seen_s-new':
            DateTime.utc(2026, 11, 2, 12).millisecondsSinceEpoch,
      });
      await t.pumpWidget(_app(StoriesStrip(follow: _follow())));
      await _settle(t);

      expect(_backend.bodies['stories_for_stores'], {'p_stores': null});
      expect(find.text('OldShop'), findsOneWidget);
      // Сұрыптау: OldShop (көрілмеген) → NewShop (жаңасы, бірақ көрілген) → SeenShop
      final order = ['OldShop', 'NewShop', 'SeenShop']
          .map((n) => t.getTopLeft(find.text(n)).dx)
          .toList();
      expect(order[0], lessThan(order[1]));
      expect(order[1], lessThan(order[2]));
      expect(find.byKey(const ValueKey('story-ring-unseen')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-ring-seen')), findsNWidgets(2));
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('жалауша өшік / сторис жоқ / гость: ештеңе жоқ', (t) async {
      _backend.replies['stories_for_stores'] = [
        group('s1', 'Shop1', '2026-11-02T12:00:00Z'),
      ];
      // Жалауша өшік
      await _flags({FeatureFlags.stories: false});
      await t.pumpWidget(_app(StoriesStrip(follow: _follow())));
      await _settle(t);
      expect(find.text('Shop1'), findsNothing);
      expect(_backend.count('stories_for_stores'), 0);
      await t.pumpWidget(const SizedBox());

      // Жалауша қосулы, бірақ сторис жоқ
      await _flags({FeatureFlags.stories: true});
      _backend.replies['stories_for_stores'] = <Object>[];
      await t.pumpWidget(_app(StoriesStrip(follow: _follow())));
      await _settle(t);
      expect(find.byKey(const ValueKey('stories-strip')), findsNothing);
      await t.pumpWidget(const SizedBox());

      // Гость
      AppUser().clear();
      _backend.calls.clear();
      _backend.replies['stories_for_stores'] = [
        group('s1', 'Shop1', '2026-11-02T12:00:00Z'),
      ];
      await t.pumpWidget(_app(StoriesStrip(follow: _follow())));
      await _settle(t);
      expect(find.text('Shop1'), findsNothing);
      expect(_backend.count('stories_for_stores'), 0);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('басса — көрермен ашылады, «Перейти в магазин» бар', (t) async {
      await _flags({FeatureFlags.stories: true});
      _backend.replies['stories_for_stores'] = [
        group('s1', 'Shop1', '2026-11-02T12:00:00Z'),
      ];
      _backend.replies['stories_for_store'] = [
        {
          'id': 'st1',
          'store_uid': 's1',
          'image_url': 'https://x.invalid/a.jpg',
          'caption': 'Скидки!',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'expires_at': DateTime.now()
              .add(const Duration(hours: 3))
              .toUtc()
              .toIso8601String(),
        }
      ];
      await t.pumpWidget(_app(StoriesStrip(follow: _follow())));
      await _settle(t);
      await t.tap(find.byKey(const ValueKey('story-s1')));
      await _settle(t);
      await t.pump(const Duration(milliseconds: 500));

      expect(find.byType(StoryViewerScreen), findsOneWidget);
      expect(_backend.bodies['stories_for_store'], {'p_store': 's1'});
      expect(find.text('Скидки!'), findsOneWidget);
      expect(find.byKey(const ValueKey('story-open-store')), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('story-close')));
      await _settle(t);
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byType(StoryViewerScreen), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('push: handlePushOpen', () {
    testWidgets('live: эфир аяқталған → хабар + «Барлық эфирлер» тізімі',
        (t) async {
      _backend.replies['live_sessions'] = {
        ..._live('gone', 'Өтті', followed: true),
        'status': 'ended',
      };
      _backend.replies['live_sessions_for_home'] = <Object>[];
      await t.pumpWidget(_app(const SizedBox(), navKey: rootNavigatorKey));
      await _settle(t);

      final f = handlePushOpen({'type': 'live', 'sessionId': 'gone'});
      await _settle(t);
      await f;
      await _settle(t);

      expect(find.text('Эфир завершён'), findsOneWidget);
      expect(find.byType(LiveAllScreen), findsOneWidget);
      rootNavigatorKey.currentState!.popUntil((r) => r.isFirst);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('store_discount: дүкен беті ашылады', (t) async {
      _backend.replies['stores'] = {
        'admin_uid': 'store-9',
        'store_name': 'Sale Shop',
        'is_published': true,
        'visible_warehouse_ids': ['w1'],
      };
      await t.pumpWidget(_app(const SizedBox(), navKey: rootNavigatorKey));
      await _settle(t);

      final f = handlePushOpen({
        'type': 'store_discount',
        'storeUid': 'store-9',
        'adminUid': 'store-9',
        'percent': '20',
      });
      await _settle(t);
      await f;
      await _settle(t);

      expect(find.byType(StorePublicScreen), findsOneWidget);
      expect(find.text('Sale Shop'), findsWidgets);
      rootNavigatorKey.currentState!.popUntil((r) => r.isFirst);
      await t.pumpWidget(const SizedBox());
    });
  });
}
