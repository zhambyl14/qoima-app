import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../data/models/cart_item_model.dart';
import '../../data/models/order_model.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';
import 'client_shell.dart';

class ClientCartScreen extends StatefulWidget {
  const ClientCartScreen({super.key});

  @override
  State<ClientCartScreen> createState() => _ClientCartScreenState();
}

class _ClientCartScreenState extends State<ClientCartScreen> {
  final _service = ClientService();
  String _orderType = OrderModel.typeSmartReservation;
  final _addressCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _isLoading = false;

  Set<String> _unavailableKeys = {};

  String _itemKey(CartItemModel item) =>
      '${item.productId}_${item.batchId}_${item.size}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAvailability());
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _noteCtrl.dispose();
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

  double _deliveryFeeFor() =>
      _orderType == OrderModel.typeDelivery ? 1500.0 : 0.0;

  String _warehouseAddress(List<CartItemModel> items) =>
      items.isNotEmpty ? items.first.warehouseAddress : '';

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

    final total = cart.total;
    final deposit = _depositFor(total);
    final deliveryFee = _deliveryFeeFor();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaymentSheet(
        orderType: _orderType,
        total: total,
        deposit: deposit,
        deliveryFee: deliveryFee,
        warehouseAddress: _warehouseAddress(cart.items),
        deliveryAddress: _addressCtrl.text.trim(),
      ),
    );

    if (confirmed != true || !mounted) return;

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
      // Delivery fee is charged once (first order only) regardless of how many
      // warehouses are involved, so the client always pays a single 1500 ₸ fee.
      int orderCount = 0;
      bool deliveryCharged = false;
      for (final entry in byWarehouse.entries) {
        final whItems = entry.value;
        final first = whItems.first;
        final whTotal = whItems.fold<double>(0, (s, i) => s + i.subtotal);
        final appliedFee = (!deliveryCharged) ? _deliveryFeeFor() : 0.0;
        if (appliedFee > 0) deliveryCharged = true;
        final depositAmt = _orderType == OrderModel.typeSmartReservation
            ? (whTotal * 0.1).ceilToDouble()
            : _orderType == OrderModel.typeDelivery
                ? whTotal + appliedFee
                : whTotal;
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
          status: _orderType == OrderModel.typeSmartReservation
              ? OrderModel.statusReserved
              : OrderModel.statusPending,
          orderType: _orderType,
          createdAt: DateTime.now(),
          address: _addressCtrl.text.trim(),
          note: _noteCtrl.text.trim(),
          depositAmount: depositAmt,
          deliveryFee: appliedFee,
        );
        await _service.placeOrder(order);
        orderCount++;
      }
      if (!mounted) return;
      cart.clear();
      context.findAncestorStateOfType<ClientShellState>()?.setIndex(2);
      if (orderCount > 1) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$orderCount заказа создано'),
          behavior: SnackBarBehavior.floating,
        ));
      }
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
                        'Курьером по адресу +1 500 ₸',
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
                      Container(
                        decoration: BoxDecoration(
                          color: cSurface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: cLine, width: 1.5),
                        ),
                        child: TextField(
                          controller: _addressCtrl,
                          style: manrope(14, FontWeight.w500, color: cInk),
                          decoration: InputDecoration(
                            hintText: 'Город, улица, дом',
                            hintStyle:
                                manrope(14, FontWeight.w500, color: cInk3),
                            prefixIcon: const Icon(Icons.location_on_outlined,
                                color: cInk3, size: 19),
                            border: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

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
                          border: InputBorder.none,
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
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _orderType == OrderModel.typeSmartReservation
                              ? 'К оплате сейчас (депозит 10%)'
                              : 'К оплате',
                          style: manrope(13.5, FontWeight.w600, color: cInk2),
                        ),
                        Text(
                          money(_depositFor(cart.total)),
                          style: manrope(20, FontWeight.w800, color: cInk),
                        ),
                      ]),
                  const SizedBox(height: 11),
                  QPrimaryButton(
                    label: _orderType == OrderModel.typeSmartReservation
                        ? 'Забронировать'
                        : 'Оплатить',
                    isLoading: _isLoading,
                    onPressed: (_isLoading || _unavailableKeys.isNotEmpty)
                        ? null
                        : _showPaymentConfirmation,
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
  final VoidCallback onRemove;
  const _CartItemCard(
      {required this.item,
      required this.isUnavailable,
      required this.onRemove});

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
        Opacity(
          opacity: isUnavailable ? 0.55 : 1.0,
          child: QShoeImage(
            imageUrl: item.imageUrl.isNotEmpty ? item.imageUrl : null,
            height: 72,
            tone: item.productId.hashCode % 5,
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
              isUnavailable
                  ? QPill('Товар закончился', tone: 'red',
                      icon: const Icon(Icons.info_outline,
                          size: 12, color: Color(0xFFB11A2B)))
                  : item.qty > 1
                      ? RichText(
                          text: TextSpan(children: [
                            TextSpan(
                                text: '${item.qty} × ',
                                style: manrope(13, FontWeight.w500, color: cInk3)),
                            TextSpan(
                                text: money(item.price),
                                style: manrope(15.5, FontWeight.w800, color: cInk)),
                          ]),
                        )
                      : Text(money(item.price),
                          style: manrope(15.5, FontWeight.w800, color: cInk)),
            ],
          ),
        ),
        GestureDetector(
          onTap: onRemove,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(Icons.delete_outline_rounded,
                color: isUnavailable ? cRed : cInk3, size: 19),
          ),
        ),
      ]),
    );
  }
}

// ── Payment sheet ──────────────────────────────────────────────────────────────
class _PaymentSheet extends StatelessWidget {
  final String orderType, warehouseAddress, deliveryAddress;
  final double total, deposit, deliveryFee;
  const _PaymentSheet({
    required this.orderType,
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

    final Color accentColor =
        isSmartRes ? cBlue : isCC ? cGreen : cAmber;

    final String typeLabel =
        isSmartRes ? 'Смарт-Бронь' : isCC ? 'Click & Collect' : 'Доставка';

    return Container(
      decoration: const BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
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
            'Товары: ${money(total)}  +  Доставка: ${money(deliveryFee)}',
            style: manrope(13, FontWeight.w500, color: cInk3),
          ),
        ],
        const SizedBox(height: 16),
        Container(height: 1, color: cLine),
        const SizedBox(height: 12),
        if (!isDelivery && warehouseAddress.isNotEmpty)
          _InfoRow(Icons.location_on_outlined, 'Адрес получения',
              warehouseAddress),
        if (isDelivery && deliveryAddress.isNotEmpty)
          _InfoRow(Icons.local_shipping_outlined, 'Доставка', deliveryAddress),
        if (isSmartRes)
          _InfoRow(Icons.timer_outlined, 'Срок брони', '1 час'),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15)),
            ),
            child: Text(
              isSmartRes
                  ? 'Подтвердить и забронировать'
                  : 'Подтвердить и оплатить',
              style: manrope(15.5, FontWeight.w700, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
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
