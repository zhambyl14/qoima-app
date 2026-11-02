import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:qoima/data/services/product_assist_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ai-product-assist жалған бэкенді: сұраныс денесін жазып алады, жауапты тест
/// береді. «Ескі функция» (жаңа режимді білмейді) = 400 bad_request.
class _Backend extends http.BaseClient {
  final bodies = <Map<String, dynamic>>[];
  Map<String, dynamic> reply = {};
  int status = 200;
  http.BaseRequest? _current;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _current = request;
    if (request.url.path.endsWith('/functions/v1/ai-product-assist') &&
        request is http.Request) {
      bodies.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(reply))),
      status,
      request: _current,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  final backend = _Backend();
  late ProductAssistService svc;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      publishableKey: 'test',
      httpClient: backend,
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
    svc = ProductAssistService();
  });

  setUp(() {
    backend.bodies.clear();
    backend.status = 200;
    backend.reply = {};
  });

  group('keywords', () {
    test('ru + kk біріктіріледі, қайталанбайды, режим дұрыс жіберіледі',
        () async {
      backend.reply = {
        'keywords_ru': ['кросы', 'Для зала'],
        'keywords_kk': ['спорттық аяқ киім', 'для зала', ' '],
        'remaining': 7,
      };
      final r = await svc.keywords(
          images: const [], fields: const {'name': 'Air Max', 'brand': ' '});
      expect(r.keywords, ['кросы', 'Для зала', 'спорттық аяқ киім']);
      expect(r.remaining, 7);
      expect(backend.bodies.single['mode'], 'keywords');
      // Бос өрістер жіберілмейді.
      expect(backend.bodies.single['fields'], {'name': 'Air Max'});
    });

    test('бос жауап = қате (шақырушы жергілікті ұсынысқа ауысады)', () async {
      backend.reply = {'keywords_ru': [], 'keywords_kk': []};
      expect(svc.keywords(images: const [], fields: const {'name': 'x'}),
          throwsA(isA<ProductAssistException>()));
    });

    test('ескі функция режимді білмейді (400) → ProductAssistException',
        () async {
      backend.status = 400;
      backend.reply = {'error': 'bad_request'};
      expect(svc.keywords(images: const [], fields: const {'name': 'x'}),
          throwsA(isA<ProductAssistException>()));
    });

    test('квота таусылса — код сақталады', () async {
      backend.status = 429;
      backend.reply = {'error': 'ai_quota_exceeded'};
      await expectLater(
          svc.keywords(images: const [], fields: const {'name': 'x'}),
          throwsA(isA<ProductAssistException>()
              .having((e) => e.code, 'code', 'ai_quota_exceeded')));
    });
  });

  group('translate', () {
    test('мәтін, from, to жіберіледі; нәтиже қайтады', () async {
      backend.reply = {'text': 'Жеңіл кроссовка', 'remaining': 4};
      final r =
          await svc.translate(text: 'Лёгкие кроссовки', from: 'ru', to: 'kk');
      expect(r.text, 'Жеңіл кроссовка');
      expect(r.remaining, 4);
      final b = backend.bodies.single;
      expect(b['mode'], 'translate');
      expect(b['text'], 'Лёгкие кроссовки');
      expect(b['from'], 'ru');
      expect(b['to'], 'kk');
      expect(b['images'], isEmpty);
    });

    test('жалауша өшік → feature_disabled коды', () async {
      backend.status = 403;
      backend.reply = {'error': 'feature_disabled'};
      await expectLater(
          svc.translate(text: 'a', from: 'ru', to: 'kk'),
          throwsA(isA<ProductAssistException>()
              .having((e) => e.code, 'code', 'feature_disabled')));
    });

    test('бос аударма = қате', () async {
      backend.reply = {'text': '  '};
      expect(svc.translate(text: 'a', from: 'kk', to: 'ru'),
          throwsA(isA<ProductAssistException>()));
    });
  });

  group('describe тілі', () {
    test('lang=kk функцияға жетеді; белгісіз тіл ru болады', () async {
      backend.reply = {'description': 'Сипаттама', 'remaining': 3};
      await svc
          .describe(images: const [], fields: const {'name': 'x'}, lang: 'kk');
      await svc
          .describe(images: const [], fields: const {'name': 'x'}, lang: 'de');
      expect(backend.bodies[0]['lang'], 'kk');
      expect(backend.bodies[0]['mode'], 'describe');
      expect(backend.bodies[1]['lang'], 'ru');
    });
  });
}
