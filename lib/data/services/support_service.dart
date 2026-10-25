import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/lang.dart';
import '../../core/stream_retry.dart';
import '../models/support_models.dart';
import 'cloudinary_service.dart';

/// RPC қатесін пайдаланушыға түсінікті мәтінге айналдырады.
class SupportException implements Exception {
  final String message;
  final String code;
  const SupportException(this.message, {this.code = ''});
  @override
  String toString() => 'Exception: $message';
}

/// Қолдау чаты (0072). Оқу — realtime `.stream()` (RLS: иесі немесе
/// superadmin), жазу — тек SECURITY DEFINER RPC арқылы.
class SupportService {
  final SupabaseClient _sb = Supabase.instance.client;

  String get _uid => _sb.auth.currentUser?.id ?? '';

  // ── Пайдаланушы жағы ──────────────────────────────────────────────────────

  /// Менің тредім (жоқ болса — null; бірінші хабарламада сервер құрады).
  Stream<SupportThread?> watchMyThread() {
    final uid = _uid;
    if (uid.isEmpty) return Stream.value(null);
    return retryStream(() => _sb
        .from('support_threads')
        .stream(primaryKey: ['id'])
        .eq('user_uid', uid)
        .map(
            (rows) => rows.isEmpty ? null : SupportThread.fromMap(rows.first)));
  }

  /// Бір реттік оқу — бірінші хабарламадан кейін тред id-ін бірден алу үшін
  /// (realtime INSERT оқиғасы кешігуі мүмкін).
  Future<SupportThread?> getMyThread() async {
    final uid = _uid;
    if (uid.isEmpty) return null;
    final row = await _sb
        .from('support_threads')
        .select()
        .eq('user_uid', uid)
        .maybeSingle();
    return row == null ? null : SupportThread.fromMap(row);
  }

  /// Пайдаланушыға арналған оқылмаған жауаптар саны (профиль бейджі).
  Stream<int> watchMyUnread() =>
      watchMyThread().map((t) => t?.unreadForUser ?? 0);

  /// Тредтің соңғы 200 хабарламасы, ескісінен жаңасына қарай.
  Stream<List<SupportMessage>> watchMessages(String threadId) =>
      retryStream(() => _sb
          .from('support_messages')
          .stream(primaryKey: ['id'])
          .eq('thread_id', threadId)
          .order('id', ascending: false)
          .limit(200)
          .map((rows) =>
              rows.map(SupportMessage.fromMap).toList().reversed.toList()));

  Future<SupportMessage> send(String body, {String? imageUrl}) async {
    try {
      final res = await _sb.rpc('support_send', params: {
        'p_body': body.trim(),
        'p_image_url': imageUrl,
      });
      return SupportMessage.fromMap(_row(res));
    } on PostgrestException catch (e) {
      throw _map(e);
    }
  }

  // ── Модератор (superadmin) жағы ───────────────────────────────────────────

  /// Барлық тредтер, соңғы хабарлама бойынша (RLS тек superadmin-ге береді).
  Stream<List<SupportThread>> watchAllThreads() => retryStream(() => _sb
      .from('support_threads')
      .stream(primaryKey: ['id'])
      .order('last_message_at', ascending: false)
      .limit(500)
      .map((rows) => rows.map(SupportThread.fromMap).toList()));

  /// Жауап күтіп тұрған тредтер саны (навигация бейджі).
  Stream<int> watchStaffUnreadThreads() => watchAllThreads()
      .map((list) => list.where((t) => t.unreadForStaff > 0).length);

  Stream<SupportThread?> watchThread(String threadId) => retryStream(() => _sb
      .from('support_threads')
      .stream(primaryKey: ['id'])
      .eq('id', threadId)
      .map((rows) => rows.isEmpty ? null : SupportThread.fromMap(rows.first)));

