import 'package:flutter/material.dart';
import 'app_user.dart';
import '../data/models/return_model.dart';
import '../data/repositories/banner_repository.dart';
import '../data/services/client_service.dart';
import '../data/services/firestore_service.dart';
import '../data/services/return_service.dart';
import '../ui/admin/my_store/admin_reviews_screen.dart';
import '../ui/admin/online_orders_screen.dart';
import '../ui/admin/returns/admin_return_detail_screen.dart';
import '../ui/admin/settings/sellers_screen.dart';
import '../ui/client/client_orders_screen.dart';
import '../ui/client/client_product_detail.dart';
import '../ui/client/store_public_screen.dart';
import '../ui/seller/sales/sale_detail_screen.dart';
import '../ui/seller/seller_online_screen.dart';
import '../ui/seller/returns/seller_return_receive_screen.dart';
import '../ui/seller/returns/seller_return_review_screen.dart';
import '../ui/superadmin/marketplace_shops_screen.dart';
import '../ui/superadmin/subscriptions_screen.dart';

/// MaterialApp-тың түбір Navigator-і. AdminShell/SellerShell/ClientShell
/// bottom-nav таптары бір ортақ Scaffold-ты IndexedStack-пен ауыстырады —
/// әр таб үшін бөлек nested Navigator ЖОҚ (зерттеу растады). Сол себепті осы
/// түбір кілт арқылы жасалған Navigator.push әрқашан ағымдағы shell/таб
/// үстіне толық экранмен дұрыс шығады — қосымша баптау қажет емес.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// PushService.onNotificationOpen-ге main()-де, PushService.init()-тен
/// БҰРЫН тіркеледі (cold-start getInitialMessage тапталуын жіберіп алмау
/// үшін). Сол сәтте Navigator әлі mount болмауы мүмкін — дайын болғанша
/// қысқа аралықпен қайталап тексереміз (PushService.registerForUser-дегі
/// APNs токен күту паттернімен бірдей идиома).
///
/// cold-start-та (қолданба мүлдем жабық түрде push арқылы ашылса) сессияны
/// қалпына келтіру (Supabase auth restore + users/clients кестесінен жол
/// оқу) Navigator mount болғаннан да кешірек аяқталуы мүмкін — сол себепті
/// user.isLoaded-ті бірден тексеріп қана қоймай, соны да қайталап күтеміз,
/// әйтпесе push тапталуы үнсіз жоғалып кетеді (навигация болмайды).
Future<void> handlePushOpen(Map<String, dynamic> data) async {
  NavigatorState? nav = rootNavigatorKey.currentState;
  for (var i = 0; nav == null && i < 50; i++) {
    await Future.delayed(const Duration(milliseconds: 100));
    nav = rootNavigatorKey.currentState;
  }
  if (nav == null) return;

  final type = data['type'] as String? ?? '';
  final user = AppUser.current;
  for (var i = 0; !user.isLoaded && i < 100; i++) {
    await Future.delayed(const Duration(milliseconds: 100));
  }
  if (!user.isLoaded) return; // сессия ешқашан қалпына келмеді — секірер жер жоқ

  try {
    switch (type) {
      case 'sale':
        await _openSale(nav, user, data);
        break;
      case 'order':
      case 'receipt':
        await _openOrder(nav, user, data);
        break;
      case 'return':
        await _openReturn(nav, user, data);
        break;
      case 'review':
        _openReview(nav, user, data);
        break;
      case 'join_request':
        _openJoinRequest(nav, user);
        break;
      case 'order_status':
        _openOrderStatus(nav, user, data);
        break;
      case 'review_reply':
        await _openReviewReply(nav, user, data);
        break;
      case 'banner':
        await _openBanner(nav, user, data);
        break;
      case 'back_in_stock':
        await _openBackInStock(nav, user, data);
        break;
      case 'store_broadcast':
      // Referral сыйлығы да сол дүкеннің бетіне апарады (сыйлық промокоды
      // «Досыңды шақыр» экранында да көрінеді).
      case 'referral_reward':
        await _openStoreBroadcast(nav, user, data);
        break;
      case 'store_registered':
        _openStoreRegistered(nav, user);
        break;
      case 'subscription_expiring':
        _openSubscriptionExpiring(nav, user);
        break;
    }
  } catch (e) {
    debugPrint('handlePushOpen failed for type=$type: $e');
  }
}

