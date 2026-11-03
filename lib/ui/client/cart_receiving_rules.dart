import '../../core/lang.dart';
import '../../data/models/cart_item_model.dart';
import '../../data/models/order_model.dart';

// ── Алу тәсілдерінің ережесі (таза функциялар, UI-сыз тестіленеді) ──────────
//
//  «Бронь» (10% қазір, қалғаны дүкенде) мен «Самовывоз» (дүкеннен өзім
//  аламын) клиент дүкенге ӨЗІ БАРАТЫН болса ғана мағыналы. Себетте клиенттің
//  қаласынан басқа қаладағы дүкен болса — бұл екеуі берілмейді, тек «Жеткізу»
//  қалады (ол әрқашан 100% алдын ала).
//
//  ⚠️ Сервер де ДӘЛ осылай тексереді: 0088 guard_orders_pickup_city
//  (clients.city ↔ stores.city, lower + Dart trim() жиынымен шет бос белгілерін
//  алу; INSERT және order_type UPDATE). Ереже өзгерсе — екеуін бір
//  коммитте өзгерту.
//
//  Клиенттің қаласы = ПРОФИЛЬДЕГІ қала (AppUser.city = clients.city), «Жеткізу»
//  ішінде таңдалған қала ЕМЕС: ол сәлемдеменің қайда баратынын айтады
//  (мыс. туысқа), клиенттің өзі қайда екенін емес.
//  Қала белгісіз (клиентте немесе дүкенде бос) — бұрынғы мінез: бәрі ашық.

/// Қала атауын салыстыруға келтіру. Сервер (0088) дәл осы trim() жиынын
/// (таб, жол ауысуы, NBSP, U+2000–200A, FEFF т.б.) regexp-пен алады.
String normCity(String? city) => (city ?? '').trim().toLowerCase();

/// «Дүкенге өзі баратын» тәсіл ме (Бронь / Самовывоз).
bool isPickupOrderType(String? type) =>
    type == OrderModel.typeSmartReservation ||
    type == OrderModel.typeClickCollect;

/// Клиенттің қаласынан басқа қаладағы дүкен.
class ForeignStore {
  final String adminUid;
  final String storeName;
  final String city;
  const ForeignStore(this.adminUid, this.storeName, this.city);
}

class PickupAvailability {
  /// Бронь/Самовывоз рұқсат па.
  final bool allowed;

  /// Басқа қаладағы дүкендер (себеттегі ретімен, қайталанбайды).
  final List<ForeignStore> foreignStores;

  const PickupAvailability._(this.allowed, this.foreignStores);

  static const PickupAvailability open = PickupAvailability._(true, []);

  /// Бұл тәсілді таңдауға бола ма. Жеткізу/белгісіз тәсіл — әрқашан бола.
  bool permits(String? orderType) => allowed || !isPickupOrderType(orderType);
}

/// [items] — тапсырысқа кететін жолдар (таңдалған + қолжетімді).
/// [storeCityByAdmin] — adminUid → дүкен қаласы (жүктелмеген дүкен = белгісіз).
PickupAvailability pickupAvailability({
  required String clientCity,
  required Iterable<CartItemModel> items,
  required Map<String, String> storeCityByAdmin,
}) {
  final mine = normCity(clientCity);
  if (mine.isEmpty) return PickupAvailability.open;
  final foreign = <String, ForeignStore>{};
  for (final i in items) {
    if (foreign.containsKey(i.adminUid)) continue;
    final raw = storeCityByAdmin[i.adminUid] ?? '';
    final city = normCity(raw);
    if (city.isEmpty || city == mine) continue;
    foreign[i.adminUid] = ForeignStore(i.adminUid, i.storeName, raw.trim());
  }
  if (foreign.isEmpty) return PickupAvailability.open;
  return PickupAvailability._(false, foreign.values.toList(growable: false));
}

/// Бір жолдық түсіндірме: неге тек жеткізу. Бір дүкен болса — атымен және
/// қаласымен (аралас себетте клиент қай дүкен кедергі екенін бірден көреді).
String pickupBlockedText(PickupAvailability a) {
  if (a.foreignStores.length == 1) {
    final s = a.foreignStores.single;
    final city = trValue(s.city);
    final name = s.storeName.trim();
    if (name.isNotEmpty) {
      return tr(
          'Магазин «$name» в другом городе ($city) — доступна только доставка с полной оплатой',
          '«$name» дүкені басқа қалада ($city) — тек толық төлеммен жеткізу қолжетімді');
    }
  }
  return tr('Магазин в другом городе — доступна только доставка с полной оплатой',
      'Дүкен басқа қалада — тек толық төлеммен жеткізу қолжетімді');
}
