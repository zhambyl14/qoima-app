import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// FCM хабарламасы осы арна арқылы келуі керек — AndroidManifest.xml-дегі
/// `com.google.firebase.messaging.default_notification_channel_id` мета-
/// деректерімен және send-push edge function-дағы android.notification.
/// channel_id-мен ДӘЛ бірдей болуы міндетті. Жоғары маңыздылық (HIGH) болмаса,
/// хабарлама тек статус-барға үнсіз түседі, экран үстіне баннер болып
/// қалқымайды (heads-up).
const String kPushChannelId = 'high_importance_channel';

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
      // Android: HIGH маңыздылық арнасын алдын ала жасаймыз (FCM хабарламасы
      // осыған келгенде heads-up баннер ретінде қалқиды, тек шторкаға емес).
      if (!kIsWeb && Platform.isAndroid) {
        const channel = AndroidNotificationChannel(
          kPushChannelId,
          'Важные уведомления',
          description: 'Заказы, продажи, возвраты и отзывы',
          importance: Importance.high,
        );
        await FlutterLocalNotificationsPlugin()
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);
      }
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

      // iOS: FCM токенін алудан БҰРЫН Apple-дың APNs токені дайын болуы керек.
      // Ол Apple серверінен бірнеше секундта келеді — дайын болмаса getToken()
      // null қайтарады немесе `apns-token-not-set` қатесін лақтырады, сондықтан
      // токен ешқашан тіркелмейді (iOS push мүлдем келмеуінің басты себебі).
      // Сол себепті APNs токенін қайталап (макс ~10 с) күтеміз.
      if (!kIsWeb && Platform.isIOS) {
        String? apns = await FirebaseMessaging.instance.getAPNSToken();
        for (var i = 0; apns == null && i < 5; i++) {
          await Future.delayed(const Duration(seconds: 2));
          apns = await FirebaseMessaging.instance.getAPNSToken();
        }
        // Әлі де жоқ болса — токенді кейін onTokenRefresh/келесі кіру тіркейді.
        if (apns == null) {
          debugPrint('PushService: APNs token not ready yet, will retry later');
          return;
        }
      }

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
