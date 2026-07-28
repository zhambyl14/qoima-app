import Flutter
import UIKit
import FirebaseMessaging
import UserNotifications

/// Push-хабарламаларды Dart-қа ЖЕТКІЗУДІ ӨЗІМІЗ БАСҚАРАМЫЗ (Firebase/flutter_
/// local_notifications плагиндерінің автоматты UNUserNotificationCenterDelegate
/// бөлісуіне сенбейміз).
///
/// НЕГЕ: Бұл жоба Flutter-дің жаңа Scene-based (FlutterImplicitEngine) шаблонын
/// қолданады. Сол шаблонда firebase_messaging мен flutter_local_notifications
/// плагиндерінің UNUserNotificationCenterDelegate-ті бөлісу логикасы (Firebase
/// плагині FlutterAppLifeCycleProvider-ді анықтап, орнын босатады деп есептейді)
/// нақты құрылғыда сенімсіз болып шықты: push келгенде де (foreground),
/// пайдаланушы push-ты басқанда да (background/tap) Dart жағындағы
/// FirebaseMessaging.onMessage/onMessageOpenedApp ағындары МҮЛДЕМ іске
/// қосылмай қалды (кеңінен тексерілді — тіркеу/токен сақтау толық дұрыс
/// жұмыс істейді, тек осы оқиғалар ғана жетпейді).
///
/// Сол себепті: осы жерден бірден-бір UNUserNotificationCenterDelegate болып,
/// FCM/APNs пейлоуын ӨЗІМІЗ оқып, тікелей meншікті MethodChannel арқылы
/// Dart-қа жібереміз (lib/data/services/push_service.dart осы арнаны тыңдайды).
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // ЕСКЕРТУ: FlutterAppDelegate негізгі класы UNUserNotificationCenterDelegate-
  // ке ӘЛДЕҚАШАН сәйкес келеді (userNotificationCenter:willPresent:/
  // didReceive: әдістерін өзінде іске асырған) — сол себепті мұнда протоколды
  // қайта жариялау («Redundant conformance») қатесін тудырады. Төмендегі екі
  // әдіс — base класстың нұсқасын override ЕТЕДІ (жаңа conformance емес).
  static let pushChannelName = "qoima/push_native"
  private var pushChannel: FlutterMethodChannel?
  /// Қосымша push тапталып, МҮЛДЕМ жабық күйден ашылса — Dart тыңдаушысы
  /// дайын болғанша осында сақталады (cold start).
  private var pendingLaunchNotification: [AnyHashable: Any]?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Scene-based (FlutterImplicitEngine) шаблонда Firebase-тің автоматты
    // AppDelegate swizzling-і APNs тіркеуін кейде байқамай қалады —
    // getAPNSToken() ешқашан толмайды (қанша күтсе де). Сол себепті мұны
    // ЖАРАТ launch кезінде АЙҚЫН шақырамыз: permission-ге тәуелсіз, кез
    // келген уақытта шақыруға болады.
    application.registerForRemoteNotifications()

    if let remoteNotif = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
      pendingLaunchNotification = remoteNotif
    }

    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // Плагиндер (firebase_messaging, flutter_local_notifications) тіркелгеннен
    // КЕЙІН — өзімізді ЖАЛҒЫЗ UNUserNotificationCenterDelegate етіп қайта
    // тағайындаймыз. Жоғарыдағы түсініктемедегі себеп бойынша.
    UNUserNotificationCenter.current().delegate = self

    return result
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("APNs registerForRemoteNotifications failed: \(error)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: AppDelegate.pushChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      // Dart тыңдаушысы дайын болғанда шақырады — cold-start push осында
      // жіберіледі (әйтпесе Dart дайын болғанша жоғалып кетер еді).
      if call.method == "getInitialPush" {
        if let userInfo = self?.pendingLaunchNotification {
          if let payloadString = userInfo["payload"] as? String {
            result(AppDelegate.decodeJsonPayload(payloadString))
          } else {
            result(AppDelegate.userInfoToDict(userInfo))
          }
        } else {
          result(nil)
        }
        self?.pendingLaunchNotification = nil
        return
      }
      result(FlutterMethodNotImplemented)
    }
    pushChannel = channel
  }

  // MARK: - UNUserNotificationCenterDelegate

  /// Push қолданба АШЫҚ тұрғанда келгенде (foreground).
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // ТЕК REMOTE (push) хабарламаларды Dart-қа жібереміз. flutter_local_
    // notifications арқылы ӨЗІМІЗ жасайтын ЖЕРГІЛІКТІ хабарламалар (мыс.
    // осы функция Dart-қа хабарлаған соң Dart local notification көрсетуі)
    // да дәл осы делегатқа түседі — тексерусіз қайта Dart-қа жіберсек,
    // ШЕКСІЗ ЦИКЛ пайда болады (қосымша дереу құлайтын түбірлік себеп
    // осы еді). UNPushNotificationTrigger — тек APNs-тен келген хабарламада
    // болады, жергілікте жоқ.
    guard notification.request.trigger is UNPushNotificationTrigger else {
      // .alert — iOS 13+ үйлесімді (.banner тек iOS 14+, деплоймент
      // target 13.0 болғандықтан қолдануға болмайды).
      completionHandler([.alert, .sound, .badge])
      return
    }
    let content = notification.request.content
    let args: [String: Any] = [
      "title": content.title,
      "body": content.body,
      "data": AppDelegate.userInfoToDict(content.userInfo),
    ]
    // FlutterMethodChannel негізгі (main) ағында шақырылуы МІНДЕТТІ —
    // UNUserNotificationCenterDelegate callback-і кепілді main thread-те
    // келе бермейді, сол себепті айқын dispatch етеміз (әйтпесе тұрақсыз
    // жұмыс істеуі/құлауы мүмкін).
    DispatchQueue.main.async { [weak self] in
      self?.pushChannel?.invokeMethod("onForegroundMessage", arguments: args)
    }
    // Жүйелік баннерді өшіреміз — Dart жағы (push_service.dart) local
    // notification арқылы өзі көрсетеді (барлық платформада бірдей жол).
    completionHandler([])
  }

  /// Пайдаланушы push-ты басқанда (background/cold-start/foreground-та
  /// өзіміз көрсеткен local notification).
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    // flutter_local_notifications арқылы ӨЗІМІЗ жасаған хабарламада (мыс.
    // foreground-та көрсетілген push айнасы) деректер тікелей userInfo-да
    // емес, JSON payload ретінде "payload" кілтінде келеді — соны ажыратып
    // декодтаймыз, әйтпесе type/orderId сияқты өрістер табылмай, навигация
    // болмай қалады.
    let data: [String: Any]
    if let payloadString = userInfo["payload"] as? String {
      data = AppDelegate.decodeJsonPayload(payloadString)
    } else {
      data = AppDelegate.userInfoToDict(userInfo)
    }
    if pushChannel != nil {
      DispatchQueue.main.async { [weak self] in
        self?.pushChannel?.invokeMethod("onNotificationTap", arguments: ["data": data])
      }
    } else {
      // Dart арнасы әлі дайын емес (өте ерте тапталу) — cold start жолымен
      // getInitialPush арқылы жеткіземіз.
      pendingLaunchNotification = userInfo
    }
    completionHandler()
  }

  /// `[AnyHashable: Any]` (APNs userInfo) → `[String: Any]` (Dart жаққа
  /// жіберуге жарамды, тек String кілттер).
  private static func userInfoToDict(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    for (key, value) in userInfo {
      if let k = key as? String {
        out[k] = value
      }
    }
    return out
  }

  /// flutter_local_notifications-тың "payload" кілтіндегі JSON жолын
  /// декодтайды (LocalNotificationService.showPush жіберетін
  /// `jsonEncode(data)` payload-ын оқу үшін).
  private static func decodeJsonPayload(_ payload: String) -> [String: Any] {
    guard let jsonData = payload.data(using: .utf8),
      let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
    else {
      return [:]
    }
    return obj
  }
}
