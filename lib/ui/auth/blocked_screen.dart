import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../data/services/auth_service.dart';
import '../../theme/qoima_design.dart';

import '../../core/lang.dart';
/// Жалпы блок экраны: superadmin блоктаған дүкен иесі/сатушысы осында тұрып
/// қалады — ешқандай әрекет жоқ. Иесі блокталған seller «Открепиться» арқылы
/// босап шығып, басқа дүкенге қосыла алады (reactive gate → SellerJoinScreen).
class BlockedScreen extends StatefulWidget {
  const BlockedScreen({super.key});

  @override
  State<BlockedScreen> createState() => _BlockedScreenState();
}

class _BlockedScreenState extends State<BlockedScreen> {
  final _authService = AuthService();
  bool _busy = false;

  Future<void> _detach() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(tr('Открепиться от магазина?', 'Дүкеннен ажырау керек пе?'),
            style: manrope(16, FontWeight.w800, color: cInk)),
        content: Text(
            tr('Вы будете откреплены от текущего владельца и сможете '
                    'присоединиться к другому магазину по бизнес-коду.',
                'Ағымдағы иесінен ажырайсыз және бизнес-код арқылы '
                    'басқа дүкенге қосыла аласыз.'),
            style: manrope(13.5, FontWeight.w500, color: cInk2, height: 1.4)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Отмена', 'Болдырмау'),
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('Открепиться', 'Ажырау'),
                  style: manrope(14, FontWeight.w700, color: cGreen))),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await _authService.detachFromOwner();
      if (!mounted) return;
      // Gate реактивті — joinStatus 'none' болған соң SellerJoinScreen ашылады.
      context.read<AppUser>().detachedFromOwner();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('Не удалось открепиться. Повторите позже', 'Ажырау сәтсіз болды. Кейінірек қайталаңыз')),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    await _authService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final appUser = context.watch<AppUser>();
    final byOwner = appUser.blockSource == 'owner';
    final reason = appUser.blockReason;

    return Scaffold(
      backgroundColor: cBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(26, 30, 26, 30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: const BoxDecoration(
                      color: cRedTint, shape: BoxShape.circle),
                  child: const Icon(Icons.lock_rounded, color: cRed, size: 42),
                ),
                const SizedBox(height: 22),
                Text(
                  byOwner
                      ? tr('Магазин заблокирован', 'Дүкен блокталған')
                      : tr('Аккаунт заблокирован', 'Аккаунт блокталған'),
                  textAlign: TextAlign.center,
                  style: manrope(21, FontWeight.w800, color: cInk),
                ),
                const SizedBox(height: 10),
                Text(
                  byOwner
                      ? tr(
                          'Владелец вашего магазина заблокирован модератором. '
                              'Все действия недоступны.',
                          'Дүкеніңіздің иесін модератор блоктаған. '
                              'Барлық әрекет қолжетімсіз.')
                      : tr(
                          'Ваш аккаунт заблокирован модератором маркетплейса. '
                              'Все действия недоступны.',
                          'Аккаунтыңызды маркетплейс модераторы блоктаған. '
                              'Барлық әрекет қолжетімсіз.'),
                  textAlign: TextAlign.center,
                  style: manrope(14, FontWeight.w500, color: cInk2, height: 1.5),
                ),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cRedTint,
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: cRed.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Причина блокировки', 'Блоктау себебі'),
                            style:
                                manrope(12, FontWeight.w800, color: cRed)),
                        const SizedBox(height: 4),
                        Text(reason,
                            style: manrope(13.5, FontWeight.w600,
                                color: cInk, height: 1.4)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 26),
                if (byOwner && appUser.isSeller) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : _detach,
                      icon: const Icon(Icons.link_off_rounded, size: 19),
                      label: Text(tr('Открепиться от магазина', 'Дүкеннен ажырау'),
                          style: manrope(15, FontWeight.w700,
                              color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(tr('Вы сможете присоединиться к другому магазину', 'Басқа дүкенге қосыла аласыз'),
                      style: manrope(12, FontWeight.w500, color: cInk3)),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _signOut,
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: Text(tr('Выйти из аккаунта', 'Аккаунттан шығу'),
                        style: manrope(14.5, FontWeight.w700, color: cInk2)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cInk2,
                      side: const BorderSide(color: cLine, width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
