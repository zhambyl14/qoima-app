import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_config.dart';
import '../../core/app_user.dart';
import '../../data/models/cart_item_model.dart';
import '../../data/models/courier_delivery_model.dart';
import '../../data/models/order_model.dart';
import '../../data/models/promo_model.dart';
import '../../data/services/client_service.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/qoima_design.dart';
import '../auth/client_login_screen.dart';
import 'client_shell.dart';

class ClientCartScreen extends StatefulWidget {
  /// Тапсырыс сәтті жасалғанда (төлемге дайын) шақырылады — ClientShell
  /// Профиль → Тапсырыстарым экранына ауыстырады. null болса (қонақ) — әрекет жоқ.
  final VoidCallback? onOrderSuccess;
  const ClientCartScreen({super.key, this.onOrderSuccess});

  @override
  State<ClientCartScreen> createState() => _ClientCartScreenState();
}

class _ClientCartScreenState extends State<ClientCartScreen> {
  final _service = ClientService();
  String _orderType = OrderModel.typeSmartReservation;
  final _addressCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _promoCtrl = TextEditingController();
  bool _isLoading = false;
  bool _applyingPromo = false;

  Set<String> _unavailableKeys = {};

  // Применённый промокод (привязан к магазину appliedAdminUid)
  PromoModel? _appliedPromo;
  String _appliedAdminUid = '';
  String? _promoError;

  String _itemKey(CartItemModel item) =>
      '${item.productId}_${item.batchId}_${item.size}';

  // Позиции магазина, к которому применён промокод
  List<CartItemModel> _promoItems(List<CartItemModel> items) {
    final p = _appliedPromo;
    if (p == null) return const [];
    return items.where((i) {
      if (i.adminUid != _appliedAdminUid) return false;
      if (p.scope == 'products') return p.productIds.contains(i.productId);
      return true;
    }).toList();
  }

  // Текущая скидка по промокоду от актуальной корзины (0 если уже не валиден)
  double _promoDiscount(List<CartItemModel> items) {
    final p = _appliedPromo;
    if (p == null) return 0;
    final base = _promoItems(items).fold<double>(0, (s, i) => s + i.subtotal);
    if (base < p.minOrder) return 0;
    return p.discountFor(base);
  }

  // Сумма экономии по скидкам на товары (зачёркнутая − итоговая)
  double _productSavings(List<CartItemModel> items) =>
      items.fold<double>(0, (s, i) => s + (i.originalSubtotal - i.subtotal));

