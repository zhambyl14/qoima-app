import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/warehouse_context.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/qoima_design.dart';

import '../../core/lang.dart';

/// Сатушының дүкен мүшелігі: қоймасы қайсы, «Мой склад» батырмасы бұрын
/// (пайдасыз) тек тауар тізімін оқуға ашатын — енді осы жерге ауыстырылды.
/// Дүкеннен шығу — owner мақұлдауын қажет ететін сұраныс (self-service
/// «Открепиться» тек блокталған кезде ғана болады, [[blocked_screen]]).
class SellerShopMembershipScreen extends StatefulWidget {
  const SellerShopMembershipScreen({super.key});

  @override
  State<SellerShopMembershipScreen> createState() =>
      _SellerShopMembershipScreenState();
}

class _SellerShopMembershipScreenState
    extends State<SellerShopMembershipScreen> {
  final _service = FirestoreService();
  bool _busy = false;

  Future<void> _requestLeave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(tr('Покинуть магазин?', 'Дүкеннен шығасыз ба?'),
            style: manrope(16, FontWeight.w800, color: cInk)),
        content: Text(
            tr(
                'Заявка будет отправлена владельцу магазина. После его '
                    'подтверждения вы будете выведены из аккаунта и сможете '
                    'присоединиться к другому магазину.',
                'Сұраныс дүкен иесіне жіберіледі. Ол растаған соң аккаунттан '
                    'шығасыз және басқа дүкенге қосыла аласыз.'),
            style: manrope(13.5, FontWeight.w500, color: cInk2, height: 1.4)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Отмена', 'Болдырмау'),
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('Отправить', 'Жіберу'),
                  style: manrope(14, FontWeight.w700, color: cRed))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _service.requestLeaveShop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('Не удалось отправить заявку. Повторите позже',
              'Сұранысты жіберу сәтсіз. Кейінірек қайталаңыз')),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelLeave() async {
    setState(() => _busy = true);
    try {
      await _service.cancelLeaveRequest();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('Не удалось отменить заявку', 'Сұранысты болдырмау сәтсіз')),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appUser = context.watch<AppUser>();
    final wCtx = context.watch<WarehouseContext>();
    final warehouseName = wCtx.current?.name ?? '';

    return Scaffold(
      backgroundColor: cBg,
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Container(
            decoration: const BoxDecoration(gradient: kGrad),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 38,
                      height: 38,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.chevron_left_rounded,
                          color: Colors.white, size: 22),
                    ),
                  ),
                  Text(tr('Мой магазин', 'Менің дүкенім'),
                      style: manrope(20, FontWeight.w800,
                          color: Colors.white, letterSpacing: -0.4)),
                ]),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
              delegate: SliverChildListDelegate([
            QCard(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                QIconTile(
                    icon: const Icon(Icons.storefront_rounded,
                        color: cGreen, size: 20),
                    tone: 'green'),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Ваш склад', 'Сіздің қоймаңыз'),
                          style: manrope(12, FontWeight.w600, color: cInk3)),
                      Text(warehouseName.isNotEmpty ? warehouseName : '—',
                          style: manrope(15.5, FontWeight.w800, color: cInk)),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            QCard(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                QIconTile(
                    icon: const Icon(Icons.person_rounded,
                        color: cInk2, size: 20),
                    tone: 'ink'),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Ваш статус', 'Мәртебеңіз'),
                          style: manrope(12, FontWeight.w600, color: cInk3)),
                      Text(
                          appUser.joinStatus == 'active'
                              ? tr('Активен', 'Белсенді')
                              : appUser.joinStatus,
                          style: manrope(15.5, FontWeight.w800, color: cInk)),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),

            StreamBuilder<String?>(
              stream: _service.watchOwnJoinRequestStatus(),
              builder: (_, snap) {
                final status = snap.data;
                if (status == 'leave_pending') {
                  return Column(children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cAmberTint,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cAmber.withValues(alpha: 0.35)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.hourglass_top_rounded,
                            color: cAmber, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                              tr(
                                  'Заявка на выход отправлена. Ждите подтверждения владельца магазина.',
                                  'Шығу сұранысы жіберілді. Дүкен иесінің растауын күтіңіз.'),
                              style: manrope(13, FontWeight.w600, color: cInk)),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton(
                        onPressed: _busy ? null : _cancelLeave,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cInk2,
                          side: const BorderSide(color: cLine, width: 1.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15)),
                        ),
                        child: Text(tr('Отменить заявку', 'Сұранысты болдырмау'),
                            style: manrope(14.5, FontWeight.w700, color: cInk2)),
                      ),
                    ),
                  ]);
                }
                return SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _requestLeave,
                    icon: const Icon(Icons.logout_rounded, size: 19, color: cRed),
                    label: Text(tr('Покинуть магазин', 'Дүкеннен шығу'),
                        style: manrope(15, FontWeight.w700, color: cRed)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: cRed, width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 6),
            Text(
                tr('После подтверждения владельцем вы автоматически выйдете из аккаунта',
                    'Иесі растаған соң аккаунттан автоматты шығасыз'),
                textAlign: TextAlign.center,
                style: manrope(12, FontWeight.w500, color: cInk3)),
          ])),
        ),
      ]),
    );
  }
}
