import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../data/models/cart_item_model.dart';
import '../../data/models/order_model.dart';
import '../../data/services/client_service.dart';
import '../../theme/app_theme.dart';
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

  // Қолжетімсіз товарлардың кілттері: "productId_batchId_size"
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

  /// Себеттегі товарлардың қолжетімдігін тексереді:
  /// (1) қойма жасырылған ба, (2) сатылым санасы жеткілікті ме.
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
        // Қойма көрінуін тексер
        final visible = visibleByAdmin[item.adminUid] ?? [];
        if (!visible.contains(item.warehouseId)) {
          unavailable.add(key);
          continue;
        }
        // Қор санасын тексер
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
    if (_orderType == OrderModel.typeDelivery) { return total + _deliveryFeeFor(); }
    return total; // ClickCollect
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
      // Қолжетімдікті жаңарт — жасырылған/сатылып кеткен товарды тоқтат
      await _checkAvailability();
      if (!mounted) return;
      if (_unavailableKeys.isNotEmpty) {
        final badItems = cart.items
            .where((i) => _unavailableKeys.contains(_itemKey(i)))
            .map((i) => '«${i.productName}»')
            .join(', ');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '$badItems қолжетімсіз (сатылып кетті немесе дүкен жаңартылды). '
              'Себеттен алып тастаңыз.'),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ));
        setState(() => _isLoading = false);
        return;
      }

      // warehouseId бойынша топта — әр қоймаға бөлек тапсырыс
      final Map<String, List<CartItemModel>> byWarehouse = {};
      for (final item in cart.items) {
        byWarehouse.putIfAbsent(item.warehouseId, () => []).add(item);
      }
      int orderCount = 0;
      for (final entry in byWarehouse.entries) {
        final whItems = entry.value;
        final first = whItems.first;
        final whTotal = whItems.fold<double>(0, (s, i) => s + i.subtotal);
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
          depositAmount: _depositFor(whTotal),
          deliveryFee: _deliveryFeeFor(),
        );
        await _service.placeOrder(order);
        orderCount++;
      }
      if (!mounted) return;
      cart.clear();
      context.findAncestorStateOfType<ClientShellState>()?.setIndex(2);
      if (orderCount > 1) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$orderCount тапсырыс құрылды'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppTheme.danger,
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

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Корзина'),
        backgroundColor: AppTheme.primary,
        actions: [
          if (cart.items.isNotEmpty)
            TextButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Очистить корзину'),
                  content: const Text('Убрать все товары из корзины?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Нет')),
                    TextButton(
                        onPressed: () {
                          cart.clear();
                          Navigator.pop(context);
                        },
                        child: const Text('Да',
                            style: TextStyle(color: AppTheme.danger))),
                  ],
                ),
              ),
              child:
                  const Text('Очистить', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: cart.items.isEmpty
          ? const Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shopping_cart_outlined,
                        size: 64, color: AppTheme.textHint),
                    SizedBox(height: 16),
                    Text('Корзина пуста',
                        style: TextStyle(
                            fontSize: 16, color: AppTheme.textSecondary)),
                  ]),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ...cart.items.asMap().entries.map((entry) {
                  final i = entry.key;
                  final item = entry.value;
                  return _CartItemTile(
                    item: item,
                    onRemove: () {
                      cart.removeAt(i);
                      _checkAvailability();
                    },
                    isUnavailable: _unavailableKeys.contains(_itemKey(item)),
                  );
                }),
                const SizedBox(height: 16),
                const Text('Способ получения',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 10),
                ...[
                  (
                    OrderModel.typeSmartReservation,
                    Icons.timer_outlined,
                    'Смарт-Бронь',
                    'Забронируйте на 1 час, чтобы примерить в магазине',
                    '10% депозит',
                    const Color(0xFF3B82F6),
                  ),
                  (
                    OrderModel.typeClickCollect,
                    Icons.qr_code_rounded,
                    'Click & Collect',
                    'Оплатите онлайн и заберите из склада',
                    '100% онлайн',
                    AppTheme.success,
                  ),
                  (
                    OrderModel.typeDelivery,
                    Icons.local_shipping_outlined,
                    'Доставка',
                    'Укажите адрес и получите курьером',
                    '+1500 ₸',
                    const Color(0xFFF59E0B),
                  ),
                ].map((t) {
                  final (type, icon, title, subtitle, badge, color) = t;
                  final selected = _orderType == type;
                  return GestureDetector(
                    onTap: () => setState(() => _orderType = type),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: selected
                            ? color.withValues(alpha: 0.07)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected ? color : AppTheme.border,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Row(children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: (selected ? color : AppTheme.textHint)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(icon,
                              color: selected ? color : AppTheme.textHint,
                              size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text(title,
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: selected
                                          ? color
                                          : AppTheme.textPrimary)),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(badge,
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: color)),
                              ),
                            ]),
                            const SizedBox(height: 2),
                            Text(subtitle,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary)),
                          ],
                        )),
                        if (selected)
                          Icon(Icons.check_circle_rounded,
                              color: color, size: 22),
                      ]),
                    ),
                  );
                }),
                if (_orderType != OrderModel.typeDelivery &&
                    _warehouseAddress(cart.items).isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.location_on_outlined,
                          color: AppTheme.primary, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(
                        'Адрес получения: ${_warehouseAddress(cart.items)}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w500),
                      )),
                    ]),
                  ),
                ],
                if (_orderType == OrderModel.typeDelivery) ...[
                  const SizedBox(height: 12),
                  const Text('Адрес доставки *',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _addressCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Город, улица, дом, квартира',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Text('Примечание (необязательно)',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _noteCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      hintText: 'Дополнительная информация...'),
                ),
                const SizedBox(height: 20),
                _PaymentSummaryCard(
                  orderType: _orderType,
                  total: cart.total,
                  deposit: _depositFor(cart.total),
                  deliveryFee: _deliveryFeeFor(),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: (_isLoading || _unavailableKeys.isNotEmpty)
                        ? null
                        : _showPaymentConfirmation,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                                const Icon(Icons.lock_outline, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  _orderType == OrderModel.typeSmartReservation
                                      ? 'Забронировать — ${_depositFor(cart.total).toStringAsFixed(0)} ₸'
                                      : 'Оплатить — ${_depositFor(cart.total).toStringAsFixed(0)} ₸',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700),
                                ),
                              ]),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

