import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_user.dart';
import '../../../core/error_text.dart';
import '../../../core/feature_flags.dart';
import '../../../core/lang.dart';
import '../../../data/services/follow_service.dart';
import '../../../theme/qoima_design.dart';
import '../../shared/require_login.dart';

/// «12 подписчиков» / «12 жазылушы». Орыс көпше түрлері: 1 подписчик,
/// 2–4 подписчика, 5+ подписчиков (11–14 — әрқашан «подписчиков»).
String followersLabel(int n) {
  if (n < 0) n = 0;
  final mod10 = n % 10;
  final mod100 = n % 100;
  final ru = (mod10 == 1 && mod100 != 11)
      ? 'подписчик'
      : (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14))
          ? 'подписчика'
          : 'подписчиков';
  return tr('$n $ru', '$n жазылушы');
}

/// «Подписаться / Жазылу» батырмасы (0084): дүкен бетінің тақырыбында (толық)
/// және дүкендер тізімінің карточкасында ([compact]).
///
/// - Жалауша `store_follow` өшік болса — мүлде көрінбейді.
/// - Дүкеннің өз иесі/сатушысына көрінбейді (сервер де бас тартады).
/// - Гость басса — қосымшаның қалыпты «Кіру қажет» диалогы.
/// - Оптимистік UI: бірден ауысады, қате болса қайтады + friendlyError.
/// - Жазылған соң қоңырау белгісі хабарламаны қосып/өшіреді (set_follow_notify).
class StoreFollowButton extends StatefulWidget {
  final String storeUid; // stores.admin_uid
  final bool compact;

  /// Жасыл градиент тақырып үстінде (ақ түсті) ме.
  final bool onDark;

  /// Сәтті жазылу/шығудан кейін (санауышты жаңарту үшін).
  final ValueChanged<bool>? onChanged;

  /// Тек тест үшін.
  final FollowService? service;

  const StoreFollowButton({
    super.key,
    required this.storeUid,
    this.compact = false,
    this.onDark = false,
    this.onChanged,
    this.service,
  });

  @override
  State<StoreFollowButton> createState() => _StoreFollowButtonState();
}

class _StoreFollowButtonState extends State<StoreFollowButton> {
  bool? _optFollow; // сервер жауабына дейінгі күту мәні
  bool? _optNotify;
  bool _busy = false;

  FollowService get _svc => widget.service ?? FollowService.instance;

  bool get _following => _optFollow ?? _svc.isFollowing(widget.storeUid);
  bool get _notify => _optNotify ?? _svc.notifyEnabled(widget.storeUid);

