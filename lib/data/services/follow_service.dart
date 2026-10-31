import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/live_models.dart';

DateTime? _dt(dynamic v) {
  if (v is DateTime) return v;
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
  return null;
}

/// Менің жазылуым (`my_follows()` жолы).
class FollowedStore {
  final String storeUid; // stores.admin_uid
  final bool notify; // false = жазылған, бірақ push алмайды
  final DateTime createdAt;
  final String storeName;
  final String logoUrl;
  final String city;

  /// false — дүкен қазір жабық/блокта: UI сұр көрсетіп, «шығу»-ды қалдырады.
  final bool available;

  const FollowedStore({
    required this.storeUid,
    this.notify = true,
    required this.createdAt,
    this.storeName = '',
    this.logoUrl = '',
    this.city = '',
    this.available = true,
  });

  FollowedStore copyWith({bool? notify}) => FollowedStore(
        storeUid: storeUid,
        notify: notify ?? this.notify,
        createdAt: createdAt,
        storeName: storeName,
        logoUrl: logoUrl,
        city: city,
        available: available,
      );

  factory FollowedStore.fromMap(Map<String, dynamic> m) => FollowedStore(
        storeUid: m['store_uid'] as String? ?? '',
        notify: m['notify'] as bool? ?? true,
        createdAt: _dt(m['created_at']) ?? DateTime.now(),
        storeName: m['store_name'] as String? ?? '',
        logoUrl: m['logo_url'] as String? ?? '',
        city: m['city'] as String? ?? '',
        available: m['available'] as bool? ?? true,
      );
}

/// Басты бет үшін тірі эфир (`live_sessions_for_home` жолы): эфирдің өзі +
/// дүкен аты/логотипі + клиент жазылған ба.
class HomeLiveSession {
  final LiveSession session;
  final String storeName;
  final String storeLogoUrl;
  final bool followed;

  const HomeLiveSession({
    required this.session,
    this.storeName = '',
    this.storeLogoUrl = '',
    this.followed = false,
  });

  factory HomeLiveSession.fromMap(Map<String, dynamic> m) => HomeLiveSession(
        session: LiveSession.fromMap(m),
        storeName: m['store_name'] as String? ?? '',
        storeLogoUrl: m['store_logo_url'] as String? ?? '',
        followed: m['followed'] as bool? ?? false,
      );
}

/// Дүкенге жазылу (0084). Бір данасы бүкіл қосымшаға — жүрекше/«Подписаться»
/// батырмалары мен басты бет `ListenableBuilder(listenable:
/// FollowService.instance, ...)` арқылы бірге жаңарады.
///
/// Жазу тек RPC арқылы (follow_store / unfollow_store / set_follow_notify) —
/// кестеге тікелей insert/update құқығы жоқ. Жалауша: FeatureFlags.storeFollow
/// (сервер де тексереді; unfollow мен хабарды ӨШІРУ жалаушасыз да жұмыс істейді).
class FollowService extends ChangeNotifier {
  /// [client] / [currentUid] — тек тест үшін (әдепкі: Supabase.instance).
  FollowService({SupabaseClient? client, String Function()? currentUid})
      : _client = client,
        _currentUid = currentUid;

  static final FollowService instance = FollowService();

  final SupabaseClient? _client;
  final String Function()? _currentUid;
  SupabaseClient get _sb => _client ?? Supabase.instance.client;

  /// Сервердегі шекпен бірдей (follow_store → follow_limit).
  static const maxFollows = 200;

  // Кэш кімдікі: аккаунт ауысса ескі тізім жаңа қолданушыға көрінбесін.
  String _cacheUid = '';
  Map<String, FollowedStore> _follows = const {};
  Future<void>? _loading;

  String get _uid => _currentUid?.call() ?? _sb.auth.currentUser?.id ?? '';

  bool get _cacheValid => _cacheUid.isNotEmpty && _cacheUid == _uid;

  /// Тізім ағымдағы аккаунт үшін жүктелді ме.
  bool get isLoaded => _cacheValid;

  /// Жаңасы алдымен (сервер реті).
  List<FollowedStore> get follows =>
      _cacheValid ? _follows.values.toList(growable: false) : const [];

  Set<String> get followedUids =>
      _cacheValid ? _follows.keys.toSet() : const <String>{};

  bool isFollowing(String storeUid) =>
      _cacheValid && _follows.containsKey(storeUid);

  /// Жазылмаған дүкенге — false.
  bool notifyEnabled(String storeUid) =>
      _cacheValid && (_follows[storeUid]?.notify ?? false);

