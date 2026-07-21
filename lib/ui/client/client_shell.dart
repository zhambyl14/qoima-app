import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/lang.dart';
import '../../theme/qoima_design.dart';
import '../../data/models/cart_item_model.dart';
import '../../data/services/local_notification_service.dart';
import 'client_home_screen.dart';
import 'client_catalog_screen.dart';
import 'client_cart_screen.dart';
import 'client_profile_screen.dart';
import 'client_orders_screen.dart';

// ── Cart state ─────────────────────────────────────────────────────────────────
class CartProvider extends ChangeNotifier {
  static const _kKey = 'cart_items_v1';

  final List<CartItemModel> _items = [];
  bool _loaded = false;

  // Гест «Оплатить» басып логинге кеткенде true болады — кіргеннен кейін
  // ClientShell бұны көріп бірден Себет табын ашады (басты бет орнына).
  bool pendingCheckout = false;

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
    // Себетте тауар бар — 2 сағаттан кейін еске салу жоспарлаймыз (серверсіз,
    // тек құрылғыда — CartProvider серверге синхрондалмайды).
    LocalNotificationService.instance.scheduleCartReminder(itemCount: count);
  }

  void removeAt(int index) {
    _items.removeAt(index);
    notifyListeners();
    _persist();
    if (_items.isEmpty) LocalNotificationService.instance.cancelCartReminder();
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
    if (_items.isEmpty) LocalNotificationService.instance.cancelCartReminder();
  }

  void incrementAt(int index) {
    if (index < 0 || index >= _items.length) return;
    _items[index] = _items[index].copyWith(qty: _items[index].qty + 1);
    notifyListeners();
    _persist();
  }

  /// Себет тазарады (checkout сәтті өтті НЕМЕСЕ қолмен тазалады) — жоспарланған
  /// еске салу керек емес.
  void clear() {
    _items.clear();
    notifyListeners();
    _persist();
    LocalNotificationService.instance.cancelCartReminder();
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
  // Профиль табы ішінде тапсырыстар экранын көрсету (true) немесе профиль (false).
  bool _showOrders = false;

  @override
  void initState() {
    super.initState();
    // Гест checkout кезінде логинге кетіп, енді кіргеннен кейін ClientShell
    // жаңадан құрылды — Себетке қайта апарамыз (клиент сол жерден тоқтап еді).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cart = context.read<CartProvider>();
      if (cart.pendingCheckout) {
        cart.pendingCheckout = false;
        if (cart.items.isNotEmpty) setIndex(_cartTabIndex);
      }
    });
  }

  void setIndex(int i) => setState(() {
        _currentIndex = i;
        _showOrders = false; // таб ауысқанда тапсырыстар экранынан шығамыз
      });

  /// Себеттен төлемнен кейін: бірден Профиль → Тапсырыстарым экранына апару.
  void openOrdersFromCart() => setState(() {
        _currentIndex = 3;
        _showOrders = true;
      });

  static const List<_TabDef> _tabs = [
    _TabDef(Icons.home_outlined, Icons.home_rounded, 'Басты'),
    _TabDef(Icons.grid_view_outlined, Icons.grid_view_rounded, 'Каталог'),
    _TabDef(Icons.shopping_bag_outlined, Icons.shopping_bag_rounded, 'Себет'),
    _TabDef(Icons.person_outline_rounded, Icons.person_rounded, 'Профиль'),
  ];

  // Себет белгісі (badge) тұратын таб индексі.
  static const int _cartTabIndex = 2;

  @override
  Widget build(BuildContext context) {
    final cartCount = context.watch<CartProvider>().count;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    final screens = <Widget>[
      const ClientHomeScreen(),
      const ClientCatalogScreen(),
      ClientCartScreen(onOrderSuccess: openOrdersFromCart),
      // Профиль табы: профиль root немесе тапсырыстар экраны.
      _showOrders
          ? ClientOrdersScreen(
              onBack: () => setState(() => _showOrders = false))
          : ClientProfileScreen(
              onOpenOrders: () => setState(() => _showOrders = true)),
    ];

    return Scaffold(
      backgroundColor: cBg,
      body: IndexedStack(index: _currentIndex, children: screens),
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
                final active = i == _currentIndex;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setIndex(i);
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
                            if (i == _cartTabIndex && cartCount > 0)
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
                              color: active ? cGreen : cInk3,
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

class _TabDef {
  final IconData icon, activeIcon;
  final String label;
  const _TabDef(this.icon, this.activeIcon, this.label);
}
