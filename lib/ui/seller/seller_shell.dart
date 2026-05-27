import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../products/products_screen.dart';
import '../profile/profile_screen.dart';
import '../sales/sales_screen.dart';
import 'seller_online_screen.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/app_theme.dart';

class SellerShell extends StatefulWidget {
  const SellerShell({super.key});
  @override
  State<SellerShell> createState() => _SellerShellState();
}

class _SellerShellState extends State<SellerShell> {
  int _index = 0;

  static const List<_TabDef> _tabs = [
    _TabDef(Icons.receipt_long_outlined,  Icons.receipt_long_rounded,  'Продажи'),
    _TabDef(Icons.inventory_2_outlined,   Icons.inventory_2_rounded,   'Склад'),
    _TabDef(Icons.shopping_bag_outlined,  Icons.shopping_bag_rounded,  'Онлайн'),
    _TabDef(Icons.person_outline_rounded, Icons.person_rounded,        'Профиль'),
  ];

  static const List<Widget> _screens = [
    SalesScreen(),
    ProductsScreen(readOnly: true),
    SellerOnlineScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: _FadeIndexedStack(index: _index, children: _screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(top: BorderSide(color: AppTheme.border)),
          boxShadow: [
            BoxShadow(
              color: Color(0x0F0F172A),
              blurRadius: 24,
              offset: Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 64,
            child: Row(
              children: List.generate(_tabs.length, (i) {
                final active = i == _index;
                final tab = _tabs[i];
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _index = i);
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(clipBehavior: Clip.none, children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 5),
                            decoration: BoxDecoration(
                              color: active
                                  ? AppTheme.primarySoft
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              active ? tab.activeIcon : tab.icon,
                              size: 20,
                              color: active
                                  ? AppTheme.primary
                                  : AppTheme.textHint,
                            ),
                          ),
                          if (i == 2)
                            const Positioned(
                              right: 0, top: 0,
                              child: _OnlineBadge(),
                            ),
                        ]),
                        const SizedBox(height: 3),
                        Text(
                          tab.label,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: active
                                ? AppTheme.primary
                                : AppTheme.textHint,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _TabDef {
  final IconData icon, activeIcon;
  final String label;
  const _TabDef(this.icon, this.activeIcon, this.label);
}

class _OnlineBadge extends StatelessWidget {
  const _OnlineBadge();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: FirestoreService().watchActiveOnlineCount(),
      builder: (_, snap) {
        final count = snap.data ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          constraints: const BoxConstraints(minWidth: 16),
          decoration: BoxDecoration(
            color: AppTheme.hot,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Text(
            count > 99 ? '99+' : '$count',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800,
            ),
          ),
        );
      },
    );
  }
}

// ─── Fade + IndexedStack (preserves screen state across tab switches) ─────────

class _FadeIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  const _FadeIndexedStack({required this.index, required this.children});

  @override
  State<_FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<_FadeIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_FadeIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _fade,
        child: IndexedStack(index: widget.index, children: widget.children),
      );
}
