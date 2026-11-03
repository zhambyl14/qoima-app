import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:qoima/core/app_user.dart';
import 'package:qoima/core/feature_flags.dart';
import 'package:qoima/core/locale_context.dart';
import 'package:qoima/data/services/ai_stream.dart';
import 'package:qoima/l10n/app_localizations.dart';
import 'package:qoima/ui/client/ai/ai_assistant_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ai-assistant SSE: кадр жолдары.
String _frame(String event, Object data) =>
    'event: $event\ndata: ${jsonEncode(data)}\n\n';

Map<String, dynamic> _hit(String id, String name) => {
      'product_id': id,
      'admin_uid': 'a1',
      'store_name': 'Дүкен',
      'name': name,
      'price': 12000,
      'available_sizes': {'M': 2},
    };

/// Желісіз бэкенд: ai-assistant жауабын тест өзі басқарады (ағын/JSON/бос).
class _Backend extends http.BaseClient {
  /// 'stream' | 'json' (ескі функция) | 'empty' (ағын ештеңе бермей үзіледі)
  String mode = 'stream';
  StreamController<List<int>>? sse;
  final accepts = <String?>[];
  int calls = 0;
  int jsonCalls = 0;
  http.BaseRequest? _current;

  http.StreamedResponse _json(Object? body, [int status = 200]) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        request: _current,
        headers: {'content-type': 'application/json'},
      );

  void push(String s) => sse!.add(utf8.encode(s));

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _current = request;
    final path = request.url.path;
    if (path.endsWith('/rpc/feature_flags')) {
      return _json({'ai_assistant': true});
    }
    if (path.endsWith('/rpc/ai_quota_remaining')) return _json(10);
    if (path.endsWith('/functions/v1/ai-assistant')) {
      calls++;
      accepts.add(request.headers['Accept'] ?? request.headers['accept']);
      final wantsSse =
          (request.headers['Accept'] ?? '').contains('text/event-stream');
      if (!wantsSse || mode == 'json') {
        jsonCalls++;
        return _json({
          'reply': 'Ответ без потока',
          'products': [_hit('p9', 'Куртка зимняя')],
          'remaining': 8,
        });
      }
      sse = StreamController<List<int>>();
      if (mode == 'empty') {
        scheduleMicrotask(() => sse!.close());
      } else {
        sse!.add(utf8.encode(': ok\n\n'));
      }
      return http.StreamedResponse(
        sse!.stream,
        200,
        request: _current,
        headers: {'content-type': 'text/event-stream; charset=utf-8'},
      );
    }
    return _json(const []);
  }
}

final _backend = _Backend();

Widget _app() => ChangeNotifierProvider<AppUser>.value(
      value: AppUser.current,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AiAssistantScreen(),
      ),
    );

/// Офлайн тестте Inter қаріпі жүктелмейді: google_fonts бұл қатені асинхронды
/// лақтырады (тест зонасынан тыс ұсталмайды). Тестті ішкі зонада жүргізіп,
/// тек осы белгілі қатені жұтамыз; қалған қате тестті құлатады.
void _widgetTest(String name, Future<void> Function(WidgetTester t) body) {
  testWidgets(name, (t) async {
    final done = Completer<void>();
    runZonedGuarded(() async {
      try {
        await body(t);
        done.complete();
      } catch (e, s) {
        if (!done.isCompleted) done.completeError(e, s);
      }
    }, (e, s) {
      if (e.toString().contains('allowRuntimeFetching')) return;
      if (!done.isCompleted) done.completeError(e, s);
    });
    await done.future;
  });
}

Future<void> _settle(WidgetTester t) async {
  // functions_client JSON-ды изолятта кодтайды: нақты асинхрон күту керек.
  for (var i = 0; i < 8; i++) {
    await t
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await t.pump(const Duration(milliseconds: 50));
    // Офлайн тестте Inter қаріпі жүктелмейді: тек осы белгілі қатені жұтамыз.
    final ex = t.takeException();
    if (ex != null && !ex.toString().contains("allowRuntimeFetching")) {
      throw ex;
    }
  }
}

