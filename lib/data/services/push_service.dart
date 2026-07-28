import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart' show MethodChannel, MethodCall;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'local_notification_service.dart';

/// iOS-тағы AppDelegate.swift-пен байланысатын арна (ios/Runner/AppDelegate.swift
/// қараңыз). Firebase/flutter_local_notifications плагиндерінің iOS-тегі
/// UNUserNotificationCenterDelegate бөлісуі Scene-based (ImplicitEngine)
/// шаблонда сенімсіз болып шықты — FirebaseMessaging.onMessage/onMessageOpenedApp
/// іске қосылмай қалатын (кеңінен тексерілді). Сол себепті iOS-те push
/// оқиғаларын AppDelegate ӨЗІ ұстап, осы арна арқылы тікелей жібереді.
/// Android-та бұл арна қолданылмайды — FirebaseMessaging стандартты жолмен
/// дұрыс жұмыс істейді.
final _nativePushChannel = MethodChannel('qoima/push_native');

/// FCM хабарламасы осы арна арқылы келуі керек — AndroidManifest.xml-дегі
/// `com.google.firebase.messaging.default_notification_channel_id` мета-
/// деректерімен және send-push edge function-дағы android.notification.
/// channel_id-мен ДӘЛ бірдей болуы міндетті. Жоғары маңыздылық (HIGH) болмаса,
/// хабарлама тек статус-барға үнсіз түседі, экран үстіне баннер болып
/// қалқымайды (heads-up).
const String kPushChannelId = 'high_importance_channel';
const String kPushChannelName = 'Важные уведомления';

