import 'dart:async';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/lang.dart';
import '../../core/supabase_config.dart';
import '../../data/services/auth_service.dart';
import '../../theme/qoima_design.dart';
import 'telegram_web_opener_stub.dart'
    if (dart.library.html) 'telegram_web_opener_web.dart';

/// Телефонды Telegram боты арқылы растайтын қайта қолданылатын виджет
/// (тіркелу + парольді қалпына келтіру). SMS-сіз, тегін.
///
/// Ағын: [AuthService.startTelegramVerification] → `t.me/<bot>?start=<token>`
/// ашылады → пайдаланушы ботта «Нөмірімді бөлісу» түймесін басады → виджет
/// [AuthService.checkTelegramVerification]-ті әр 2 сек сұрап отырады → расталса
/// [onVerified] (phone + token) шақырылады.
class TelegramVerifyButton extends StatefulWidget {
  /// Нөмір расталғанда: [phone] — E.164 (+7XXXXXXXXXX), [token] — растау токені
  /// (парольді қалпына келтіруде edge функцияға беру үшін қажет).
  final void Function(String phone, String token) onVerified;
  const TelegramVerifyButton({super.key, required this.onVerified});

  @override
  State<TelegramVerifyButton> createState() => _TelegramVerifyButtonState();
}

enum _VState { idle, waiting, verified }

class _TelegramVerifyButtonState extends State<TelegramVerifyButton> {
  final _auth = AuthService();
  _VState _state = _VState.idle;
  String? _token;
  String? _phone;
  String? _error;
  Timer? _poll;
  Timer? _timeout;

  @override
  void dispose() {
    _poll?.cancel();
    _timeout?.cancel();
    super.dispose();
  }

  void _stopPolling() {
    _poll?.cancel();
    _timeout?.cancel();
    _poll = null;
    _timeout = null;
  }

  Future<void> _start() async {
    setState(() {
      _state = _VState.waiting;
      _error = null;
    });
    // iOS/Safari-дегі попап-блокер: window.open тек пайдаланушы басқан
    // СӘТТЕ (асинхронды RPC-тен БҰРЫН) синхронды шақырылса ғана өтеді —
    // кейін шақырылса үнсіз бұғатталады. Сондықтан RPC-тен БҰРЫН бос
    // терезе ашамыз да, токен келгенде оны нақты URL-ге бағыттаймыз.
    final placeholderWin = kIsWeb ? openBlankWindow() : null;
    try {
      final token = await _auth.startTelegramVerification();
      _token = token;
      final url = SupabaseConfig.telegramStartUrl(token);
      if (kIsWeb) {
        navigateWindowTo(placeholderWin, url);
        _beginPolling();
      } else {
        final opened = await _openTelegram(token);
        // Поллингті бәрібір бастаймыз — пайдаланушы Telegram-ды орнатып
        // жатып та (немесе басқа құрылғыда) нөмірін растай алады.
        _beginPolling();
        if (!opened && mounted) {
          // tg:// ашылмады → Telegram орнатылмаған сияқты. Бұзылған t.me
          // сілтемесіне (DNS_PROBE_FINISHED_NXDOMAIN) лақтырмай, орнату
          // диалогын көрсетеміз.
          _showInstallTelegramDialog();
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _VState.idle;
        _error = tr('Не удалось открыть Telegram', 'Telegram ашылмады');
      });
    }
  }

