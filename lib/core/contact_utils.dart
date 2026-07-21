import 'package:url_launcher/url_launcher.dart';

import 'lang.dart';
/// Прямой звонок. Использует схему tel:.
Future<void> makePhoneCall(String phone) async {
  final uri = Uri(scheme: 'tel', path: phone);
  if (!await launchUrl(uri)) {
    throw Exception(tr('Не удалось совершить звонок: $phone', 'Қоңырау шалу мүмкін болмады: $phone'));
  }
}

/// Открывает произвольную ссылку во внешнем приложении/браузере
/// (Kaspi QR сілтемесі, карта т.б.). http/https болмаса — қосамыз.
Future<void> openExternalUrl(String rawUrl) async {
  var url = rawUrl.trim();
  if (url.isEmpty) return;
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = 'https://$url';
  }
  final uri = Uri.parse(url);
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw Exception(tr('Не удалось открыть ссылку', 'Сілтемені ашу мүмкін болмады'));
  }
}

/// Открывает адрес на карте (геопоиск по строке).
Future<void> openMapQuery(String address) async {
  final q = Uri.encodeComponent(address.trim());
  if (q.isEmpty) return;
  final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw Exception(tr('Не удалось открыть карту', 'Картаны ашу мүмкін болмады'));
  }
}

/// Открывает Telegram в официальном приложении.
/// username — без @, например 'zhambyl_magzhan'.
Future<void> openTelegram(String username) async {
  final uri = Uri.parse('https://t.me/$username');
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw Exception(tr('Не удалось открыть Telegram', 'Telegram ашылмады'));
  }
}

/// Открывает WhatsApp с предзаполненным сообщением.
/// Очищает номер от +, -, пробелов; заменяет ведущую «8» на «7».
Future<void> openWhatsApp(String phone, String message) async {
  var cleaned = phone.replaceAll(RegExp(r'[\s\-\+\(\)]'), '');
  if (cleaned.startsWith('8')) {
    cleaned = '7${cleaned.substring(1)}';
  }
  final encoded = Uri.encodeComponent(message);
  final uri = Uri.parse('https://wa.me/$cleaned?text=$encoded');
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw Exception(tr('Не удалось открыть WhatsApp', 'WhatsApp ашылмады'));
  }
}
