import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/locale_context.dart';
import '../../core/l10n_ext.dart';
import '../../data/models/order_model.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';

class ClientProfileScreen extends StatelessWidget {
  const ClientProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appUser = context.watch<AppUser>();
    final name = appUser.name.isNotEmpty ? appUser.name : 'Покупатель';
    final phone = appUser.phone;
    final initials = _initials(name);

    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        // ── Gradient header with avatar ────────────────────────────────
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(gradient: kGrad),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 26),
              child: Column(children: [
                // Avatar
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4), width: 2),
                  ),
                  child: Center(
                    child: Text(initials,
                        style:
                            manrope(26, FontWeight.w800, color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 12),
                Text(name,
                    style: manrope(21, FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 2),
                if (phone.isNotEmpty)
                  Text(phone,
                      style: manrope(13.5, FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.8))),
              ]),
            ),
          ),
        ),

        // ── Body ─────────────────────────────────────────────────────
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              // Stats row
              StreamBuilder<List<OrderModel>>(
                stream: phone.isNotEmpty
                    ? ClientService().watchClientOrders(phone)
                    : const Stream.empty(),
                builder: (_, snap) {
                  final count = snap.data?.length ?? 0;
                  return Row(children: [
                    _StatCard(
                        value: '$count',
                        label: 'Заказов'),
                    const SizedBox(width: 12),
                    const _StatCard(
                        value: '—', label: 'В избранном', valueColor: cRed),
                  ]);
                },
              ),

              const SizedBox(height: 16),
              const QSecLabel('Аккаунт'),

              // Menu items
              _MenuItem(
                icon: Icons.favorite_border_rounded,
                tone: 'red',
                title: 'Избранное',
                sub: 'Список желаний',
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Избранное — скоро'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2)),
                ),
              ),
              const SizedBox(height: 10),
              _MenuItem(
                icon: Icons.location_on_outlined,
                tone: 'blue',
                title: 'Адреса доставки',
                sub: 'Сохранённые адреса',
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Адреса — скоро'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2)),
                ),
              ),
              const SizedBox(height: 10),
              _MenuItem(
                icon: Icons.notifications_outlined,
                tone: 'amber',
                title: 'Уведомления',
                value: 'Вкл',
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Уведомления — скоро'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2)),
                ),
              ),
              const SizedBox(height: 10),
              _MenuItem(
                icon: Icons.language_outlined,
                tone: 'gray',
                title: context.l10n.language,
                value: context.watch<LocaleContext>().locale.languageCode == 'kk'
                    ? context.l10n.kazakh
                    : context.l10n.russian,
                onTap: () => _showLanguageDialog(context),
              ),
              const SizedBox(height: 10),
              _MenuItem(
                icon: Icons.logout_rounded,
                tone: 'red',
                title: 'Выйти',
                danger: true,
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text('Выйти',
                          style: manrope(17, FontWeight.w700, color: cInk)),
                      content: Text('Выйти из аккаунта?',
                          style: manrope(14, FontWeight.w500, color: cInk2)),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text('Нет',
                                style: manrope(14, FontWeight.w600,
                                    color: cInk2))),
                        TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text('Выйти',
                                style: manrope(14, FontWeight.w600,
                                    color: cRed))),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await AuthService().signOut();
                  }
                },
              ),
            ],
          ),
        ),
      ]),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
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
}

// ── Stat card ──────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String value, label;
  final Color? valueColor;
  const _StatCard(
      {required this.value, required this.label, this.valueColor});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: cSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cLine),
            boxShadow: kShadowSm,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                style: manrope(22, FontWeight.w800,
                    color: valueColor ?? cInk)),
            const SizedBox(height: 2),
            Text(label,
                style: manrope(12, FontWeight.w600, color: cInk3)),
          ]),
        ),
      );
}

// ── Menu item ──────────────────────────────────────────────────────────────────
class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String tone;
  final String title;
  final String? sub;
  final String? value;
  final bool danger;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.tone,
    required this.title,
    this.sub,
    this.value,
    this.danger = false,
    required this.onTap,
  });

  Color _iconColor() {
    switch (tone) {
      case 'red':
        return cRed;
      case 'blue':
        return cBlue;
      case 'amber':
        return cAmber;
      case 'green':
        return cGreen;
      default:
        return cInk2;
    }
  }

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
              icon: Icon(icon, color: _iconColor(), size: 20),
              tone: danger ? 'red' : tone,
              size: 40,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: manrope(14.5, FontWeight.w700,
                            color: danger ? cRed : cInk)),
                    if (sub != null)
                      Text(sub!,
                          style: manrope(12.5, FontWeight.w500, color: cInk3)),
                  ]),
            ),
            if (value != null)
              Text(value!,
                  style: manrope(13.5, FontWeight.w600, color: cInk2)),
            if (!danger)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.chevron_right_rounded, color: cInk3, size: 20),
              ),
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
          color: selected ? cGreen.withValues(alpha: 0.1) : cBg,
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
                      color: selected ? cGreen : cInk))),
          if (selected)
            const Icon(Icons.check_circle_rounded, color: cGreen, size: 18),
        ]),
      ),
    );
  }
}
