import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/qoima_design.dart';
import '../../data/models/cart_item_model.dart';
import 'client_home_screen.dart';
import 'client_cart_screen.dart';
import 'client_orders_screen.dart';
import 'client_profile_screen.dart';

// ── Cart state ─────────────────────────────────────────────────────────────────
class CartProvider extends ChangeNotifier {
  static const _kKey = 'cart_items_v1';

  final List<CartItemModel> _items = [];
  bool _loaded = false;

  CartProvider() {
    _load();
  }

  List<CartItemModel> get items => List.unmodifiable(_items);
  int get count => _items.fold(0, (s, i) => s + i.qty);
  double get total => _items.fold(0.0, (s, i) => s + i.subtotal);

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _items.addAll(list
            .map((e) => CartItemModel.fromJson(e as Map<String, dynamic>))
            .toList());
      } catch (_) {}
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kKey, jsonEncode(_items.map((e) => e.toJson()).toList()));
  }

  bool get isLoaded => _loaded;

  void addItem(CartItemModel item) {
    final idx = _items.indexWhere(
        (e) => e.productId == item.productId && e.size == item.size);
    if (idx >= 0) {
      _items[idx] = _items[idx].copyWith(qty: _items[idx].qty + item.qty);
    } else {
      _items.add(item);
    }
    notifyListeners();
    _persist();
  }

  void removeAt(int index) {
    _items.removeAt(index);
    notifyListeners();
    _persist();
  }

  void decrementAt(int index) {
    if (index < 0 || index >= _items.length) return;
    final item = _items[index];
    if (item.qty <= 1) {
      _items.removeAt(index);
    } else {
      _items[index] = item.copyWith(qty: item.qty - 1);
    }
    notifyListeners();
    _persist();
  }

  void incrementAt(int index) {
    if (index < 0 || index >= _items.length) return;
    _items[index] = _items[index].copyWith(qty: _items[index].qty + 1);
    notifyListeners();
    _persist();
  }

  void clear() {
    _items.clear();
    notifyListeners();
    _persist();
  }
}

// ── Shell ──────────────────────────────────────────────────────────────────────
class ClientShell extends StatefulWidget {
  const ClientShell({super.key});

  @override
  State<ClientShell> createState() => ClientShellState();
}

class ClientShellState extends State<ClientShell> {
  int _currentIndex = 0;

  void setIndex(int i) => setState(() => _currentIndex = i);

  static const List<_TabDef> _tabs = [
    _TabDef(Icons.storefront_outlined, Icons.storefront_rounded, 'Каталог'),
    _TabDef(Icons.shopping_cart_outlined, Icons.shopping_cart_rounded, 'Корзина'),
    _TabDef(Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Заказы'),
    _TabDef(Icons.person_outline_rounded, Icons.person_rounded, 'Профиль'),
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
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: cBg,
      body: IndexedStack(index: _currentIndex, children: _screens),
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
                final active = i == _currentIndex;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _currentIndex = i);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              active ? _tabs[i].activeIcon : _tabs[i].icon,
                              color: active ? cGreen : cInk3,
                              size: 24,
                            ),
                            if (i == 1 && cartCount > 0)
                              Positioned(
                                top: -4,
                                right: -6,
                                child: Container(
                                  width: 14,
                                  height: 14,
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
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _tabs[i].label,
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
