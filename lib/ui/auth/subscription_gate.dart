import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/lang.dart';
import '../../data/services/auth_service.dart';
import '../../theme/qoima_design.dart';
import '../admin/products/products_screen.dart';

/// «Заморозка» экраны: жазылым мерзімі өткеніне 3 күннен асқан дүкен иесі
/// (және оның сатушылары) осында тұрып қалады — ТЕК тауарларды көре алады,
/// ешқандай қосу/өшіру/өзгерту жоқ. Модератор жазылымды ұзартқанда
/// (қолданбаға қайта кіргенде) қалыпты режим оралады.
class SubscriptionFrozenScreen extends StatelessWidget {
  const SubscriptionFrozenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppUser>();
    final until = user.subscriptionUntil;
    final untilStr = until == null
        ? ''
        : '${until.day.toString().padLeft(2, '0')}.${until.month.toString().padLeft(2, '0')}.${until.year}';

    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        // ── Қызыл ескерту тақтасы ─────────────────────────────────────────
        Container(
          width: double.infinity,
          color: const Color(0xFFB11A2B),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 10, 14),
              child: Row(children: [
                const Icon(Icons.ac_unit_rounded,
                    color: Colors.white, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          user.isSeller
                              ? tr('Подписка магазина истекла',
                                  'Дүкен жазылымы аяқталды')
                              : tr('Подписка истекла — доступ заморожен',
                                  'Жазылым аяқталды — доступ тоқтатылды'),
                          style: manrope(15, FontWeight.w800,
                              color: Colors.white)),
                      const SizedBox(height: 2),
                      Text(
                          untilStr.isEmpty
                              ? tr('Товары доступны только для просмотра. Продлите подписку у модератора.',
                                  'Тауарлар тек қарау үшін. Модератордан жазылымды ұзартыңыз.')
                              : tr('Истекла $untilStr. Товары только для просмотра. Продлите подписку у модератора.',
                                  '$untilStr аяқталды. Тауарлар тек қарау үшін. Модератордан жазылымды ұзартыңыз.'),
                          style: manrope(12, FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.9),
                              height: 1.35)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => AuthService().signOut(),
                  tooltip: tr('Выйти', 'Шығу'),
                  icon: const Icon(Icons.logout_rounded,
                      color: Colors.white, size: 20),
                ),
              ]),
            ),
          ),
        ),
        // ── Тек оқу режимі: тауарлар тізімі (қосу/өңдеу батырмалары жоқ) ──
        const Expanded(child: ProductsScreen(readOnly: true)),
      ]),
    );
  }
}

/// Мерзім өткен (бірақ әлі «заморозка» емес, 0–3 күн) — қолданбаға кірген
/// сайын бір рет жабылатын (✕) ескерту диалогын көрсетеді.
class SubscriptionExpiryNotice extends StatefulWidget {
  final Widget child;
  const SubscriptionExpiryNotice({super.key, required this.child});

  @override
  State<SubscriptionExpiryNotice> createState() =>
      _SubscriptionExpiryNoticeState();
}

class _SubscriptionExpiryNoticeState extends State<SubscriptionExpiryNotice> {
  // Бір қолданба сессиясында бір-ақ рет көрсетеміз (uid-ге байланған —
  // басқа аккаунтпен қайта кірсе қайтадан шығады).
  static String _shownForUid = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  void _maybeShow() {
    if (!mounted) return;
    final user = context.read<AppUser>();
    if (!user.subExpired || user.subFrozen) return;
    if (_shownForUid == user.uid) return;
    _shownForUid = user.uid;

    final d = user.subExpiredDays ?? 0;
    final freezeIn = 4 - d; // d>3 болғанда «заморозка» → қалған күн
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        backgroundColor: cSurface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // ✕ жабу
            Align(
              alignment: Alignment.topRight,
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                      color: cLine2, shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded,
                      size: 17, color: cInk2),
                ),
              ),
            ),
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: cAmber.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.hourglass_bottom_rounded,
                  color: cAmber, size: 32),
            ),
            const SizedBox(height: 14),
            Text(
              context.read<AppUser>().isSeller
                  ? tr('Подписка магазина истекла', 'Дүкен жазылымы аяқталды')
                  : tr('Ваша подписка истекла', 'Жазылымыңыз аяқталды'),
              textAlign: TextAlign.center,
              style: manrope(17.5, FontWeight.w800, color: cInk),
            ),
            const SizedBox(height: 8),
            Text(
              freezeIn > 0
                  ? tr('Если не продлить, через $freezeIn дн. доступ будет заморожен: товары останутся только для просмотра.',
                      'Ұзартылмаса, $freezeIn күннен кейін доступ тоқтатылады: тауарлар тек қарауға қалады.')
                  : tr('Доступ будет заморожен сегодня: товары останутся только для просмотра.',
                      'Доступ бүгін тоқтатылады: тауарлар тек қарауға қалады.'),
              textAlign: TextAlign.center,
              style: manrope(13.5, FontWeight.w500, color: cInk2, height: 1.45),
            ),
            const SizedBox(height: 6),
            Text(
              tr('Для продления свяжитесь с модератором маркетплейса.',
                  'Ұзарту үшін маркетплейс модераторымен байланысыңыз.'),
              textAlign: TextAlign.center,
              style: manrope(12.5, FontWeight.w600, color: cInk3),
            ),
            const SizedBox(height: 16),
            QPrimaryButton(
              label: tr('Понятно', 'Түсінікті'),
              onPressed: () => Navigator.pop(ctx),
              height: 48,
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
