import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_user.dart';
import '../../core/lang.dart';

/// AI-ға жіберілетін бір сурет: не Cloudinary URL (сақталған тауар), не
/// жергілікті байттар (қосу формасы — суреттер сақтау сәтінде ғана
/// Cloudinary-ге жүктеледі).
class AssistImage {
  final String? url;
  final Uint8List? bytes;
  const AssistImage.url(String this.url) : bytes = null;
  const AssistImage.bytes(Uint8List this.bytes) : url = null;
}

/// «Суреттен толтыру» нәтижесі. Барлық мәндер — каталогтың КАНОНДЫҚ мәндері
/// (DB-де сақталатын орысша жолдар) немесе бос жол (= AI сенімді емес).
class ProductSuggestion {
  final String categoryKey;
  final String type;
  final String category; // кімге: Мужские|Женские|Унисекс|Детские
  final String color;
  final String season;
  final String material;
  final String brand;
  final String nameSuggestion;
  final String confidence; // high|medium|low
  final int? remaining;

  const ProductSuggestion({
    required this.categoryKey,
    required this.type,
    required this.category,
    required this.color,
    required this.season,
    required this.material,
    required this.brand,
    required this.nameSuggestion,
    required this.confidence,
    this.remaining,
  });

  factory ProductSuggestion.fromMap(Map<String, dynamic> m) {
    String s(String k) => (m[k] as String? ?? '').trim();
    return ProductSuggestion(
      categoryKey: s('category_key'),
      type: s('type'),
      category: s('category'),
      color: s('color'),
      season: s('season'),
      material: s('material'),
      brand: s('brand'),
      nameSuggestion: s('name_suggestion'),
      confidence: s('confidence'),
      remaining: (m['remaining'] as num?)?.toInt(),
    );
  }

  bool get isLowConfidence => confidence == 'low';
}

/// AI көмекшісінің қатесі — [message] қолданушыға көрсетуге дайын (tr()).
class ProductAssistException implements Exception {
  final String code;
  final String message;
  const ProductAssistException(this.code, this.message);
  @override
  String toString() => message;
}

/// Тауар қосуда AI көмегі (edge функция `ai-product-assist`, 0075 квотасы)
/// + қайтарылмайтын тауар белгісін сақтау.
///
/// ЕШҚАШАН өзі сақтамайды: нәтиже формаға толтырылады, иесі қарап растайды.
class ProductAssistService {
  final SupabaseClient _sb = Supabase.instance.client;

  static const String _fn = 'ai-product-assist';
  static const int _maxImages = 3; // токен/трафик үнемдеу: 3 сурет жеткілікті
  static const int _maxSide = 1024;
  static const int _maxJpegBytes = 1400000; // base64 ≈ 1.87M < сервер 2M