// ── admin: жаңа сатылым — тек иесіне келеді ──────────────────────────────────
Future<void> _openSale(
    NavigatorState nav, AppUser user, Map<String, dynamic> data) async {
  if (!user.isAdmin) return;
  final saleId = data['saleId'] as String? ?? '';
  if (saleId.isEmpty) return;
  final sale = await FirestoreService().getSaleById(saleId);
  if (sale == null) return;
  nav.push(MaterialPageRoute(builder: (_) => SaleDetailScreen(sale: sale)));
}

// ── admin+seller: жаңа тапсырыс / чек тіркелді ───────────────────────────────
Future<void> _openOrder(
    NavigatorState nav, AppUser user, Map<String, dynamic> data) async {
  final orderId = data['orderId'] as String? ?? '';
  if (orderId.isEmpty) return;
  if (user.isAdmin) {
    nav.push(MaterialPageRoute(
        builder: (_) => OnlineOrdersScreen(openOrderId: orderId)));
  } else if (user.isSeller) {
    nav.push(MaterialPageRoute(
        builder: (_) => SellerOnlineScreen(openOrderId: orderId)));
  }
}

// ── admin (+seller — тек онлайн возврат): жаңа возврат ───────────────────────
Future<void> _openReturn(
    NavigatorState nav, AppUser user, Map<String, dynamic> data) async {
  final returnId = data['returnId'] as String? ?? '';
  if (returnId.isEmpty) return;
  if (user.isAdmin) {
    final ret = await ReturnService().watchReturn(user.uid, returnId).first;
    if (ret == null) return;
    nav.push(
        MaterialPageRoute(builder: (_) => AdminReturnDetailScreen(ret: ret)));
  } else if (user.isSeller) {
    final all = await ReturnService().watchSellerReturns(user.ownerUid).first;
    final matches = all.where((r) => r.id == returnId);
    if (matches.isEmpty) return;
    final ret = matches.first;
    // seller_returns_tab.dart-тағы конвенциямен бірдей: approved →
    // қабылдау экраны, қалғаны (requested/received/refunded/rejected) —
    // қарау/тек оқу экраны.
    if (ret.status == ReturnStatus.approved) {
      nav.push(MaterialPageRoute(
          builder: (_) => SellerReturnReceiveScreen(ret: ret)));
    } else {
      nav.push(MaterialPageRoute(
          builder: (_) => SellerReturnReviewScreen(ret: ret)));
    }
  }
}

// ── admin: жаңа пікір ─────────────────────────────────────────────────────────
void _openReview(NavigatorState nav, AppUser user, Map<String, dynamic> data) {
  if (!user.isAdmin) return;
  final productId = data['productId'] as String? ?? '';
  nav.push(MaterialPageRoute(
      builder: (_) =>
          AdminReviewsScreen(productId: productId.isEmpty ? null : productId)));
}

// ── admin: сатушы қосылу өтінімі ─────────────────────────────────────────────
void _openJoinRequest(NavigatorState nav, AppUser user) {
  if (!user.isAdmin) return;
  nav.push(
      MaterialPageRoute(builder: (_) => const SellersScreen(initialTab: 1)));
}

// ── client: тапсырыс статусы өзгерді ─────────────────────────────────────────
void _openOrderStatus(
    NavigatorState nav, AppUser user, Map<String, dynamic> data) {
  if (!user.isClient) return;
  final orderId = data['orderId'] as String? ?? '';
  final status = data['status'] as String? ?? '';
  final completedTab = status == 'completed' ||
      status == 'cancelled' ||
      status == 'returned';
  nav.push(MaterialPageRoute(
      builder: (_) => ClientOrdersScreen(
            highlightOrderId: orderId.isEmpty ? null : orderId,
            initialTabIndex: completedTab ? 1 : 0,
          )));
}

