import 'package:flutter/material.dart';
import '../theme/qoima_design.dart';
import '../data/models/order_model.dart';

import 'lang.dart';
/// Тапсырыс статусын қазақша белгілерге, түстерге және QPill тонына
/// айналдыратын ортақ көмекшілер. Қолданыстағы [OrderModel] статустарына
/// негізделген (жаңа статус схемасын ЕНГІЗБЕЙДІ — админ/сатушы ағындары сол
/// статустармен жұмыс істейді).
String orderStatusLabel(String status) {
  switch (status) {
    case OrderModel.statusPending:
      return tr('Ожидает оплаты', 'Төлем күтілуде');
    case OrderModel.statusReserved:
      return tr('В брони', 'Броньда');
    case OrderModel.statusRejected:
      return tr('Отклонён', 'Қабылданбады');
    case OrderModel.statusConfirmed:
      return tr('Оплачен · Готов', 'Төленді · Дайын');
    case OrderModel.statusReady:
      return tr('Готов', 'Дайын');
    case OrderModel.statusCompleted:
      return tr('Получен', 'Алынды');
    case OrderModel.statusCancelled:
      return tr('Отменён', 'Бас тартылды');
    case OrderModel.statusReturned:
      return tr('Возвращён', 'Қайтарылды');
    default:
      return status;
  }
}

/// Казпочта: «confirmed» екі кезеңді жасырады (дайындалып жатыр / жолда), ал
/// «Оплачен · Готов» клиентке «алуға болады» деп оқылады. Басқа тапсырыста null.
String? kazpostStatusLabel(OrderModel o) {
  if (!o.isKazpost || o.status != OrderModel.statusConfirmed) return null;
  return o.postInTransit ? tr('В пути', 'Жолда') : tr('Оплачен', 'Төленді');
}

Color orderStatusColor(String status) {
  switch (status) {
    case OrderModel.statusPending:
      return cAmber;
    case OrderModel.statusReserved:
      return cBlue;
    case OrderModel.statusConfirmed:
    case OrderModel.statusReady:
    case OrderModel.statusCompleted:
      return cGreen;
    case OrderModel.statusRejected:
    case OrderModel.statusCancelled:
    case OrderModel.statusReturned:
      return cRed;
    default:
      return cInk3;
  }
}

/// QPill үшін тон кілті (green|amber|blue|red|gray).
String orderStatusTone(String status) {
  switch (status) {
    case OrderModel.statusPending:
      return 'amber';
    case OrderModel.statusReserved:
      return 'blue';
    case OrderModel.statusConfirmed:
    case OrderModel.statusReady:
    case OrderModel.statusCompleted:
      return 'green';
    case OrderModel.statusRejected:
    case OrderModel.statusCancelled:
    case OrderModel.statusReturned:
      return 'red';
    default:
      return 'gray';
  }
}

/// Тапсырыс «белсенді» ме (аяқталмаған/бас тартылмаған).
bool orderIsActive(String status) =>
    status != OrderModel.statusCompleted &&
    status != OrderModel.statusCancelled &&
    status != OrderModel.statusReturned;

/// «Кім отменил» деген белгі (0030 — cancelled_by_*). Viewer-дің өз әрекеті
/// болса «Вы отменили» деп көрсетеді, әйтпесе рөліне қарай (client/seller/
/// admin/system-авто-мерзім).
String cancelledByLabel(OrderModel o, {required String viewerUid}) {
  if (o.status != OrderModel.statusCancelled || o.cancelledByRole.isEmpty) {
    return tr('Отменён', 'Бас тартылды');
  }
  if (viewerUid.isNotEmpty && o.cancelledByUid == viewerUid) {
    return tr('Вы отменили', 'Сіз болдырмадыңыз');
  }
  switch (o.cancelledByRole) {
    case 'client':
      return tr('Отменил клиент', 'Клиент болдырмады');
    case 'seller':
      return tr('Отменил продавец', 'Сатушы болдырмады');
    case 'admin':
      return tr('Отменил владелец', 'Дүкен иесі болдырмады');
    case 'system':
      return tr('Отменено (истёк срок)', 'Болдырылмады (мерзімі өтті)');
    default:
      return tr('Отменён', 'Бас тартылды');
  }
}