  /// Бүгін дүкенге қалған AI шақыру саны (null — белгісіз/дүкен қызметкері емес).
  Future<int?> remainingToday() async {
    try {
      final res = await _sb.rpc('owner_ai_quota_remaining');
      return (res as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  /// Суреттен өрістерді ұсыну.
  Future<ProductSuggestion> suggest({
    required List<AssistImage> images,
    Map<String, String> fields = const {},
  }) async {
    final data = await _invoke('suggest', images, fields, 'ru');
    return ProductSuggestion.fromMap(data);
  }

  /// Сипаттама жазу. [lang] — 'ru' | 'kk'.
  /// Қайтарады: (сипаттама, бүгін қалған шақыру саны).
  Future<({String description, int? remaining})> describe({
    required List<AssistImage> images,
    Map<String, String> fields = const {},
    required String lang,
  }) async {
    final data = await _invoke('describe', images, fields, lang);
    final text = (data['description'] as String? ?? '').trim();
    if (text.isEmpty) {
      throw ProductAssistException(
          'ai_failed',
          tr('AI не смог написать описание. Попробуйте ещё раз.',
              'AI сипаттама жаза алмады. Қайта көріңіз.'));
    }
    return (
      description: text,
      remaining: (data['remaining'] as num?)?.toInt(),
    );
  }

  Future<Map<String, dynamic>> _invoke(String mode, List<AssistImage> images,
      Map<String, String> fields, String lang) async {
    try {
      // Кодтау да try ішінде: isolate/decode/base64 қатесі қолданушыға
      // түсінікті хабарға айналады (өңделмеген async қате болмайды).
      final payload = await _encodeImages(images);
      if (images.isNotEmpty && payload.isEmpty) {
        throw _mapError('bad_image');
      }
      final res = await _sb.functions.invoke(_fn, body: {
        'mode': mode,
        'images': payload,
        'fields': {
          for (final e in fields.entries)
            if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
        },
        'lang': lang == 'kk' ? 'kk' : 'ru',
      });
      final data = res.data;
      if (data is Map) return data.cast<String, dynamic>();
      if (data is String && data.isNotEmpty) {
        final decoded = jsonDecode(data);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      }
      throw _mapError('ai_failed');
    } on FunctionException catch (e) {
      final detail = (e.details is Map) ? (e.details as Map)['error'] : null;
      throw _mapError(detail?.toString() ?? '', status: e.status);
    } on ProductAssistException {
      rethrow;
    } catch (_) {
      throw _mapError('network');
    }
  }

  ProductAssistException _mapError(String code, {int? status}) {
    switch (code) {
      case 'ai_quota_exceeded':
        return ProductAssistException(
            code,
            tr('Лимит AI-помощника на сегодня исчерпан. Завтра снова будет доступен.',
                'AI көмекшісінің бүгінгі лимиті таусылды. Ертең қайта қолжетімді болады.'));
      case 'feature_disabled':
        return ProductAssistException(
            code, tr('Функция временно отключена', 'Функция уақытша өшірулі'));
      case 'not_configured':
        return ProductAssistException(
            code,
            tr('AI-помощник пока не подключён. Обратитесь в поддержку.',
                'AI көмекшісі әлі қосылмаған. Қолдау қызметіне жазыңыз.'));
      case 'not_authorized':
        return ProductAssistException(
            code,
            tr('AI-помощник доступен только сотрудникам магазина.',
                'AI көмекшісі тек дүкен қызметкерлеріне қолжетімді.'));
      case 'refused':
        return ProductAssistException(
            code,
            tr('AI не может обработать это фото. Попробуйте другое.',
                'AI бұл суретті өңдей алмайды. Басқа сурет таңдаңыз.'));
      case 'bad_request':
        return ProductAssistException(
            code,
            tr('Добавьте фото товара или его название.',
                'Тауардың суретін немесе атауын қосыңыз.'));
      case 'ai_busy':
        return ProductAssistException(
            code,
            tr('AI сейчас перегружен. Повторите через минуту.',
                'AI қазір бос емес. Бір минуттан соң қайталаңыз.'));
      case 'bad_image':
        return ProductAssistException(
            code,
            tr('Не удалось обработать фото. Выберите другое изображение.',
                'Суретті өңдеу мүмкін болмады. Басқа сурет таңдаңыз.'));
      case 'network':
        return ProductAssistException(
            code,
            tr('Нет связи с сервером. Проверьте интернет.',
                'Серверге қосылу жоқ. Интернетті тексеріңіз.'));
      default:
        if (status == 401) {
          return ProductAssistException(
              'invalid_session',
              tr('Сессия истекла — войдите заново.',
                  'Сессия аяқталды — қайта кіріңіз.'));
        }
        return ProductAssistException(
            'ai_failed',
            tr('Не получилось. Попробуйте ещё раз.',
                'Болмады. Қайта көріңіз.'));
    }
  }

  /// URL-дер өзгеріссіз; байттар ≤1024px JPEG-ке кішірейтіліп base64 болады
  /// (isolate-та, UI қатпайды).
  Future<List<String>> _encodeImages(List<AssistImage> images) async {
    final out = <String>[];
    for (final im in images.take(_maxImages)) {
      if (im.url != null && im.url!.startsWith('https://')) {
        out.add(im.url!);
      } else if (im.bytes != null && im.bytes!.isNotEmpty) {
        final jpg = await compute(_shrinkJpeg, im.bytes!);
        // Декодталмаған/тым ауыр сурет жіберілмейді (сервер лимиті ~1.5 МБ).
        if (jpg == null || jpg.length > _maxJpegBytes) continue;
        out.add('data:image/jpeg;base64,${base64Encode(jpg)}');
      }
    }
    return out;
  }

  // ── Қайтарылмайтын тауар (Returns pack келісімі) ─────────────────────────

  /// Суперадмин бұл дүкенге «қайтарылмайтын тауар» белгісін рұқсат етті ме
  /// (stores.allow_non_returnable — Returns pack; StoreModel.allowNonReturnable).
  /// Тікелей жолдан оқимыз: баған әлі жоқ болса (миграция қолданылмаған) —
  /// false, форма бұрынғыдай жұмыс істейді.
  Future<bool> storeAllowsNonReturnable() async {
    try {
      final owner = _ownerUid;
      if (owner.isEmpty) return false;
      final row = await _sb
          .from('stores')
          .select('allow_non_returnable')
          .eq('admin_uid', owner)
          .maybeSingle();
      return row?['allow_non_returnable'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Тауардың ағымдағы белгісі (өңдеу формасы үшін). Баған жоқ болса — бос.
  Future<({bool nonReturnable, String returnNote})> productReturnability(
      String productId) async {
    try {
      final row = await _sb
          .from('products')
          .select('non_returnable, return_note')
          .eq('id', productId)
          .maybeSingle();
      return (
        nonReturnable: row?['non_returnable'] == true,
        returnNote: (row?['return_note'] as String?) ?? '',
      );
    } catch (_) {
      return (nonReturnable: false, returnNote: '');
    }
  }

  String get _ownerUid => AppUser.current.ownerUid.isNotEmpty
      ? AppUser.current.ownerUid
      : (_sb.auth.currentUser?.id ?? '');

  /// Тауардың қайтарылмайтын белгісі мен түсініктемесін сақтау. Тауардың
  /// негізгі өрістерінен БӨЛЕК жазылады — addNewProduct/updateProductInfo
  /// бұл бағандарды білмесе де жоғалмайды.
  Future<void> setReturnability(String productId,
      {required bool nonReturnable, required String returnNote}) async {
    final note = returnNote.trim();
    await _sb.from('products').update({
      'non_returnable': nonReturnable,
      'return_note': note.length > 300 ? note.substring(0, 300) : note,
    }).eq('id', productId);
  }
}

/// Isolate жұмысшысы: суретті ≤[ProductAssistService._maxSide] px-ке
/// кішірейтіп, JPEG (q80) етеді. Декодтау сәтсіз болса — null (сурет түсіріледі).
Uint8List? _shrinkJpeg(Uint8List raw) {
  try {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return null;
    const maxSide = ProductAssistService._maxSide;
    final resized = (decoded.width > maxSide || decoded.height > maxSide)
        ? img.copyResize(decoded,
            width: decoded.width >= decoded.height ? maxSide : null,
            height: decoded.height > decoded.width ? maxSide : null,
            interpolation: img.Interpolation.average)
        : decoded;
    return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
  } catch (_) {
    return null;
  }
}
