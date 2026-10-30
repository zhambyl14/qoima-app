import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error_text.dart';
import '../../core/feature_flags.dart';
import '../../core/lang.dart';
import '../../theme/qoima_design.dart';
import 'courier_change_requests_screen.dart';
import 'kazpost_tariffs_screen.dart';
import 'return_policy_stores_screen.dart';
import 'support_inbox_screen.dart';

/// Superadmin: платформа баптаулары.
///
/// 1) «Функциялар» — жаңа мүмкіндіктердің қосқыштары (feature_<атау>).
///    Сервер де әр шақыруда тексереді, сондықтан өшіру толық күшке ие.
/// 2) Сұрақ-жауап жариялығы (qa_public).
/// 3) AI күнделікті лимиттері.
/// 4) Басқа superadmin бөлімдеріне сілтемелер.
class PlatformSettingsScreen extends StatefulWidget {
  const PlatformSettingsScreen({super.key});

  @override
  State<PlatformSettingsScreen> createState() => _PlatformSettingsScreenState();
}

class _FlagInfo {
  final String name;
  final IconData icon;
  final String tone;
  final String titleRu, titleKk, descRu, descKk;

  /// Сыртқы кілт керек болса — secret атаулары (өшік функцияны қосар алдында еске салу).
  final String secrets;
  const _FlagInfo(this.name, this.icon, this.tone, this.titleRu, this.titleKk,
      this.descRu, this.descKk,
      {this.secrets = ''});
}

const _flagInfos = <_FlagInfo>[
  _FlagInfo(
    FeatureFlags.aiTryOn,
    Icons.checkroom_rounded,
    'purple',
    'AI-примерка',
    'AI киіп көру',
    'Покупатель видит себя в выбранной одежде по своему фото.',
    'Сатып алушы өз суретінен таңдалған киімді киіп көреді.',
    secrets: 'FASHN_API_KEY',
  ),
  _FlagInfo(
    FeatureFlags.aiStylist,
    Icons.style_rounded,
    'purple',
    'AI-стилист',
    'AI стилист',
    'Подбирает готовый образ из товаров каталога.',
    'Каталогтағы тауарлардан дайын образ құрастырады.',
    secrets: 'ANTHROPIC_API_KEY',
  ),
  _FlagInfo(
    FeatureFlags.aiAssistant,
    Icons.auto_awesome_rounded,
    'purple',
    'AI-помощник',
    'AI көмекші',
    'Чат-помощник подсказывает товары по запросу покупателя.',
    'Чат-көмекші сатып алушының сұрауы бойынша тауар ұсынады.',
    secrets: 'ANTHROPIC_API_KEY',
  ),
  _FlagInfo(
    FeatureFlags.aiProductAssist,
    Icons.edit_note_rounded,
    'purple',
    'AI-описание товара',
    'AI тауар сипаттамасы',
    'Владелец магазина получает черновик описания при добавлении товара.',
    'Дүкен иесі тауар қосқанда сипаттама жобасын алады.',
    secrets: 'ANTHROPIC_API_KEY',
  ),
  _FlagInfo(
    FeatureFlags.liveShopping,
    Icons.live_tv_rounded,
    'red',
    'Live-эфир',
    'Live-эфир',
    'Магазины ведут прямые эфиры с товарами; покупатели смотрят и пишут в чат.',
    'Дүкендер тауармен тікелей эфир жүргізеді; сатып алушылар көріп, чатқа жазады.',
    secrets: 'LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET',
  ),
  _FlagInfo(
    FeatureFlags.giftRegistry,
    Icons.card_giftcard_rounded,
    'amber',
    'Список желаний',
    'Тілек тізімі',
    'Покупатель создаёт список товаров для события, друзья покупают из него.',
    'Сатып алушы іс-шараға тауар тізімін жасайды, достары сол тізімнен алады.',
  ),
  _FlagInfo(
    FeatureFlags.giftLinks,
    Icons.link_rounded,
    'amber',
    'Ссылка-подарок',
    'Сыйлық сілтемесі',
    'Можно оплатить товар и отправить получателю ссылку: размер и адрес он укажет сам.',
    'Тауардың ақысын төлеп, алушыға сілтеме жіберуге болады: өлшем мен мекенжайды ол өзі көрсетеді.',
  ),
  _FlagInfo(
    FeatureFlags.supportChat,
    Icons.support_agent_rounded,
    'green',
    'Чат поддержки',
    'Қолдау чаты',
    'Пользователи пишут в поддержку Qoima прямо из приложения.',
    'Пайдаланушылар қолдау қызметіне қосымшаның ішінен жазады.',
  ),
  _FlagInfo(
    FeatureFlags.nonReturnable,
    Icons.assignment_return_outlined,
    'blue',
    'Невозвратный товар',
    'Қайтарылмайтын тауар',
    'Магазины с вашего разрешения помечают товары, которые нельзя вернуть.',
    'Сіздің рұқсатыңызбен дүкендер қайтаруға болмайтын тауарларды белгілейді.',
  ),
  _FlagInfo(
    FeatureFlags.kazpostDelivery,
    Icons.local_post_office_outlined,
    'blue',
    'Доставка Казпочтой',
    'Казпочтамен жеткізу',
    'Покупатель из другого города получает товар почтой. Цены задаются ниже в разделе «Тарифы Казпочты».',
    'Басқа қаладағы сатып алушы тауарды почтамен алады. Бағалар төмендегі «Казпочта тарифтері» бөлімінде қойылады.',
  ),
  _FlagInfo(
    FeatureFlags.returnNotice,
    Icons.fact_check_outlined,
    'green',
    'Условия возврата при получении',
    'Алған кезде қайтару шарттары',
    'Покупатель один раз видит условия магазина, когда заказ у него на руках.',
    'Сатып алушы тапсырыс қолына тигенде дүкен шарттарын бір рет көреді.',
  ),
];

