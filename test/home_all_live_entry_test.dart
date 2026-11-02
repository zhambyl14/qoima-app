import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qoima/core/app_user.dart';
import 'package:qoima/core/feature_flags.dart';
import 'package:qoima/core/locale_context.dart';
import 'package:qoima/l10n/app_localizations.dart';
import 'package:qoima/ui/client/client_home_screen.dart';
import 'package:qoima/ui/live/live_all_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_backend.dart';

final _backend = FakeBackend();

Future<void> _flags(Map<String, bool> f) async {
  _backend.replies['feature_flags'] = f;
  await FeatureFlags.instance.refresh();
}

Future<void> _openHome(WidgetTester t) async {
  t.view.physicalSize = const Size(600, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(ChangeNotifierProvider<AppUser>.value(
    value: AppUser.current,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: ClientHomeScreen()),
    ),
  ));
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await initFakeSupabase(_backend);
  });

  setUp(() {
    LocaleContext.currentLang = 'ru';
    _backend.replies.clear();
    _backend.calls.clear();
    AppUser().set(
        uid: 'client-1',
        ownerUid: 'client-1',
        name: 'Клиент',
        email: '',
        role: 'client');
  });

  testWidgets('«Все эфиры» белгісі: екі жалауша қосулы болғанда ғана',
      (t) async {
    await _flags(
        {FeatureFlags.liveShopping: true, FeatureFlags.storeFollow: true});
    _backend.replies['live_sessions_for_home'] = <Object>[];
    await _openHome(t);
    expect(find.byKey(const ValueKey('home-all-live')), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('home-all-live')));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(LiveAllScreen), findsOneWidget);
  });

  testWidgets('жазылу өшік не эфир өшік: белгі жоқ (бұрынғы мінез)', (t) async {
    await _flags(
        {FeatureFlags.liveShopping: true, FeatureFlags.storeFollow: false});
    await _openHome(t);
    expect(find.byKey(const ValueKey('home-all-live')), findsNothing);

    await _flags(
        {FeatureFlags.liveShopping: false, FeatureFlags.storeFollow: true});
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('home-all-live')), findsNothing);
  });

  testWidgets('гость басса — кіру диалогы, тізім ашылмайды', (t) async {
    AppUser().clear();
    await _flags(
        {FeatureFlags.liveShopping: true, FeatureFlags.storeFollow: true});
    await _openHome(t);
    await t.tap(find.byKey(const ValueKey('home-all-live')));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Нужен вход'), findsOneWidget);
    expect(find.byType(LiveAllScreen), findsNothing);
  });

  testWidgets('басты бет: жазылған эфир мен сторис «Рекомендуем вам» үстінде',
      (t) async {
    await _flags({
      FeatureFlags.liveShopping: true,
      FeatureFlags.storeFollow: true,
      FeatureFlags.stories: true,
    });
    _backend.replies['stores'] = [
      {
        'admin_uid': 'store-1',
        'store_name': 'Aru Shop',
        'is_published': true,
        'visible_warehouse_ids': ['w1'],
      }
    ];
    _backend.replies['live_sessions_for_home'] = [
      {
        'id': 'a',
        'admin_uid': 'store-1',
        'host_uid': 'h',
        'title': 'Жазылған эфир',
        'cover_url': '',
        'status': 'live',
        'room_name': 'r',
        'viewer_count': 1,
        'started_at': '2026-11-02T10:00:00Z',
        'store_name': 'Aru Shop',
        'store_logo_url': '',
        'followed': true,
      },
      {
        'id': 'b',
        'admin_uid': 'store-2',
        'host_uid': 'h',
        'title': 'Бөтен эфир',
        'cover_url': '',
        'status': 'live',
        'room_name': 'r2',
        'viewer_count': 50,
        'started_at': '2026-11-02T10:00:00Z',
        'store_name': 'Other',
        'store_logo_url': '',
        'followed': false,
      },
    ];
    _backend.replies['stories_for_stores'] = [
      {
        'store_uid': 'store-1',
        'store_name': 'Aru Shop',
        'logo_url': '',
        'story_count': 1,
        'latest_at': '2026-11-02T12:00:00Z',
        'oldest_at': '2026-11-02T12:00:00Z',
      }
    ];
    await _openHome(t);
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Жазылған эфир'), findsOneWidget);
    expect(find.text('Бөтен эфир'), findsNothing);
    expect(find.byKey(const ValueKey('stories-strip')), findsOneWidget);
    final live = t.getTopLeft(find.text('Эфиры ваших магазинов')).dy;
    final stories =
        t.getTopLeft(find.byKey(const ValueKey('stories-strip'))).dy;
    final reco = t
        .getTopLeft(find.text('Ұсынылады сізге').evaluate().isEmpty
            ? find.text('Рекомендуем вам')
            : find.text('Ұсынылады сізге'))
        .dy;
    expect(live, lessThan(stories));
    expect(stories, lessThan(reco));
  });
}
