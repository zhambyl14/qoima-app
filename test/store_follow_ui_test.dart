import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qoima/core/app_user.dart';
import 'package:qoima/core/feature_flags.dart';
import 'package:qoima/core/locale_context.dart';
import 'package:qoima/data/models/store_model.dart';
import 'package:qoima/data/services/follow_service.dart';
import 'package:qoima/l10n/app_localizations.dart';
import 'package:qoima/ui/client/follow/store_follow_button.dart';
import 'package:qoima/ui/client/store_public_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_backend.dart';

final _backend = FakeBackend();
late SupabaseClient _client;

Future<void> _flags(Map<String, bool> flags) async {
  _backend.replies['feature_flags'] = flags;
  await FeatureFlags.instance.refresh();
}

FollowService _service({String uid = 'client-1'}) =>
    FollowService(client: _client, currentUid: () => uid);

Widget _host(Widget child) => ChangeNotifierProvider<AppUser>.value(
      value: AppUser.current,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: Container(
                color: const Color(0xFF00693C),
                padding: const EdgeInsets.all(16),
                child: child),
          ),
        ),
      ),
    );

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void _signIn({String uid = 'client-1'}) => AppUser()
    .set(uid: uid, ownerUid: uid, name: 'Клиент', email: '', role: 'client');

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
    _backend.calls.clear();
    _backend.bodies.clear();
    _backend.errors.clear();
    _backend.gates.clear();
    _backend.replies
      ..clear()
      ..['my_follows'] = <Object>[]
      ..['follow_store'] = true
      ..['unfollow_store'] = false
      ..['set_follow_notify'] = true;
    _signIn();
    await _flags({FeatureFlags.storeFollow: true});
  });

  group('followersLabel', () {
    test('орыс көпше түрлері', () {
      expect(followersLabel(0), '0 подписчиков');
      expect(followersLabel(1), '1 подписчик');
      expect(followersLabel(2), '2 подписчика');
      expect(followersLabel(5), '5 подписчиков');
      expect(followersLabel(11), '11 подписчиков');
      expect(followersLabel(14), '14 подписчиков');
      expect(followersLabel(21), '21 подписчик');
      expect(followersLabel(102), '102 подписчика');
      expect(followersLabel(-3), '0 подписчиков');
    });

    test('қазақша', () {
      LocaleContext.currentLang = 'kk';
      expect(followersLabel(7), '7 жазылушы');
    });
  });

  group('StoreFollowButton', () {
    testWidgets('жалауша өшік: ештеңе көрінбейді', (t) async {
      await _flags({FeatureFlags.storeFollow: false});
      await t.pumpWidget(
          _host(StoreFollowButton(storeUid: 'store-1', service: _service())));
      await _settle(t);
      expect(find.text('Подписаться'), findsNothing);
      expect(find.byKey(const ValueKey('follow-main')), findsNothing);
    });

    testWidgets('өз дүкені: көрінбейді', (t) async {
      _signIn(uid: 'store-1');
      await t.pumpWidget(_host(StoreFollowButton(
          storeUid: 'store-1', service: _service(uid: 'store-1'))));
      await _settle(t);
      expect(find.text('Подписаться'), findsNothing);
    });

    testWidgets('жазылмаған: «Подписаться»; басса — жазылды + қоңырау',
        (t) async {
      bool? changed;
      await t.pumpWidget(_host(StoreFollowButton(
          storeUid: 'store-1',
          service: _service(),
          onChanged: (v) => changed = v)));
      await _settle(t);
      expect(find.text('Подписаться'), findsOneWidget);
      expect(find.byKey(const ValueKey('follow-bell')), findsNothing);

      await t.tap(find.byKey(const ValueKey('follow-main')));
      await _settle(t);

      expect(_backend.bodies['follow_store'], {'p_store': 'store-1'});
      expect(find.text('Вы подписаны ✓'), findsOneWidget);
      expect(find.byKey(const ValueKey('follow-bell')), findsOneWidget);
      expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
      expect(changed, isTrue);
    });

    testWidgets('оптимистік UI: жауап келгенше бірден «подписаны»', (t) async {
      final gate = Completer<void>();
      _backend.gates['follow_store'] = gate.future;
      await t.pumpWidget(
          _host(StoreFollowButton(storeUid: 'store-1', service: _service())));
      await _settle(t);

      await t.tap(find.byKey(const ValueKey('follow-main')));
      await t.pump();
      expect(find.text('Вы подписаны ✓'),
          findsOneWidget); // сервер әлі жауап бермеді

      // Қайталап басу екінші сұраныс жасамайды.
      await t.tap(find.byKey(const ValueKey('follow-main')),
          warnIfMissed: false);
      await t.pump();
      expect(_backend.count('follow_store'), 1);

      gate.complete();
      await _settle(t);
      expect(find.text('Вы подписаны ✓'), findsOneWidget);
    });

    testWidgets('қате (follow_limit): ескі күйге қайтады + түсінікті мәтін',
        (t) async {
      _backend.errors['follow_store'] = 'follow_limit';
      bool? changed;
      await t.pumpWidget(_host(Builder(
        builder: (_) => StoreFollowButton(
            storeUid: 'store-1',
            service: _service(),
            onChanged: (v) => changed = v),
      )));
      await _settle(t);
      await t.tap(find.byKey(const ValueKey('follow-main')));
      await _settle(t);

      expect(find.text('Подписаться'), findsOneWidget); // қайтты
      expect(find.byKey(const ValueKey('follow-bell')), findsNothing);
      expect(changed, isNull);
      expect(
          find.textContaining('не более чем на 200 магазинов'), findsOneWidget);
    });

    testWidgets('қоңырау: хабарламаны өшіру/қосу', (t) async {
      _backend.replies['my_follows'] = [
        {
          'store_uid': 'store-1',
          'notify': true,
          'created_at': '2026-10-31T10:00:00Z',
          'store_name': 'Aru',
        }
      ];
      await t.pumpWidget(
          _host(StoreFollowButton(storeUid: 'store-1', service: _service())));
      await _settle(t);
      expect(find.text('Вы подписаны ✓'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('follow-bell')));
      await _settle(t);
      expect(_backend.bodies['set_follow_notify'],
          {'p_store': 'store-1', 'p_notify': false});
      expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('follow-bell')));
      await _settle(t);
      expect(_backend.bodies['set_follow_notify'],
          {'p_store': 'store-1', 'p_notify': true});
      expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
    });

    testWidgets('отписка: растау диалогы, «Отмена» ештеңе өзгертпейді',
        (t) async {
      _backend.replies['my_follows'] = [
        {
          'store_uid': 'store-1',
          'notify': true,
          'created_at': '2026-10-31T10:00:00Z',
        }
      ];
      await t.pumpWidget(
          _host(StoreFollowButton(storeUid: 'store-1', service: _service())));
      await _settle(t);

      await t.tap(find.byKey(const ValueKey('follow-main')));
      await _settle(t);
      expect(find.text('Отписаться от магазина?'), findsOneWidget);
      await t.tap(find.text('Отмена'));
      await _settle(t);
      expect(_backend.count('unfollow_store'), 0);
      expect(find.text('Вы подписаны ✓'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('follow-main')));
      await _settle(t);
      await t.tap(find.text('Отписаться'));
      await _settle(t);
      expect(_backend.bodies['unfollow_store'], {'p_store': 'store-1'});
      expect(find.text('Подписаться'), findsOneWidget);
      expect(find.byKey(const ValueKey('follow-bell')), findsNothing);
    });

    testWidgets('гость басса: «Нужен вход», сұраныс жоқ', (t) async {
      AppUser().clear();
      await t.pumpWidget(_host(
          StoreFollowButton(storeUid: 'store-1', service: _service(uid: ''))));
      await _settle(t);
      expect(find.text('Подписаться'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('follow-main')));
      await _settle(t);
      expect(find.text('Нужен вход'), findsOneWidget);
      expect(_backend.count('follow_store'), 0);
      expect(_backend.count('my_follows'), 0);
    });

    testWidgets('шағын нұсқа: жазылу және шығу (растаусыз), мәтін қазақша',
        (t) async {
      LocaleContext.currentLang = 'kk';
      await t.pumpWidget(_host(StoreFollowButton(
          storeUid: 'store-1', compact: true, service: _service())));
      await _settle(t);
      expect(find.text('Жазылу'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('follow-compact')));
      await _settle(t);
      expect(find.text('Жазылдыңыз'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('follow-compact')));
      await _settle(t);
      expect(_backend.count('unfollow_store'), 1);
      expect(find.text('Жазылу'), findsOneWidget);
    });
  });

  group('StorePublicScreen', () {
    StoreModel store() => StoreModel.fromMap(const {
          'admin_uid': 'store-1',
          'store_name': 'Aru Shop',
          'is_published': true,
          'city': 'Алматы',
          'visible_warehouse_ids': ['w1'],
        });

    Future<void> openStore(WidgetTester t, {FollowService? follow}) async {
      t.view.physicalSize = const Size(600, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      _backend.replies['stores'] = {
        'admin_uid': 'store-1',
        'store_name': 'Aru Shop',
        'is_published': true,
        'visible_warehouse_ids': ['w1'],
      };
      await t.pumpWidget(ChangeNotifierProvider<AppUser>.value(
        value: AppUser.current,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: StorePublicScreen(
              store: store(), followService: follow ?? _service()),
        ),
      ));
      await _settle(t);
    }

    testWidgets('тақырыпта «Подписаться» + жазылушылар саны; басқанда +1',
        (t) async {
      _backend.replies['store_follower_count'] = 4;
      await openStore(t);
      expect(find.byKey(const ValueKey('follow-main')), findsOneWidget);
      expect(find.text('4 подписчика'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('follow-main')));
      await _settle(t);
      expect(find.text('5 подписчиков'), findsOneWidget);
      expect(find.text('Вы подписаны ✓'), findsOneWidget);
    });

    testWidgets('жалауша өшік: батырма да, сан да жоқ', (t) async {
      await _flags({FeatureFlags.storeFollow: false});
      _backend.replies['store_follower_count'] = 4;
      await openStore(t);
      expect(find.byKey(const ValueKey('follow-main')), findsNothing);
      expect(find.byKey(const ValueKey('follower-count')), findsNothing);
      expect(_backend.count('store_follower_count'), 0);
    });

    testWidgets('сторис бар: логотипте шеңбер; жоқ болса — шеңбер жоқ',
        (t) async {
      await _flags({
        FeatureFlags.storeFollow: true,
        FeatureFlags.stories: true,
      });
      final soon = DateTime.now().add(const Duration(hours: 5));
      _backend.replies['stories_for_store'] = [
        {
          'id': 'st1',
          'store_uid': 'store-1',
          'image_url': 'https://x.invalid/a.jpg',
          'caption': 'Жаңа',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'expires_at': soon.toUtc().toIso8601String(),
        }
      ];
      await openStore(t);
      expect(find.byKey(const ValueKey('store-logo-stories')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-ring-unseen')), findsOneWidget);

      // Көрілген соң (жергілікті белгі) шеңбер сұр болады.
      SharedPreferences.setMockInitialValues({
        'story_seen_store-1': DateTime.now()
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
      });
      await openStore(t);
      await t.pumpWidget(const SizedBox());
      await openStore(t);
      expect(find.byKey(const ValueKey('story-ring-seen')), findsOneWidget);
      SharedPreferences.setMockInitialValues({});

      // Сторис жоқ.
      _backend.replies['stories_for_store'] = <Object>[];
      await t.pumpWidget(const SizedBox());
      await openStore(t);
      expect(find.byKey(const ValueKey('store-logo-stories')), findsNothing);
    });

    testWidgets('stories жалауша өшік: сторис сұралмайды', (t) async {
      await _flags(
          {FeatureFlags.storeFollow: true, FeatureFlags.stories: false});
      await openStore(t);
      expect(_backend.count('stories_for_store'), 0);
      expect(find.byKey(const ValueKey('store-logo-stories')), findsNothing);
    });
  });
}
