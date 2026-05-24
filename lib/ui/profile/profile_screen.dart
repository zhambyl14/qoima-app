import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/contact_utils.dart';
import '../../core/locale_context.dart';
import '../../core/l10n_ext.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/app_theme.dart';
import 'sellers_screen.dart';
import 'warehouses_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l       = context.l10n;
    final name    = AppUser.name;
    final email   = AppUser.email;
    final isAdmin = AppUser.isAdmin;
    final initials = name.trim().split(' ')
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .take(2)
        .join();
    final service = FirestoreService();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(slivers: [
        // ── Header ──────────────────────────────────────────────────────
        SliverToBoxAdapter(child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFF1E3A8A), Color(0xFF2D4FB5)],
                begin: Alignment.topLeft, end: Alignment.bottomRight)),
          child: SafeArea(bottom: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
            child: Column(children: [
              // Bell icon (admin only)
              if (isAdmin) Align(
                alignment: Alignment.centerRight,
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: service.watchPendingRequests(),
                  builder: (_, snap) {
                    final count = snap.data?.length ?? 0;
                    return GestureDetector(
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const SellersScreen())),
                      child: Stack(clipBehavior: Clip.none, children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.notifications_outlined,
                              color: Colors.white, size: 20)),
                        if (count > 0) Positioned(
                          right: -2, top: -2,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                                color: Color(0xFFEF4444),
                                shape: BoxShape.circle),
                            child: Text('$count',
                                style: const TextStyle(color: Colors.white,
                                    fontSize: 9, fontWeight: FontWeight.w700)),
                          )),
                      ]),
                    );
                  },
                ),
              ),
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4), width: 2)),
                child: Center(child: Text(initials.isEmpty ? '?' : initials,
                    style: const TextStyle(color: Colors.white, fontSize: 26,
                        fontWeight: FontWeight.w700)))),
              const SizedBox(height: 12),
              Text(name.isEmpty ? '...' : name,
                  style: const TextStyle(color: Colors.white, fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(email,
                  style: const TextStyle(color: Colors.white60, fontSize: 13)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3))),
                child: Text(
                  isAdmin ? l.adminBadge : l.sellerBadge,
                  style: const TextStyle(color: Colors.white, fontSize: 12,
                      fontWeight: FontWeight.w600),
                )),

              // Бизнес-код карточка (тек admin үшін)
              if (isAdmin && AppUser.businessCode.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25))),
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Row(children: [
                        const Icon(Icons.vpn_key_rounded, color: Colors.white70, size: 14),
                        const SizedBox(width: 6),
                        Text(l.businessCode,
                            style: const TextStyle(color: Colors.white60, fontSize: 11)),
                      ]),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(
                              ClipboardData(text: AppUser.businessCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l.businessCodeCopied),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: Row(children: [
                          const Icon(Icons.copy_rounded, color: Colors.white60, size: 13),
                          const SizedBox(width: 4),
                          Text(l.copy,
                              style: const TextStyle(color: Colors.white60, fontSize: 11)),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      _formatCode(AppUser.businessCode),
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
          sliver: SliverList(delegate: SliverChildListDelegate([
            const SizedBox(height: 8),

            if (isAdmin) ...[
              _MenuItem(
                icon: Icons.group_outlined,
                color: AppTheme.primary,
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
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const WarehousesScreen())),
              ),
              const SizedBox(height: 8),
            ],

            _MenuItem(
              icon: Icons.language_rounded,
              color: const Color(0xFF0891B2),
              title: l.language,
              subtitle: context.watch<LocaleContext>().locale.languageCode == 'kk'
                  ? l.kazakh
                  : l.russian,
              onTap: () => _showLanguageDialog(context),
            ),
            const SizedBox(height: 8),
            _MenuItem(
              icon: Icons.info_outline_rounded,
              color: AppTheme.primary,
              title: l.about,
              subtitle: l.appVersion,
              onTap: () {},
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
                  boxShadow: [BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8, offset: const Offset(0, 2))]),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppTheme.dangerLight,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.logout_rounded,
                      color: AppTheme.danger, size: 20)),
                title: Text(l.signOut, style: const TextStyle(
                    color: AppTheme.danger, fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textHint),
                onTap: () async {
                  final ok = await showDialog<bool>(context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      title: Text(l.signOutConfirmTitle,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      content: Text(l.signOutConfirmBody),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(l.cancel,
                                style: const TextStyle(color: AppTheme.textSecondary))),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.danger,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10))),
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
            onTap: () { localeCtx.setLocale(const Locale('kk')); Navigator.pop(ctx); },
          ),
          const SizedBox(height: 8),
          _LangTile(
            label: l.russian,
            code: 'ru',
            current: localeCtx.locale.languageCode,
            onTap: () { localeCtx.setLocale(const Locale('ru')); Navigator.pop(ctx); },
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
class _ContactCard extends StatelessWidget {
  const _ContactCard();

  static const _phone    = '87474005347';
  static const _tgUser   = 'zhambyl_magzhan';
  static const _waMsg    = 'Сәлеметсіз бе! Мен Qoima қолданбасы бойынша хабарласып тұрмын.';

  static void _showErr(ScaffoldMessengerState messenger, String text) {
    messenger.showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppTheme.danger,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Заголовок ──────────────────────────────────────────────────
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.support_agent_rounded,
                  color: AppTheme.primary, size: 20)),
            const SizedBox(width: 10),
            Text(l.contactTitle,
                style: const TextStyle(fontWeight: FontWeight.w700,
                    fontSize: 15, color: AppTheme.textPrimary)),
          ]),
          const SizedBox(height: 14),

          // ── Телефон — прямой звонок ─────────────────────────────────
          _ContactTile(
            icon: Icons.phone_rounded,
            iconColor: const Color(0xFF1E3A8A),
            bgColor: const Color(0xFFEFF6FF),
            label: l.contactPhone,
            value: _phone,
            actionLabel: 'Қоңырау / Звонок',
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await makePhoneCall(_phone);
              } catch (_) {
                _showErr(messenger, 'Телефон қосымшасы табылмады');
              }
            },
          ),
          const SizedBox(height: 10),

          // ── Telegram ────────────────────────────────────────────────
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
                _showErr(messenger, 'Telegram қосымшасы табылмады');
              }
            },
          ),
          const SizedBox(height: 10),

          // ── WhatsApp ────────────────────────────────────────────────
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
                _showErr(messenger, 'WhatsApp қосымшасы табылмады');
              }
            },
          ),
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
              width: 40, height: 40,
              decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            // Текст
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(
                    fontSize: 11, color: iconColor,
                    fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(
                    fontSize: 14, color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700)),
              ],
            )),
            // Кнопка действия
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: iconColor,
                  borderRadius: BorderRadius.circular(8)),
              child: Text(actionLabel,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 11,
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
    required this.icon, required this.color,
    required this.title, required this.subtitle, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 2))]),
    child: ListTile(
      leading: Container(padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 20)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500,
          color: AppTheme.textPrimary)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: AppTheme.textHint, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textHint),
      onTap: onTap,
    ),
  );
}

class _LangTile extends StatelessWidget {
  final String label, code, current;
  final VoidCallback onTap;
  const _LangTile({required this.label, required this.code,
      required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final selected = code == current;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary.withValues(alpha: 0.06) : AppTheme.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? AppTheme.primary : AppTheme.border,
              width: selected ? 1.5 : 1),
        ),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(
              fontWeight: FontWeight.w600,
              color: selected ? AppTheme.primary : AppTheme.textPrimary))),
          if (selected) const Icon(Icons.check_circle_rounded,
              color: AppTheme.primary, size: 18),
        ]),
      ),
    );
  }
}
