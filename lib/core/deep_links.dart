import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../ui/client/gift/gift_receive_screen.dart';
import '../ui/client/registry/registry_public_screen.dart';
import '../ui/live/live_navigation.dart';
import 'app_user.dart';
import 'push_navigation.dart' show rootNavigatorKey;
import 'supabase_config.dart';

/// Сілтеме түрлері: сыйлық / тілек тізімі / тікелей эфир.
enum DeepLinkKind { gift, registry, live }

class DeepLink {
  final DeepLinkKind kind;

  /// Gift/registry — токен (uuid), live — эфир сессиясының id-і (uuid).
  final String id;
  const DeepLink(this.kind, this.id);

  String get key => '${kind.name}:$id';
}

final RegExp _uuidRe = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

/// Қолданбаның терең сілтемелері.
///
/// Қолдау көрсетілетін пішімдер:
///   • `qoima://gift/<token>`, `qoima://registry/<token>`, `qoima://live/<id>`
///     (Deno-бет «Qoima-да ашу» батырмасы осыны береді);
///   • `https://<shareBaseUrl хосты>/?g=<token>` (сыйлық),
///     `https://<хост>/?w=<token>` (тілек тізімі) — қолданбаға жолығатын сілтеме.
///
/// Қонаққа да жұмыс істейді: AppUser.isLoaded КҮТІЛМЕЙДІ — сыйлық пен тізімді
/// кірмеген адам да көреді, кіру тек әрекет (алу/брондау) кезінде сұралады.
class DeepLinks {
  DeepLinks._();
  static final DeepLinks instance = DeepLinks._();

  bool _started = false;
  StreamSubscription<Uri>? _sub;

  // Бір сілтеме бастапқы link-те де, stream-де де қайталануы мүмкін.
  String? _lastKey;
  DateTime? _lastAt;

  // Гость сыйлықты алу үшін кіргенде LoginScreen бүкіл стекті тазалайды
  // (popUntil first) — сондықтан токенді есте сақтап, кіргеннен кейін қайта ашамыз.
  DeepLink? _pending;
  DateTime? _pendingAt;

  // Ашық тұрған сыйлық беттері (қайталап ашпау үшін).
  final Set<String> _openGifts = {};
  void giftScreenOpened(String token) => _openGifts.add(token.toLowerCase());
  void giftScreenClosed(String token) => _openGifts.remove(token.toLowerCase());
  static const _pendingTtl = Duration(minutes: 15);

  /// main.dart-тан бір рет шақырылады (Navigator дайын болған соң).
  Future<void> init() async {
    if (_started) return;
    _started = true;
    final links = AppLinks();
    try {
      final initial = await links.getInitialLink();
      if (initial != null) unawaited(handleUri(initial));
    } catch (e) {
      debugPrint('deep_links: initial link failed: $e');
    }
    _sub = links.uriLinkStream.listen(
      (uri) => unawaited(handleUri(uri)),
      onError: (Object e) => debugPrint('deep_links: stream error: $e'),
    );
    // Кіру аяқталғанда кідіртілген сыйлықты ашу.
    await _waitNavigator();
    AppUser.current.addListener(_onUserChanged);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
  }

  // ── Парсинг ────────────────────────────────────────────────────────────────

  /// Uri → [DeepLink] (танылмаса / токен uuid емес болса — null).
  static DeepLink? parse(Uri uri) {
    String? clean(String? v) {
      final t = v?.trim() ?? '';
      return _uuidRe.hasMatch(t) ? t.toLowerCase() : null;
    }

    if (uri.scheme == SupabaseConfig.appScheme) {
      // qoima://gift/<token> → host=gift, path=/<token>
      final kind = switch (uri.host) {
        'gift' => DeepLinkKind.gift,
        'registry' => DeepLinkKind.registry,
        'live' => DeepLinkKind.live,
        _ => null,
      };
      if (kind == null) return null;
      final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      final id = clean(seg.isNotEmpty ? seg.first : uri.queryParameters['t']);
      return id == null ? null : DeepLink(kind, id);
    }

    if (uri.scheme == 'https' || uri.scheme == 'http') {
      final base = Uri.tryParse(SupabaseConfig.shareBaseUrl);
      if (base == null || base.host.isEmpty || uri.host != base.host) {
        return null;
      }
      final g = clean(uri.queryParameters['g']);
      if (g != null) return DeepLink(DeepLinkKind.gift, g);
      final w = clean(uri.queryParameters['w']);
      if (w != null) return DeepLink(DeepLinkKind.registry, w);
    }
    return null;
  }

  // ── Өңдеу ──────────────────────────────────────────────────────────────────

  Future<void> handleUri(Uri uri) async {
    final link = parse(uri);
    if (link == null) return;
    final now = DateTime.now();
    if (_lastKey == link.key &&
        _lastAt != null &&
        now.difference(_lastAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastKey = link.key;
    _lastAt = now;
    await open(link);
  }

  Future<NavigatorState?> _waitNavigator() async {
    NavigatorState? nav = rootNavigatorKey.currentState;
    for (var i = 0; nav == null && i < 50; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      nav = rootNavigatorKey.currentState;
    }
    return nav;
  }

  Future<void> open(DeepLink link) async {
    final nav = await _waitNavigator();
    if (nav == null) return;
    try {
      switch (link.kind) {
        case DeepLinkKind.gift:
          if (_openGifts.contains(link.id)) return;
          await nav.push(MaterialPageRoute(
            settings: RouteSettings(name: 'deeplink/gift/${link.id}'),
            builder: (_) => GiftReceiveScreen(token: link.id),
          ));
        case DeepLinkKind.registry:
          await nav.push(MaterialPageRoute(
            settings: RouteSettings(name: 'deeplink/registry/${link.id}'),
            builder: (_) => RegistryPublicScreen(token: link.id),
          ));
        case DeepLinkKind.live:
          // ignore: use_build_context_synchronously
          await openLiveSession(nav.context, link.id);
      }
    } catch (e) {
      debugPrint('deep_links: open failed for ${link.key}: $e');
    }
  }

  // ── Кіруден кейін жалғастыру ───────────────────────────────────────────────

  /// Гость «Сыйлықты алу» басты: кіру экраны стекті тазалайды, сондықтан
  /// токенді сақтап қоямыз.
  void rememberGift(String token) {
    _pending = DeepLink(DeepLinkKind.gift, token.toLowerCase());
    _pendingAt = DateTime.now();
  }

  void clearPending() {
    _pending = null;
    _pendingAt = null;
  }

  void _onUserChanged() {
    final p = _pending;
    final at = _pendingAt;
    if (p == null || at == null) return;
    if (!AppUser.current.isLoaded) return;
    if (DateTime.now().difference(at) > _pendingTtl) {
      clearPending();
      return;
    }
    if (!AppUser.current.isClient) {
      clearPending();
      return;
    }
    clearPending();
    // Түбірлік shell құрылып, LoginScreen жабылғанша аз күтеміз.
    Future.delayed(const Duration(milliseconds: 900), () => open(p));
  }
}
