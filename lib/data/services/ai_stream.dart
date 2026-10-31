import 'dart:convert';

import '../models/catalog_hit.dart';

/// ai-assistant SSE ағынының таза логикасы (желі/Flutter тәуелділігі жоқ):
/// байттар -> кадрлар -> оқиғалар. Сервер жағы: supabase/functions/ai-assistant.

/// Бір SSE кадры (`event:` + `data:`).
class SseFrame {
  final String event;
  final String data;
  const SseFrame(this.event, this.data);
}

/// Бөлшектеніп келген мәтінді кадрларға бөледі (\n\n, \r\n\r\n, \r\r;
/// `: ...` түсініктеме жолдары ескерілмейді).
class SseParser {
  String _buf = '';
  static final _sep = RegExp(r'\r\n\r\n|\n\n|\r\r');

  List<SseFrame> feed(String chunk) {
    _buf += chunk;
    final out = <SseFrame>[];
    for (;;) {
      final m = _sep.firstMatch(_buf);
      if (m == null) break;
      final raw = _buf.substring(0, m.start);
      _buf = _buf.substring(m.end);
      final f = _parseFrame(raw);
      if (f != null) out.add(f);
    }
    return out;
  }

  /// Ағын бос жолсыз үзілсе — қалған кадр.
  List<SseFrame> flush() {
    final rest = _buf;
    _buf = '';
    if (rest.trim().isEmpty) return const [];
    final f = _parseFrame(rest);
    return f == null ? const [] : [f];
  }

  static SseFrame? _parseFrame(String raw) {
    var event = 'message';
    final data = <String>[];
    for (final line in raw.split(RegExp(r'\r\n|\n|\r'))) {
      if (line.isEmpty || line.startsWith(':')) continue;
      final i = line.indexOf(':');
      final field = i < 0 ? line : line.substring(0, i);
      var value = i < 0 ? '' : line.substring(i + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      if (field == 'event') {
        event = value;
      } else if (field == 'data') {
        data.add(value);
      }
    }
    return data.isEmpty ? null : SseFrame(event, data.join('\n'));
  }
}

/// Ақырғы нәтиже (`done`): шындықтың жалғыз көзі.
class AssistantReply {
  final String reply;
  final List<CatalogHit> products;
  final int? remaining;
  const AssistantReply(this.reply, this.products, this.remaining);

  /// `done` / қарапайым JSON жауабының пішіні бірдей.
  factory AssistantReply.fromMap(Map<String, dynamic> data) {
    return AssistantReply(
      (data['reply'] as String?)?.trim() ?? '',
      parseHits(data['products']),
      (data['remaining'] as num?)?.toInt(),
    );
  }
}

List<CatalogHit> parseHits(Object? raw) => (raw as List? ?? const [])
    .whereType<Map>()
    .map((e) => CatalogHit.fromMap(Map<String, dynamic>.from(e)))
    .where((h) => h.productId.isNotEmpty)
    .toList();

sealed class AssistantEvent {
  const AssistantEvent();
}

/// Прогресс: 'searching' | 'thinking'.
class AssistantStatus extends AssistantEvent {
  final String stage;
  const AssistantStatus(this.stage);
}

/// Модель жауабын күтпей табылған тауарлар.
class AssistantPreview extends AssistantEvent {
  final List<CatalogHit> products;
  const AssistantPreview(this.products);
}

/// Модель мәтінінің келесі бөлігі.
class AssistantDelta extends AssistantEvent {
  final String text;
  const AssistantDelta(this.text);
}

/// Осы уақытқа дейінгі мәтінді тастау (жаңа айналым басталды).
class AssistantReset extends AssistantEvent {
  const AssistantReset();
}

class AssistantDone extends AssistantEvent {
  final AssistantReply reply;
  const AssistantDone(this.reply);
}

class AssistantErrorEvent extends AssistantEvent {
  final String code;
  const AssistantErrorEvent(this.code);
}

/// Кадр -> оқиға. Белгісіз/бүлінген кадр — null (елемейміз).
AssistantEvent? parseAssistantFrame(SseFrame f) {
  Map<String, dynamic> m;
  try {
    final d = jsonDecode(f.data);
    if (d is! Map) return null;
    m = Map<String, dynamic>.from(d);
  } catch (_) {
    return null;
  }
  switch (f.event) {
    case 'status':
      return AssistantStatus((m['stage'] as String?) ?? 'thinking');
    case 'preview':
      final hits = parseHits(m['products']);
      return hits.isEmpty ? null : AssistantPreview(hits);
    case 'delta':
      final t = m['text'] as String? ?? '';
      return t.isEmpty ? null : AssistantDelta(t);
    case 'reset':
      return const AssistantReset();
    case 'done':
      return AssistantDone(AssistantReply.fromMap(m));
    case 'error':
      return AssistantErrorEvent((m['error'] as String?) ?? 'ai_failed');
  }
  return null;
}

/// Байт ағыны -> оқиғалар. UTF-8 көпбайтты таңба екі чанкқа бөлінсе де дұрыс.
Stream<AssistantEvent> assistantEvents(Stream<List<int>> bytes) async* {
  final parser = SseParser();
  await for (final text in bytes.cast<List<int>>().transform(utf8.decoder)) {
    for (final f in parser.feed(text)) {
      final e = parseAssistantFrame(f);
      if (e != null) yield e;
    }
  }
  for (final f in parser.flush()) {
    final e = parseAssistantFrame(f);
    if (e != null) yield e;
  }
}