  Future<void> _applyPromo() async {
    final cart = context.read<CartProvider>();
    final appUser = context.read<AppUser>();
    final code = _promoCtrl.text.trim();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _applyingPromo = true;
      _promoError = null;
    });
    try {
      // Пробуем по каждому магазину в корзине — берём первый подходящий
      final admins = cart.items.map((i) => i.adminUid).toSet();
      PromoResult? success;
      String? firstError;
      String okAdmin = '';
      for (final adminUid in admins) {
        final items =
            cart.items.where((i) => i.adminUid == adminUid).toList();
        final res = await _service.validatePromo(
          adminUid: adminUid,
          code: code,
          items: items,
          clientUid: appUser.uid,
        );
        if (res.isOk) {
          success = res;
          okAdmin = adminUid;
          break;
        }
        firstError ??= res.error;
      }
      if (!mounted) return;
      if (success != null) {
        setState(() {
          _appliedPromo = success!.promo;
          _appliedAdminUid = okAdmin;
          _promoError = null;
        });
      } else {
        setState(() {
          _appliedPromo = null;
          _appliedAdminUid = '';
          _promoError = firstError ?? 'Промокод не найден';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _promoError = 'Не удалось проверить промокод');
      }
    } finally {
      if (mounted) setState(() => _applyingPromo = false);
    }
  }

  void _removePromo() {
    setState(() {
      _appliedPromo = null;
      _appliedAdminUid = '';
      _promoError = null;
      _promoCtrl.clear();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAvailability());
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _noteCtrl.dispose();
    _promoCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkAvailability() async {
    final cart = context.read<CartProvider>();
    if (cart.items.isEmpty) {
      if (mounted) setState(() => _unavailableKeys = {});
      return;
    }
    try {
      final stores = await _service.getPublishedStores();
      final visibleByAdmin = {
        for (final s in stores) s.adminUid: s.visibleWarehouseIds,
      };
      final unavailable = <String>{};
      for (final item in cart.items) {
        final key = _itemKey(item);
        final visible = visibleByAdmin[item.adminUid] ?? [];
        if (!visible.contains(item.warehouseId)) {
          unavailable.add(key);
          continue;
        }
        try {
          final avail = await _service.getBatchAvailability(
              item.adminUid, item.productId, item.batchId);
          if ((avail[item.size] ?? 0) < item.qty) {
            unavailable.add(key);
          }
        } catch (_) {}
      }
      if (mounted) setState(() => _unavailableKeys = unavailable);
    } catch (_) {}
  }

  double _depositFor(double total) {
    if (_orderType == OrderModel.typeSmartReservation) {
      return (total * 0.1).ceilToDouble();
    }
    if (_orderType == OrderModel.typeDelivery) return total + _deliveryFeeFor();
    return total;
  }

  /// Delivery fee from central config — change AppConfig.deliveryFee to enable.
  double _deliveryFeeFor() =>
      _orderType == OrderModel.typeDelivery ? AppConfig.deliveryFee : 0.0;

  String _warehouseAddress(List<CartItemModel> items) =>
      items.isNotEmpty ? items.first.warehouseAddress : '';

  /// Төлем батырмасы: кірмеген → логин; кірген → бірден төлем (верификация жоқ).
  Future<void> _onCheckoutPressed() async {
    if (Supabase.instance.client.auth.currentUser == null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ClientLoginScreen()),
      );
      return;
    }
    await _showPaymentConfirmation();
  }

  Future<void> _showPaymentConfirmation() async {
    final cart = context.read<CartProvider>();
    final appUser = context.read<AppUser>();
    if (cart.items.isEmpty) return;

    if (_orderType == OrderModel.typeDelivery &&
        _addressCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Введите адрес доставки'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    final subtotal = cart.total;
    final promoDiscount = _promoDiscount(cart.items);
    final total = (subtotal - promoDiscount).clamp(0.0, subtotal);
    final deposit = _depositFor(total);
    final deliveryFee = _deliveryFeeFor();

    // Returns the bank name ('kaspi' / 'halyk') or null if cancelled.
    final bank = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaymentSheet(
        orderType: _orderType,
        subtotal: subtotal,
        promoDiscount: promoDiscount,
        promoCode: _appliedPromo?.code ?? '',
        total: total,
        deposit: deposit,
        deliveryFee: deliveryFee,
        warehouseAddress: _warehouseAddress(cart.items),
        deliveryAddress: _addressCtrl.text.trim(),
      ),
    );

    if (bank == null || bank.isEmpty || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await _checkAvailability();
      if (!mounted) return;
      if (_unavailableKeys.isNotEmpty) {
        final badItems = cart.items
            .where((i) => _unavailableKeys.contains(_itemKey(i)))
            .map((i) => '«${i.productName}»')
            .join(', ');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$badItems недоступен. Удалите из корзины.'),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ));
        setState(() => _isLoading = false);
        return;
      }

      final Map<String, List<CartItemModel>> byWarehouse = {};
      for (final item in cart.items) {
        byWarehouse.putIfAbsent(item.warehouseId, () => []).add(item);
      }

      // ── Промокод: распределяем скидку по суб-заказам нужного магазина ─────
      // Учёт used_count ведёт ровно один суб-заказ (usageOwner), отмена которого
      // вернёт счётчик ровно один раз.
      final promo = _appliedPromo;
      final totalPromoDiscount = _promoDiscount(cart.items);
      final promoShares = <String, double>{}; // warehouseId → скидка ₸
      String usageOwnerWh = '';
      if (promo != null && totalPromoDiscount > 0) {
        final adminWhTotals = <String, double>{};
        double adminTotal = 0;
        for (final entry in byWarehouse.entries) {
          if (entry.value.first.adminUid != _appliedAdminUid) continue;
          // только подходящие по scope позиции участвуют в сумме скидки
          final base = entry.value
              .where((i) =>
                  promo.scope != 'products' ||
                  promo.productIds.contains(i.productId))
              .fold<double>(0, (s, i) => s + i.subtotal);
          if (base <= 0) continue;
          adminWhTotals[entry.key] = base;
          adminTotal += base;
        }
        if (adminTotal > 0) {
          final keys = adminWhTotals.keys.toList();
          usageOwnerWh = keys.first;
          double assigned = 0;
          for (var i = 0; i < keys.length; i++) {
            final share = i == keys.length - 1
                ? (totalPromoDiscount - assigned)
                : (totalPromoDiscount * adminWhTotals[keys[i]]! / adminTotal)
                    .roundToDouble();
            promoShares[keys[i]] = share;
            assigned += share;
          }
        }
      }

      // deliveryFee lives on the courier_deliveries record (one per checkout),
      // NOT on individual sub-orders. Sub-orders always have deliveryFee: 0.
      OrderModel? firstPlacedOrder;
      final placedOrders = <OrderModel>[];
      for (final entry in byWarehouse.entries) {
        final whItems = entry.value;
        final first = whItems.first;
        final whTotal = whItems.fold<double>(0, (s, i) => s + i.subtotal);
        final whPromo = (promoShares[entry.key] ?? 0).clamp(0.0, whTotal);
        final whFinal = (whTotal - whPromo).clamp(0.0, whTotal);
        final depositAmt = _orderType == OrderModel.typeSmartReservation
            ? (whFinal * 0.1).ceilToDouble()
            : whFinal; // delivery fee excluded from sub-order deposit
        final isUsageOwner = entry.key == usageOwnerWh;
        final order = OrderModel(
          id: '',
          clientPhone: appUser.phone,
          clientName: appUser.name,
          clientUid: appUser.uid,
          adminUid: first.adminUid,
          storeName: first.storeName,
          warehouseId: entry.key,
          warehouseAddress: first.warehouseAddress,
          items: List.from(whItems),
          status: OrderModel.statusPending,
          orderType: _orderType,
          createdAt: DateTime.now(),
          address: _addressCtrl.text.trim(),
          note: _noteCtrl.text.trim(),
          depositAmount: depositAmt,
          deliveryFee: 0.0, // fee tracked separately in courier_deliveries
          promoId: whPromo > 0 && promo != null ? promo.id : '',
          promoCode: whPromo > 0 && promo != null ? promo.code : '',
          promoDiscount: whPromo,
          promoCountsUsage: isUsageOwner && promo != null,
        );
        final placed = await _service.placeOrder(order);
        placedOrders.add(placed);
        firstPlacedOrder ??= placed;
      }

      // Confirm payment immediately — moves order to confirmed / reserved.
      final fsvc = FirestoreService();
      for (final placed in placedOrders) {
        await fsvc.confirmPaymentByClient(placed, bank);
      }

      // For delivery orders: create ONE courier_deliveries record.
      // This is supplementary — if it fails, the order is still valid.
      if (_orderType == OrderModel.typeDelivery && firstPlacedOrder != null) {
        try {
          final whAddresses = byWarehouse.values
              .map((items) => items.first.warehouseAddress)
              .where((a) => a.isNotEmpty)
              .toSet()
              .toList();
          await _service.createCourierDelivery(CourierDeliveryModel(
            id: '',
            orderId: firstPlacedOrder.id,
            orderNumber: firstPlacedOrder.orderNumber,
            amount: AppConfig.deliveryFee,
            address: _addressCtrl.text.trim(),
            clientName: appUser.name,
            clientPhone: appUser.phone,
            warehouseAddresses: whAddresses,
            createdAt: DateTime.now(),
            status: CourierDeliveryModel.statusNew,
          ));
        } catch (_) {
          // Non-fatal: orders are placed. Courier record will sync later.
        }
      }

      if (!mounted) return;
      cart.clear();
      _appliedPromo = null;
      _appliedAdminUid = '';
      _promoCtrl.clear();
      // Төлемге дайын тапсырыс жасалды → Профиль → Тапсырыстарым экранына
      // апарамыз, сонда клиент Kaspi/Halyk арқылы НАҚТЫ төлейді.
      final shell = context.findAncestorStateOfType<ClientShellState>();
      if (widget.onOrderSuccess != null) {
        widget.onOrderSuccess!();
      } else {
        shell?.openOrdersFromCart();
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Тапсырыс қабылданды! ✓'),
        backgroundColor: cGreen,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final itemCount = cart.items.length;

    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: 'Корзина',
          subtitle: itemCount == 0
              ? 'Пусто'
              : '$itemCount ${_pluralItem(itemCount)}',
          action: itemCount > 0
              ? QHeaderBtn(
                  Icons.delete_sweep_outlined,
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text('Очистить корзину',
                          style: manrope(17, FontWeight.w700, color: cInk)),
                      content: Text('Убрать все товары?',
                          style: manrope(14, FontWeight.w500, color: cInk2)),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text('Нет',
                                style: manrope(14, FontWeight.w600,
                                    color: cInk2))),
                        TextButton(
                            onPressed: () {
                              cart.clear();
                              Navigator.pop(context);
                            },
                            child: Text('Да',
                                style: manrope(14, FontWeight.w600,
                                    color: cRed))),
                      ],
                    ),
                  ),
                )
              : null,
        ),
        Expanded(
          child: cart.items.isEmpty
              ? Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                      const Icon(Icons.shopping_cart_outlined,
                          size: 64, color: cInk3),
                      const SizedBox(height: 16),
                      Text('Корзина пуста',
                          style: manrope(16, FontWeight.w500, color: cInk2)),
                    ]))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  children: [
                    // Cart items
                    ...cart.items.asMap().entries.map((entry) {
                      final i = entry.key;
                      final item = entry.value;
                      return _CartItemCard(
                        item: item,
                        isUnavailable:
                            _unavailableKeys.contains(_itemKey(item)),
                        onDecrement: () {
                          cart.decrementAt(i);
                          _checkAvailability();
                        },
                        onIncrement: () {
                          cart.incrementAt(i);
                          _checkAvailability();
                        },
                        onRemove: () {
                          cart.removeAt(i);
                          _checkAvailability();
                        },
                      );
                    }),

                    const SizedBox(height: 8),
                    QSecLabel('Способ получения'),

                    // Delivery methods
                    ...[
                      (
                        OrderModel.typeSmartReservation,
                        Icons.timer_outlined,
                        'Смарт-Бронь',
                        'Бронь на 1 час, 10% депозит',
                        'blue',
                      ),
                      (
                        OrderModel.typeClickCollect,
                        Icons.qr_code_rounded,
                        'Click & Collect',
                        '100% онлайн, самовывоз',
                        'green',
                      ),
                      (
                        OrderModel.typeDelivery,
                        Icons.local_shipping_outlined,
                        'Доставка',
                        AppConfig.deliveryFee > 0
                            ? 'Курьером по адресу +${AppConfig.deliveryFee.toStringAsFixed(0)} ₸'
                            : 'Курьером по адресу · Бесплатно',
                        'amber',
                      ),
                    ].map((t) {
                      final (type, icon, title, subtitle, tone) = t;
                      final selected = _orderType == type;
                      return GestureDetector(
                        onTap: () => setState(() => _orderType = type),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: cSurface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: selected ? cGreen : cLine,
                              width: selected ? 1.5 : 1,
                            ),
                            boxShadow: kShadowSm,
                          ),
                          child: Row(children: [
                            QIconTile(
                              icon: Icon(_iconFor(type),
                                  color: _iconColor(tone), size: 19),
                              tone: tone,
                              size: 40,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(title,
                                        style: manrope(
                                            14, FontWeight.w700,
                                            color: cInk)),
                                    Text(subtitle,
                                        style: manrope(
                                            12, FontWeight.w500,
                                            color: cInk3)),
                                  ]),
                            ),
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: selected ? cGreen : cSurface,
                                border: Border.all(
                                  color: selected ? cGreen : cLine,
                                  width: 2,
                                ),
                              ),
                              child: selected
                                  ? const Icon(Icons.check_rounded,
                                      size: 13, color: Colors.white)
                                  : null,
                            ),
                          ]),
                        ),
                      );
                    }),

                    // Pickup address info
                    if (_orderType != OrderModel.typeDelivery &&
                        _warehouseAddress(cart.items).isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cGreenTint,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(children: [
                          const Icon(Icons.location_on_outlined,
                              color: cGreenDeep, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(
                            'Получение: ${_warehouseAddress(cart.items)}',
                            style: manrope(12, FontWeight.w500,
                                color: cGreenDeep),
                          )),
                        ]),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Delivery address input
                    if (_orderType == OrderModel.typeDelivery) ...[
                      Text('Адрес доставки *',
                          style: manrope(12.5, FontWeight.w700, color: cInk2)),
                      const SizedBox(height: 6),
                      // Saved addresses picker
                      StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _service.watchAddresses(),
                        builder: (context, snap) {
                          final saved = snap.data ?? [];
                          if (saved.isEmpty) return const SizedBox.shrink();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Сохранённые адреса',
                                  style: manrope(11.5, FontWeight.w600,
                                      color: cInk3)),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: saved.map((a) {
                                  final label = a['label'] as String? ?? '';
                                  final addr = a['address'] as String? ?? '';
                                  final display =
                                      label.isNotEmpty ? label : addr;
                                  return GestureDetector(
                                    onTap: () {
                                      setState(() =>
                                          _addressCtrl.text = addr);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: _addressCtrl.text == addr
                                            ? cGreen
                                            : cSurface,
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        border: Border.all(
                                            color: _addressCtrl.text == addr
                                                ? cGreen
                                                : cLine),
                                      ),
                                      child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.location_on_outlined,
                                                size: 13,
                                                color: _addressCtrl.text ==
                                                        addr
                                                    ? Colors.white
                                                    : cInk3),
                                            const SizedBox(width: 4),
                                            Text(display,
                                                style: manrope(
                                                    12.5,
                                                    FontWeight.w600,
                                                    color: _addressCtrl
                                                                .text ==
                                                            addr
                                                        ? Colors.white
                                                        : cInk)),
                                          ]),
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 10),
                            ],
                          );
                        },
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: cSurface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: cLine, width: 1.5),
                        ),
                        child: TextField(
                          controller: _addressCtrl,
                          style: manrope(14, FontWeight.w500, color: cInk),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Город, улица, дом',
                            hintStyle:
                                manrope(14, FontWeight.w500, color: cInk3),
                            prefixIcon: const Icon(Icons.location_on_outlined,
                                color: cInk3, size: 19),
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Promo code
                    QSecLabel('Промокод'),
                    _PromoField(
                      controller: _promoCtrl,
                      applied: _appliedPromo,
                      discount: _promoDiscount(cart.items),
                      error: _promoError,
                      loading: _applyingPromo,
                      onApply: _applyPromo,
                      onRemove: _removePromo,
                    ),
                    const SizedBox(height: 12),

                    // Note
                    Text('Примечание',
                        style: manrope(12.5, FontWeight.w700, color: cInk2)),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: cSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cLine, width: 1.5),
                      ),
                      child: TextField(
                        controller: _noteCtrl,
                        maxLines: 2,
                        style: manrope(14, FontWeight.w500, color: cInk),
                        decoration: InputDecoration(
                          hintText: 'Дополнительная информация...',
                          hintStyle:
                              manrope(14, FontWeight.w500, color: cInk3),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.all(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 120),
                  ],
                ),
        ),
      ]),
      bottomNavigationBar: cart.items.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                decoration: const BoxDecoration(
                  color: cSurface,
                  border: Border(top: BorderSide(color: cLine)),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Builder(builder: (_) {
                    final promoDiscount = _promoDiscount(cart.items);
                    final productSavings = _productSavings(cart.items);
                    final finalTotal =
                        (cart.total - promoDiscount).clamp(0.0, cart.total);
                    return Column(children: [
                      if (productSavings > 0)
                        _SummaryLine('Скидка по акции',
                            '−${money(productSavings)}', color: cGreen),
                      if (promoDiscount > 0)
                        _SummaryLine(
                            'Промокод ${_appliedPromo?.code ?? ''}',
                            '−${money(promoDiscount)}',
                            color: cGreen),
                      if (productSavings > 0 || promoDiscount > 0)
                        const SizedBox(height: 8),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _orderType == OrderModel.typeSmartReservation
                                  ? 'К оплате сейчас (депозит 10%)'
                                  : 'К оплате',
                              style: manrope(13.5, FontWeight.w600,
                                  color: cInk2),
                            ),
                            Text(
                              money(_depositFor(finalTotal)),
                              style:
                                  manrope(20, FontWeight.w800, color: cInk),
                            ),
                          ]),
                    ]);
                  }),
                  const SizedBox(height: 11),
                  QPrimaryButton(
                    label: _orderType == OrderModel.typeSmartReservation
                        ? 'Забронировать'
                        : 'Оплатить',
                    isLoading: _isLoading,
                    onPressed: (_isLoading || _unavailableKeys.isNotEmpty)
                        ? null
                        : _onCheckoutPressed,
                    height: 54,
                  ),
                ]),
              ),
            ),
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case OrderModel.typeClickCollect:
        return Icons.qr_code_rounded;
      case OrderModel.typeDelivery:
        return Icons.local_shipping_outlined;
      default:
        return Icons.timer_outlined;
    }
  }

  Color _iconColor(String tone) {
    switch (tone) {
      case 'amber':
        return cAmber;
      case 'green':
        return cGreen;
      default:
        return cBlue;
    }
  }

  String _pluralItem(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'товар';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) {
      return 'товара';
    }
    return 'товаров';
  }
}

