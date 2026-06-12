import 'package:flutter/material.dart';
import '../../core/card_utils.dart';

/// storeEditRequests өрістерін UI-да көрсету көмекшілері (pending + diff экрандары).

IconData editFieldIcon(String field) {
  switch (field) {
    case 'storeName':
      return Icons.store_outlined;
    case 'city':
      return Icons.location_on_outlined;
    case 'description':
      return Icons.notes_rounded;
    case 'ownerName':
      return Icons.person_outline_rounded;
    case 'ownerIin':
      return Icons.credit_card_outlined;
    case 'phone':
      return Icons.phone_outlined;
    case 'paymentCardNumber':
      return Icons.account_balance_wallet_outlined;
    default:
      return Icons.edit_outlined;
  }
}

/// Карта номерін топтап көрсетеді; қалғаны өзгеріссіз.
String editFieldDisplay(String field, String value) {
  if (value.isEmpty) return '—';
  if (field == 'paymentCardNumber') return formatCardDisplay(value);
  return value;
}