class _LimitInfo {
  final String key;
  final int def;
  final String ru, kk;
  const _LimitInfo(this.key, this.def, this.ru, this.kk);
}

const _limitInfos = <_LimitInfo>[
  _LimitInfo('ai_tryon_daily_limit', 3, 'AI-примерка', 'AI киіп көру'),
  _LimitInfo('ai_stylist_daily_limit', 10, 'AI-стилист', 'AI стилист'),
  _LimitInfo('ai_assistant_daily_limit', 40, 'AI-помощник', 'AI көмекші'),
  _LimitInfo('ai_describe_daily_limit', 30, 'AI-описание товара',
      'AI тауар сипаттамасы'),
];

class _PlatformSettingsScreenState extends State<PlatformSettingsScreen> {
  final _sb = Supabase.instance.client;

  /// Қосқыш ауыстырылып жатқанда (сервер жауабын күтіп тұрған) оптимистік мән.
  final Map<String, bool> _optimistic = {};

  /// app_settings-тен тікелей оқылған нақты күй (сервердегі шындық).
  /// FeatureFlags RPC құласа да қосқыштар жалған «OFF» көрсетпесін.
  final Map<String, bool> _flagDb = {};

  bool _loading = true;
  Object? _error;
  bool _qaPublic = false;
  bool _qaSaving = false;

  /// AI провайдері (0080): 'auto' | 'gemini' | 'anthropic'. Edge функциялар
  /// app_settings.ai_provider-ді оқиды (≤60 с ішінде күшіне енеді).
  String _aiProvider = 'auto';
  bool _aiProviderSaving = false;
  final Map<String, TextEditingController> _limitCtrl = {};
  final Map<String, int> _limitSaved = {};
  final Set<String> _limitSaving = {};

  @override
  void initState() {
    super.initState();
    for (final l in _limitInfos) {
      _limitCtrl[l.key] = TextEditingController(text: '${l.def}');
      _limitSaved[l.key] = l.def;
    }
    FeatureFlags.instance.refresh();
    _load();
  }

