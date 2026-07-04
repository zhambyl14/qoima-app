import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/warehouse_context.dart';
import '../../core/contact_utils.dart';
import '../../core/locale_context.dart';
import '../../core/l10n_ext.dart';
import '../../data/models/models.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/qoima_design.dart';
import '../admin/settings/sellers_screen.dart';
import '../admin/settings/warehouses_screen.dart';
import '../../data/repositories/my_store_repository.dart';
import '../admin/my_store/admin_my_store_hub_screen.dart';
import '../onboarding/my_store_gate.dart';
import '../auth/account_security_screen.dart';

import '../../core/lang.dart';
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final appUser = context.watch<AppUser>();
    final name = appUser.name;
    final email = appUser.email;
    final isAdmin = appUser.isAdmin;
    final initials = name
        .trim()
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .take(2)
        .join();
    final service = FirestoreService();
    final wCtx = context.watch<WarehouseContext>();
    final warehouseName = wCtx.current?.name ?? '';

    return Scaffold(
      backgroundColor: cBg,
      body: CustomScrollView(slivers: [
        // ── Header ──────────────────────────────────────────────────────
        SliverToBoxAdapter(
            child: Container(
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFF00713F), Color(0xFF00A862)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight)),
          child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
                child: Column(children: [
                  // Bell icon (admin only)
                  if (isAdmin)
                    Align(
                      alignment: Alignment.centerRight,
                      child: StreamBuilder<List<Map<String, dynamic>>>(
                        stream: service.watchPendingRequests(),
                        builder: (_, snap) {
                          final count = snap.data?.length ?? 0;
                          return GestureDetector(
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const SellersScreen())),
                            child: Stack(clipBehavior: Clip.none, children: [
                              Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10)),
                                  child: const Icon(
                                      Icons.notifications_outlined,
                                      color: Colors.white,
                                      size: 20)),
                              if (count > 0)
                                Positioned(
                                    right: -2,
                                    top: -2,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                          color: Color(0xFFEF4444),
                                          shape: BoxShape.circle),
                                      child: Text('$count',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700)),
                                    )),
                            ]),
                          );
                        },
                      ),
                    ),
                  Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                              width: 2)),
                      child: Center(
                          child: Text(initials.isEmpty ? '?' : initials,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700)))),
                  const SizedBox(height: 12),
                  Text(name.isEmpty ? '...' : name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(email,
                      style:
                          const TextStyle(color: Colors.white60, fontSize: 13)),
                  const SizedBox(height: 10),
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3))),
                      child: Text(
                        isAdmin
                            ? l.adminBadge
                            : (warehouseName.isNotEmpty
                                ? '${l.sellerBadge} · $warehouseName'
                                : l.sellerBadge),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      )),

                  // Бизнес-код карточка (тек admin үшін)
                  if (isAdmin && appUser.businessCode.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25))),
                      child: Column(children: [
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(children: [
                                const Icon(Icons.vpn_key_rounded,
                                    color: Colors.white70, size: 14),
                                const SizedBox(width: 6),
                                Text(l.businessCode,
                                    style: const TextStyle(
                                        color: Colors.white60, fontSize: 11)),
                              ]),
                              GestureDetector(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(
                                      text: appUser.businessCode));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(l.businessCodeCopied),
                                      duration: const Duration(seconds: 2),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                                child: Row(children: [
                                  const Icon(Icons.copy_rounded,
                                      color: Colors.white60, size: 13),
                                  const SizedBox(width: 4),
                                  Text(l.copy,
                                      style: const TextStyle(
                                          color: Colors.white60, fontSize: 11)),
                                ]),
                              ),
                            ]),
                        const SizedBox(height: 8),
                        Text(
                          _formatCode(appUser.businessCode),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 8),
                        ),
                      ]),
                    ),
                  ],
                ]),
              )),
        )),

        // ── Меню ────────────────────────────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
              delegate: SliverChildListDelegate([
            const SizedBox(height: 8),

            // ── Seller stats ──────────────────────────────────────────────
            if (!isAdmin) ...[
              StreamBuilder<List<SaleModel>>(
                stream: service.watchSalesHistory(),
                builder: (_, snap) {
                  final now = DateTime.now();
                  final mySales = (snap.data ?? [])
                      .where((s) =>
                          s.sellerId == appUser.uid &&
                          s.saleDate.month == now.month &&
                          s.saleDate.year == now.year)
                      .toList();
                  final total =
                      mySales.fold<double>(0, (a, b) => a + b.totalPrice);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      QSecLabel(tr('Статистика за месяц', 'Айлық статистика')),
                      Row(children: [
                        Expanded(
                          child: QCard(
                            padding: const EdgeInsets.all(15),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${mySales.length}',
                                    style: manrope(22, FontWeight.w800,
                                        color: cInk)),
                                Text(tr('Продаж за месяц', 'Айдағы сатылым'),
                                    style: manrope(12, FontWeight.w600,
                                        color: cInk3)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: QCard(
                            padding: const EdgeInsets.all(15),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(money(total),
                                    style: manrope(18, FontWeight.w800,
                                        color: cGreen)),
                                Text(tr('Выручка, ₸', 'Түсім, ₸'),
                                    style: manrope(12, FontWeight.w600,
                                        color: cInk3)),
                              ],
                            ),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),
              QSecLabel(tr('Настройки', 'Баптаулар')),
              QMenuItem(
                icon: Icons.storefront_outlined,
                tone: 'blue',
                title: tr('Мой склад', 'Менің қоймам'),
                subtitle: warehouseName.isNotEmpty ? warehouseName : null,
                value: warehouseName.isNotEmpty ? tr('Привязан', 'Байланған') : null,
              ),
              const SizedBox(height: 8),
              QMenuItem(
                icon: Icons.shield_outlined,
                tone: 'green',
                title: tr('Личные данные', 'Жеке деректер'),
                subtitle: tr('Email, пароль', 'Email, құпиясөз'),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AccountSecurityScreen())),
              ),
              const SizedBox(height: 8),
              QMenuItem(
                icon: Icons.language_rounded,
                tone: 'ink',
                title: l.language,
                value: context.watch<LocaleContext>().locale.languageCode ==
                        'kk'
                    ? l.kazakh
                    : l.russian,
                onTap: () => _showLanguageDialog(context),
              ),
              const SizedBox(height: 8),
              QMenuItem(
                icon: Icons.info_outline_rounded,
                tone: 'ink',
                title: l.about,
                subtitle: l.appVersion,
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'Qoima',
                  applicationVersion: '2.3',
                  applicationLegalese: '© 2024 Qoima',
                ),
              ),
              const SizedBox(height: 8),
              QMenuItem(
                icon: Icons.logout_rounded,
                tone: 'red',
                title: l.signOut,
                danger: true,
                onTap: () async {
                  final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                            title: Text(l.signOutConfirmTitle,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            content: Text(l.signOutConfirmBody),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text(l.cancel,
                                      style:
                                          const TextStyle(color: cInk2))),
                              ElevatedButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: cRed,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10))),
                                  child: Text(l.signOut)),
                            ],
                          ));
                  if (ok == true && context.mounted) {
                    await AuthService().signOut();
                  }
                },
              ),
              const SizedBox(height: 24),
              const _ContactCard(),
              const SizedBox(height: 32),
            ],

            if (isAdmin) ...[
              // ── Менің дүкенім ─────────────────────────────────────────
              // Дүкені бар (модератор бекіткен) admin → толық хаб карточкасы.
              // Дүкені жоқ admin → «интернет-дүкен ашу» сұрауы (MyStoreGate).
              StreamBuilder(
                stream: service.watchStore(),
                builder: (_, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const SizedBox.shrink();
                  }
                  final store = snap.data;
                  if (store == null) {
                    return Column(children: [
                      _OpenStoreMenuItem(
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const MyStoreGate())),
                      ),
                      const SizedBox(height: 16),
                    ]);
                  }
                  return Column(children: [
                    _AdminStoreCard(
                      storeName: store.storeName,
                      isOnline: store.isPublished,
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const AdminMyStoreHubScreen())),
                    ),
                    const SizedBox(height: 16),
                  ]);
                },
              ),
              _MenuItem(
                icon: Icons.group_outlined,
                color: cGreen,
                title: l.sellers,
                subtitle: l.manageSellers,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SellersScreen())),
              ),
              const SizedBox(height: 8),
              _MenuItem(
                icon: Icons.warehouse_outlined,
                color: const Color(0xFF059669),
                title: l.warehouses,
                subtitle: l.manageWarehouses,
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const WarehousesScreen())),
              ),
              const SizedBox(height: 8),
            ],

            if (isAdmin) ...[
            _MenuItem(
              icon: Icons.shield_outlined,
              color: cGreen,
              title: tr('Личные данные', 'Жеке деректер'),
              subtitle: tr('Email, пароль', 'Email, құпиясөз'),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AccountSecurityScreen())),
            ),
            const SizedBox(height: 8),
            _MenuItem(
              icon: Icons.language_rounded,
              color: const Color(0xFF0891B2),
              title: l.language,
              subtitle:
                  context.watch<LocaleContext>().locale.languageCode == 'kk'
                      ? l.kazakh
                      : l.russian,
              onTap: () => _showLanguageDialog(context),
            ),
            const SizedBox(height: 8),
            _MenuItem(
              icon: Icons.info_outline_rounded,
              color: cGreen,
              title: l.about,
              subtitle: l.appVersion,
              onTap: () => showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      title: const Text('Qoima',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      content: Text(tr('Версия 2.3\n© 2024 Qoima', 'Нұсқа 2.3\n© 2024 Qoima')),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('OK')),
                      ],
                    ),
                  ),
            ),
            const SizedBox(height: 16),

            // ── Байланыс / Контакты ──────────────────────────────────
            const _ContactCard(),
            const SizedBox(height: 24),

            // Шығу
            Container(
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ]),
              child: ListTile(
                leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: cRedTint,
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.logout_rounded,
                        color: cRed, size: 20)),
                title: Text(l.signOut,
                    style: const TextStyle(
                        color: cRed, fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: cInk3),
                onTap: () async {
                  final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                            title: Text(l.signOutConfirmTitle,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            content: Text(l.signOutConfirmBody),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text(l.cancel,
                                      style: const TextStyle(
                                          color: cInk2))),
                              ElevatedButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: cRed,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10))),
                                  child: Text(l.signOut)),
                            ],
                          ));
                  if (ok == true && context.mounted) {
                    await AuthService().signOut();
                  }
                },
              ),
            ),

            const SizedBox(height: 32),
            ], // end if (isAdmin)
          ])),
        ),
      ]),
    );
  }

  static void _showLanguageDialog(BuildContext context) {
    final l = context.l10n;
    final localeCtx = context.read<LocaleContext>();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l.selectLanguage,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _LangTile(
            label: l.kazakh,
            code: 'kk',
            current: localeCtx.locale.languageCode,
            onTap: () {
              localeCtx.setLocale(const Locale('kk'));
              Navigator.pop(ctx);
            },
          ),
          const SizedBox(height: 8),
          _LangTile(
            label: l.russian,
            code: 'ru',
            current: localeCtx.locale.languageCode,
            onTap: () {
              localeCtx.setLocale(const Locale('ru'));
              Navigator.pop(ctx);
            },
          ),
        ]),
      ),
    );
  }

  static String _formatCode(String code) {
    if (code.length != 6) return code;
    return '${code.substring(0, 3)} ${code.substring(3)}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Контакт карточкасы — 3 әрекет: қоңырау, Telegram, WhatsApp
// ─────────────────────────────────────────────────────────────────────────────
class _ContactCard extends StatefulWidget {
  const _ContactCard();

  @override
  State<_ContactCard> createState() => _ContactCardState();
}

class _ContactCardState extends State<_ContactCard> {
  bool _expanded = false;

  static const _phone = '87474005347';
  static const _tgUser = 'zhambyl_magzhan';
  static String get _waMsg =>
      tr('Здравствуйте! Я обращаюсь по поводу приложения Qoima.', 'Сәлеметсіз бе! Мен Qoima қолданбасы бойынша хабарласып тұрмын.');

  static void _showErr(ScaffoldMessengerState messenger, String text) {
    messenger.showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      backgroundColor: cRed,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Заголовок (басқанда ашылады/жабылады) ──────────────────────
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(children: [
              Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: cGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.support_agent_rounded,
                      color: cGreen, size: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(l.contactTitle,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: cInk)),
              ),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.expand_more_rounded, color: cInk3),
              ),
            ]),
          ),

          // ── Дереккөздер — тек ашылғанда ────────────────────────────────
          if (_expanded) ...[
            const SizedBox(height: 14),
            _ContactTile(
              icon: Icons.phone_rounded,
              iconColor: cBlue,
              bgColor: cBlueTint,
              label: l.contactPhone,
              value: _phone,
              actionLabel: tr('Звонок', 'Қоңырау'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await makePhoneCall(_phone);
                } catch (_) {
                  _showErr(messenger, tr('Приложение телефона не найдено', 'Телефон қосымшасы табылмады'));
                }
              },
            ),
            const SizedBox(height: 10),
            _ContactTile(
              icon: Icons.send_rounded,
              iconColor: const Color(0xFF229ED9),
              bgColor: const Color(0xFFE8F5FD),
              label: l.contactTelegram,
              value: '@$_tgUser',
              actionLabel: 'Telegram',
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await openTelegram(_tgUser);
                } catch (_) {
                  _showErr(messenger, tr('Приложение Telegram не найдено', 'Telegram қосымшасы табылмады'));
                }
              },
            ),
            const SizedBox(height: 10),
            _ContactTile(
              icon: Icons.chat_rounded,
              iconColor: const Color(0xFF25D366),
              bgColor: const Color(0xFFEAFBEE),
              label: 'WhatsApp',
              value: _phone,
              actionLabel: 'WhatsApp',
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await openWhatsApp(_phone, _waMsg);
                } catch (_) {
                  _showErr(messenger, tr('Приложение WhatsApp не найдено', 'WhatsApp қосымшасы табылмады'));
                }
              },
            ),
          ],
        ]),
      ),
    );
  }
}