  /// Мобильде Telegram қосымшасын `tg://` схемасымен ТІКЕЛЕЙ ашады — браузер
  /// де, `t.me` DNS-і де қатыспайды (сол себепті t.me бөгелген желіде де
  /// DNS_PROBE_FINISHED_NXDOMAIN болмайды). Сәтті ашылса `true`. Telegram
  /// орнатылмаса `false` — бұзылған t.me сілтемесіне АВТО лақтырмаймыз,
  /// оның орнына шақырушы орнату диалогын көрсетеді.
  Future<bool> _openTelegram(String token) async {
    try {
      final appUri = Uri.parse(SupabaseConfig.telegramAppUrl(token));
      return await launchUrl(appUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Telegram-ды қайта ашу (күту панелінен). Мобильде `tg://`, ашылмаса
  /// орнату диалогы. Веб-те синхронды жаңа терезе ашып, t.me-ге бағыттайды.
  Future<void> _reopen() async {
    final token = _token;
    if (token == null) return;
    if (kIsWeb) {
      final win = openBlankWindow();
      navigateWindowTo(win, SupabaseConfig.telegramStartUrl(token));
      return;
    }
    final opened = await _openTelegram(token);
    if (!opened && mounted) _showInstallTelegramDialog();
  }

  /// Telegram орнату сілтемесі — дүкендер (Play/App Store) домені t.me емес,
  /// сол себепті t.me бөгелген желіде де ашылады.
  String _installUrl() {
    if (kIsWeb) return 'https://telegram.org/dl';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'https://apps.apple.com/app/telegram-messenger/id686449807';
      case TargetPlatform.android:
        return 'https://play.google.com/store/apps/details?id=org.telegram.messenger';
      default:
        return 'https://telegram.org/dl';
    }
  }

  Future<void> _openInstall() async {
    final uri = Uri.parse(_installUrl());
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {/* фолбэк */}
    try {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (_) {/* қолмен ашсын */}
  }

  /// Telegram орнатылмаған кезде — бұзылған сілтеменің орнына анық диалог:
  /// ескерту баннері + «Telegram орнату» + «Қайта тексеру».
  void _showInstallTelegramDialog() {
    const tgBlue = Color(0xFF229ED9);
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: cSurface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Ескерту баннері ──
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: tgBlue.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: tgBlue.withValues(alpha: 0.18)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_rounded, color: tgBlue, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        tr(
                          'На устройстве нет Telegram. Подтверждение номера происходит через Telegram (без SMS, бесплатно). Установите Telegram и нажмите «Проверить снова».',
                          'Құрылғыда Telegram жоқ. Нөмірді растау Telegram арқылы жүреді (SMS-сіз, тегін). Telegram-ды орнатып, «Қайта тексеру» түймесін басыңыз.',
                        ),
                        style: manrope(13, FontWeight.w600, color: cInk2, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // ── «Telegram орнату» (көк) ──
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openInstall();
                  },
                  icon: const Icon(Icons.download_rounded,
                      color: Colors.white, size: 21),
                  label: Text(tr('Установить Telegram', 'Telegram орнату'),
                      style: manrope(15, FontWeight.w800, color: Colors.white)),
                  style: FilledButton.styleFrom(
                    backgroundColor: tgBlue,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // ── «Қайта тексеру» (ашық) — Telegram-ды қайта ашады ──
              SizedBox(
                height: 52,
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _reopen();
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: tgBlue.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                  ),
                  child: Text(tr('Проверить снова', 'Қайта тексеру'),
                      style: manrope(14.5, FontWeight.w700,
                          color: const Color(0xFF1B7FB0))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _beginPolling() {
    _stopPolling();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
    // 2 минут ішінде расталмаса — тоқтатамыз.
    _timeout = Timer(const Duration(minutes: 2), () {
      if (!mounted || _state == _VState.verified) return;
      _stopPolling();
      setState(() {
        _state = _VState.idle;
        _error = tr('Время истекло. Попробуйте снова.', 'Уақыт бітті. Қайта көріңіз.');
      });
    });
  }

  Future<void> _check() async {
    final token = _token;
    if (token == null) return;
    try {
      final res = await _auth.checkTelegramVerification(token);
      if (res.verified && res.phone != null && res.phone!.isNotEmpty) {
        _stopPolling();
        if (!mounted) return;
        setState(() {
          _state = _VState.verified;
          _phone = res.phone;
        });
        widget.onVerified(res.phone!, token);
      }
    } catch (_) {
      // Желі қатесінде поллингті жалғастыра береміз.
    }
  }

  void _reset() {
    _stopPolling();
    setState(() {
      _state = _VState.idle;
      _token = null;
      _phone = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_state == _VState.verified)
          _VerifiedBox(phone: _phone ?? '', onChange: _reset)
        else if (_state == _VState.waiting)
          kIsWeb
              ? _WebWaitingBox(
                  token: _token ?? '',
                  onOpen: _reopen,
                  onCancel: _reset)
              : _WaitingBox(
                  onCheck: _check,
                  onCancel: _reset,
                  onReopen: _reopen,
                  onInstall: _openInstall)
        else
          _IdleButton(onTap: _start),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: manrope(12.5, FontWeight.w600, color: cRed)),
        ],
      ],
    );
  }
}

// ── Idle: «Telegram арқылы растау» түймесі ────────────────────────────────────
class _IdleButton extends StatelessWidget {
  final VoidCallback onTap;
  const _IdleButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: const Color(0xFF229ED9).withValues(alpha: 0.08),
          side: const BorderSide(color: Color(0xFF229ED9), width: 1.5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.send_rounded, color: Color(0xFF229ED9), size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                tr('Подтвердить номер через Telegram', 'Telegram арқылы нөмірді растау'),
                style: manrope(14.5, FontWeight.w700, color: const Color(0xFF1B7FB0)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Waiting: Telegram-да нөмірді бөлісуді күтеміз ─────────────────────────────
class _WaitingBox extends StatelessWidget {
  final VoidCallback onCheck;
  final VoidCallback onCancel;
  final VoidCallback onReopen;
  final VoidCallback onInstall;
  const _WaitingBox({
    required this.onCheck,
    required this.onCancel,
    required this.onReopen,
    required this.onInstall,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF229ED9).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF229ED9).withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        Row(children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Color(0xFF229ED9)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tr('Откройте Telegram и нажмите «Поделиться номером»',
                  'Telegram-ды ашып, «Нөмірімді бөлісу» түймесін басыңыз'),
              style: manrope(13, FontWeight.w600, color: cInk2, height: 1.4),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextButton(
              onPressed: onCheck,
              child: Text(tr('Я подтвердил', 'Растадым'),
                  style: manrope(13.5, FontWeight.w700, color: const Color(0xFF1B7FB0))),
            ),
          ),
          Expanded(
            child: TextButton(
              onPressed: onCancel,
              child: Text(tr('Отмена', 'Болдырмау'),
                  style: manrope(13.5, FontWeight.w600, color: cInk3)),
            ),
          ),
        ]),
        // Telegram ашылмады ма? (t.me бөгелген / қосымша жоқ) — қалпына келтіру
        const Divider(height: 18),
        Row(children: [
          Expanded(
            child: Text(
              tr('Telegram не открылся?', 'Telegram ашылмады ма?'),
              style: manrope(12, FontWeight.w600, color: cInk3),
            ),
          ),
          GestureDetector(
            onTap: onReopen,
            child: Text(tr('Открыть снова', 'Қайта ашу'),
                style: manrope(12.5, FontWeight.w700, color: const Color(0xFF1B7FB0))),
          ),
          const SizedBox(width: 14),
          GestureDetector(
            onTap: onInstall,
            child: Text(tr('Установить', 'Орнату'),
                style: manrope(12.5, FontWeight.w700, color: const Color(0xFF1B7FB0))),
          ),
        ]),
      ]),
    );
  }
}

