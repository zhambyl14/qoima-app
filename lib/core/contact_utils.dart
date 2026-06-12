import 'package:url_launcher/url_launcher.dart';

/// Прямой звонок. Использует схему tel:.
Future<void> makePhoneCall(String phone) async {
  final uri = Uri(scheme: 'tel', path: phone);
  if (!await launchUrl(uri)) {
    throw Exception('Не удалось совершить звонок: $phone');
  }
}

/// Открывает Telegram в официальном приложении.
/// username — без @, например 'zhambyl_magzhan'.
Future<void> openTelegram(String username) async {
  final uri = Uri.parse('https://t.me/$username');
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw Exception('Не удалось открыть Telegram');
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
    throw Exception('Не удалось открыть WhatsApp');
  }
}
