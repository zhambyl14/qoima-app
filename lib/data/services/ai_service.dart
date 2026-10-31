import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error_text.dart';
import '../../core/lang.dart';
import '../../core/locale_context.dart';
import '../models/catalog_hit.dart';
import 'ai_stream.dart';

export 'ai_stream.dart';

/// AI функциялары қатесі: [message] — қолданушыға көрсетуге дайын (tr()),
/// [code] — сервер коды ('ai_quota_exceeded', 'feature_disabled', ...).
class AiException implements Exception {
  final String code;
  final String message;
  const AiException(this.code, this.message);

  bool get isQuota => code == 'ai_quota_exceeded';
  bool get isDisabled => code == 'feature_disabled';

  @override
  String toString() => message;
}

/// Чат хабарламасы (көмекші).
class AiChatMessage {
  final String role; // 'user' | 'assistant'
  final String text;
  const AiChatMessage(this.role, this.text);
}

class LookResult {
  final String title;
  final String summary;
  final CatalogHit base;
  final List<CatalogHit> items;
  final int? remaining;
  const LookResult({
    required this.title,
    required this.summary,
    required this.base,
    required this.items,
    required this.remaining,
  });
}

class TryOnResult {
  final String imageUrl;
  final int? remaining;
  const TryOnResult(this.imageUrl, this.remaining);
}

/// AI edge функцияларына (ai-assistant, ai-stylist, virtual-tryon) клиент.
/// Токенді supabase_flutter өзі қосады; квота мен жалауды сервер тексереді.
class AiService {
  final _sb = Supabase.instance.client;

  static String get _lang => LocaleContext.currentLang == 'kk' ? 'kk' : 'ru';