/// Firebase-тің фондық isolate-інде шақырылады (қолданба background/
/// terminated күйде FCM хабарламасы келгенде). ТОП-ДЕҢГЕЙ функция болуы
/// МІНДЕТТІ (класс әдісі жарамайды) — Flutter/Firebase талабы. «notification»
/// өрісі бар хабарламаларды осы режимде OS өзі автоматты көрсетеді, сол
/// себепті денесі бос — тек хендлер тіркелмеді деген Firebase ескертуін
/// болдырмау және болашақ data-only өңдеу үшін орын дайындау мақсатында.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

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

  /// Push баннерін басып ашқанда (background тап немесе cold start) шақырылады
  /// — data payload-пен. Қазір навигация роутері жоқ, сол себепті бұл — UI
  /// қабатына data-ны жеткізетін кеңею нүктесі (мыс. белгілі бір экранға
  /// секіру). Тіркелмесе — тек debugPrint-пен шектеледі.
  void Function(Map<String, dynamic> data)? onNotificationOpen;

  /// main()-де бір рет: Firebase-ті көтереміз. Сәтсіз болса (конфиг жоқ,
  /// желі т.б.) — үнсіз өтеміз, қолданба push-сыз жұмыс істей береді.
  ///
  /// МАҢЫЗДЫ: LocalNotificationService.instance.init() бұдан БҰРЫН
  /// аяқталған болуы керек (main.dart-та шақыру ретін қараңыз) — foreground
  /// FCM хабарламасын local notification ретінде көрсету үшін _plugin
  /// дайын тұруы қажет.
  Future<void> init() async {
    if (kIsWeb) return; // web push (VAPID) — бөлек баптау, әзірге қосылмаған
    try {
      await Firebase.initializeApp();
      _firebaseReady = true;

      // ── КРИТИКАЛЫ ТІРКЕУ — БӘРІНЕН БҰРЫН, ЕШБІР БАЯУ ШАҚЫРУДЫ КҮТПЕЙ ────
      // main.dart бұл init()-ті сыртқы таймаутпен шақырады (интерфейсті
      // мәңгі бөгемеу үшін). Бұрын тыңдаушылар (onMessage/onMessageOpenedApp)
      // төмендегі баяу native шақырулардан (setForegroundNotificationPresen-
      // tationOptions, getInitialMessage) КЕЙІН тіркелетін — сол шақырулардың
      // біреуі баяулап сыртқы таймаутқа ілінсе, init() толық үзіліп, ешбір
      // тыңдаушы тіркелмей қалатын (push мүлде өңделмейтін түбірлік себеп
      // осы болатын). Енді тыңдаушылар алдымен, синхронды тіркеледі —
      // сыртқы таймаут іске қосылса да, push өңдеу жұмыс істей береді.
      LocalNotificationService.instance.onPushTap = _handleOpen;
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        final uid = _sb.auth.currentUser?.id;
        if (uid != null) _saveToken(t);
      });
      if (!kIsWeb && Platform.isIOS) {
        // iOS: push оқиғаларын AppDelegate.swift ұстап, осы арна арқылы
        // жібереді (себебі жоғарыдағы файл түсініктемесінде).
        _nativePushChannel.setMethodCallHandler(_handleNativeCall);
        unawaited(_checkNativeInitialPush());
      } else {
        // Android: стандартты Firebase ағындары дұрыс жұмыс істейді.
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
        FirebaseMessaging.onMessageOpenedApp.listen((m) => _handleOpen(m.data));
      }

      // ── Қалғаны — міндетті емес/баяу болуы мүмкін, бөлек тар таймаутпен ──
      // iOS-тің өз баннерін ӨШІРЕМІЗ (alert/sound false) — тек badge қалады.
      // _handleForegroundMessage барлық платформада ӨЗІМІЗ local notification
      // көрсетеді — жалғыз, сенімді, платформа-тәуелсіз жол.
      try {
        await FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(
                alert: false, badge: true, sound: false)
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('PushService: setForegroundNotificationPresentationOptions skipped: $e');
      }
      // Android: HIGH маңыздылық арнасын алдын ала жасаймыз (FCM хабарламасы
      // осыған келгенде heads-up баннер ретінде қалқиды, тек шторкаға емес).
      if (!kIsWeb && Platform.isAndroid) {
        const channel = AndroidNotificationChannel(
          kPushChannelId,
          kPushChannelName,
          description: 'Заказы, продажи, возвраты и отзывы',
          importance: Importance.high,
        );
        await FlutterLocalNotificationsPlugin()
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);
      }
      // Қолданба МҮЛДЕМ жабық күйде push басып ашылса (cold start) —
      // алғашқы кадрдан кейін тексереміз.
      try {
        final initial = await FirebaseMessaging.instance
            .getInitialMessage()
            .timeout(const Duration(seconds: 5));
        if (initial != null) _handleOpen(initial.data);
      } catch (e) {
        debugPrint('PushService: getInitialMessage skipped: $e');
      }
    } catch (e) {
      debugPrint('PushService init skipped: $e');
    }
  }

  /// Foreground-та келген FCM хабарламасын БАРЛЫҚ платформада local
  /// notification ретінде көрсетеді (iOS-тің меншікті баннері жоғарыда
  /// өшірілген — қосарланып көрінбейді).
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return; // тек data-хабарлама — көрсетілетін мәтін жоқ
    if (kIsWeb) return;
    await LocalNotificationService.instance.showPush(
      channelId: kPushChannelId,
      channelName: kPushChannelName,
      title: n.title ?? '',
      body: n.body ?? '',
      payload: jsonEncode(message.data),
    );
  }

  /// iOS: AppDelegate.swift-тен келетін «qoima/push_native» арнасының
  /// шақырулары (ios/Runner/AppDelegate.swift қараңыз).
  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onForegroundMessage':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final data = _asStringMap(args['data']);
        final title = args['title'] as String? ?? '';
        final body = args['body'] as String? ?? '';
        if (title.isEmpty && body.isEmpty) return; // тек data-хабарлама
        await LocalNotificationService.instance.showPush(
          channelId: kPushChannelId,
          channelName: kPushChannelName,
          title: title,
          body: body,
          payload: jsonEncode(data),
        );
        break;
      case 'onNotificationTap':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final data = _asStringMap(args['data']);
        _handleOpen(data);
        break;
    }
  }

  /// Қолданба МҮЛДЕМ жабық күйден push арқылы ашылса (cold start) —
  /// AppDelegate.swift launchOptions-тан сақтап қойған хабарламаны сұраймыз.
  Future<void> _checkNativeInitialPush() async {
    try {
      // ЕСКЕРТУ: AppDelegate.swift getInitialPush деректерді {"data": ...}
      // ЕМЕС, тікелей карта ретінде қайтарады (onForegroundMessage/
      // onNotificationTap-тан айырмашылығы).
      final initial = await _nativePushChannel
          .invokeMethod<Map>('getInitialPush')
          .timeout(const Duration(seconds: 5));
      if (initial == null) return;
      final data = _asStringMap(initial);
      if (data.isNotEmpty) _handleOpen(data);
    } catch (e) {
      debugPrint('PushService: native getInitialPush skipped: $e');
    }
  }

  Map<String, dynamic> _asStringMap(Object? raw) {
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return {};
  }

  void _handleOpen(Map<String, dynamic> data) {
    debugPrint('PushService: notification opened, data=$data');
    onNotificationOpen?.call(data);
  }

  /// Логиннен кейін: рұқсат сұрап, токенді fcm_tokens-ке жазамыз.
  /// [role] — хабарламаларды рөл бойынша бағыттау үшін (admin/seller/client).
  Future<void> registerForUser({required String role}) async {
    debugPrint('PushService: registerForUser start (firebaseReady=$_firebaseReady, role=$role)');
    if (!_firebaseReady) return;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
          alert: true, badge: true, sound: true);
      debugPrint('PushService: permission status = ${settings.authorizationStatus}');
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      // iOS: FCM токенін алудан БҰРЫН Apple-дың APNs токені дайын болуы керек.
      // Құрылғы логынан расталды: apsd байланысы (APSConnection) кейде
      // ~1.5 минутқа дейін созылады (10 секунд ЖЕТКІЛІКСІЗ болды — токен
      // сол себепті сақталмай қалды). Сол себепті ұзағырақ (макс ~2 мин)
      // қайталап күтеміз. await жоқ шақыруда тұрғандықтан (логинді
      // бөгемейді) — бұл ешбір UI-ды тоспайды.
      if (!kIsWeb && Platform.isIOS) {
        String? apns = await FirebaseMessaging.instance.getAPNSToken();
        for (var i = 0; apns == null && i < 40; i++) {
          await Future.delayed(const Duration(seconds: 3));
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