// ── Cart item card ─────────────────────────────────────────────────────────────
class _CartItemCard extends StatelessWidget {
  final CartItemModel item;
  final bool isUnavailable;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onRemove;
  const _CartItemCard({
    required this.item,
    required this.isUnavailable,
    required this.onDecrement,
    required this.onIncrement,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isUnavailable ? cRed.withValues(alpha: 0.44) : cLine,
        ),
        boxShadow: kShadowSm,
      ),
      child: Row(children: [
        SizedBox(
          width: 72,
          height: 72,
          child: Opacity(
            opacity: isUnavailable ? 0.55 : 1.0,
            child: QShoeImage(
              imageUrl: item.imageUrl.isNotEmpty ? item.imageUrl : null,
              height: 72,
              tone: item.productId.hashCode % 5,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.productName,
                  style: manrope(13.5, FontWeight.w700, color: cInk),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('Размер ${item.size}',
                  style: manrope(12, FontWeight.w500, color: cInk3)),
              const SizedBox(height: 6),
              if (isUnavailable)
                QPill('Товар закончился', tone: 'red',
                    icon: const Icon(Icons.info_outline,
                        size: 12, color: Color(0xFFB11A2B)))
              else if (item.hasDiscount)
                Row(children: [
                  Text(money(item.subtotal),
                      style: manrope(15.5, FontWeight.w800, color: cRed)),
                  const SizedBox(width: 6),
                  Text(money(item.originalSubtotal),
                      style: manrope(12, FontWeight.w500, color: cInk3)
                          .copyWith(decoration: TextDecoration.lineThrough)),
                ])
              else
                Text(money(item.subtotal),
                    style: manrope(15.5, FontWeight.w800, color: cInk)),
            ],
          ),
        ),
        // Quantity stepper
        if (isUnavailable)
          GestureDetector(
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.delete_outline_rounded, color: cRed, size: 20),
            ),
          )
        else
          Row(mainAxisSize: MainAxisSize.min, children: [
            _QtyBtn(
              icon: item.qty <= 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
              color: item.qty <= 1 ? cRed : cInk2,
              onTap: onDecrement,
            ),
            SizedBox(
              width: 28,
              child: Text('${item.qty}',
                  textAlign: TextAlign.center,
                  style: manrope(15, FontWeight.w800, color: cInk)),
            ),
            _QtyBtn(icon: Icons.add_rounded, color: cGreen, onTap: onIncrement),
          ]),
      ]),
    );
  }
}

