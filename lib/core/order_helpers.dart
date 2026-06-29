import 'package:flutter/material.dart';
import '../theme/qoima_design.dart';
import '../data/models/order_model.dart';

/// Тапсырыс статусын қазақша белгілерге, түстерге және QPill тонына
/// айналдыратын ортақ көмекшілер. Қолданыстағы [OrderModel] статустарына
/// негізделген (жаңа статус схемасын ЕНГІЗБЕЙДІ — админ/сатушы ағындары сол
/// статустармен жұмыс істейді).
String orderStatusLabel(String status) {
  switch (status) {
    case OrderModel.statusPending:
      return 'Төлем күтілуде';
    case OrderModel.statusReserved:
      return 'Броньда';
    case OrderModel.statusRejected:
      return 'Қабылданбады';
    case OrderModel.statusConfirmed:
      return 'Төленді · Дайын';
    case OrderModel.statusReady:
      return 'Дайын';
    case OrderModel.statusCompleted:
      return 'Алынды';
    case OrderModel.statusCancelled:
      return 'Бас тартылды';
    case OrderModel.statusReturned:
      return 'Қайтарылды';
    default:
      return status;
  }
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
