import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/lang.dart';
import '../models/story_model.dart';
import 'cloudinary_service.dart';

/// Дүкен сторисі (0084) сервисі.
///
/// Барлық жазу — SECURITY DEFINER RPC арқылы (story_create / story_delete);
/// кестеге тікелей insert/delete құқығы жоқ. Оқу гостьқа да ашық.
/// Жалауша: FeatureFlags.stories (сервер өзі де тексереді).
class StoriesService {
  StoriesService({SupabaseClient? client, CloudinaryService? cloudinary})
      : _client = client,
        _cloudinary = cloudinary ?? CloudinaryService();

  final SupabaseClient? _client;
  final CloudinaryService _cloudinary;

  SupabaseClient get _sb => _client ?? Supabase.instance.client;

  // ── Оқу ─────────────────────────────────────────────────────────────────────

  /// Бір дүкеннің белсенді стористері, ЕСКІСІ алдымен (көру реті).
  /// Дүкен қызметкеріне өз дүкені жабық/жалауша өшік болса да қайтады.
  Future<List<StoryModel>> storiesForStore(String storeUid) async {
    if (storeUid.isEmpty) return const [];
    final rows =
        await _sb.rpc('stories_for_store', params: {'p_store': storeUid});
    return _list(rows).map(StoryModel.fromMap).toList();
  }

  /// Басты беттегі жолақ: жазылған дүкендердің сторисі (гостьқа — бос).
  Future<List<StoryStoreGroup>> storiesForFollowed() async {
    final rows =
        await _sb.rpc('stories_for_stores', params: {'p_stores': null});
    return _list(rows).map(StoryStoreGroup.fromMap).toList();
  }

  /// Нақты дүкендер тізімі бойынша жолақ (мысалы гость не «танымал дүкендер»).
  /// Сервер ең көбі 200 дүкенді қарайды.
  Future<List<StoryStoreGroup>> storiesForStores(List<String> storeUids) async {
    final ids = storeUids.where((e) => e.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const [];
    final rows = await _sb.rpc('stories_for_stores', params: {'p_stores': ids});
    return _list(rows).map(StoryStoreGroup.fromMap).toList();
  }

  // ── Жазу ────────────────────────────────────────────────────────────────────

  /// Сторис жариялау (дүкен иесі не белсенді сатушы). [imageBytes] — дайын
  /// (қиылған/сығылған) JPEG. Сурет алдымен qoima_stories қалтасына
  /// жүктеледі; сервер бас тартса — жетім қалмасын деп бірден өшіріледі.
  ///
  /// Қателер (friendlyError аударады): feature_disabled, not_authorized,
  /// store_unavailable, stories_limit, invalid_image_url, invalid_caption,
  /// user_blocked, subscription_frozen.
  Future<StoryModel> create({
    required Uint8List imageBytes,
    String caption = '',
  }) async {
    final text = caption.trim();
    if (text.length > StoryModel.maxCaption) {
      // Сервер де бас тартады (invalid_caption) — жүктемей тұрып тоқтаймыз.
      // Exception мәтіні friendlyError-да сол күйі көрсетіледі.
      throw Exception(tr('Подпись слишком длинная — не больше 200 символов.',
          'Жазу тым ұзын — 200 таңбадан аспасын.'));
    }
    final url = await _cloudinary.uploadStory(imageBytes);
    try {
      final res = await _sb
          .rpc('story_create', params: {'p_image_url': url, 'p_caption': text});
      return StoryModel.fromMap(Map<String, dynamic>.from(res as Map));
    } catch (_) {
      // Сторис жазылмады — суретті Cloudinary-ден тазалаймыз (best-effort).
      _cloudinary.deleteByUrl(url);
      rethrow;
    }
  }

  /// Сторисді өшіру (сол дүкеннің қызметкері не суперадмин). Сурет серверде
  /// cloudinary_delete_queue-ге өзі түседі. Жоқ сторис → үнсіз.
  Future<void> delete(String id) async {
    if (id.isEmpty) return;
    await _sb.rpc('story_delete', params: {'p_id': id});
  }

  // ── «Көрілді» белгісі (тек құрылғыда) ───────────────────────────────────────
  //  Серверде «кім көрді» сақталмайды (жеке дерек әрі әр ашылу — жазу).
  //  Жолақ дөңгелегі StoryStoreGroup.hasUnseen(seenUntil) арқылы боялады.

  static String _seenKey(String storeUid) => 'story_seen_$storeUid';

  /// Осы дүкеннің сторисі соңғы рет қай уақытқа дейін көрілді (null = ешқашан).
  Future<DateTime?> seenUntil(String storeUid) async {
    final p = await SharedPreferences.getInstance();
    final ms = p.getInt(_seenKey(storeUid));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Бірнеше дүкен үшін бір оқумен (жолақ құрғанда).
  Future<Map<String, DateTime>> seenUntilMany(
      Iterable<String> storeUids) async {
    final p = await SharedPreferences.getInstance();
    final out = <String, DateTime>{};
    for (final uid in storeUids) {
      final ms = p.getInt(_seenKey(uid));
      if (ms != null) out[uid] = DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return out;
  }

  /// [at] — көрілген ең жаңа стористің created_at-ы. Белгі тек алға жылжиды.
  Future<void> markSeen(String storeUid, DateTime at) async {
    if (storeUid.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    final prev = p.getInt(_seenKey(storeUid)) ?? 0;
    final ms = at.millisecondsSinceEpoch;
    if (ms > prev) await p.setInt(_seenKey(storeUid), ms);
  }

  static List<Map<String, dynamic>> _list(dynamic rows) => rows is List
      ? [
          for (final r in rows)
            if (r is Map) Map<String, dynamic>.from(r)
        ]
      : const [];
}