// ── Кликабельная строка контакта ─────────────────────────────────────────────
class _ContactTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor, bgColor;
  final String label, value, actionLabel;
  final VoidCallback onTap;

  const _ContactTile({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.label,
    required this.value,
    required this.actionLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            // Иконка
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            // Текст
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: iconColor,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14,
                        color: cInk,
                        fontWeight: FontWeight.w700)),
              ],
            )),
            // Кнопка действия
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: iconColor, borderRadius: BorderRadius.circular(8)),
              child: Text(actionLabel,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          decoration: BoxDecoration(
              color: cSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cLine)),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: manrope(14.5, FontWeight.w700, color: cInk)),
                  Text(subtitle,
                      style: manrope(12.5, FontWeight.w500, color: cInk3)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: cInk3, size: 20),
          ]),
        ),
      );
}

// ── Admin Store Card (дүкені бар admin) ───────────────────────────────────────
class _AdminStoreCard extends StatelessWidget {
  final String storeName;
  final bool isOnline;
  final VoidCallback onTap;
  const _AdminStoreCard({
    required this.storeName,
    required this.isOnline,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final repo = MyStoreRepository();
    final name = storeName.isNotEmpty ? storeName : tr('Мой магазин', 'Менің дүкенім');
    return StreamBuilder<List<StoreDiscountModel>>(
      stream: repo.watchDiscounts(),
      builder: (ctx, dSnap) {
        final activeDisc = (dSnap.data ?? []).where((d) => d.isActive).length;
        return GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: kGrad,
              borderRadius: BorderRadius.circular(20),
              boxShadow: kShadowGreen,
            ),
            child: Column(children: [
              Row(children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                  ),
                  child: const Icon(Icons.storefront_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Мой магазин', 'Менің дүкенім'),
                          style: manrope(17, FontWeight.w800,
                              color: Colors.white, letterSpacing: -0.3)),
                      const SizedBox(height: 2),
                      Text(
                        '$name · ${isOnline ? tr('Онлайн включён', 'Онлайн қосулы') : tr('Онлайн выключен', 'Онлайн өшірулі')}',
                        style: manrope(12.5, FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.72)),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: Colors.white.withValues(alpha: 0.65), size: 22),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                _StoreChip(icon: Icons.percent_rounded,
                    label: '$activeDisc акция',
                    bg: cGreenTint, fg: cGreenDeep),
                const SizedBox(width: 8),
                _StoreChip(icon: Icons.language_rounded,
                    label: isOnline ? 'Онлайн' : 'Оффлайн',
                    bg: Colors.white.withValues(alpha: 0.15), fg: Colors.white),
              ]),
            ]),
          ),
        );
      },
    );
  }
}