// ── Quantity button ────────────────────────────────────────────────────────────
class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _QtyBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      );
}

// ── Payment sheet ──────────────────────────────────────────────────────────────
class _PaymentSheet extends StatelessWidget {
  final String orderType, warehouseAddress, deliveryAddress, promoCode;
  final double total, deposit, deliveryFee, subtotal, promoDiscount;
  const _PaymentSheet({
    required this.orderType,
    required this.subtotal,
    required this.promoDiscount,
    required this.promoCode,
    required this.total,
    required this.deposit,
    required this.deliveryFee,
    required this.warehouseAddress,
    required this.deliveryAddress,
  });

  @override
  Widget build(BuildContext context) {
    final isSmartRes = orderType == OrderModel.typeSmartReservation;
    final isDelivery = orderType == OrderModel.typeDelivery;
    final isCC = orderType == OrderModel.typeClickCollect;

    final String typeLabel =
        isSmartRes ? 'Смарт-Бронь' : isCC ? 'Click & Collect' : 'Доставка';

    return Container(
      decoration: const BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40, height: 4,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
              color: cLine, borderRadius: BorderRadius.circular(2)),
        ),
        QPill(typeLabel, tone: isSmartRes ? 'blue' : isCC ? 'green' : 'amber'),
        const SizedBox(height: 16),
        Text(money(deposit),
            style: manrope(34, FontWeight.w800, color: cInk, letterSpacing: -1)),
        const SizedBox(height: 4),
        Text(
          isSmartRes ? 'К оплате сейчас (10% депозит)' : 'Итого к оплате',
          style: manrope(13, FontWeight.w500, color: cInk2),
        ),
        if (isSmartRes) ...[
          const SizedBox(height: 6),
          Text(
            'В магазине: ${money((total - deposit).clamp(0, total))}',
            style: manrope(13, FontWeight.w500, color: cInk3),
          ),
        ],
        if (isDelivery) ...[
          const SizedBox(height: 6),
          Text(
            deliveryFee > 0
                ? 'Товары: ${money(total)}  +  Доставка: ${money(deliveryFee)}'
                : 'Товары: ${money(total)}  +  Доставка: Бесплатно',
            style: manrope(13, FontWeight.w500, color: cInk3),
          ),
        ],
        const SizedBox(height: 16),
        Container(height: 1, color: cLine),
        const SizedBox(height: 12),
        // Подытог → Промокод → Итого
        if (promoDiscount > 0) ...[
          _SummaryLine('Подытог', money(subtotal), color: cInk2),
          _SummaryLine(
              promoCode.isNotEmpty ? 'Промокод $promoCode' : 'Промокод',
              '−${money(promoDiscount)}',
              color: cGreen),
          _SummaryLine('Итого', money(total), color: cInk, bold: true),
          const SizedBox(height: 8),
        ],
        if (!isDelivery && warehouseAddress.isNotEmpty)
          _InfoRow(Icons.location_on_outlined, 'Адрес получения',
              warehouseAddress),
        if (isDelivery && deliveryAddress.isNotEmpty)
          _InfoRow(Icons.local_shipping_outlined, 'Доставка', deliveryAddress),
        if (isSmartRes)
          _InfoRow(Icons.timer_outlined, 'Срок брони', '1 час'),
        const SizedBox(height: 20),
        Text(
          isSmartRes ? 'Депозит банкі' : 'Банк арқылы төлеу',
          style: manrope(13, FontWeight.w700, color: cInk2),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, 'kaspi'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEB3333),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Kaspi',
                style: manrope(15, FontWeight.w700, color: Colors.white)),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, 'halyk'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A550),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Halyk Bank',
                style: manrope(15, FontWeight.w700, color: Colors.white)),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text('Отмена',
              style: manrope(14, FontWeight.w600, color: cInk3)),
        ),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: cGreen),
          const SizedBox(width: 8),
          Expanded(
              child: RichText(
                  text: TextSpan(children: [
            TextSpan(
                text: '$label: ',
                style: manrope(13, FontWeight.w500, color: cInk2)),
            TextSpan(
                text: value,
                style: manrope(13, FontWeight.w700, color: cInk)),
          ]))),
        ]),
      );
}