// ── Waiting (ВЕБ): t.me бөгелген желіге арналған қолмен растау фолбэгі ──────────
// Веб-те браузер `t.me` доменін шеше алмауы мүмкін (DNS_PROBE_FINISHED_NXDOMAIN).
// Сондықтан «Telegram-ды ашу» түймесімен қатар ботты + `/start <токен>` кодын
// көрсетеміз: қолданушы Telegram-ды кез келген құрылғыда қолмен ашып, ботты
// тауып, кодты жіберсе — растау бәрібір өтеді (поллинг байқайды).
class _WebWaitingBox extends StatelessWidget {
  final String token;
  final VoidCallback onOpen;
  final VoidCallback onCancel;
  const _WebWaitingBox({
    required this.token,
    required this.onOpen,
    required this.onCancel,
  });

  String get _botHandle => '@${SupabaseConfig.telegramBot}';
  String get _startCode => '/start $token';

  @override
  Widget build(BuildContext context) {
    const tgBlue = Color(0xFF229ED9);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tgBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: tgBlue.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── Нұсқаулық ──
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_rounded, color: tgBlue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr(
                'Нажмите в Telegram кнопку «Поделиться номером». Не открылось — нажмите кнопку ниже ещё раз. Ждём подтверждение…',
                'Telegram-да «Нөмірімді бөлісу» түймесін басыңыз. Ашылмаса — төмендегі түймені қайта басыңыз. Растауды күтудеміз…',
              ),
              style: manrope(13, FontWeight.w600, color: cInk2, height: 1.4),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        // ── «Telegram-ды ашу» ──
        SizedBox(
          height: 54,
          child: FilledButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            label: Text(tr('Открыть Telegram', 'Telegram-ды ашу'),
                style: manrope(15.5, FontWeight.w800, color: Colors.white)),
            style: FilledButton.styleFrom(
              backgroundColor: tgBlue,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // ── Күту статусы ──
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: tgBlue),
          ),
          const SizedBox(width: 8),
          Text(tr('Ждём подтверждение…', 'Растауды күтудеміз…'),
              style: manrope(12.5, FontWeight.w600, color: cInk3)),
        ]),
        const Divider(height: 22),
        // ── Қолмен растау фолбэгі ──
        Text(
          tr(
            'Ссылка не открывается (бывает в сетях, где Telegram заблокирован): откройте приложение Telegram вручную, найдите бота ниже и отправьте код.',
            'Сілтеме ашылмаса (Telegram веб-те бұғатталған желілерде болады): Telegram қолданбасын қолмен ашып, төмендегі ботты іздеп, кодты жіберіңіз.',
          ),
          style: manrope(12, FontWeight.w500, color: cInk3, height: 1.4),
        ),
        const SizedBox(height: 10),
        _CopyField(label: tr('Бот', 'Бот'), value: _botHandle),
        const SizedBox(height: 8),
        _CopyField(label: tr('Код', 'Код'), value: _startCode),
        const SizedBox(height: 4),
        Center(
          child: TextButton(
            onPressed: onCancel,
            child: Text(tr('Отмена', 'Болдырмау'),
                style: manrope(13, FontWeight.w600, color: cInk3)),
          ),
        ),
      ]),
    );
  }
}