  /// Менің жазылуларым. Гостьқа — бос (RPC шақырылмайды). Қатар шақырулар
  /// бір сұранысқа біріктіріледі. [force] = false болса және кэш ағымдағы
  /// аккаунттікі болса — желіге бармайды.
  Future<void> loadMyFollows({bool force = false}) {
    final uid = _uid;
    if (uid.isEmpty) {
      clear();
      return Future.value();
    }
    if (!force && _cacheUid == uid) return Future.value();
    return _loading ??= _load(uid).whenComplete(() => _loading = null);
  }

  Future<void> _load(String uid) async {
    final rows = await _sb.rpc('my_follows');
    final map = <String, FollowedStore>{};
    if (rows is List) {
      for (final r in rows) {
        if (r is! Map) continue;
        final f = FollowedStore.fromMap(Map<String, dynamic>.from(r));
        if (f.storeUid.isNotEmpty) map[f.storeUid] = f;
      }
    }
    // Жүктеу кезінде аккаунт ауысса — нәтижені тастаймыз.
    if (_uid != uid) return;
    _cacheUid = uid;
    _follows = map;
    notifyListeners();
  }

  /// Жазылу (қайталап шақыру қауіпсіз). Қателер: feature_disabled,
  /// store_unavailable, cannot_follow_own_store, follow_limit, user_blocked,
  /// not_authorized (гость) — friendlyError аударады.
  Future<void> follow(String storeUid) async {
    if (storeUid.isEmpty) return;
    await _sb.rpc('follow_store', params: {'p_store': storeUid});
    if (!_cacheValid) {
      // Тізім әлі жүктелмеген — толық жүктейміз (дүкен аты да керек).
      await loadMyFollows(force: true);
    }
    // Жүктеу бұрыннан жүріп жатса, жаңа жазылу оның нәтижесінде болмауы
    // мүмкін — сондықтан тексеріп, жоқ болса өзіміз қосамыз.
    if (!_cacheValid || _follows.containsKey(storeUid)) return;
    _follows = {
      storeUid: FollowedStore(storeUid: storeUid, createdAt: DateTime.now()),
      ..._follows,
    };
    notifyListeners();
  }

  /// Жазылудан шығу (жалауша өшік болса да жұмыс істейді).
  Future<void> unfollow(String storeUid) async {
    if (storeUid.isEmpty) return;
    await _sb.rpc('unfollow_store', params: {'p_store': storeUid});
    if (_cacheValid && _follows.containsKey(storeUid)) {
      _follows = Map.of(_follows)..remove(storeUid);
      notifyListeners();
    }
  }

  /// Push-ты қосу/өшіру. Жазылмаған дүкенге → not_following қатесі;
  /// қосу жалауша өшік болса → feature_disabled.
  Future<void> setNotify(String storeUid, bool notify) async {
    if (storeUid.isEmpty) return;
    await _sb.rpc('set_follow_notify',
        params: {'p_store': storeUid, 'p_notify': notify});
    final cur = _cacheValid ? _follows[storeUid] : null;
    if (cur != null && cur.notify != notify) {
      _follows = {..._follows, storeUid: cur.copyWith(notify: notify)};
      notifyListeners();
    }
  }

  /// Дүкеннің жазылушылар саны (гостьқа да; жабық дүкенге — 0).
  Future<int> followerCount(String storeUid) async {
    if (storeUid.isEmpty) return 0;
    final res =
        await _sb.rpc('store_follower_count', params: {'p_store': storeUid});
    return (res as num?)?.toInt() ?? 0;
  }

  /// Басты бет: қазір тірі эфирлер, жазылған дүкендер БІРІНШІ, сосын көрермені
  /// көп / жаңасы. Гостьқа сервер бос тізім қайтарады (live_sessions_read
  /// саясатымен бірдей). Realtime емес — UI 30 с сайын қайта сұрайды.
  Future<List<HomeLiveSession>> liveSessionsForHome({int limit = 30}) async {
    final rows =
        await _sb.rpc('live_sessions_for_home', params: {'p_limit': limit});
    if (rows is! List) return const [];
    return [
      for (final r in rows)
        if (r is Map) HomeLiveSession.fromMap(Map<String, dynamic>.from(r)),
    ];
  }

  /// Шыққанда (logout) шақырылады; аккаунт ауысса кэш өздігінен де жарамсыз.
  void clear() {
    if (_cacheUid.isEmpty && _follows.isEmpty) return;
    _cacheUid = '';
    _follows = const {};
    notifyListeners();
  }
}