// ── Payment summary card ───────────────────────────────────────────────────────
class _PaymentSummaryCard extends StatelessWidget {
  final String orderType;
  final double total, deposit, deliveryFee;
  const _PaymentSummaryCard({
    required this.orderType,
    required this.total,
    required this.deposit,
    required this.deliveryFee,
  });

  @override
  Widget build(BuildContext context) {
    final isSmartRes = orderType == OrderModel.typeSmartReservation;
    final isDelivery = orderType == OrderModel.typeDelivery;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(children: [
        _Row('Сумма товаров', '${total.toStringAsFixed(0)} ₸'),
        if (isDelivery)
          _Row('Доставка', '+${deliveryFee.toStringAsFixed(0)} ₸',
              valueColor: const Color(0xFFF59E0B)),
        const Divider(height: 16),
        if (isSmartRes) ...[
          _Row('Оплата сейчас (10%)', '${deposit.toStringAsFixed(0)} ₸',
              valueColor: AppTheme.primary, bold: true),
          _Row('Доплата в магазине (90%)',
              '${(total - deposit).clamp(0, total).toStringAsFixed(0)} ₸',
              valueColor: AppTheme.textSecondary),
        ] else
          _Row('Сумма к оплате', '${deposit.toStringAsFixed(0)} ₸',
              valueColor: AppTheme.primary, bold: true),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final String label, value;
  final Color? valueColor;
  final bool bold;
  const _Row(this.label, this.value, {this.valueColor, this.bold = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          Text(value,
              style: TextStyle(
                  fontSize: bold ? 16 : 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: valueColor ?? AppTheme.textPrimary)),
        ]),
      );
}

// ── Payment confirmation bottom sheet ─────────────────────────────────────────
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

    final Color accentColor = isSmartRes
        ? const Color(0xFF3B82F6)
        : isCC
            ? AppTheme.success
            : const Color(0xFFF59E0B);

    final String typeLabel = isSmartRes
        ? 'Смарт-Бронь'
        : isCC
            ? 'Click & Collect'
            : 'Доставка';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
              color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(typeLabel,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: accentColor)),
        ),
        const SizedBox(height: 16),
        Text(
          '${deposit.toStringAsFixed(0)} ₸',
          style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: AppTheme.textPrimary,
              letterSpacing: -1),
        ),
        const SizedBox(height: 4),
        Text(
          isSmartRes ? 'Сумма к оплате сейчас (10% депозит)' : 'Итого к оплате',
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        if (isSmartRes) ...[
          const SizedBox(height: 8),
          Text(
            'В магазине: ${(total - deposit).clamp(0, total).toStringAsFixed(0)} ₸',
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
        ],
        if (isDelivery) ...[
          const SizedBox(height: 8),
          Text(
            'Товары: ${total.toStringAsFixed(0)} ₸  +  Доставка: ${deliveryFee.toStringAsFixed(0)} ₸',
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
        ],
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 12),
        if (!isDelivery && warehouseAddress.isNotEmpty)
          _InfoRow(
              Icons.location_on_outlined, 'Адрес получения', warehouseAddress),
        if (isDelivery && deliveryAddress.isNotEmpty)
          _InfoRow(Icons.local_shipping_outlined, 'Доставка', deliveryAddress),
        if (isSmartRes) _InfoRow(Icons.timer_outlined, 'Срок брони', '1 час'),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: Text(
              isSmartRes
                  ? 'Подтвердить и забронировать'
                  : 'Подтвердить и оплатить',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена',
              style: TextStyle(color: AppTheme.textHint, fontSize: 14)),
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
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(
              child: RichText(
                  text: TextSpan(
            style: const TextStyle(fontSize: 13),
            children: [
              TextSpan(
                  text: '$label: ',
                  style: const TextStyle(color: AppTheme.textSecondary)),
              TextSpan(
                  text: value,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600)),
            ],
          ))),
        ]),
      );
}