// ── Көшірілетін өріс (бот / код) ──────────────────────────────────────────────
class _CopyField extends StatelessWidget {
  final String label;
  final String value;
  const _CopyField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cLine),
      ),
      child: Row(children: [
        Text('$label: ',
            style: manrope(13, FontWeight.w700, color: cInk)),
        Expanded(
          child: Text(value,
              style: manrope(12.5, FontWeight.w600, color: cInk2),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: const Icon(Icons.copy_rounded, size: 18, color: cInk3),
          tooltip: tr('Копировать', 'Көшіру'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(tr('Скопировано', 'Көшірілді'),
                  style: manrope(13, FontWeight.w600, color: Colors.white)),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ));
          },
        ),
      ]),
    );
  }
}

// ── Verified: жасыл растау белгісі ────────────────────────────────────────────
class _VerifiedBox extends StatelessWidget {
  final String phone;
  final VoidCallback onChange;
  const _VerifiedBox({required this.phone, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cGreenTint,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: cGreen.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        const Icon(Icons.verified_rounded, color: cGreen, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Номер подтверждён', 'Нөмір расталды'),
                style: manrope(12, FontWeight.w600, color: cInk2)),
            Text(phone, style: manrope(15.5, FontWeight.w800, color: cInk)),
          ]),
        ),
        GestureDetector(
          onTap: onChange,
          child: Text(tr('Изменить', 'Өзгерту'),
              style: manrope(13, FontWeight.w700, color: cGreen)),
        ),
      ]),
    );
  }
}
