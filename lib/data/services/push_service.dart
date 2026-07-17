import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

/// FCM push-хабарламалар сервисі.
///
/// Backend Supabase күйінде қалады — Firebase ТЕК push жеткізу үшін
/// (fcm_tokens кестесі + send-push edge function → FCM v1 API).
/// Firebase конфигі жоқ/қате болса қолданба құламайды — push жай өшік тұрады.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  bool _firebaseReady = false;
  String? _lastSavedToken;

  SupabaseClient get _sb => Supabase.instance.client;

  /// main()-де бір рет: Firebase-ті көтереміз. Сәтсіз болса (конфиг жоқ,
  /// желі т.б.) — үнсіз өтеміз, қолданба push-сыз жұмыс істей береді.
  Future<void> init() async {
    if (kIsWeb) return; // web push (VAPID) — бөлек баптау, әзірге қосылмаған
    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
      // iOS: қолданба ашық тұрғанда да жүйелік баннер көрсетілсін.
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
              alert: true, badge: true, sound: true);
      // Токен жаңарса — тіркелген қолданушыға қайта сақтаймыз.
      FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        final uid = _sb.auth.currentUser?.id;
        if (uid != null) _saveToken(t);
      });
    } catch (e) {
      debugPrint('PushService init skipped: $e');
    }
  }

  /// Логиннен кейін: рұқсат сұрап, токенді fcm_tokens-ке жазамыз.
  /// [role] — хабарламаларды рөл бойынша бағыттау үшін (admin/seller/client).
  Future<void> registerForUser({required String role}) async {
    if (!_firebaseReady) return;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
          alert: true, badge: true, sound: true);
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await _saveToken(token, role: role);
    } catch (e) {
      debugPrint('PushService register skipped: $e');
    }
  }

  Future<void> _saveToken(String token, {String role = ''}) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    if (_lastSavedToken == token && role.isEmpty) return;
    try {
      await _sb.from('fcm_tokens').upsert({
        'token': token,
        'uid': uid,
        if (role.isNotEmpty) 'role': role,
        'platform': kIsWeb
            ? 'web'
            : Platform.isIOS
                ? 'ios'
                : 'android',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'token');
      _lastSavedToken = token;
    } catch (e) {
      debugPrint('PushService save token failed: $e');
    }
  }

  /// Шығу алдында: осы құрылғының токенін өшіреміз — басқа аккаунтқа
  /// арналған push бұл құрылғыға келмейді.
  Future<void> unregister() async {
    if (!_firebaseReady) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _sb.from('fcm_tokens').delete().eq('token', token);
      }
      _lastSavedToken = null;
    } catch (_) {}
  }
}
