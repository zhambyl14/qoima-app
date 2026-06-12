import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/kz_cities.dart';
import '../../core/locale_context.dart';
import '../../core/l10n_ext.dart';
import '../../data/models/order_model.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/client_service.dart';
import '../../core/order_helpers.dart';
import '../../theme/qoima_design.dart';
import 'favorites_screen.dart';
import 'addresses_screen.dart';
import '../auth/account_security_screen.dart';

class ClientProfileScreen extends StatelessWidget {
  /// «Тапсырыстарым» басылғанда — ClientShell тапсырыстар экранын ашады.
  final VoidCallback onOpenOrders;
  const ClientProfileScreen({super.key, required this.onOpenOrders});

  @override
  Widget build(BuildContext context) {
    final appUser = context.watch<AppUser>();
    final name = appUser.name.isNotEmpty ? appUser.name : 'Сатып алушы';
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
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
            children: [
              // ── Тапсырыстарым — prominent (белсенді санымен) ───────────
              StreamBuilder<List<OrderModel>>(
                stream: appUser.uid.isNotEmpty
                    ? ClientService().watchClientOrders(appUser.uid)
                    : const Stream.empty(),
                builder: (_, snap) {
                  final all = snap.data ?? [];
                  final activeCount =
                      all.where((o) => orderIsActive(o.status)).length;
                  return _OrdersTile(
                      activeCount: activeCount, onTap: onOpenOrders);
                },
              ),

              const SizedBox(height: 18),
              const QSecLabel('Аккаунт'),

              // Menu items
              _MenuItem(
                icon: Icons.favorite_border_rounded,
                tone: 'red',
                title: 'Таңдаулылар',
                sub: 'Қалаулар тізімі',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const FavoritesScreen())),
              ),
              const SizedBox(height: 10),
              _MenuItem(
                icon: Icons.location_on_outlined,
                tone: 'blue',
                title: 'Мекенжайларым',
                sub: 'Сақталған мекенжайлар',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AddressesScreen())),
              ),
              const SizedBox(height: 10),
              _MenuItem(
                icon: Icons.notifications_outlined,
                tone: 'amber',
                title: 'Хабарламалар',
                value: 'Қосылған',
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Хабарламалар — жақында'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2)),
                ),
              ),
              const SizedBox(height: 10),
              _MenuItem(
                icon: Icons.location_city_outlined,
                tone: 'blue',
                title: 'Қала',
                value: appUser.city.isNotEmpty ? appUser.city : 'Таңдалмаған',
                onTap: () => _showCityDialog(context, appUser),
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
                icon: Icons.shield_outlined,
                tone: 'green',
                title: 'Аккаунт қауіпсіздігі',
                sub: 'Телефон, email, құпиясөз',
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            const AccountSecurityScreen(showPhone: true))),
              ),
              const SizedBox(height: 10),
              _MenuItem(
                icon: Icons.logout_rounded,
                tone: 'red',
                title: 'Шығу',
                danger: true,
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text('Шығу',
                          style: manrope(17, FontWeight.w700, color: cInk)),
                      content: Text('Аккаунттан шығасыз ба?',
                          style: manrope(14, FontWeight.w500, color: cInk2)),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text('Жоқ',
                                style: manrope(14, FontWeight.w600,
                                    color: cInk2))),
                        TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text('Шығу',
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

  static void _showCityDialog(BuildContext context, AppUser appUser) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.85,
        minChildSize: 0.4,
        expand: false,
        builder: (_, ctrl) => Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(children: [
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: cLine, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Text('Ваш город',
                    style: manrope(17, FontWeight.w700, color: cInk)),
              ]),
              const SizedBox(height: 4),
              Text('Вы будете видеть только магазины своего города',
                  style: manrope(12.5, FontWeight.w500, color: cInk3)),
              const SizedBox(height: 12),
              const Divider(height: 1),
            ]),
          ),
          Expanded(
            child: ListView(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: kzCities.map((city) {
                final selected = city == appUser.city;
                return GestureDetector(
                  onTap: () async {
                    Navigator.pop(ctx);
                    appUser.updateCity(city);
                    await AuthService().updateClientCity(appUser.uid, city);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 13),
                    decoration: BoxDecoration(
                      color: selected ? cGreenTint : cSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: selected ? cGreen : cLine,
                          width: selected ? 1.5 : 1),
                    ),
                    child: Row(children: [
                      Icon(Icons.location_city_outlined,
                          color: selected ? cGreen : cInk3, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(city,
                            style: manrope(14.5, FontWeight.w600,
                                color: selected ? cGreen : cInk)),
                      ),
                      if (selected)
                        const Icon(Icons.check_circle_rounded,
                            color: cGreen, size: 20),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
        ]),
      ),
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
}

// ── Тапсырыстарым tile (белсенді санымен) ────────────────────────────────────
class _OrdersTile extends StatelessWidget {
  final int activeCount;
  final VoidCallback onTap;
  const _OrdersTile({required this.activeCount, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          decoration: BoxDecoration(
            color: cSurface,
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: cGreen.withValues(alpha: 0.2), width: 1.5),
            boxShadow: kShadowSm,
          ),
          child: Row(children: [
            Stack(clipBehavior: Clip.none, children: [
              QIconTile(
                icon: const Icon(Icons.receipt_long_rounded,
                    color: cGreen, size: 21),
                tone: 'green',
                size: 44,
              ),
              if (activeCount > 0)
                Positioned(
                  top: -5,
                  right: -5,
                  child: Container(
                    constraints:
                        const BoxConstraints(minWidth: 20, minHeight: 20),
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: cGreen,
                      shape: BoxShape.circle,
                      border: Border.all(color: cSurface, width: 2),
                    ),
                    child: Center(
                      child: Text('$activeCount',
                          style: manrope(10.5, FontWeight.w800,
                              color: Colors.white)),
                    ),
                  ),
                ),
            ]),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Тапсырыстарым',
                        style: manrope(14.5, FontWeight.w800, color: cInk)),
                    const SizedBox(height: 2),
                    Text('$activeCount белсенді тапсырыс',
                        style: manrope(12.5, FontWeight.w500, color: cInk3)),
                  ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: cInk3, size: 20),
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