// ── Cart item tile ─────────────────────────────────────────────────────────────
class _CartItemTile extends StatelessWidget {
  final CartItemModel item;
  final VoidCallback onRemove;
  final bool isUnavailable;
  const _CartItemTile({
    required this.item,
    required this.onRemove,
    this.isUnavailable = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUnavailable
              ? AppTheme.dangerLight
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: isUnavailable
              ? Border.all(color: AppTheme.danger.withValues(alpha: 0.4))
              : null,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: item.imageUrl.isNotEmpty
                ? Image.network(item.imageUrl,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _Placeholder())
                : _Placeholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.productName,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isUnavailable
                          ? AppTheme.danger
                          : AppTheme.textPrimary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              if (isUnavailable) ...[
                const SizedBox(height: 3),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.danger,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text(
                    'Сатылып кетті / қолжетімсіз',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                ),
              ],
              const SizedBox(height: 2),
              Text('Размер: ${item.size}  ×${item.qty}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
              Text('${item.subtotal.toStringAsFixed(0)} ₸',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary)),
              if (item.storeName.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.store_outlined,
                      size: 10, color: AppTheme.textHint),
                  const SizedBox(width: 3),
                  Text(item.storeName,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textHint)),
                ]),
              ],
              if (item.warehouseAddress.isNotEmpty)
                Row(children: [
                  const Icon(Icons.location_on_outlined,
                      size: 10, color: AppTheme.textHint),
                  const SizedBox(width: 3),
                  Expanded(
                      child: Text(item.warehouseAddress,
                          style: const TextStyle(
                              fontSize: 10, color: AppTheme.textHint),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)),
                ]),
            ],
          )),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: AppTheme.danger, size: 20),
            onPressed: onRemove,
          ),
        ]),
      );
}

class _Placeholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 60,
        height: 60,
        color: AppTheme.primary.withValues(alpha: 0.06),
        child: const Icon(Icons.image_outlined,
            color: AppTheme.textHint, size: 24),
      );
}
