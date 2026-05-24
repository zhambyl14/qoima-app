import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import 'products/products_screen.dart';
import 'sales/sales_screen.dart';
import 'analytics/analytics_screen.dart';
import 'profile/profile_screen.dart';
import 'profile/admin_onboarding_screen.dart';
import '../core/app_user.dart';
import '../core/warehouse_context.dart';
import '../core/l10n_ext.dart';
import 'auth/seller_join_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  List<_TabDef> _tabs(BuildContext context) {
    final l = context.l10n;
    return AppUser.isAdmin
        ? [
            _TabDef(Icons.inventory_2_outlined, Icons.inventory_2_rounded, l.stockTitle),
            _TabDef(Icons.receipt_long_outlined, Icons.receipt_long_rounded, l.salesTitle),
            _TabDef(Icons.bar_chart_outlined, Icons.bar_chart_rounded, l.analyticsTitle),
            _TabDef(Icons.person_outline_rounded, Icons.person_rounded, l.profileTitle),
          ]
        : [
            _TabDef(Icons.inventory_2_outlined, Icons.inventory_2_rounded, l.stockTitle),
            _TabDef(Icons.receipt_long_outlined, Icons.receipt_long_rounded, l.salesTitle),
            _TabDef(Icons.person_outline_rounded, Icons.person_rounded, l.profileTitle),
          ];
  }

  List<Widget> get _screens => AppUser.isAdmin
      ? const [
          ProductsScreen(),
          SalesScreen(),
          AnalyticsScreen(),
          ProfileScreen(),
        ]
      : const [
          ProductsScreen(readOnly: true),
          SalesScreen(),
          ProfileScreen(),
        ];

  @override
  Widget build(BuildContext context) {
    // Seller joinStatus guard
    if (AppUser.isSeller && AppUser.joinStatus != 'active') {
      return const SellerJoinScreen();
    }

    // Admin warehouse guard — no warehouses yet → onboarding
    if (AppUser.isAdmin && context.watch<WarehouseContext>().isEmpty) {
      return const AdminOnboardingScreen();
    }

    final tabs    = _tabs(context);
    final screens = _screens;
    final safeIdx = _currentIndex.clamp(0, screens.length - 1);

    return Scaffold(
      body: IndexedStack(index: safeIdx, children: screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 64,
            child: Row(
              children: List.generate(tabs.length, (i) => _NavItem(
                icon:         tabs[i].icon,
                activeIcon:   tabs[i].activeIcon,
                label:        tabs[i].label,
                index:        i,
                currentIndex: safeIdx,
                onTap: (idx) {
                  HapticFeedback.selectionClick();
                  setState(() => _currentIndex = idx);
                },
              )),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabDef {
  final IconData icon, activeIcon;
  final String label;
  const _TabDef(this.icon, this.activeIcon, this.label);
}

class _NavItem extends StatelessWidget {
  final IconData icon, activeIcon;
  final String label;
  final int index, currentIndex;
  final void Function(int) onTap;

  const _NavItem({
    required this.icon, required this.activeIcon, required this.label,
    required this.index, required this.currentIndex, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = index == currentIndex;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: active ? AppTheme.primary.withValues(alpha: 0.1) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(active ? activeIcon : icon,
                  color: active ? AppTheme.primary : AppTheme.textHint, size: 22),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(
              fontSize: 10,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              color: active ? AppTheme.primary : AppTheme.textHint,
            )),
          ],
        ),
      ),
    );
  }
}
