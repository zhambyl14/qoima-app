import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../data/models/cart_item_model.dart';
import 'client_home_screen.dart';
import 'client_cart_screen.dart';
import 'client_orders_screen.dart';
import 'client_profile_screen.dart';

// ── Cart state ─────────────────────────────────────────────────────────────────
class CartProvider extends ChangeNotifier {
  final List<CartItemModel> _items = [];

  List<CartItemModel> get items => List.unmodifiable(_items);
  int    get count => _items.fold(0, (s, i) => s + i.qty);
  double get total => _items.fold(0.0, (s, i) => s + i.subtotal);

  void addItem(CartItemModel item) {
    final idx = _items.indexWhere(
        (e) => e.productId == item.productId && e.size == item.size);
    if (idx >= 0) {
      _items[idx] = _items[idx].copyWith(qty: _items[idx].qty + item.qty);
    } else {
      _items.add(item);
    }
    notifyListeners();
  }

  void removeAt(int index) {
    _items.removeAt(index);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}

// ── Shell ──────────────────────────────────────────────────────────────────────
class ClientShell extends StatefulWidget {
  const ClientShell({super.key});

  @override
  State<ClientShell> createState() => _ClientShellState();
}

class _ClientShellState extends State<ClientShell> {
  int _index = 0;

  static const List<_TabDef> _tabs = [
    _TabDef(Icons.storefront_outlined,  Icons.storefront_rounded,   'Дүкен'),
    _TabDef(Icons.shopping_cart_outlined, Icons.shopping_cart_rounded, 'Себет'),
    _TabDef(Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Тапсырыстар'),
    _TabDef(Icons.person_outline_rounded, Icons.person_rounded,     'Профиль'),
  ];

  static const List<Widget> _screens = [
    ClientHomeScreen(),
    ClientCartScreen(),
    ClientOrdersScreen(),
    ClientProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final cartCount = context.watch<CartProvider>().count;

    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
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
              children: List.generate(_tabs.length, (i) {
                final active = i == _index;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _index = i);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              decoration: BoxDecoration(
                                color: active
                                    ? AppTheme.primary.withValues(alpha: 0.1)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                active ? _tabs[i].activeIcon : _tabs[i].icon,
                                color: active
                                    ? AppTheme.primary
                                    : AppTheme.textHint,
                                size: 22,
                              ),
                            ),
                            if (i == 1 && cartCount > 0)
                              Positioned(
                                top: -2, right: -2,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                      color: AppTheme.danger,
                                      shape: BoxShape.circle),
                                  child: Text(
                                    cartCount > 9 ? '9+' : '$cartCount',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(_tabs[i].label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: active
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: active
                                  ? AppTheme.primary
                                  : AppTheme.textHint,
                            )),
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