// ── «Интернет-дүкен ашу» (дүкені жоқ admin) ───────────────────────────────────
class _OpenStoreMenuItem extends StatelessWidget {
  final VoidCallback onTap;
  const _OpenStoreMenuItem({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          decoration: BoxDecoration(
            color: cSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cLine),
          ),
          child: Row(children: [
            QIconTile(
              icon: const Icon(Icons.storefront_rounded, color: cAmber, size: 20),
              tone: 'amber',
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Мой магазин', 'Менің дүкенім'),
                      style: manrope(14.5, FontWeight.w700, color: cInk)),
                  Text(tr('Отправить заявку на открытие интернет-магазина', 'Интернет-дүкен ашуға сұраныс жіберу'),
                      style: manrope(12, FontWeight.w500, color: cInk3)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: cInk3, size: 20),
          ]),
        ),
      );
}

class _StoreChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bg, fg;
  const _StoreChip({required this.icon, required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: fg, size: 17),
            const SizedBox(height: 5),
            Text(label,
                style: manrope(11.5, FontWeight.w700, color: fg),
                textAlign: TextAlign.center),
          ]),
        ),
      );
}

class _LangTile extends StatelessWidget {
  final String label, code, current;
  final VoidCallback onTap;
  const _LangTile(
      {required this.label,
      required this.code,
      required this.current,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final selected = code == current;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? cGreen.withValues(alpha: 0.1)
              : cBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? cGreen : cLine,
              width: selected ? 1.5 : 1),
        ),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color:
                          selected ? cGreen : cInk))),
          if (selected)
            const Icon(Icons.check_circle_rounded,
                color: cGreen, size: 18),
        ]),
      ),
    );
  }
}
