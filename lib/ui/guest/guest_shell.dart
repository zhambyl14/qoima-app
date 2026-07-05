import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/lang.dart';
import '../../theme/qoima_design.dart';
import '../auth/client_login_screen.dart';
import '../client/client_home_screen.dart';
import '../client/client_catalog_screen.dart';
import '../client/client_cart_screen.dart';
import '../client/client_shell.dart';

/// Авторизацияланбаған пайдаланушы үшін shell — навбар клиенттікіндей:
/// Басты · Каталог · Себет толық жұмыс істейді (CartProvider SharedPreferences),
/// «Профиль» — ClientLoginScreen шақырады.
/// Кіргеннен кейін корневой gate автоматты ClientShell/AdminShell-ге ауысады;
/// CartProvider-дегі тауарлар сол күйінде қалады (жүктемелік migrate жоқ).
class GuestShell extends StatefulWidget {
  const GuestShell({super.key});

  @override
  State<GuestShell> createState() => GuestShellState();
}

class GuestShellState extends State<GuestShell> {
  int _index = 0;

  void setIndex(int i) => setState(() => _index = i);

  static const List<_TabDef> _tabs = [
    _TabDef(Icons.home_outlined, Icons.home_rounded, 'Басты', false),
    _TabDef(Icons.grid_view_outlined, Icons.grid_view_rounded, 'Каталог', false),
    _TabDef(Icons.shopping_bag_outlined, Icons.shopping_bag_rounded, 'Себет', false),
    _TabDef(Icons.person_outline_rounded, Icons.person_rounded, 'Профиль', true),
  ];

  // Тек ашық табтардың экрандары (0..2). «Профиль» (3) — locked.
  static const List<Widget> _pages = [
    ClientHomeScreen(),
    ClientCatalogScreen(),
    _GuestCartPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final cartCount = context.watch<CartProvider>().count;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: cBg,
      body: IndexedStack(
        index: _index < _pages.length ? _index : 0,
        children: _pages,
      ),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              border: const Border(top: BorderSide(color: cLine, width: 1)),
            ),
            // Edge-to-edge (Android 15+) режимде bottomPad жүйелік навбардың
            // өз биіктігін береді — оған тұрақты 26 қоспаймыз, әйтпесе екі
            // навбар арасында үлкен бос орын пайда болады.
            padding: EdgeInsets.fromLTRB(
                12, 9, 12, bottomPad > 0 ? bottomPad + 8 : 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_tabs.length, (i) {
                final active = i == _index;
                final locked = _tabs[i].locked;

                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      if (locked) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ClientLoginScreen(),
                          ),
                        );
                      } else {
                        setState(() => _index = i);
                      }
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(clipBehavior: Clip.none, children: [
                          Icon(
                            active
                                ? _tabs[i].activeIcon
                                : _tabs[i].icon,
                            color: locked
                                ? cInk3.withValues(alpha: 0.45)
                                : (active ? cGreen : cInk3),
                            size: 24,
                          ),
                          if (i == 2 && cartCount > 0)
                            Positioned(
                              top: -4, right: -6,
                              child: Container(
                                width: 14, height: 14,
                                decoration: const BoxDecoration(
                                    color: cRed, shape: BoxShape.circle),
                                child: Center(
                                  child: Text(
                                    cartCount > 9 ? '9+' : '$cartCount',
                                    style: manrope(8, FontWeight.w800,
                                        color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                          if (locked)
                            Positioned(
                              top: -3, right: -5,
                              child: Icon(Icons.lock_rounded,
                                  size: 10,
                                  color: cInk3.withValues(alpha: 0.55)),
                            ),
                        ]),
                        const SizedBox(height: 3),
                        // FittedBox — үлкен жүйелік шрифтте лейбл екі жолға
                        // бөлінбей, таб еніне сыйып кішірейеді.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            trValue(_tabs[i].label),
                            maxLines: 1,
                            style: manrope(
                              10.5,
                              active ? FontWeight.w700 : FontWeight.w600,
                              color: locked
                                  ? cInk3.withValues(alpha: 0.45)
                                  : (active ? cGreen : cInk3),
                            ),
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

// ── Guest cart page — ClientCartScreen + checkout guard ────────────────────────
class _GuestCartPage extends StatelessWidget {
  const _GuestCartPage();

  @override
  Widget build(BuildContext context) {
    // ClientCartScreen checkout-ты өзі ішінде guest-ті тексереді.
    return const ClientCartScreen();
  }
}

class _TabDef {
  final IconData icon, activeIcon;
  final String label;
  final bool locked;
  const _TabDef(this.icon, this.activeIcon, this.label, this.locked);
}