// ── client: дүкен пікірге жауап берді ────────────────────────────────────────
Future<void> _openReviewReply(
    NavigatorState nav, AppUser user, Map<String, dynamic> data) async {
  if (!user.isClient) return;
  final productId = data['productId'] as String? ?? '';
  if (productId.isEmpty) return;
  final client = ClientService();
  final product = await client.getProductById(user.uid, productId);
  if (product == null || product.storefrontHidden) return;
  final ownerUid = await client.getProductOwnerUid(productId);
  if (ownerUid == null || ownerUid.isEmpty) return;
  final store = await client.getStoreByAdminUid(ownerUid);
  if (store == null || !store.isPublished || store.isBlocked) return;
  nav.push(MaterialPageRoute(
      builder: (_) => ClientProductDetail(product: product, store: store)));
}

// ── client: таңдаулыдағы тауар қоймаға қайта келді (0041) ────────────────────
Future<void> _openBackInStock(
    NavigatorState nav, AppUser user, Map<String, dynamic> data) async {
  if (!user.isClient) return;
  final productId = data['productId'] as String? ?? '';
  if (productId.isEmpty) return;
  final client = ClientService();
  final product = await client.getProductById(user.uid, productId);
  if (product == null || product.storefrontHidden) return;
  final ownerUid = await client.getProductOwnerUid(productId);
  if (ownerUid == null || ownerUid.isEmpty) return;
  final store = await client.getStoreByAdminUid(ownerUid);
  if (store == null || !store.isPublished || store.isBlocked) return;
  nav.push(MaterialPageRoute(
      builder: (_) => ClientProductDetail(product: product, store: store)));
}

// ── client: дүкеннің өз жарнама push-ы (0043) ────────────────────────────────
Future<void> _openStoreBroadcast(
    NavigatorState nav, AppUser user, Map<String, dynamic> data) async {
  if (!user.isClient) return;
  final adminUid = data['adminUid'] as String? ?? '';
  if (adminUid.isEmpty) return;
  final store = await ClientService().getStoreByAdminUid(adminUid);
  if (store == null || !store.isPublished || store.isBlocked) return;
  nav.push(MaterialPageRoute(builder: (_) => StorePublicScreen(store: store)));
}

// ── client: жаңа баннер (тек дүкенге сілтейтіндер ашылады) ───────────────────
Future<void> _openBanner(
    NavigatorState nav, AppUser user, Map<String, dynamic> data) async {
  if (!user.isClient) return;
  final bannerId = data['bannerId'] as String? ?? '';
  if (bannerId.isEmpty) return;
  final banner = await BannerRepository().getBannerById(bannerId);
  if (banner == null || !banner.hasStoreLink) return;
  // Пуштен ашқанда таңдау парағы жоқ — бірінші сілтелген дүкенге апарамыз.
  final store =
      await ClientService().getStoreByAdminUid(banner.storeAdminUids.first);
  if (store == null || !store.isPublished || store.isBlocked) return;
  nav.push(MaterialPageRoute(builder: (_) => StorePublicScreen(store: store)));
}

// ── superadmin: жаңа дүкен тіркелді (0031) ───────────────────────────────────
void _openStoreRegistered(NavigatorState nav, AppUser user) {
  if (!user.isSuperadmin) return;
  nav.push(
      MaterialPageRoute(builder: (_) => const MarketplaceShopsScreen()));
}

// ── superadmin: иенің жазылым мерзімі жақындап қалды (0031) ──────────────────
void _openSubscriptionExpiring(NavigatorState nav, AppUser user) {
  if (!user.isSuperadmin) return;
  nav.push(MaterialPageRoute(builder: (_) => const SubscriptionsScreen()));
}
