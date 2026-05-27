import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../data/services/auth_service.dart';
import '../../theme/app_theme.dart';

class ClientProfileScreen extends StatelessWidget {
  const ClientProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appUser = context.watch<AppUser>();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Профиль'),
        backgroundColor: AppTheme.primary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),

          // Avatar + name
          Center(
            child: Column(children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_rounded,
                    color: AppTheme.primary, size: 40),
              ),
              const SizedBox(height: 12),
              Text(appUser.name.isNotEmpty ? appUser.name : 'Сатып алушы',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary, letterSpacing: -0.3)),
              const SizedBox(height: 4),
              Text(appUser.phone,
                  style: const TextStyle(
                      fontSize: 14, color: AppTheme.textSecondary)),
            ]),
          ),
          const SizedBox(height: 24),

          // Info card
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(children: [
              _InfoRow(
                icon: Icons.person_outline,
                label: 'Аты',
                value: appUser.name.isNotEmpty ? appUser.name : '—',
              ),
              const Divider(height: 1, indent: 52),
              _InfoRow(
                icon: Icons.phone_outlined,
                label: 'Телефон',
                value: appUser.phone.isNotEmpty ? appUser.phone : '—',
              ),
            ]),
          ),
          const SizedBox(height: 32),

          // Sign out
          SizedBox(
            width: double.infinity, height: 52,
            child: OutlinedButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Шығу'),
                    content: const Text('Жүйеден шығасыз ба?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false),
                          child: const Text('Жоқ')),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Шығу',
                              style: TextStyle(color: AppTheme.danger))),
                    ],
                  ),
                );
                if (ok == true) {
                  await AuthService().signOut();
                }
              },
              icon: const Icon(Icons.logout_rounded, color: AppTheme.danger),
              label: const Text('Шығу',
                  style: TextStyle(color: AppTheme.danger,
                      fontSize: 15, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.danger),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(children: [
      Icon(icon, color: AppTheme.primary, size: 20),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(
            fontSize: 11, color: AppTheme.textHint, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(
            fontSize: 14, color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
      ]),
    ]),
  );
}