  @override
  void dispose() {
    for (final c in _limitCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows =
          await _sb.from('app_settings').select('key,value').inFilter('key', [
        'qa_public',
        'ai_provider',
        ..._limitInfos.map((e) => e.key),
        ...FeatureFlags.all.map((n) => 'feature_$n'),
      ]);
      final m = {
        for (final r in rows as List)
          (r as Map)['key'].toString(): r['value']?.toString() ?? '',
      };
      if (!mounted) return;
      setState(() {
        _qaPublic = m['qa_public'] == 'true';
        final ap = m['ai_provider'] ?? 'auto';
        _aiProvider = (ap == 'gemini' || ap == 'anthropic') ? ap : 'auto';
        // Кілт жоқ — сервер (feature_enabled) оны өшік деп есептейді.
        for (final n in FeatureFlags.all) {
          _flagDb[n] = m['feature_$n'] == 'true';
        }
        for (final l in _limitInfos) {
          // Кілт жоқ (миграция әлі қолданылмаған) — әдепкі мән көрсетіледі.
          final v = int.tryParse(m[l.key] ?? '') ?? l.def;
          _limitSaved[l.key] = v;
          _limitCtrl[l.key]!.text = '$v';
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _upsert(String key, String value) =>
      _sb.from('app_settings').upsert({
        'key': key,
        'value': value,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

  Future<void> _toggleFlag(_FlagInfo f, bool on) async {
    HapticFeedback.selectionClick();
    setState(() => _optimistic[f.name] = on);
    try {
      await FeatureFlags.instance.setFlag(f.name, on);
      if (!mounted) return;
      setState(() {
        _flagDb[f.name] = on;
        _optimistic.remove(f.name);
      });
      _snack(
          on
              ? tr('«${f.titleRu}» включено', '«${f.titleKk}» қосылды')
              : tr('«${f.titleRu}» отключено', '«${f.titleKk}» өшірілді'),
          on ? cGreen : cInk);
    } catch (e) {
      if (!mounted) return;
      // Сервер қабылдамады — қосқышты бұрынғы күйіне қайтарамыз.
      setState(() => _optimistic.remove(f.name));
      _snack(friendlyError(e), cRed);
    }
  }

  Future<void> _toggleQa(bool on) async {
    HapticFeedback.selectionClick();
    final prev = _qaPublic;
    setState(() {
      _qaPublic = on;
      _qaSaving = true;
    });
    try {
      await _upsert('qa_public', on ? 'true' : 'false');
      if (!mounted) return;
      _snack(tr('Настройка сохранена', 'Баптау сақталды'), cGreen);
    } catch (e) {
      if (!mounted) return;
      setState(() => _qaPublic = prev);
      _snack(friendlyError(e), cRed);
    } finally {
      if (mounted) setState(() => _qaSaving = false);
    }
  }

  Future<void> _saveLimit(_LimitInfo l) async {
    final v = int.tryParse(_limitCtrl[l.key]!.text.trim());
    if (v == null || v < 0 || v > 100000) {
      _snack(
          tr('Введите целое число от 0 до 100000',
              '0-ден 100000-ға дейінгі бүтін сан енгізіңіз'),
          cRed);
      return;
    }
    setState(() => _limitSaving.add(l.key));
    try {
      await _upsert(l.key, '$v');
      if (!mounted) return;
      setState(() => _limitSaved[l.key] = v);
      FocusScope.of(context).unfocus();
      _snack(tr('Лимит сохранён', 'Лимит сақталды'), cGreen);
    } catch (e) {
      _snack(friendlyError(e), cRed);
    } finally {
      if (mounted) setState(() => _limitSaving.remove(l.key));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Настройки платформы', 'Платформа баптаулары'),
          subtitle:
              tr('Функции, лимиты и режимы', 'Функциялар, лимиттер, режимдер'),
          showBack: true,
          compact: true,
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: cGreen, strokeWidth: 2))
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(friendlyError(_error),
                              textAlign: TextAlign.center,
                              style:
                                  manrope(13, FontWeight.w600, color: cInk3)),
                          const SizedBox(height: 12),
                          QSoftButton(
                              label: tr('Повторить', 'Қайталау'),
                              onPressed: _load),
                        ]),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      children: [
                        _featuresSection(),
                        const SizedBox(height: 22),
                        _aiProviderSection(),
                        const SizedBox(height: 22),
                        _qaSection(),
                        const SizedBox(height: 22),
                        _limitsSection(),
                        const SizedBox(height: 22),
                        _linksSection(),
                      ],
                    ),
        ),
      ]),
    );
  }

  // ── AI провайдері ──────────────────────────────────────────────────────────

  Future<void> _setAiProvider(String v) async {
    if (_aiProviderSaving || v == _aiProvider) return;
    HapticFeedback.selectionClick();
    final prev = _aiProvider;
    setState(() {
      _aiProvider = v;
      _aiProviderSaving = true;
    });
    try {
      await _upsert('ai_provider', v);
      _snack(
          tr('Сохранено — применится в течение минуты',
              'Сақталды — бір минут ішінде күшіне енеді'),
          cGreen);
    } catch (e) {
      if (mounted) setState(() => _aiProvider = prev);
      _snack(friendlyError(e), cRed);
    } finally {
      if (mounted) setState(() => _aiProviderSaving = false);
    }
  }

  Widget _aiProviderSection() {
    Widget opt(String value, String titleRu, String titleKk, String subRu,
        String subKk, IconData icon) {
      final sel = _aiProvider == value;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(kR16),
          onTap: _aiProviderSaving ? null : () => _setAiProvider(value),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: sel ? cGreenTint : cSurface,
              borderRadius: BorderRadius.circular(kR16),
              border:
                  Border.all(color: sel ? cGreen : cLine, width: sel ? 1.6 : 1),
            ),
            child: Row(children: [
              Icon(icon, color: sel ? cGreen : cInk3, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(titleRu, titleKk),
                        style: manrope(14, FontWeight.w800, color: cInk)),
                    const SizedBox(height: 2),
                    Text(tr(subRu, subKk),
                        style: manrope(12, FontWeight.w500,
                            color: cInk2, height: 1.35)),
                  ],
                ),
              ),
              if (sel)
                const Icon(Icons.check_circle_rounded, color: cGreen, size: 22),
            ]),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      QSecLabel(tr('AI-провайдер', 'AI провайдері')),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
            tr('Через какой ИИ работают помощник, стилист, описание товара и примерка. Ключи хранятся в Supabase Secrets.',
                'Көмекші, стилист, тауар сипаттамасы және киіп көру қай AI арқылы жұмыс істейді. Кілттер Supabase Secrets-те.'),
            style: manrope(12.5, FontWeight.w500, color: cInk2, height: 1.4)),
      ),
      opt(
          'gemini',
          'Gemini (Google)',
          'Gemini (Google)',
          'Ключ GEMINI_API_KEY. Текст — бесплатный лимит; примерка (генерация фото) — только при включённой оплате в Google.',
          'GEMINI_API_KEY кілті. Мәтін — тегін лимит; киіп көру (сурет генерациясы) — тек Google-да төлем қосылғанда.',
          Icons.auto_awesome_rounded),
      opt(
          'anthropic',
          'Claude (Anthropic)',
          'Claude (Anthropic)',
          'Ключ ANTHROPIC_API_KEY. Если ключ не работает — автоматически Gemini. Примерка — через FASHN.',
          'ANTHROPIC_API_KEY кілті. Кілт жұмыс істемесе — автоматты Gemini. Киіп көру — FASHN арқылы.',
          Icons.psychology_alt_rounded),
      opt(
          'auto',
          'Автоматически',
          'Автоматты',
          'Claude, если есть ключ, иначе Gemini.',
          'Кілті болса Claude, әйтпесе Gemini.',
          Icons.tune_rounded),
    ]);
  }

  // ── 1. Функциялар ──────────────────────────────────────────────────────────

  Widget _featuresSection() {
    return ListenableBuilder(
      listenable: FeatureFlags.instance,
      builder: (context, _) {
        final ff = FeatureFlags.instance;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          QSecLabel(tr('Функции', 'Функциялар')),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
                tr('Выключенная функция скрывается в приложении и блокируется на сервере — даже в старых версиях.',
                    'Өшірілген функция қосымшада жасырылады және серверде бұғатталады — ескі нұсқада да.'),
                style:
                    manrope(12.5, FontWeight.w500, color: cInk2, height: 1.4)),
          ),
          // Күй app_settings-тен оқылған (_load) — экран жүктелгеннен кейін ғана
          // осы жерге жетеміз, сондықтан спиннер қажет емес.
          for (final f in _flagInfos) ...[
            _flagTile(
                f, _optimistic[f.name] ?? _flagDb[f.name] ?? ff.isOn(f.name)),
            const SizedBox(height: 10),
          ],
        ]);
      },
    );
  }

  Widget _flagTile(_FlagInfo f, bool on) {
    final busy = _optimistic.containsKey(f.name);
    return QCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          QIconTile(
            tone: f.tone,
            size: 40,
            icon: Icon(f.icon, size: 20, color: _toneInk(f.tone)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(f.titleRu, f.titleKk),
                    style: manrope(14.5, FontWeight.w800, color: cInk)),
                const SizedBox(height: 2),
                Text(tr(f.descRu, f.descKk),
                    style: manrope(12.5, FontWeight.w500,
                        color: cInk2, height: 1.35)),
              ],
            ),
          ),
          Switch.adaptive(
            value: on,
            activeThumbColor: Colors.white,
            activeTrackColor: cGreen,
            onChanged: busy ? null : (v) => _toggleFlag(f, v),
          ),
        ]),
        if (f.secrets.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, right: 6),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: cAmberTint,
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.key_rounded, size: 14, color: cAmberInk),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                      tr('Нужен ключ в secrets: ${f.secrets}. Без него функция не заработает.',
                          'Secrets-те кілт керек: ${f.secrets}. Онсыз функция жұмыс істемейді.'),
                      style: manrope(11.5, FontWeight.w600,
                          color: cAmberInk, height: 1.35)),
                ),
              ]),
            ),
          ),
      ]),
    );
  }

  Color _toneInk(String tone) {
    switch (tone) {
      case 'red':
        return cRedInk;
      case 'amber':
        return cAmberInk;
      case 'blue':
        return cBlueInk;
      case 'purple':
        return cPurpleInk;
      default:
        return cGreenDeep;
    }
  }

  // ── 2. Сұрақ-жауап ─────────────────────────────────────────────────────────

  Widget _qaSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      QSecLabel(tr('Вопросы по товарам', 'Тауар туралы сұрақтар')),
      QCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(tr('Вопросы и ответы публичные', 'Сұрақ-жауап жария'),
                  style: manrope(14.5, FontWeight.w800, color: cInk)),
            ),
            Switch.adaptive(
              value: _qaPublic,
              activeThumbColor: Colors.white,
              activeTrackColor: cGreen,
              onChanged: _qaSaving ? null : _toggleQa,
            ),
          ]),
          const SizedBox(height: 4),
          _modeLine(
            active: !_qaPublic,
            title: tr('Выключено (по умолчанию)', 'Өшірулі (әдепкі)'),
            text: tr(
                'Вопрос виден только задавшему его покупателю и магазину. Другие покупатели его не видят.',
                'Сұрақты тек оны қойған сатып алушы мен дүкен көреді. Басқа сатып алушыларға көрінбейді.'),
          ),
          const SizedBox(height: 6),
          _modeLine(
            active: _qaPublic,
            title: tr('Включено', 'Қосулы'),
            text: tr(
                'Вопросы и ответы показываются на странице товара всем покупателям.',
                'Сұрақ пен жауап тауар бетінде барлық сатып алушыға көрінеді.'),
          ),
        ]),
      ),
    ]);
  }

  Widget _modeLine(
      {required bool active, required String title, required String text}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        color: active ? cGreenTint : cBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? cGreen : cLine),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: manrope(12.5, FontWeight.w800,
                color: active ? cGreenDeep : cInk2)),
        const SizedBox(height: 2),
        Text(text,
            style: manrope(12, FontWeight.w500, color: cInk2, height: 1.35)),
      ]),
    );
  }

  // ── 3. AI лимиттері ────────────────────────────────────────────────────────

  Widget _limitsSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      QSecLabel(tr('AI-лимиты в сутки', 'AI тәуліктік лимиттері')),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
            tr('Сколько запросов в сутки может сделать один пользователь. 0 — запретить.',
                'Бір пайдаланушы тәулігіне неше сұрау жасай алады. 0 — тыйым салу.'),
            style: manrope(12.5, FontWeight.w500, color: cInk2, height: 1.4)),
      ),
      QCard(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: Column(children: [
          for (var i = 0; i < _limitInfos.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: cLine),
            _limitRow(_limitInfos[i]),
          ],
        ]),
      ),
    ]);
  }

  Widget _limitRow(_LimitInfo l) {
    final ctrl = _limitCtrl[l.key]!;
    final saving = _limitSaving.contains(l.key);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(
          child: Text(tr(l.ru, l.kk),
              style: manrope(13.5, FontWeight.w700, color: cInk)),
        ),
        SizedBox(
          width: 76,
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            maxLength: 6,
            style: manrope(14, FontWeight.w700, color: cInk),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              filled: true,
              fillColor: cBg,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: cLine)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: cLine)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: cGreen)),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 44,
          child: saving
              ? const Center(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: cGreen)))
              : IconButton(
                  tooltip: tr('Сохранить', 'Сақтау'),
                  onPressed: ctrl.text.trim() == '${_limitSaved[l.key]}'
                      ? null
                      : () => _saveLimit(l),
                  icon: const Icon(Icons.check_circle_rounded),
                  color: cGreen,
                ),
        ),
      ]),
    );
  }

  // ── 4. Басқа бөлімдер ──────────────────────────────────────────────────────

  Widget _linksSection() {
    void open(Widget screen) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      QSecLabel(tr('Связанные разделы', 'Байланысты бөлімдер')),
      QMenuItem(
        icon: Icons.support_agent_rounded,
        tone: 'green',
        title: tr('Чат поддержки', 'Қолдау чаты'),
        subtitle: tr('Обращения пользователей', 'Пайдаланушы өтініштері'),
        onTap: () => open(const SupportInboxScreen()),
      ),
      const SizedBox(height: 8),
      QMenuItem(
        icon: Icons.assignment_return_outlined,
        tone: 'blue',
        title: tr('Разрешение на невозвратные товары',
            'Қайтарылмайтын тауар рұқсаты'),
        subtitle: tr('Каким магазинам можно помечать товары',
            'Қай дүкендер тауарды белгілей алады'),
        onTap: () => open(const ReturnPolicyStoresScreen()),
      ),
      const SizedBox(height: 8),
      QMenuItem(
        icon: Icons.manage_accounts_outlined,
        tone: 'amber',
        title: tr('Запросы на изменение данных курьера',
            'Курьер деректерін өзгерту сұраулары'),
        subtitle: tr('Имя, телефон, город', 'Аты, телефон, қала'),
        onTap: () => open(const CourierChangeRequestsScreen()),
      ),
      const SizedBox(height: 8),
      // Жалауша өшік болса да көрінеді: тарифті қосар алдында толтырады.
      QMenuItem(
        icon: Icons.local_post_office_outlined,
        tone: 'purple',
        title: tr('Тарифы Казпочты', 'Казпочта тарифтері'),
        subtitle: tr('Цены по направлениям и включение доставки',
            'Бағыт бағалары және жеткізуді қосу'),
        onTap: () async {
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const KazpostTariffsScreen()));
          // Сол жалауша ол экранда да ауыстырылады: _flagDb ескірмесін.
          try {
            final row = await _sb
                .from('app_settings')
                .select('value')
                .eq('key', 'feature_${FeatureFlags.kazpostDelivery}')
                .maybeSingle();
            if (!mounted) return;
            setState(() => _flagDb[FeatureFlags.kazpostDelivery] =
                row?['value']?.toString() == 'true');
          } catch (_) {
            // Желі жоқ: қосқыш келесі ашқанда жаңарады.
          }
        },
      ),
    ]);
  }
}
