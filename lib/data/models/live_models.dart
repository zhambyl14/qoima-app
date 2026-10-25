// Live shopping (0071) модельдері: эфир, чат хабары, эфирдегі тауар, токен.

DateTime? _dt(dynamic v) {
  if (v is DateTime) return v;
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
  return null;
}

int _int(dynamic v) => (v as num?)?.toInt() ?? 0;

/// `live_sessions` жолы.
class LiveSession {
  final String id;
  final String adminUid; // дүкен кілті (stores.admin_uid)
  final String hostUid; // нақты кім эфирде (иесі не сатушы)
  final String title;
  final String coverUrl;
  final String status; // 'live' | 'ended'
  final String roomName;
  final String currentProductId; // '' = бекітілген тауар жоқ
  final int viewerCount;
  final int peakViewers;
  final int likeCount;
  final DateTime? heartbeatAt;
  final DateTime startedAt;
  final DateTime? endedAt;

  const LiveSession({
    required this.id,
    required this.adminUid,
    required this.hostUid,
    required this.title,
    this.coverUrl = '',
    required this.status,
    required this.roomName,
    this.currentProductId = '',
    this.viewerCount = 0,
    this.peakViewers = 0,
    this.likeCount = 0,
    this.heartbeatAt,
    required this.startedAt,
    this.endedAt,
  });

  static const statusLive = 'live';
  static const statusEnded = 'ended';

  bool get isLive => status == statusLive;

  /// Тірі ЖӘНЕ хост соңғы 2.5 минутта heartbeat жіберген. Cron 2 минуттан соң
  /// жабады, бірақ realtime ағыны ескі жолды ұстап қалуы мүмкін — UI-де
  /// «ілулі» эфирді көрсетпеу үшін осыны қолданамыз.
  bool get isFreshLive {
    if (!isLive) return false;
    final hb = heartbeatAt;
    if (hb == null) return true;
    return DateTime.now().difference(hb) < const Duration(seconds: 150);
  }

  Duration get duration {
    final d = (endedAt ?? DateTime.now()).difference(startedAt);
    return d.isNegative ? Duration.zero : d;
  }

  factory LiveSession.fromMap(Map<String, dynamic> m) => LiveSession(
        id: m['id'] as String? ?? '',
        adminUid: m['admin_uid'] as String? ?? '',
        hostUid: m['host_uid'] as String? ?? '',
        title: m['title'] as String? ?? '',
        coverUrl: m['cover_url'] as String? ?? '',
        status: m['status'] as String? ?? statusEnded,
        roomName: m['room_name'] as String? ?? '',
        currentProductId: m['current_product_id'] as String? ?? '',
        viewerCount: _int(m['viewer_count']),
        peakViewers: _int(m['peak_viewers']),
        likeCount: _int(m['like_count']),
        heartbeatAt: _dt(m['heartbeat_at']),
        startedAt: _dt(m['started_at']) ?? DateTime.now(),
        endedAt: _dt(m['ended_at']),
      );
}

/// `live_messages` жолы.
class LiveMessage {
  final int id;
  final String sessionId;
  final String userUid;
  final String userName; // тек аты; бос болуы мүмкін
  final String body; // chat → мәтін; cart → тауар аты; system → код
  final String kind; // 'chat' | 'system' | 'cart' | 'like'
  final bool isHost;
  final DateTime createdAt;

  const LiveMessage({
    required this.id,
    required this.sessionId,
    required this.userUid,
    required this.userName,
    required this.body,
    required this.kind,
    required this.isHost,
    required this.createdAt,
  });

  static const kindChat = 'chat';
  static const kindSystem = 'system';
  static const kindCart = 'cart';

  /// Жүйелік хабар кодтары (SQL-мен бірге өзгертілсін).
  static const sysStarted = 'live_started';
  static const sysEnded = 'live_ended';

  factory LiveMessage.fromMap(Map<String, dynamic> m) => LiveMessage(
        id: _int(m['id']),
        sessionId: m['session_id'] as String? ?? '',
        userUid: m['user_uid'] as String? ?? '',
        userName: m['user_name'] as String? ?? '',
        body: m['body'] as String? ?? '',
        kind: m['kind'] as String? ?? kindChat,
        isHost: m['is_host'] as bool? ?? false,
        createdAt: _dt(m['created_at']) ?? DateTime.now(),
      );
}

/// `live_session_products` жолы (тауардың өз деректері бөлек жүктеледі).
class LiveProduct {
  final String sessionId;
  final String productId;
  final int position;
  final int addToCartCount;

  const LiveProduct({
    required this.sessionId,
    required this.productId,
    required this.position,
    required this.addToCartCount,
  });

  factory LiveProduct.fromMap(Map<String, dynamic> m) => LiveProduct(
        sessionId: m['session_id'] as String? ?? '',
        productId: m['product_id'] as String? ?? '',
        position: _int(m['position']),
        addToCartCount: _int(m['add_to_cart_count']),
      );
}

/// `livekit-token` edge fn жауабы.
class LiveToken {
  final String url;
  final String token;
  final String role; // 'host' | 'viewer'
  final String identity;

  const LiveToken({
    required this.url,
    required this.token,
    required this.role,
    required this.identity,
  });

  bool get isHost => role == 'host';

  factory LiveToken.fromMap(Map<String, dynamic> m) => LiveToken(
        url: m['url'] as String? ?? '',
        token: m['token'] as String? ?? '',
        role: m['role'] as String? ?? 'viewer',
        identity: m['identity'] as String? ?? '',
      );
}