  Future<SupportThread?> getThread(String threadId) async {
    final row = await _sb
        .from('support_threads')
        .select()
        .eq('id', threadId)
        .maybeSingle();
    return row == null ? null : SupportThread.fromMap(row);
  }

  Future<SupportMessage> reply(String threadId, String body,
      {String? imageUrl}) async {
    try {
      final res = await _sb.rpc('support_reply', params: {
        'p_thread': threadId,
        'p_body': body.trim(),
        'p_image_url': imageUrl,
      });
      return SupportMessage.fromMap(_row(res));
    } on PostgrestException catch (e) {
      throw _map(e);
    }
  }

  Future<void> setStatus(String threadId, String status) async {
    try {
      await _sb.rpc('support_set_status',
          params: {'p_thread': threadId, 'p_status': status});
    } on PostgrestException catch (e) {
      throw _map(e);
    }
  }

  // ── Ортақ ─────────────────────────────────────────────────────────────────

  /// Иесі ашса — unread_for_user, superadmin ашса — unread_for_staff
  /// нөлденеді (сервер өзі анықтайды). Сәтсіз болса үнсіз — чат бұзылмайды.
  Future<void> markRead(String threadId) async {
    try {
      await _sb.rpc('support_mark_read', params: {'p_thread': threadId});
    } catch (_) {}
  }

  /// Чатқа сурет жүктеу. Бөлек қалта жоқ — чек қалтасын қолданамыз
  /// (`qoima_receipts`: жетім-тауар sweep оған тимейді).
  Future<String> uploadImage(XFile file) =>
      CloudinaryService().uploadReceipt(file);

  // ── Көмекшілер ────────────────────────────────────────────────────────────

  Map<String, dynamic> _row(dynamic res) {
    if (res is Map) return Map<String, dynamic>.from(res);
    if (res is List && res.isNotEmpty && res.first is Map) {
      return Map<String, dynamic>.from(res.first as Map);
    }
    return <String, dynamic>{'created_at': DateTime.now().toIso8601String()};
  }

  SupportException _map(PostgrestException e) {
    final m = e.message.toLowerCase();
    if (m.contains('feature_disabled')) {
      return SupportException(
          tr('Функция временно отключена', 'Функция уақытша өшірулі'),
          code: 'feature_disabled');
    }
    if (m.contains('rate_limited')) {
      return SupportException(
          tr('Слишком часто. Подождите немного.', 'Тым жиі. Сәл күте тұрыңыз.'),
          code: 'rate_limited');
    }
    if (m.contains('too_long')) {
      return SupportException(
          tr('Сообщение слишком длинное (до 2000 символов).',
              'Хабарлама тым ұзын (2000 таңбаға дейін).'),
          code: 'too_long');
    }
    if (m.contains('empty_message')) {
      return SupportException(
          tr('Напишите сообщение или прикрепите фото.',
              'Хабарлама жазыңыз немесе сурет тіркеңіз.'),
          code: 'empty_message');
    }
    if (m.contains('bad_image_url')) {
      return SupportException(
          tr('Не удалось прикрепить фото.', 'Суретті тіркеу мүмкін болмады.'),
          code: 'bad_image_url');
    }
    if (m.contains('not_found')) {
      return SupportException(tr('Чат не найден.', 'Чат табылмады.'),
          code: 'not_found');
    }
    if (m.contains('not_allowed')) {
      return SupportException(
          tr('Модератор отвечает из раздела «Чат поддержки».',
              'Модератор «Қолдау чаты» бөлімінен жауап береді.'),
          code: 'not_allowed');
    }
    if (m.contains('not_authorized')) {
      return SupportException(
          tr('Недостаточно прав для этого действия.',
              'Бұл әрекетке құқығыңыз жеткіліксіз.'),
          code: 'not_authorized');
    }
    return SupportException(
        tr('Не удалось отправить. Попробуйте ещё раз.',
            'Жіберу мүмкін болмады. Қайталап көріңіз.'),
        code: e.code ?? '');
  }
}
