import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Желісіз PostgREST: жол бойынша (RPC атауы не кесте) дайын жауап береді.
/// [replies] кілті — URL-дің соңғы сегменті (мыс. `my_follows`, `stores`).
class FakeBackend extends http.BaseClient {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  final replies = <String, Object?>{};
  final errors = <String, String>{};

  /// Жауапты ұстап тұру (оптимистік UI тексеру үшін): complete болғанша күтеді.
  final gates = <String, Future<void>>{};

  /// Әр шақыруда бүкіл кіріс мәнін ауыстыра алатын қосымша өңдеуші.
  Object? Function(String name, Map<String, dynamic> body)? handler;

  http.BaseRequest? _current;

  http.StreamedResponse _json(Object? body, [int status = 200]) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        request: _current,
        headers: {'content-type': 'application/json'},
      );

  int count(String name) => calls.where((c) => c == name).length;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _current = request;
    final name = request.url.pathSegments.last;
    calls.add(name);
    final raw = request is http.Request && request.body.isNotEmpty
        ? jsonDecode(request.body)
        : null;
    final body =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    bodies[name] = body;
    final gate = gates[name];
    if (gate != null) await gate;
    final err = errors[name];
    if (err != null) {
      return _json(
          {'code': 'P0001', 'message': err, 'details': null, 'hint': null},
          400);
    }
    if (handler != null) {
      final r = handler!(name, body);
      if (r != null) return _json(r);
    }
    return _json(replies.containsKey(name) ? replies[name] : const []);
  }
}

/// Supabase.instance-ты жалған бэкендпен бір рет іске қосады.
Future<void> initFakeSupabase(FakeBackend backend) async {
  await Supabase.initialize(
    url: 'http://localhost:54321',
    publishableKey: 'test-anon-key',
    httpClient: backend,
    authOptions: const FlutterAuthClientOptions(
      detectSessionInUri: false,
      localStorage: EmptyLocalStorage(),
    ),
  );
}