  @override
  void initState() {
    super.initState();
    // Тізім жүктелмесе «жазылған ба» білінбейді. Кэш бөліседі: бір сұраныс.
    if (AppUser.current.uid.isNotEmpty) {
      _svc.loadMyFollows().catchError((_) {});
    }
  }

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? cRed : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _toggleFollow() async {
    if (_busy) return;
    final ok = await requireLogin(
      context,
      reasonRu: 'Войдите, чтобы подписаться на магазин.',
      reasonKk: 'Дүкенге жазылу үшін кіріңіз.',
    );
    if (!ok || !mounted) return;
    final next = !_following;
    // Толық нұсқада кездейсоқ басып жазылудан шығып кетпеу үшін сұраймыз.
    if (!next && !widget.compact) {
      final sure = await _confirmUnfollow();
      if (sure != true || !mounted) return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _busy = true;
      _optFollow = next;
      if (next) _optNotify = true; // жаңа жазылу әдепкіде хабарламамен
    });
    try {
      if (next) {
        await _svc.follow(widget.storeUid);
      } else {
        await _svc.unfollow(widget.storeUid);
      }
      widget.onChanged?.call(next);
    } catch (e) {
      _toast(friendlyError(e), error: true);
      // Нәтиже белгісіз болуы мүмкін (желі үзілді) — сервер күйін қайта оқимыз.
      _svc.loadMyFollows(force: true).catchError((_) {});
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _optFollow = null;
          _optNotify = null;
        });
      }
    }
  }

  Future<bool?> _confirmUnfollow() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: cSurface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(tr('Отписаться от магазина?', 'Дүкеннен шығасыз ба?'),
              style: manrope(16, FontWeight.w800, color: cInk)),
          content: Text(
              tr('Вы перестанете видеть его эфиры и сторис на главной и получать уведомления.',
                  'Басты беттегі эфирі мен сторисі көрінбейді, хабарлама келмейді.'),
              style: manrope(13.5, FontWeight.w500, color: cInk2)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Отмена', 'Болдырмау'),
                    style: manrope(14, FontWeight.w600, color: cInk2))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('Отписаться', 'Шығу'),
                    style: manrope(14, FontWeight.w700, color: cRed))),
          ],
        ),
      );

  Future<void> _toggleNotify() async {
    if (_busy) return;
    final next = !_notify;
    setState(() {
      _busy = true;
      _optNotify = next;
    });
    try {
      await _svc.setNotify(widget.storeUid, next);
      _toast(next
          ? tr('Уведомления включены', 'Хабарламалар қосылды')
          : tr('Уведомления выключены', 'Хабарламалар өшірілді'));
    } catch (e) {
      _toast(friendlyError(e), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _optNotify = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([FeatureFlags.instance, _svc]),
      builder: (_, __) {
        if (!FeatureFlags.instance.isOn(FeatureFlags.storeFollow)) {
          return const SizedBox.shrink();
        }
        final me = AppUser.current;
        // Өз дүкеніне жазылмайды (иесі де, сатушы да осы кілтпен тұр).
        if (me.uid.isNotEmpty && me.ownerUid == widget.storeUid) {
          return const SizedBox.shrink();
        }
        return widget.compact ? _compact() : _full();
      },
    );
  }

  // ── Карточкадағы шағын нұсқа ───────────────────────────────────────────────
  Widget _compact() {
    final on = _following;
    return Padding(
      padding: const EdgeInsets.only(top: 8), // картаның соңғы жолынан бөлу
      child: Semantics(
        button: true,
        label:
            on ? tr('Вы подписаны', 'Жазылдыңыз') : tr('Подписаться', 'Жазылу'),
        child: GestureDetector(
          key: const ValueKey('follow-compact'),
          behavior: HitTestBehavior.opaque,
          onTap: _toggleFollow,
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: on ? cGreenTint : cGreen,
              borderRadius: BorderRadius.circular(kRPill),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(on ? Icons.check_rounded : Icons.add_rounded,
                  size: 14, color: on ? cGreenDeep : Colors.white),
              const SizedBox(width: 4),
              Text(
                  on
                      ? tr('Вы подписаны', 'Жазылдыңыз')
                      : tr('Подписаться', 'Жазылу'),
                  style: manrope(11.5, FontWeight.w800,
                      color: on ? cGreenDeep : Colors.white)),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Дүкен бетінің тақырыбындағы толық нұсқа ────────────────────────────────
  Widget _full() {
    final on = _following;
    final dark = widget.onDark;
    final bg = on
        ? (dark ? Colors.white.withValues(alpha: 0.18) : cGreenTint)
        : (dark ? Colors.white : cGreen);
    final fg = on
        ? (dark ? Colors.white : cGreenDeep)
        : (dark ? cGreenDeep : Colors.white);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        key: const ValueKey('follow-main'),
        behavior: HitTestBehavior.opaque,
        onTap: _toggleFollow,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(kRPill),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (!on) Icon(Icons.add_rounded, size: 17, color: fg),
            if (!on) const SizedBox(width: 4),
            Text(
                on
                    ? tr('Вы подписаны ✓', 'Жазылдыңыз ✓')
                    : tr('Подписаться', 'Жазылу'),
                style: manrope(13, FontWeight.w800, color: fg)),
          ]),
        ),
      ),
      if (on) ...[
        const SizedBox(width: 8),
        Tooltip(
          message: _notify
              ? tr('Выключить уведомления', 'Хабарламаны өшіру')
              : tr('Включить уведомления', 'Хабарламаны қосу'),
          child: GestureDetector(
            key: const ValueKey('follow-bell'),
            behavior: HitTestBehavior.opaque,
            onTap: _toggleNotify,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: dark ? Colors.white.withValues(alpha: 0.18) : cGreenTint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                  _notify
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_off_outlined,
                  size: 18,
                  color: dark ? Colors.white : cGreenDeep),
            ),
          ),
        ),
      ],
    ]);
  }
}
