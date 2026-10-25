import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Жаңа функцияларды суперадмин қосып/өшіретін жалаушалар (0067b).
///
/// Мән app_settings-тегі 'feature_<атау>' кілттерінен `feature_flags` RPC
/// арқылы оқылады (guest-ке де ашық). Тексеру сервер жағында да бар —
/// мұндағы мақсат тек өшік функцияның батырмасын көрсетпеу.
///
/// Қолдану: `ListenableBuilder(listenable: FeatureFlags.instance,
///   builder: (_, __) => FeatureFlags.instance.isOn(FeatureFlags.liveShopping)
///       ? ... : const SizedBox.shrink())`.
class FeatureFlags extends ChangeNotifier {
  FeatureFlags._();
  static final FeatureFlags instance = FeatureFlags._();

  static const aiTryOn = 'ai_tryon';
  static const aiStylist = 'ai_stylist';
  static const aiAssistant = 'ai_assistant';
  static const aiProductAssist = 'ai_product_assist';
  static const liveShopping = 'live_shopping';
  static const giftRegistry = 'gift_registry';
  static const giftLinks = 'gift_links';
  static const supportChat = 'support_chat';
  static const nonReturnable = 'non_returnable';

  /// Суперадмин бетіндегі реттілік.
  static const all = [
    aiTryOn,
    aiStylist,
    aiAssistant,
    aiProductAssist,
    liveShopping,
    giftRegistry,
    giftLinks,
    supportChat,
    nonReturnable,
  ];

  static const _ttl = Duration(minutes: 5);

  Map<String, bool> _flags = const {};
  DateTime? _loadedAt;
  bool _loading = false;

  bool get isLoaded => _loadedAt != null;

  /// Жүктелмеген/белгісіз жалауша — false (функция жабық).
  bool isOn(String name) {
    _refreshIfStale();
    return _flags[name] ?? false;
  }

  void _refreshIfStale() {
    final at = _loadedAt;
    if (_loading) return;
    if (at == null || DateTime.now().difference(at) > _ttl) {
      // build() ішінен шақырылуы мүмкін — notifyListeners тек await-тан
      // кейін болады, сондықтан кадр ортасында setState қатесі шықпайды.
      refresh();
    }
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final res = await Supabase.instance.client.rpc('feature_flags');
      if (res is Map) {
        _flags = {
          for (final e in res.entries) e.key.toString(): e.value == true,
        };
      }
      _loadedAt = DateTime.now();
      notifyListeners();
    } catch (_) {
      // Желі жоқ — бұрынғы мәндер қалады; келесі isOn қайта тырысады.
      _loadedAt = DateTime.now().subtract(_ttl - const Duration(seconds: 30));
    } finally {
      _loading = false;
    }
  }

  /// Тек суперадмин (app_settings_write RLS: is_superadmin()).
  Future<void> setFlag(String name, bool on) async {
    await Supabase.instance.client.from('app_settings').upsert({
      'key': 'feature_$name',
      'value': on ? 'true' : 'false',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    _flags = {..._flags, name: on};
    notifyListeners();
  }
}