// ── Summary line (Подытог / Скидка / Промокод / Итого) ──────────────────────────
class _SummaryLine extends StatelessWidget {
  final String label, value;
  final Color color;
  final bool bold;
  const _SummaryLine(this.label, this.value,
      {required this.color, this.bold = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: manrope(bold ? 14.5 : 13, FontWeight.w600,
                    color: bold ? cInk : cInk2)),
            Text(value,
                style: manrope(bold ? 16 : 13.5,
                    bold ? FontWeight.w800 : FontWeight.w700,
                    color: color)),
          ],
        ),
      );
}

// ── Promo code field ────────────────────────────────────────────────────────────
class _PromoField extends StatelessWidget {
  final TextEditingController controller;
  final PromoModel? applied;
  final double discount;
  final String? error;
  final bool loading;
  final VoidCallback onApply;
  final VoidCallback onRemove;

  const _PromoField({
    required this.controller,
    required this.applied,
    required this.discount,
    required this.error,
    required this.loading,
    required this.onApply,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    // Применён и действует
    if (applied != null) {
      final ineffective = discount <= 0;
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: ineffective ? cAmberTint : cGreenTint,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: ineffective
                  ? cAmber.withValues(alpha: 0.4)
                  : cGreen.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          Icon(ineffective ? Icons.info_outline : Icons.check_circle_rounded,
              size: 18, color: ineffective ? cAmber : cGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(applied!.code,
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: cGreenDeep)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                        color: ineffective ? cAmber : cGreen,
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(ineffective ? 'Не активен' : 'Применён',
                        style: manrope(10, FontWeight.w700,
                            color: Colors.white)),
                  ),
                ]),
                Text(
                  ineffective
                      ? 'Не хватает до минимальной суммы заказа'
                      : 'Скидка −${money(discount)}',
                  style: manrope(12, FontWeight.w600,
                      color: ineffective ? cAmber : cGreenDeep),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18, color: cInk3),
            onPressed: onRemove,
          ),
        ]),
      );
    }

    // Поле ввода
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: cSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: error != null ? cRed : cLine, width: 1.5),
            ),
            child: TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              style: manrope(14, FontWeight.w700, color: cInk),
              decoration: InputDecoration(
                hintText: 'Введите промокод',
                hintStyle: manrope(14, FontWeight.w500, color: cInk3),
                prefixIcon:
                    const Icon(Icons.local_offer_outlined, color: cInk3, size: 19),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: loading ? null : onApply,
            style: ElevatedButton.styleFrom(
              backgroundColor: cGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Text('Применить',
                    style: manrope(14, FontWeight.w700, color: Colors.white)),
          ),
        ),
      ]),
      if (error != null) ...[
        const SizedBox(height: 6),
        Text(error!, style: manrope(12, FontWeight.w600, color: cRed)),
      ],
    ]);
  }
}
