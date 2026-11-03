import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qoima/core/error_text.dart';
import 'package:qoima/core/locale_context.dart';
import 'package:qoima/data/services/ai_service.dart';
import 'package:qoima/data/services/gift_service.dart';
import 'package:qoima/data/services/live_service.dart';
import 'package:qoima/data/services/registry_service.dart';
import 'package:qoima/data/services/return_service.dart';
import 'package:qoima/ui/shared/coming_soon_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Сатып алушыға көрінетін қате мәтіндері оператордың ішкі жұмысын
/// (жалауша, кілт, провайдер, баптау, квота, HTTP/SQL) ашпауын тексереді,
/// ал оператор қоспаған функциялар жұмсақ «жақында» мәтініне түсуін дәлелдейді.
void main() {
  // Экранға шықпауы тиіс сөздер (ru + kk). Регистрге тәуелсіз.
  final forbidden = <RegExp>[
    RegExp(r'ключ', caseSensitive: false),
    RegExp(r'секрет', caseSensitive: false),
    RegExp(r'провайдер', caseSensitive: false),
    RegExp(r'токен', caseSensitive: false),
    RegExp(r'подключ', caseSensitive: false),
    RegExp(r'отключ', caseSensitive: false),
    RegExp(r'не\s+настро', caseSensitive: false),
    RegExp(r'\bAPI\b'),
    RegExp(r'квот', caseSensitive: false),
    RegExp(r'Gemini|FASHN|Cloudinary|Supabase|LiveKit|Edge|Postgres|SQL|RPC'),
    RegExp(r'Exception|null|Instance of', caseSensitive: false),
    RegExp(r'(^|\D)[45]\d\d(\D|$)'), // HTTP коды
    RegExp(r'кілт\b', caseSensitive: false),
    RegExp(r'өшірул', caseSensitive: false),
    RegExp(r'өшірілг', caseSensitive: false),
    RegExp(r'бапталмаған', caseSensitive: false),
    RegExp(r'қосылмаған', caseSensitive: false),
  ];

  void expectClean(String text, String where) {
    for (final re in forbidden) {
      expect(re.hasMatch(text), isFalse,
          reason: '«$text» ($where) ішінде тыйым салынған үлгі: ${re.pattern}');
    }
  }

  PostgrestException pg(String message, {String code = 'P0001'}) =>
      PostgrestException(message: message, code: code);

  // «Оператор қоспаған» кодтар: барлығы бірдей жұмсақ мәтінге түсуі керек.
  const softCodes = ['feature_disabled', 'not_configured', 'not_eligible'];

  // Күтпеген/ішкі кодтар — жалпы мәтінге түсуі керек.
  const internalCodes = [
    'ai_failed',
    'provider_error',
    'gemini_error',
    'missing_api_key',
    'internal_error',
    'FASHN_API_KEY is not set',
    'something_totally_unknown',
  ];

  for (final lang in ['ru', 'kk']) {
    group('сатып алушы мәтіндері [$lang]', () {
      setUp(() => LocaleContext.currentLang = lang);
      tearDown(() => LocaleContext.currentLang = 'ru');

      test('feature_disabled / not_configured / not_eligible → «жақында»', () {
        final soon = comingSoonText();
        expect(
            soon,
            lang == 'ru'
                ? 'Скоро будет доступно'
                : 'Жақында қолжетімді болады');
        for (final c in softCodes) {
          expect(AiService.messageFor(c), soon, reason: 'AiService $c');
          expect(friendlyError(pg(c)), soon, reason: 'friendlyError $c');
          if (c != 'not_eligible') {
            expect(liveErrorText(c), soon, reason: 'live $c');
          }
          expect(GiftService.errorText(c), soon, reason: 'gift $c');
          expect(policyErrorText(pg(c)), soon, reason: 'return $c');
          expect(registryErrorText(pg(c)), soon, reason: 'registry $c');
        }
        expect(const AiException('not_eligible', '').isComingSoon, isTrue);
        expect(const AiException('feature_disabled', '').isComingSoon, isTrue);
        expect(const AiException('not_configured', '').isComingSoon, isTrue);
        expect(const AiException('tryon_failed', '').isComingSoon, isFalse);
      });

      test('ішкі/белгісіз кодтар → жалпы мәтін, техникалық мәліметсіз', () {
        final generic = genericErrorText();
        for (final c in internalCodes) {
          final ai = AiService.messageFor(c);
          expect(ai, generic, reason: 'AiService $c');
          expectClean(ai, 'AiService $c');
          final fe = friendlyError(pg(c));
          expect(fe, generic, reason: 'friendlyError $c');
          expectClean(fe, 'friendlyError $c');
        }
      });

      test('барлық AiService кодтары таза', () {
        const all = [
          'ai_quota_exceeded',
          'feature_disabled',
          'not_enough_items',
          'not_supported',
          'not_eligible',
          'not_found',
          'tryon_failed',
          'tryon_timeout',
          'timeout',
          'not_configured',
          'refused',
          'ai_busy',
          'no_auth',
          'invalid_session',
          'bad_request',
          'ai_failed',
          'network',
          'whatever',
        ];
        for (final c in all) {
          expectClean(AiService.messageFor(c), 'AiService $c');
        }
      });

      test('жалпы қателер экранға техникалық мәтін шығармайды', () {
        final samples = <Object>[
          Exception('download 404'),
          Exception('gift_size_unavailable'),
          Exception('no done event'),
          Exception('FunctionException(status: 500, details: boom)'),
          StateError('Bad state: No element'),
          const FormatException('Unexpected character'),
          AuthException('Database error saving new user', statusCode: '500'),
          pg('relation "orders" does not exist', code: '42P01'),
          pg('JWT expired', code: 'PGRST301'),
          pg('canceling statement due to statement timeout', code: '57014'),
          pg('Could not find the function public.foo in the schema cache',
              code: 'PGRST202'),
        ];
        for (final s in samples) {
          final t = friendlyError(s);
          expectClean(t, 'friendlyError(${s.runtimeType})');
          expect(t.trim(), isNotEmpty);
        }
      });

      test('Казпочта/жеткізу кодтары: операторлық себепсіз', () {
        for (final c in [
          'kazpost_disabled',
          'kazpost_store_disabled',
          'kazpost_route_unavailable',
        ]) {
          expectClean(friendlyError(pg(c)), c);
        }
        expectClean(GiftService.errorText('courier_unavailable'),
            'courier_unavailable');
        expectClean(GiftService.errorText('promo_inactive'), 'promo_inactive');
      });

      test('live кодтары таза', () {
        for (final c in [
          'feature_disabled',
          'not_configured',
          'internal',
          'live_not_found',
          'live_ended',
          'store_unavailable',
          'live_rate_limited',
          'live_muted',
          'invalid_message',
          'no_auth',
        ]) {
          expectClean(liveErrorText(c), 'live $c');
        }
      });

      test('пайдаланушы әрекет ете алатын қателер нақты қалады', () {
        // Интернет жоқ, сессия, қойма — нақты мәтін, «жалпы» емес.
        final generic = genericErrorText();
        expect(friendlyError(const _SocketLikeError()), networkErrorText());
        expect(networkErrorText(), isNot(generic));
        expect(friendlyError(pg('', code: 'PGRST301')), isNot(generic));
        // PGRST301 = сессия бітті: «құқық жоқ» емес, «қайта кіріңіз».
        expect(
            friendlyError(pg('JWT expired', code: 'PGRST301')),
            lang == 'ru'
                ? 'Сессия истекла. Войдите заново.'
                : 'Сессия мерзімі бітті. Қайта кіріңіз.');
        expect(friendlyError(pg('x', code: 'PGRST302')),
            isNot(contains('Сессия')));
        expect(friendlyError(pg('user_blocked')), isNot(generic));
        expect(GiftService.errorText('gift_out_of_stock'), isNot(generic));
        expect(AiService.messageFor('ai_quota_exceeded'), isNot(generic));
        expect(AiService.messageFor('tryon_failed'), isNot(generic));
        expect(AiService.messageFor('no_auth'), isNot(generic));
      });
    });
  }

  group('looksTechnical', () {
    test('кілттер, HTTP, тип атаулары — техникалық', () {
      for (final s in [
        'gift_size_unavailable',
        'download 404',
        'FunctionException(status: 500)',
        "type 'Null' is not a subtype of type 'String'",
        "Instance of 'Foo'",
        'JWT expired',
        '',
        // Кириллицасыз (кітапхана/сервер ағылшынша қалдығы).
        'Database error saving new user',
        'Invalid upload preset',
        'Missing FASHN key',
        // Кириллица ішінде де: жақшадағы HTTP коды, api_key.
        'Ошибка [400]: Invalid api_key',
        'Қате [500]: boom',
      ]) {
        expect(looksTechnical(s), isTrue, reason: s);
      }
    });
    test('адамша жазылған хабар — техникалық емес', () {
      for (final s in [
        'Недостаточно остатка «Куртка» в размере 42',
        'Промокод табылмады',
        'Минимальная сумма заказа 5000 ₸',
        'Недостаточно остатка «Nike Air 270» в размере 42',
      ]) {
        expect(looksTechnical(s), isFalse, reason: s);
      }
    });
  });

  group('бастапқы код сканері', () {
    // Сатып алушы экрандары мен сервистердегі ЛИТЕРАЛДАР: оператор тілі қайта
    // кіріп кетпесін. Комментарийлер алынып тасталады.
    final targets = <String>[
      'lib/core/error_text.dart',
      'lib/data/services/ai_service.dart',
      'lib/data/services/gift_service.dart',
      'lib/data/services/follow_service.dart',
      'lib/data/services/stories_service.dart',
      'lib/data/services/client_service.dart',
      'lib/data/services/return_service.dart',
      'lib/data/services/kazpost_service.dart',
      'lib/data/services/registry_service.dart',
      'lib/data/services/support_service.dart',
      'lib/ui/live/live_all_screen.dart',
      'lib/ui/live/live_navigation.dart',
      'lib/ui/live/live_viewer_screen.dart',
      'lib/ui/live/live_now_row.dart',
      'lib/ui/support/support_chat_screen.dart',
    ];
    final dirs = <String>['lib/ui/client', 'lib/ui/shared'];

    final bad = <RegExp>[
      RegExp(r'временно\s+отключ', caseSensitive: false),
      RegExp(r'уақытша\s+өшірул', caseSensitive: false),
      RegExp(r'не\s+подключ', caseSensitive: false),
      RegExp(r'пока\s+не\s+настро', caseSensitive: false),
      RegExp(r'әлі\s+бапталмаған', caseSensitive: false),
      RegExp(r'Обратитесь\s+в\s+поддержку', caseSensitive: false),
      RegExp(r'API[-\s]?(key|ключ)', caseSensitive: false),
      RegExp(r'провайдер', caseSensitive: false),
    ];

    String stripComments(String s) => s
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('сатып алушы кодында оператор формулировкалары жоқ', () {
      final files = <File>[
        for (final t in targets) File(t),
        for (final d in dirs)
          ...Directory(d)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')),
      ];
      expect(files, isNotEmpty);
      final hits = <String>[];
      for (final f in files) {
        if (!f.existsSync()) continue;
        final src = stripComments(f.readAsStringSync());
        for (final re in bad) {
          if (re.hasMatch(src)) hits.add('${f.path}: ${re.pattern}');
        }
      }
      expect(hits, isEmpty, reason: hits.join('\n'));
    });
  });

  testWidgets('ComingSoonView «жақында» мәтінін көрсетеді', (t) async {
    LocaleContext.currentLang = 'ru';
    await t.pumpWidget(
        const MaterialApp(home: Scaffold(body: ComingSoonView())));
    expect(find.text('Скоро будет доступно'), findsOneWidget);
    LocaleContext.currentLang = 'kk';
    await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: ComingSoonView(key: Key('kk')))));
    expect(find.text('Жақында қолжетімді болады'), findsOneWidget);
    LocaleContext.currentLang = 'ru';
  });
}

/// isNetworkError тану үшін «желі қатесі» тәрізді нысан.
class _SocketLikeError implements Exception {
  const _SocketLikeError();
  @override
  String toString() => 'SocketException: Failed host lookup';
}
