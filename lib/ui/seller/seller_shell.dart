import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../admin/products/products_screen.dart';
import '../profile/profile_screen.dart';
import 'sales/sales_screen.dart';
import 'seller_online_screen.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/qoima_design.dart';

import '../../core/lang.dart';
class SellerShell extends StatefulWidget {
  const SellerShell({super.key});
  @override
  State<SellerShell> createState() => _SellerShellState();
}

class _SellerShellState extends State<SellerShell> {
  int _index = 0;

  static const List<_TabDef> _tabs = [
    _TabDef(Icons.inventory_2_outlined, Icons.inventory_2_rounded, 'Склад'),
    _TabDef(Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'История'),
    _TabDef(Icons.language_outlined, Icons.language_rounded, 'Онлайн'),
    _TabDef(Icons.person_outline_rounded, Icons.person_rounded, 'Профиль'),
  ];

  static const List<Widget> _screens = [
    ProductsScreen(readOnly: true),
    SalesScreen(),
    SellerOnlineScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: cBg,
      body: _FadeIndexedStack(index: _index, children: _screens),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              border: const Border(top: BorderSide(color: cLine, width: 1)),
            ),
            padding: EdgeInsets.fromLTRB(12, 9, 12, 26 + bottomPad),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_tabs.length, (i) {
                final active = i == _index;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _index = i);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(clipBehavior: Clip.none, children: [
                          Icon(
                            active ? _tabs[i].activeIcon : _tabs[i].icon,
                            color: active ? cGreen : cInk3,
                            size: 24,
                          ),
                          if (i == 2)
                            Positioned(
                              top: -4,
                              right: -6,
                              child: _OnlineBadge(),
                            ),
                        ]),
                        const SizedBox(height: 3),
                        Text(
                          trValue(_tabs[i].label),
                          style: manrope(
                            10.5,
                            active ? FontWeight.w700 : FontWeight.w600,
                            color: active ? cGreen : cInk3,
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

class _TabDef {
  final IconData icon, activeIcon;
  final String label;
  const _TabDef(this.icon, this.activeIcon, this.label);
}

class _OnlineBadge extends StatefulWidget {
  @override
  State<_OnlineBadge> createState() => _OnlineBadgeState();
}

class _OnlineBadgeState extends State<_OnlineBadge> {
  // Ағынды бір рет жасаймыз — shell әр таб басқанда rebuild болғанда
  // badge қайта жазылып, жыпылықтамауы үшін.
  final Stream<int> _stream = FirestoreService().watchActiveOnlineCount();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _stream,
      builder: (_, snap) {
        final count = snap.data ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return Container(
          constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: cRed,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: Center(
            child: Text(
              count > 99 ? '99+' : '$count',
              textAlign: TextAlign.center,
              style: manrope(8, FontWeight.w800, color: Colors.white),
            ),
          ),
        );
      },
    );
  }
}

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
