import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:qoima/core/error_text.dart';
import 'package:qoima/core/feature_flags.dart';
import 'package:qoima/core/locale_context.dart';
import 'package:qoima/data/models/story_model.dart';
import 'package:qoima/data/services/cloudinary_service.dart';
import 'package:qoima/data/services/follow_service.dart';
import 'package:qoima/data/services/stories_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Желісіз PostgREST: тек 0084 RPC-лерін біледі.
class _Backend extends http.BaseClient {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  final replies = <String, Object?>{};
  final errors = <String, String>{};

  http.BaseRequest? _current;

  http.StreamedResponse _json(Object? body, [int status = 200]) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        request: _current,
        headers: {'content-type': 'application/json'},
      );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _current = request;
    final name = request.url.pathSegments.last;
    calls.add(name);
    // Параметрсіз RPC (my_follows) денесі `null` болып келеді.
    final raw = request is http.Request && request.body.isNotEmpty
        ? jsonDecode(request.body)
        : null;
    final body =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    bodies[name] = body;
    final err = errors[name];
    if (err != null) {
      // plpgsql `raise exception '…'` → PostgREST 400, code P0001.
      return _json(
          {'code': 'P0001', 'message': err, 'details': null, 'hint': null},
          400);
    }
    return _json(replies[name]);
  }
}

class _FakeCloud extends CloudinaryService {
  final uploaded = <String>[];
  final deleted = <String>[];

  @override
  Future<String> uploadStory(Uint8List bytes) async {
    const url =
        'https://res.cloudinary.com/divynstru/image/upload/v1/qoima_stories/story_1.jpg';
    uploaded.add(url);
    return url;
  }

  @override
  Future<void> deleteByUrl(String url) async => deleted.add(url);
}

Map<String, dynamic> _storyRow({
  String id = 's1',
  String created = '2026-10-31T10:00:00+00:00',
  String expires = '2026-11-01T10:00:00+00:00',
}) =>
    {
      'id': id,
      'store_uid': 'store-1',
      'image_url':
          'https://res.cloudinary.com/divynstru/image/upload/v1/qoima_stories/a.jpg',
      'caption': 'Жаңа коллекция',
      'created_by': 'owner-1',
      'created_at': created,
      'expires_at': expires,
    };

