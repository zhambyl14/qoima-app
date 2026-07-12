import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/lang.dart';
import '../../core/supabase_config.dart';
import '../../data/services/auth_service.dart';
import '../../theme/qoima_design.dart';

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
    try {
      final token = await _auth.startTelegramVerification();
      _token = token;
      final uri = Uri.parse(SupabaseConfig.telegramStartUrl(token));
      // Telegram қосымшасын (мобильде) немесе браузер бетін (вебте) ашамыз.
      // Вебте жаңа бетте ашылады (_blank), мобильде — сыртқы қосымша.
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
      if (!ok) {
        await launchUrl(uri,
            mode: LaunchMode.platformDefault, webOnlyWindowName: '_blank');
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
