import 'dart:async';
import 'dart:io' show SocketException, HandshakeException, HttpException;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'lang.dart';

/// Пайдаланушыға көрсетілетін қате мәтіндері.
///
/// НЕГЕ КЕРЕК: бұрын экрандар `e.toString()`-ті тікелей шығаратын, сол себепті
/// интернет жоқ кезде клиент «ClientException with SocketException: Failed host
/// lookup: ...supabase.co, uri=https://...» деген түсініксіз техникалық мәтінді
/// көретін. Мұнда сол шикі қателерді адам түсінетін, аударылған мәтінге
/// айналдырамыз (шикі мәтін тек debugPrint арқылы логқа кетеді).

/// Желі қатесі ме (интернет жоқ / DNS шешілмеді / таймаут / TLS)?
bool isNetworkError(Object? e) {
  if (e == null) return false;
  if (e is SocketException ||
      e is TimeoutException ||
      e is ClientException ||
      e is HandshakeException ||
      e is HttpException) {
    return true;
  }
  // gotrue желі қатесін өз түріне орайды (қайталауға болатын fetch қатесі).
  if (e is AuthRetryableFetchException) return true;
  if (e is StorageException && (e.statusCode == null || e.statusCode == '0')) {
    return true;
  }
  final s = e.toString().toLowerCase();
  const markers = [
    'failed host lookup',
    'socketexception',
    'clientexception',
    'timeoutexception',
    'connection closed',
    'connection refused',
    'connection reset',
    'connection failed',
    'connection attempt failed',
    'network is unreachable',
    'no address associated with hostname',
    'software caused connection abort',
    'handshakeexception',
    'os error: nodename nor servname provided',
    'operation timed out',
  ];
  return markers.any(s.contains);
}

/// Интернет жоқ кездегі бірыңғай мәтін.
String networkErrorText() => tr(
      'Нет подключения к интернету. Проверьте Wi-Fi или мобильный интернет и попробуйте снова.',
      'Интернет байланысы жоқ. Wi-Fi немесе мобильді интернетті тексеріп, қайталап көріңіз.',
    );

/// Кез келген қатені пайдаланушыға көрсетуге жарамды мәтінге айналдырады.
///
/// [fallback] — түрі белгісіз қате үшін арнайы мәтін (берілмесе — жалпы мәтін).
String friendlyError(Object? e, {String? fallback}) {
  if (e == null) return fallback ?? _genericText();
  // Шикі мәтін әзірлеушіге керек — логта қалады, экранға шықпайды.
  debugPrint('friendlyError: $e');

  if (isNetworkError(e)) return networkErrorText();

  // Қосымшаның өз бизнес-қателері (мәтіні әлдеқашан адамша жазылған).
  final raw = e.toString();
  if (raw.startsWith('Exception: ')) return raw.substring('Exception: '.length);
  if (raw.startsWith('SaleException: ')) {
    return raw.substring('SaleException: '.length);
  }

  if (e is PostgrestException) return _postgrestText(e);
  if (e is AuthException) return _authText(e);
  if (e is StorageException) {
    return tr('Не удалось загрузить файл. Попробуйте ещё раз.',
        'Файлды жүктеу мүмкін болмады. Қайталап көріңіз.');
  }

  return fallback ?? _genericText();
}

String _genericText() => tr(
      'Что-то пошло не так. Попробуйте ещё раз.',
      'Бірдеңе дұрыс болмады. Қайталап көріңіз.',
    );

/// Дерекқор (PostgREST) қатесі: техникалық мәтіннің орнына мәні бойынша
/// түсінікті хабар. Кодтары: https://postgrest.org/en/stable/errors.html
String _postgrestText(PostgrestException e) {
  final code = e.code ?? '';
  if (code == '23505') {
    return tr('Такая запись уже существует.', 'Мұндай жазба әлдеқашан бар.');
  }
  if (code == '23503') {
    return tr('Запись используется в другом месте — удалить нельзя.',
        'Жазба басқа жерде қолданылып тұр — өшіру мүмкін емес.');
  }
  if (code == '42501' || code.startsWith('PGRST3')) {
    return tr('Недостаточно прав для этого действия.',
        'Бұл әрекетке құқығыңыз жеткіліксіз.');
  }
  if (code == 'PGRST301' || code == '401') {
    return tr('Сессия истекла. Войдите заново.',
        'Сессия мерзімі бітті. Қайта кіріңіз.');
  }
  return tr('Ошибка сервера. Попробуйте позже.',
      'Сервер қатесі. Кейінірек қайталап көріңіз.');
}

/// Auth қателері ағылшынша келеді — жиі кездесетіндерін аударамыз.
String _authText(AuthException e) {
  final m = e.message.toLowerCase();
  if (m.contains('invalid login credentials')) {
    return tr('Неверный логин или пароль.', 'Логин немесе құпиясөз қате.');
  }
  if (m.contains('email not confirmed')) {
    return tr('Почта не подтверждена.', 'Пошта расталмаған.');
  }
  if (m.contains('user already registered') ||
      m.contains('already been registered')) {
    return tr('Пользователь с такими данными уже зарегистрирован.',
        'Мұндай деректермен пайдаланушы тіркелген.');
  }
  if (m.contains('password should be at least')) {
    return tr('Пароль слишком короткий.', 'Құпиясөз тым қысқа.');
  }
  if (m.contains('over_email_send_rate_limit') || m.contains('rate limit')) {
    return tr('Слишком много попыток. Попробуйте позже.',
        'Тым көп әрекет жасалды. Кейінірек көріңіз.');
  }
  if (m.contains('jwt') || m.contains('session')) {
    return tr('Сессия истекла. Войдите заново.',
        'Сессия мерзімі бітті. Қайта кіріңіз.');
  }
  return tr('Ошибка входа. Попробуйте ещё раз.',
      'Кіру қатесі. Қайталап көріңіз.');
}