Future<void> _sendText(WidgetTester t, String text) async {
  await t.enterText(find.byType(TextField), text);
  await t.tap(find.byIcon(Icons.arrow_upward_rounded));
  await _settle(t);
}

void main() {
  group('SseParser / assistantEvents', () {
    test('бөлшектенген кадрлар, CRLF және түсініктеме жолдары', () {
      final p = SseParser();
      expect(p.feed(': ok\n\nevent: sta'), isEmpty);
      final a =
          p.feed('tus\r\ndata: {"stage":"searching"}\r\n\r\nevent: delta\n');
      expect(a.length, 1);
      expect(a.first.event, 'status');
      final b = p.feed('data: {"text":"Сәлем "}\n\n');
      expect(b.single.event, 'delta');
      expect(p.feed('event: done\ndata: {}'), isEmpty);
      expect(p.flush().single.event, 'done');
    });

    test('көп жолды data біріктіріледі, event әдепкісі message', () {
      final f = SseParser().feed('data: a\ndata: b\n\n').single;
      expect(f.event, 'message');
      expect(f.data, 'a\nb');
    });

    test('оқиғалар: status/preview/delta/reset/done/error', () {
      AssistantEvent? ev(String e, Object d) =>
          parseAssistantFrame(SseFrame(e, jsonEncode(d)));
      expect((ev('status', {'stage': 'searching'}) as AssistantStatus).stage,
          'searching');
      expect(ev('delta', {'text': 'ab'}), isA<AssistantDelta>());
      expect(ev('delta', {'text': ''}), isNull);
      expect(ev('reset', {}), isA<AssistantReset>());
      expect(ev('preview', {'products': []}), isNull);
      final pv = ev('preview', {
        'products': [
          _hit('p1', 'A'),
          {'name': 'id жоқ'}
        ]
      }) as AssistantPreview;
      expect(pv.products.map((h) => h.productId), ['p1']);
      final done = ev('done', {
        'reply': ' Дайын ',
        'products': [_hit('p1', 'A')],
        'remaining': 4
      }) as AssistantDone;
      expect(done.reply.reply, 'Дайын');
      expect(done.reply.remaining, 4);
      expect((ev('error', {'error': 'ai_busy'}) as AssistantErrorEvent).code,
          'ai_busy');
      expect(ev('unknown', {}), isNull);
      expect(parseAssistantFrame(const SseFrame('delta', 'not json')), isNull);
    });

    test('UTF-8 таңба екі чанкқа бөлінсе де дұрыс оқылады', () async {
      final bytes = utf8.encode(_frame('delta', {'text': 'Қазақша жауап'}));
      final cut = bytes.indexOf(0xD2) + 1; // «Қ» ортасынан бөлеміз
      final events = await assistantEvents(
              Stream.fromIterable([bytes.sublist(0, cut), bytes.sublist(cut)]))
          .toList();
      expect((events.single as AssistantDelta).text, 'Қазақша жауап');
    });
  });

  group('AiAssistantScreen (ағынды жауап)', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      GoogleFonts.config.allowRuntimeFetching = false;
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(
        url: 'http://localhost:54321',
        publishableKey: 'test-anon-key',
        httpClient: _backend,
        authOptions: const FlutterAuthClientOptions(
          detectSessionInUri: false,
          localStorage: EmptyLocalStorage(),
        ),
      );
    });

    setUp(() async {
      LocaleContext.currentLang = 'ru';
      _backend
        ..mode = 'stream'
        ..sse = null
        ..calls = 0
        ..jsonCalls = 0
        ..accepts.clear();
      AppUser().set(
        uid: 'client-1',
        ownerUid: 'owner-1',
        name: 'Клиент',
        email: '',
        role: 'client',
      );
      SharedPreferences.setMockInitialValues({});
    });

    Future<void> openScreen(WidgetTester t) async {
      await t.runAsync(FeatureFlags.instance.refresh);
      await t.pumpWidget(_app());
      await _settle(t);
    }

    _widgetTest(
        'прогресс -> табылған тауарлар -> мәтін -> done, карточка қайталанбайды',
        (t) async {
      await openScreen(t);
      await _sendText(t, 'куртка');
      expect(_backend.calls, 1);
      expect(_backend.accepts.single, contains('text/event-stream'));
      // Бірінші кадрлар келгенше: нақты прогресс жазуы.
      _backend.push(_frame('status', {'stage': 'searching'}));
      await _settle(t);
      expect(find.text('Ищу в каталоге…'), findsOneWidget);

      // Табылған тауарлар модель жауабын күтпей шығады.
      _backend.push(_frame('preview', {
        'products': [_hit('p1', 'Куртка зимняя')]
      }));
      await _settle(t);
      expect(find.text('Найденные товары'), findsOneWidget);
      expect(find.text('Куртка зимняя'), findsOneWidget);

      // Мәтін токен-токен келеді.
      _backend.push(_frame('delta', {'text': 'Нашла '}));
      _backend.push(_frame('delta', {'text': 'куртку '}));
      await _settle(t);
      expect(find.text('Нашла куртку '), findsOneWidget);

      // Жаңа айналым: мәтін тасталады.
      _backend.push(_frame('reset', {}));
      await _settle(t);
      expect(find.text('Нашла куртку '), findsNothing);

      _backend.push(_frame('done', {
        'reply': 'Вот курточка.',
        'products': [_hit('p1', 'Куртка зимняя')],
        'remaining': 7,
      }));
      await _backend.sse!.close();
      await _settle(t);

      expect(find.text('Вот курточка.'), findsOneWidget);
      // Карточка бір-ақ рет (preview мен done қосарланбайды).
      expect(find.text('Куртка зимняя'), findsOneWidget);
      expect(find.text('Найденные товары'), findsNothing);
      expect(
          find.textContaining('Осталось сообщений сегодня: 7'), findsOneWidget);

      await t.pumpWidget(const SizedBox.shrink());
    });

    _widgetTest('сервер error оқиғасы: хабар қайтарылады, мәтін өріске оралады',
        (t) async {
      await openScreen(t);
      await _sendText(t, 'платье');
      _backend.push(_frame('error', {'error': 'ai_busy'}));
      await _backend.sse!.close();
      await _settle(t);
      expect(find.textContaining('Сейчас много запросов'), findsOneWidget);
      final field = t.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'платье');
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 5));
    });

    _widgetTest(
        'сервер not_configured: техникалық мәтінсіз, жұмсақ «Скоро будет доступно»',
        (t) async {
      await openScreen(t);
      await _sendText(t, 'платье');
      _backend.push(_frame('error', {'error': 'not_configured'}));
      await _backend.sse!.close();
      await _settle(t);
      expect(find.text('Скоро будет доступно'), findsOneWidget);
      expect(find.textContaining('настро'), findsNothing);
      expect(find.byType(TextField), findsNothing); // чат орнына жұмсақ күй
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 5));
    });

    _widgetTest('ескі функция (JSON) — бір ақырғы жауап, қосымша сұраусыз',
        (t) async {
      _backend.mode = 'json';
      await openScreen(t);
      await _sendText(t, 'куртка');
      expect(find.text('Ответ без потока'), findsOneWidget);
      expect(find.text('Куртка зимняя'), findsOneWidget);
      expect(_backend.calls, 1);
      await t.pumpWidget(const SizedBox.shrink());
    });

    _widgetTest('ағын ештеңе бермей үзілсе — ағынсыз fallback', (t) async {
      _backend.mode = 'empty';
      await openScreen(t);
      await _sendText(t, 'куртка');
      expect(_backend.calls, 2);
      expect(_backend.jsonCalls, 1);
      expect(find.text('Ответ без потока'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    });
  });
}
