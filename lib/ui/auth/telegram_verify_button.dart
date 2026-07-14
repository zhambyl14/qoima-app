import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
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
      } else {
        await _openTelegram(token, url);
      }
      _beginPolling();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _VState.idle;
        _error = tr('Не удалось открыть Telegram', 'Telegram ашылмады');
      });
    }
  }

  /// Мобильде Telegram-ды ашады. Алдымен `tg://` схемасы (Telegram қосымшасын
  /// ТІКЕЛЕЙ ашады — браузер де, `t.me` DNS-і де қатыспайды, сол себепті
  /// t.me бөгелген желіде DNS_PROBE_FINISHED_NXDOMAIN болмайды). Қосымша
  /// орнатылмаған болса ғана `https://t.me/...`-ке (браузер) түсеміз.
  Future<void> _openTelegram(String token, String webUrl) async {
    final appUri = Uri.parse(SupabaseConfig.telegramAppUrl(token));
    final webUri = Uri.parse(webUrl);
    bool ok = false;
    try {
      ok = await launchUrl(appUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (ok) return;
    // Telegram қосымшасы жоқ — веб-сілтемеге түсеміз.
    ok = await launchUrl(webUri, mode: LaunchMode.externalApplication);
    if (!ok) {
      await launchUrl(webUri, mode: LaunchMode.platformDefault);
    }
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
          _WaitingBox(onCheck: _check, onCancel: _reset)
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
  const _WaitingBox({required this.onCheck, required this.onCancel});

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
