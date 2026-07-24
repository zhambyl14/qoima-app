import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Жергілікті (серверсіз) хабарламалар: «себет тұрып қалды» еске салуы +
/// PushService-тің foreground FCM хабарламаларын жүйелік баннер ретінде
/// көрсетуі (Android-та FCM «notification» пейлоуын OS foreground-та
/// автоматты көрсетпейді — сол алшақтықты осы сервис жабады).
class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService instance = LocalNotificationService._();

  static const int _cartReminderId = 9001;
  static const Duration _reminderDelay = Duration(hours: 2);

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  // showPush() әр шақыруда бөлек id алады (cart reminder-дің бекітілген
  // 9001 id-мен қақтығыспас үшін бөлек диапазоннан бастаймыз) — әйтпесе
  // қатарынан келген push-тар бір-бірін алмастырып, тек соңғысы көрінер еді.
  int _pushNotifId = 20000;

  /// PushService FCM push-ты (foreground) local notification ретінде
  /// көрсеткенде пайдаланушы оны басса шақырылады — data payload-пен.
  /// Навигацияны PushService жағында байланыстырады.
  void Function(Map<String, dynamic> data)? onPushTap;

  Future<void> init() async {
    if (kIsWeb) return; // web-те локал хабарлама схемасы бөлек — қосылмаған
    try {
      tzdata.initializeTimeZones();
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false, // рұқсатты кейін, орынды сәтте сұраймыз
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
        onDidReceiveNotificationResponse: _onTap,
      );
      _ready = true;
    } catch (e) {
      debugPrint('LocalNotificationService init skipped: $e');
    }
  }

  void _onTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      onPushTap?.call(data);
    } catch (e) {
      debugPrint('LocalNotificationService: tap payload decode failed: $e');
    }
  }

  /// FCM push-ты (foreground) жүйелік хабарлама ретінде көрсетеді.
  /// [channelId]/[channelName] — PushService-тегі HIGH маңыздылық арнасымен
  /// ДӘЛ бірдей болуы керек: сол кезде дыбыс/діріл/heads-up баннер
  /// background/terminated режимдегідей бірдей болады.
  Future<void> showPush({
    required String channelId,
    required String channelName,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_ready) return;
    try {
      _pushNotifId++;
      await _plugin.show(
        _pushNotifId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('showPush failed: $e');
    }
  }

  Future<bool> _ensurePermission() async {
    if (!_ready) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final granted = await android.requestNotificationsPermission();
        if (granted == false) return false;
      }
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        final granted = await ios.requestPermissions(
            alert: true, badge: true, sound: true);
        if (granted == false) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Себетке тауар қосылғанда шақырылады: 2 сағаттан кейін бір еске салу
  /// жоспарлайды (алдыңғысы болса — ауыстырады, стектелмейді).
  Future<void> scheduleCartReminder({required int itemCount}) async {
    if (!_ready) return;
    if (!await _ensurePermission()) return;
    try {
      await _plugin.cancel(_cartReminderId);
      final when = tz.TZDateTime.now(tz.local).add(_reminderDelay);
      await _plugin.zonedSchedule(
        _cartReminderId,
        'Товары ждут в корзине',
        itemCount > 1
            ? 'У вас $itemCount товара в корзине — оформите заказ, пока они в наличии'
            : 'У вас товар в корзине — оформите заказ, пока он в наличии',
        when,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'cart_reminder',
            'Напоминания о корзине',
            channelDescription: 'Напоминание, если товары остались в корзине',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('scheduleCartReminder failed: $e');
    }
  }

  /// Себет бос қалды/checkout сәтті өтті — жоспарланған еске салуды өшіреді.
  Future<void> cancelCartReminder() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(_cartReminderId);
    } catch (_) {}
  }
}