  /// Бүгінге қалған сұрау саны (kind: 'tryon' | 'stylist' | 'assistant').
  /// Қате болса null (UI санауышты жасырады).
  Future<int?> quotaRemaining(String kind) async {
    try {
      final r = await _sb.rpc('ai_quota_remaining', params: {'p_kind': kind});
      return (r as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _assistantBody(
      List<AiChatMessage> history, String city) {
    final msgs =
        history.length > 20 ? history.sublist(history.length - 20) : history;
    return {
      'messages': [
        for (final m in msgs)
          {
            'role': m.role,
            'content': m.text.length > 2000 ? m.text.substring(0, 2000) : m.text,
          }
      ],
      if (city.isNotEmpty) 'city': city,
      'lang': _lang,
    };
  }

  /// Көмекшімен чат (ағынсыз). [history] — соңғы хабарламалар (соңғысы user).
  Future<AssistantReply> assistantChat(
    List<AiChatMessage> history, {
    String city = '',
  }) async {
    final data = await _invoke('ai-assistant', _assistantBody(history, city),
        timeout: const Duration(seconds: 100));
    return AssistantReply.fromMap(data);
  }

  /// Көмекшімен чат, SSE ағынымен: статус, табылған тауарлар және мәтін келген
  /// сайын оқиға беріледі; соңғысы [AssistantDone]. Қате — [AiException].
  /// Сервер әлі ескі нұсқада болса (қарапайым JSON қайтарса) немесе ағын ештеңе
  /// бермей үзілсе — бір ақырғы оқиға / ағынсыз сұрау (fallback).
  Stream<AssistantEvent> assistantChatStream(
    List<AiChatMessage> history, {
    String city = '',
    Duration idleTimeout = const Duration(seconds: 45),
  }) async* {
    final body = _assistantBody(history, city);
    Object? data;
    try {
      final res = await _sb.functions.invoke(
        'ai-assistant',
        body: body,
        headers: const {'Accept': 'text/event-stream'},
      ).timeout(const Duration(seconds: 60));
      data = res.data;
    } on FunctionException catch (e) {
      final detail = e.details is Map ? (e.details as Map)['error'] : null;
      final code = detail?.toString() ?? 'ai_failed';
      throw AiException(code, _msg(code));
    } on TimeoutException {
      throw AiException('timeout', _msg('timeout'));
    } catch (e) {
      if (isNetworkError(e)) throw AiException('network', friendlyError(e));
      throw AiException('ai_failed', _msg('ai_failed'));
    }

    // Ескі функция: ағынсыз JSON.
    if (data is Map) {
      if (data['error'] != null) {
        final code = data['error'].toString();
        throw AiException(code, _msg(code));
      }
      yield AssistantDone(AssistantReply.fromMap(Map<String, dynamic>.from(data)));
      return;
    }
    if (data is! Stream<List<int>>) {
      throw AiException('ai_failed', _msg('ai_failed'));
    }

    var any = false;
    var finished = false;
    try {
      // Үнсіз қалған ағынды күтпейміз: сервердің жалпы мерзімі 55 с.
      await for (final e in assistantEvents(data).timeout(idleTimeout)) {
        if (e is AssistantErrorEvent) {
          throw AiException(e.code, _msg(e.code));
        }
        any = true;
        yield e;
        if (e is AssistantDone) {
          finished = true;
          return;
        }
      }
    } on AiException {
      rethrow;
    } on TimeoutException {
      throw AiException('timeout', _msg('timeout'));
    } catch (e) {
      if (isNetworkError(e)) throw AiException('network', friendlyError(e));
      throw AiException('ai_failed', _msg('ai_failed'));
    }
    if (finished) return;
    // Ештеңе келмей үзілді (мысалы, прокси ағынды буферлеп тастады): ағынсыз жол.
    // Бірдеңе келіп үзілсе — қайта жібермейміз (квота екі рет кетпесін).
    if (any) throw AiException('ai_failed', _msg('ai_failed'));
    yield AssistantDone(await assistantChat(history, city: city));
  }

  /// «Образ құрастыру».
  Future<LookResult> buildLook(String productId, {String city = ''}) async {
    final data = await _invoke(
        'ai-stylist',
        {
          'productId': productId,
          if (city.isNotEmpty) 'city': city,
          'lang': _lang,
        },
        timeout: const Duration(seconds: 100));
    final items = (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => CatalogHit.fromMap(Map<String, dynamic>.from(e)))
        .where((h) => h.productId.isNotEmpty)
        .toList();
    if (items.isEmpty) {
      throw AiException('not_enough_items', _msg('not_enough_items'));
    }
    final b = Map<String, dynamic>.from((data['base'] as Map?) ?? const {});
    return LookResult(
      title: (data['title'] as String?)?.trim() ?? '',
      summary: (data['summary'] as String?)?.trim() ?? '',
      base: CatalogHit.fromMap({
        'product_id': b['product_id'],
        'name': b['name'],
        'brand': b['brand'],
        'type': b['type'],
        'color': b['color'],
        'category_key': b['category_key'],
        'image_url': b['image_url'],
      }),
      items: items,
      remaining: (data['remaining'] as num?)?.toInt(),
    );
  }

  /// Онлайн киіп көру. [bytes] — адам суреті (JPEG), сервер сақтамайды.
  Future<TryOnResult> virtualTryOn(
    String productId,
    int imageIndex,
    Uint8List bytes,
  ) async {
    final data = await _invoke(
        'virtual-tryon',
        {
          'productId': productId,
          'imageIndex': imageIndex,
          'personImageBase64': base64Encode(bytes),
          'lang': _lang,
        },
        timeout: const Duration(seconds: 90));
    final url = data['imageUrl'] as String? ?? '';
    if (url.isEmpty) throw AiException('tryon_failed', _msg('tryon_failed'));
    return TryOnResult(url, (data['remaining'] as num?)?.toInt());
  }

  // ── Ортақ шақыру + қате карталау ──────────────────────────────────────────
  Future<Map<String, dynamic>> _invoke(
    String fn,
    Map<String, dynamic> body, {
    required Duration timeout,
  }) async {
    try {
      final res = await _sb.functions.invoke(fn, body: body).timeout(timeout);
      final d = res.data;
      if (d is Map) {
        if (d['error'] != null) {
          final code = d['error'].toString();
          throw AiException(code, _msg(code));
        }
        return Map<String, dynamic>.from(d);
      }
      throw AiException('ai_failed', _msg('ai_failed'));
    } on AiException {
      rethrow;
    } on FunctionException catch (e) {
      final detail = e.details is Map ? (e.details as Map)['error'] : null;
      final code = detail?.toString() ?? 'ai_failed';
      throw AiException(code, _msg(code));
    } on TimeoutException {
      throw AiException('timeout', _msg('timeout'));
    } catch (e) {
      if (isNetworkError(e)) {
        throw AiException('network', friendlyError(e));
      }
      throw AiException('ai_failed', _msg('ai_failed'));
    }
  }

  static String _msg(String code) {
    switch (code) {
      case 'ai_quota_exceeded':
        return tr('Дневной лимит исчерпан, попробуйте завтра',
            'Бүгінгі лимит бітті, ертең қайталаңыз');
      case 'feature_disabled':
        return tr('Функция временно отключена', 'Функция уақытша өшірулі');
      case 'not_enough_items':
        return tr('Пока не нашлось подходящих товаров для образа',
            'Образ үшін әзірге сәйкес тауар табылмады');
      case 'not_supported':
        return tr('Для этого товара образ собрать нельзя',
            'Бұл тауарға образ құрастыру мүмкін емес');
      case 'not_eligible':
        return tr('Этот товар нельзя примерить онлайн',
            'Бұл тауарды онлайн киіп көру мүмкін емес');
      case 'not_found':
        return tr('Товар недоступен', 'Тауар қолжетімсіз');
      case 'tryon_failed':
        return tr(
            'Не удалось создать примерку. Попробуйте другое фото: в полный рост, хорошее освещение',
            'Киіп көру жасалмады. Басқа сурет таңдаңыз: толық бойымен, жақсы жарықта');
      case 'tryon_timeout':
      case 'timeout':
        return tr('Слишком долго. Попробуйте ещё раз',
            'Тым ұзаққа созылды. Қайталап көріңіз');
      case 'not_configured':
        return tr('Функция ещё не настроена, попробуйте позже',
            'Функция әлі бапталмаған, кейінірек қайталаңыз');
      case 'refused':
        return tr('Не получилось обработать этот запрос',
            'Бұл сұрауды өңдеу мүмкін болмады');
      case 'ai_busy':
        return tr('AI сейчас перегружен, повторите через минуту',
            'AI қазір бос емес, бір минуттан кейін қайталаңыз');
      case 'no_auth':
      case 'invalid_session':
        return tr('Войдите в аккаунт, чтобы продолжить',
            'Жалғастыру үшін аккаунтқа кіріңіз');
      case 'bad_request':
        return tr('Не удалось отправить запрос. Проверьте фото и повторите',
            'Сұрау жіберілмеді. Суретті тексеріп, қайталаңыз');
      default:
        return tr('Что-то пошло не так, попробуйте ещё раз',
            'Бірдеңе дұрыс болмады, қайталап көріңіз');
    }
  }
}