void main() {
  late _Backend backend;
  late SupabaseClient client;

  setUp(() {
    LocaleContext.currentLang = 'ru';
    SharedPreferences.setMockInitialValues({});
    backend = _Backend();
    client = SupabaseClient('http://localhost:54321', 'test-anon-key',
        httpClient: backend,
        authOptions: const AuthClientOptions(autoRefreshToken: false));
  });

  group('модельдер', () {
    test('StoryModel.fromMap толық жол', () {
      final s = StoryModel.fromMap(_storyRow());
      expect(s.id, 's1');
      expect(s.storeUid, 'store-1');
      expect(s.caption, 'Жаңа коллекция');
      expect(s.createdBy, 'owner-1');
      expect(s.expiresAt.difference(s.createdAt), const Duration(hours: 24));
      expect(s.isExpiredAt(DateTime.utc(2026, 11, 1, 9)), isFalse);
      expect(s.isExpiredAt(DateTime.utc(2026, 11, 1, 10)), isTrue);
    });

    test('StoryModel null өрістерге төзімді', () {
      final s = StoryModel.fromMap({
        'id': 'x',
        'store_uid': 'st',
        'image_url': 'u',
        'caption': null,
        'created_by': null,
        'created_at': '2026-10-31T10:00:00Z',
        'expires_at': null,
      });
      expect(s.caption, '');
      expect(s.createdBy, '');
      expect(s.expiresAt, s.createdAt.add(StoryModel.lifetime));
    });

    test('StoryStoreGroup.fromMap + hasUnseen', () {
      final g = StoryStoreGroup.fromMap({
        'store_uid': 'store-1',
        'store_name': 'Aru Shoes',
        'logo_url': '',
        'story_count': 3,
        'latest_at': '2026-10-31T12:00:00Z',
        'oldest_at': '2026-10-31T08:00:00Z',
      });
      expect(g.storyCount, 3);
      expect(g.storeName, 'Aru Shoes');
      expect(g.oldestAt.isBefore(g.latestAt), isTrue);
      expect(g.hasUnseen(null), isTrue);
      expect(g.hasUnseen(g.latestAt), isFalse);
      expect(
          g.hasUnseen(g.latestAt.subtract(const Duration(minutes: 1))), isTrue);
    });

    test('FollowedStore.fromMap', () {
      final f = FollowedStore.fromMap({
        'store_uid': 'store-1',
        'notify': false,
        'created_at': '2026-10-30T10:00:00Z',
        'store_name': 'Aru',
        'logo_url': 'l',
        'city': 'Тараз',
        'available': false,
      });
      expect(f.notify, isFalse);
      expect(f.available, isFalse);
      expect(f.city, 'Тараз');
      expect(f.copyWith(notify: true).notify, isTrue);
    });

    test('HomeLiveSession.fromMap эфир өрістерін LiveSession-ға береді', () {
      final h = HomeLiveSession.fromMap({
        'id': 'ls1',
        'admin_uid': 'store-1',
        'host_uid': 'seller-1',
        'title': 'Жаңа кроссовкалар',
        'cover_url': null,
        'status': 'live',
        'room_name': 'room',
        'current_product_id': null,
        'viewer_count': 12,
        'peak_viewers': 20,
        'like_count': 5,
        'heartbeat_at': '2026-10-31T10:01:00Z',
        'started_at': '2026-10-31T10:00:00Z',
        'ended_at': null,
        'store_name': 'Aru',
        'store_logo_url': 'logo',
        'followed': true,
      });
      expect(h.session.id, 'ls1');
      expect(h.session.isLive, isTrue);
      expect(h.session.viewerCount, 12);
      expect(h.storeName, 'Aru');
      expect(h.followed, isTrue);
    });
  });

  group('FollowService', () {
    test('гость: RPC шақырылмайды, тізім бос', () async {
      final svc = FollowService(client: client, currentUid: () => '');
      await svc.loadMyFollows();
      expect(svc.isLoaded, isFalse);
      expect(svc.follows, isEmpty);
      expect(backend.calls, isEmpty);
    });

    test('жүктеу, қатар шақыру біріктіріледі, кэш аккаунтқа байланған',
        () async {
      var uid = 'client-1';
      backend.replies['my_follows'] = [
        {
          'store_uid': 'store-1',
          'notify': true,
          'created_at': '2026-10-31T10:00:00Z',
          'store_name': 'Aru',
          'logo_url': '',
          'city': 'Тараз',
          'available': true,
        },
      ];
      final svc = FollowService(client: client, currentUid: () => uid);
      var notified = 0;
      svc.addListener(() => notified++);
      await Future.wait([svc.loadMyFollows(), svc.loadMyFollows()]);
      expect(backend.calls.where((c) => c == 'my_follows').length, 1);
      expect(svc.isFollowing('store-1'), isTrue);
      expect(svc.notifyEnabled('store-1'), isTrue);
      expect(notified, 1);

      // Кэш бар — қайта сұрамайды.
      await svc.loadMyFollows();
      expect(backend.calls.where((c) => c == 'my_follows').length, 1);

      // Басқа аккаунт — ескі тізім көрінбейді.
      uid = 'client-2';
      expect(svc.isFollowing('store-1'), isFalse);
      expect(svc.follows, isEmpty);
    });

    test('follow / setNotify / unfollow кэшті жаңартады', () async {
      backend.replies['my_follows'] = <Object>[];
      backend.replies['follow_store'] = true;
      backend.replies['set_follow_notify'] = false;
      backend.replies['unfollow_store'] = false;
      final svc = FollowService(client: client, currentUid: () => 'client-1');
      await svc.loadMyFollows();

      await svc.follow('store-9');
      expect(backend.bodies['follow_store'], {'p_store': 'store-9'});
      expect(svc.isFollowing('store-9'), isTrue);
      expect(svc.notifyEnabled('store-9'), isTrue);

      await svc.setNotify('store-9', false);
      expect(backend.bodies['set_follow_notify'],
          {'p_store': 'store-9', 'p_notify': false});
      expect(svc.notifyEnabled('store-9'), isFalse);

      await svc.unfollow('store-9');
      expect(svc.isFollowing('store-9'), isFalse);
    });

    test('follow жүктелмеген кэшпен — толық тізімді әкеледі', () async {
      backend.replies['follow_store'] = true;
      backend.replies['my_follows'] = [
        {
          'store_uid': 'store-5',
          'notify': true,
          'created_at': '2026-10-31T10:00:00Z',
          'store_name': 'Five',
          'logo_url': '',
          'city': '',
          'available': true
        },
      ];
      final svc = FollowService(client: client, currentUid: () => 'client-1');
      await svc.follow('store-5');
      expect(backend.calls, ['follow_store', 'my_follows']);
      expect(svc.follows.single.storeName, 'Five');
    });

    test('сервер қатесі лақтырылады, кэш өзгермейді, мәтін аударылады',
        () async {
      backend.replies['my_follows'] = <Object>[];
      backend.errors['follow_store'] = 'follow_limit';
      final svc = FollowService(client: client, currentUid: () => 'client-1');
      await svc.loadMyFollows();
      Object? err;
      try {
        await svc.follow('store-1');
      } catch (e) {
        err = e;
      }
      expect(err, isA<PostgrestException>());
      expect(svc.isFollowing('store-1'), isFalse);
      expect(friendlyError(err), contains('200'));
    });

    test('followerCount және liveSessionsForHome', () async {
      backend.replies['store_follower_count'] = 42;
      backend.replies['live_sessions_for_home'] = [
        {
          'id': 'a',
          'admin_uid': 's1',
          'status': 'live',
          'started_at': '2026-10-31T10:00:00Z',
          'store_name': 'S1',
          'store_logo_url': '',
          'followed': true
        },
        {
          'id': 'b',
          'admin_uid': 's2',
          'status': 'live',
          'started_at': '2026-10-31T10:00:00Z',
          'store_name': 'S2',
          'store_logo_url': '',
          'followed': false
        },
      ];
      final svc = FollowService(client: client, currentUid: () => 'client-1');
      expect(await svc.followerCount('s1'), 42);
      final live = await svc.liveSessionsForHome(limit: 10);
      expect(backend.bodies['live_sessions_for_home'], {'p_limit': 10});
      expect(live.map((e) => e.session.id), ['a', 'b']);
      expect(live.first.followed, isTrue);
    });
  });

  group('StoriesService', () {
    test('create: жүктейді, RPC-ге URL мен кесілген жазуды береді', () async {
      final cloud = _FakeCloud();
      backend.replies['story_create'] = _storyRow();
      final svc = StoriesService(client: client, cloudinary: cloud);
      final s = await svc.create(
          imageBytes: Uint8List.fromList([1, 2, 3]), caption: '  Жаңа  ');
      expect(s.id, 's1');
      expect(backend.bodies['story_create'],
          {'p_image_url': cloud.uploaded.single, 'p_caption': 'Жаңа'});
      expect(cloud.deleted, isEmpty);
    });

    test('create: сервер бас тартса сурет өшіріледі', () async {
      final cloud = _FakeCloud();
      backend.errors['story_create'] = 'stories_limit';
      final svc = StoriesService(client: client, cloudinary: cloud);
      Object? err;
      try {
        await svc.create(imageBytes: Uint8List.fromList([1]));
      } catch (e) {
        err = e;
      }
      expect(err, isA<PostgrestException>());
      expect(cloud.deleted, cloud.uploaded);
      expect(friendlyError(err), contains('10'));
    });

    test('create: ұзын жазу жүктеуге дейін тоқтайды', () async {
      final cloud = _FakeCloud();
      final svc = StoriesService(client: client, cloudinary: cloud);
      Object? err;
      try {
        await svc.create(
            imageBytes: Uint8List.fromList([1]), caption: 'а' * 201);
      } catch (e) {
        err = e;
      }
      expect(err, isNotNull);
      expect(cloud.uploaded, isEmpty);
      expect(backend.calls, isEmpty);
      expect(friendlyError(err), contains('200'));
    });

    test('оқу RPC-лері және параметрлері', () async {
      backend.replies['stories_for_store'] = [
        _storyRow(id: 'old', created: '2026-10-31T08:00:00Z'),
        _storyRow(id: 'new', created: '2026-10-31T09:00:00Z'),
      ];
      backend.replies['stories_for_stores'] = [
        {
          'store_uid': 'store-1',
          'store_name': 'Aru',
          'logo_url': '',
          'story_count': 2,
          'latest_at': '2026-10-31T09:00:00Z',
          'oldest_at': '2026-10-31T08:00:00Z'
        },
      ];
      final svc = StoriesService(client: client, cloudinary: _FakeCloud());
      final list = await svc.storiesForStore('store-1');
      expect(list.map((e) => e.id), ['old', 'new']);
      expect(backend.bodies['stories_for_store'], {'p_store': 'store-1'});

      final strip = await svc.storiesForFollowed();
      expect(backend.bodies['stories_for_stores'], {'p_stores': null});
      expect(strip.single.storyCount, 2);

      await svc.storiesForStores(['a', 'a', '', 'b']);
      expect(backend.bodies['stories_for_stores'], {
        'p_stores': ['a', 'b']
      });

      backend.calls.clear();
      expect(await svc.storiesForStores(const []), isEmpty);
      expect(backend.calls, isEmpty);
    });

    test('delete RPC', () async {
      backend.replies['story_delete'] = null;
      final svc = StoriesService(client: client, cloudinary: _FakeCloud());
      await svc.delete('s1');
      expect(backend.bodies['story_delete'], {'p_id': 's1'});
    });

    test('«көрілді» белгісі тек алға жылжиды', () async {
      final svc = StoriesService(client: client, cloudinary: _FakeCloud());
      expect(await svc.seenUntil('store-1'), isNull);
      final t1 = DateTime.utc(2026, 10, 31, 10);
      await svc.markSeen('store-1', t1);
      await svc.markSeen('store-1', t1.subtract(const Duration(hours: 1)));
      expect((await svc.seenUntil('store-1'))!.isAtSameMomentAs(t1), isTrue);
      final many = await svc.seenUntilMany(['store-1', 'store-2']);
      expect(many.keys, ['store-1']);
    });
  });

  group('қате мәтіндері мен жалаушалар', () {
    String msg(String code) =>
        friendlyError(PostgrestException(message: code, code: 'P0001'));

    test('0084 кодтары аударылады (жалпы «сервер қатесі» емес)', () {
      const generic = 'Ошибка сервера. Попробуйте позже.';
      for (final c in [
        'follow_limit',
        'cannot_follow_own_store',
        'not_following',
        'stories_limit',
        'invalid_image_url',
        'invalid_caption',
        'store_unavailable',
        'user_blocked',
        'subscription_frozen',
        'not_authorized',
        'feature_disabled',
      ]) {
        expect(msg(c), isNot(generic), reason: c);
      }
      LocaleContext.currentLang = 'kk';
      expect(msg('follow_limit'), contains('200 дүкенге'));
    });

    test('жалаушалар тізімде', () {
      expect(FeatureFlags.all, contains(FeatureFlags.storeFollow));
      expect(FeatureFlags.all, contains(FeatureFlags.stories));
      expect(FeatureFlags.storeFollow, 'store_follow');
      expect(FeatureFlags.stories, 'stories');
    });
  });
}
