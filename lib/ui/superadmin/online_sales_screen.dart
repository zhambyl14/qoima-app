import 'package:flutter/material.dart';
import '../../core/lang.dart';
import '../../data/models/order_model.dart';
import '../../data/services/cloudinary_service.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/qoima_design.dart';

/// Модератор (superadmin) — БАРЛЫҚ дүкендердің онлайн-сатылымдарын бақылау.
/// Тек көру режимі: қай дүкен, не сатты, қаншаға, төлем түрі, чек, статус.
/// Растау/болдырмау — дүкен иесінің жұмысы (мұнда әрекет батырмалары жоқ).
class OnlineSalesScreen extends StatefulWidget {
  const OnlineSalesScreen({super.key});

  @override
  State<OnlineSalesScreen> createState() => _OnlineSalesScreenState();
}

class _OnlineSalesScreenState extends State<OnlineSalesScreen> {
  final _service = FirestoreService();
  late final Stream<List<OrderModel>> _stream =
      _service.watchAllOnlineOrders();
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _filter = 'all'; // all | review | active | done

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<OrderModel> _apply(List<OrderModel> all) {
    Iterable<OrderModel> list = all;
    switch (_filter) {
      case 'review':
        list = list.where((o) => o.isAwaitingReview);
        break;
      case 'active':
        list = list.where((o) =>
            o.status == OrderModel.statusPending ||
            o.status == OrderModel.statusReserved ||
            o.status == OrderModel.statusRejected ||
            o.status == OrderModel.statusConfirmed);
        break;
      case 'done':
        list = list.where((o) => o.status == OrderModel.statusCompleted);
        break;
    }
    final q = _search.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((o) =>
          o.storeName.toLowerCase().contains(q) ||
          o.clientName.toLowerCase().contains(q) ||
          o.clientPhone.contains(q) ||
          o.orderNumber.toString().contains(q));
    }
    return list.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Онлайн-продажи', 'Онлайн-сатылымдар'),
          subtitle: tr('Все магазины', 'Барлық дүкендер'),
          compact: true,
          showBack: true,
        ),
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: cSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cLine),
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v),
              style: const TextStyle(fontSize: 14, color: cInk),
              decoration: InputDecoration(
                hintText: tr('Магазин, клиент, № заказа…',
                    'Дүкен, клиент, тапсырыс №…'),
                hintStyle: manrope(13.5, FontWeight.w500, color: cInk3),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: cInk3, size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<OrderModel>>(
            stream: _stream,
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: cGreen));
              }
              final all = snap.data ?? [];
              final review = all.where((o) => o.isAwaitingReview).length;
              final active = all
                  .where((o) =>
                      o.status == OrderModel.statusPending ||
                      o.status == OrderModel.statusReserved ||
                      o.status == OrderModel.statusRejected ||
                      o.status == OrderModel.statusConfirmed)
                  .length;
              final done = all
                  .where((o) => o.status == OrderModel.statusCompleted)
                  .toList();
              // «Сатылды» сомасы — аяқталған + беруге дайын тапсырыстар.
              final soldSum = all
                  .where((o) =>
                      o.status == OrderModel.statusCompleted ||
                      o.status == OrderModel.statusConfirmed)
                  .fold<double>(0, (s, o) => s + o.total);

              final list = _apply(all);

              return Column(children: [
                // Summary
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                  child: Row(children: [
                    Expanded(
                      child: _StatTile(
                          label: tr('Продано', 'Сатылды'),
                          value: money(soldSum),
                          color: cGreen),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatTile(
                          label: tr('Завершено', 'Аяқталды'),
                          value: '${done.length}',
                          color: cInk),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatTile(
                          label: tr('На проверке', 'Тексеруде'),
                          value: '$review',
                          color: review > 0 ? cAmber : cInk3),
                    ),
                  ]),
                ),
                // Filter tabs
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  child: Row(children: [
                    _Chip(tr('Все ${all.length}', 'Барлығы ${all.length}'),
                        'all', _filter, (v) => setState(() => _filter = v)),
                    const SizedBox(width: 8),
                    _Chip(tr('Чек на проверке $review', 'Чек тексеруде $review'),
                        'review', _filter, (v) => setState(() => _filter = v)),
                    const SizedBox(width: 8),
                    _Chip(tr('Активные $active', 'Белсенді $active'), 'active',
                        _filter, (v) => setState(() => _filter = v)),
                    const SizedBox(width: 8),
                    _Chip(tr('Завершено ${done.length}', 'Аяқталды ${done.length}'),
                        'done', _filter, (v) => setState(() => _filter = v)),
                  ]),
                ),
                Expanded(
                  child: list.isEmpty
                      ? Center(
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                              Icon(Icons.inbox_outlined,
                                  size: 54, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text(tr('Продаж не найдено', 'Сатылым табылмады'),
                                  style: manrope(14.5, FontWeight.w500,
                                      color: cInk2)),
                            ]))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                          itemCount: list.length,
                          itemBuilder: (_, i) => _SaleCard(order: list[i]),
                        ),
                ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

// ── Sale card (read-only) ────────────────────────────────────────────────────
class _SaleCard extends StatelessWidget {
  final OrderModel order;
  const _SaleCard({required this.order});

  OrderModel get o => order;

  void _viewReceipt(BuildContext context) {
    final url = CloudinaryService.receiptPreviewUrl(o.receiptUrl);
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(children: [
          InteractiveViewer(
            maxScale: 5,
            child: Center(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const Padding(
                        padding: EdgeInsets.all(60),
                        child: CircularProgressIndicator(
                            color: cGreen, strokeWidth: 2),
                      ),
                errorBuilder: (_, __, ___) => Padding(
                  padding: const EdgeInsets.all(40),
                  child: Text(
                    tr('Не удалось загрузить чек', 'Чекті жүктеу мүмкін болмады'),
                    style: manrope(14, FontWeight.w600, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.circular(16),
        border: o.isAwaitingReview
            ? Border.all(color: cAmber, width: 1.5)
            : Border.all(color: cLine),
        boxShadow: kShadowSm,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header: store + type + status
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _typeColor(o.orderType).withValues(alpha: 0.07),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            const Icon(Icons.storefront_outlined, size: 15, color: cInk2),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                  o.storeName.isEmpty ? tr('Магазин', 'Дүкен') : o.storeName,
                  style: manrope(13.5, FontWeight.w800, color: cInk),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _statusColor(o.status).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(_statusLabel(o),
                  style: TextStyle(
                      color: _statusColor(o.status),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (o.orderNumber > 0)
                    Text('#${o.orderNumber.toString().padLeft(5, '0')}',
                        style: manrope(12.5, FontWeight.w700, color: cInk3)),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: _typeColor(o.orderType).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(_typeLabel(o.orderType),
                        style: TextStyle(
                            color: _typeColor(o.orderType),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 8),
                  Text(_date(o.createdAt),
                      style: manrope(11.5, FontWeight.w500, color: cInk3)),
                ]),
                const SizedBox(height: 8),
                // Client
                Row(children: [
                  const Icon(Icons.person_outline, size: 15, color: cInk3),
                  const SizedBox(width: 6),
                  Text(
                      o.clientName.isEmpty
                          ? tr('Клиент', 'Клиент')
                          : o.clientName,
                      style: manrope(13, FontWeight.w600, color: cInk)),
                  const SizedBox(width: 10),
                  const Icon(Icons.phone_outlined, size: 13, color: cInk3),
                  const SizedBox(width: 4),
                  Text(o.clientPhone,
                      style: manrope(12, FontWeight.w500, color: cInk2)),
                ]),
                const Divider(height: 16),
                // Items
                ...o.items.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Expanded(
                          child: Text('${item.productName}  (${item.size})',
                              style: manrope(12.5, FontWeight.w500,
                                  color: cInk),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        Text('×${item.qty}  ${money(item.subtotal)}',
                            style: manrope(12, FontWeight.w600, color: cInk2)),
                      ]),
                    )),
                const Divider(height: 16),
                // Amount + payment method
                Row(children: [
                  Text(tr('Сумма', 'Сома'),
                      style: manrope(12.5, FontWeight.w500, color: cInk2)),
                  const Spacer(),
                  Text(money(o.total),
                      style: manrope(15, FontWeight.w800, color: cGreen)),
                ]),
                if (o.isSmartReservation) ...[
                  const SizedBox(height: 3),
                  Row(children: [
                    Text(tr('Задаток (10%)', 'Кепілпұл (10%)'),
                        style: manrope(11.5, FontWeight.w500, color: cInk3)),
                    const Spacer(),
                    Text(money(o.depositAmount),
                        style: manrope(12, FontWeight.w600, color: cInk2)),
                  ]),
                ],
                if (o.paymentBank.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(Icons.credit_card_rounded,
                        size: 14, color: _payColor(o.paymentBank)),
                    const SizedBox(width: 6),
                    Text(_payLabel(o.paymentBank),
                        style: manrope(12, FontWeight.w600,
                            color: _payColor(o.paymentBank))),
                  ]),
                ],
                // Receipt
                if (o.receiptUrl.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => _viewReceipt(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: cGreenTint,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cGreen.withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.receipt_long_rounded,
                            color: cGreen, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                              tr('Посмотреть чек', 'Чекті көру'),
                              style: manrope(12.5, FontWeight.w700,
                                  color: cGreenDeep)),
                        ),
                        const Icon(Icons.open_in_full_rounded,
                            color: cGreen, size: 14),
                      ]),
                    ),
                  ),
                ],
              ]),
        ),
      ]),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────
Color _typeColor(String t) {
  switch (t) {
    case OrderModel.typeSmartReservation:
      return const Color(0xFF3B82F6);
    case OrderModel.typeClickCollect:
      return cGreen;
    case OrderModel.typeDelivery:
      return const Color(0xFFF59E0B);
    default:
      return cInk3;
  }
}

String _typeLabel(String t) {
  switch (t) {
    case OrderModel.typeSmartReservation:
      return tr('БРОНЬ', 'БРОНЬ');
    case OrderModel.typeClickCollect:
      return tr('САМОВЫВОЗ', 'ӨЗІ АЛАДЫ');
    case OrderModel.typeDelivery:
      return tr('ДОСТАВКА', 'ЖЕТКІЗУ');
    default:
      return t.toUpperCase();
  }
}

Color _statusColor(String s) {
  switch (s) {
    case OrderModel.statusPending:
      return cAmber;
    case OrderModel.statusReserved:
      return const Color(0xFF3B82F6);
    case OrderModel.statusRejected:
      return cRed;
    case OrderModel.statusConfirmed:
    case OrderModel.statusCompleted:
      return cGreen;
    case OrderModel.statusCancelled:
    case OrderModel.statusReturned:
      return cRed;
    default:
      return cInk3;
  }
}

String _statusLabel(OrderModel o) {
  switch (o.status) {
    case OrderModel.statusPending:
      return o.isAwaitingReview
          ? tr('Чек на проверке', 'Чек тексеруде')
          : tr('Ждёт оплаты', 'Төлем күтуде');
    case OrderModel.statusReserved:
      return tr('Бронь', 'Бронь');
    case OrderModel.statusRejected:
      return tr('Чек отклонён', 'Чек қабылданбады');
    case OrderModel.statusConfirmed:
      return tr('Оплачено', 'Төленді');
    case OrderModel.statusCompleted:
      return tr('Завершён', 'Аяқталды');
    case OrderModel.statusCancelled:
      return tr('Отменён', 'Бас тартылды');
    case OrderModel.statusReturned:
      return tr('Возврат', 'Қайтару');
    default:
      return o.status;
  }
}

String _normMethod(String m) {
  final s = m.toLowerCase();
  if (s.contains('kaspi')) return 'kaspi';
  if (s.contains('halyk')) return 'halyk';
  if (s == 'card' || s.contains('карт')) return 'card';
  if (s == 'cash' || s.contains('налич')) return 'cash';
  return s;
}

String _payLabel(String method) {
  switch (_normMethod(method)) {
    case 'kaspi':
      return '📱 Kaspi';
    case 'halyk':
      return '📱 Halyk Bank';
    case 'card':
      return tr('💳 Оплата картой', '💳 Картамен төлем');
    case 'cash':
      return tr('💵 Наличный', '💵 Қолма-қол');
    default:
      return method;
  }
}

Color _payColor(String method) {
  switch (_normMethod(method)) {
    case 'kaspi':
      return const Color(0xFFEB3333);
    case 'halyk':
      return const Color(0xFF00A550);
    case 'card':
      return const Color(0xFF3B82F6);
    default:
      return cGreen;
  }
}

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class _StatTile extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatTile(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cLine),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: manrope(16, FontWeight.w800, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(label, style: manrope(11, FontWeight.w500, color: cInk3)),
        ]),
      );
}

class _Chip extends StatelessWidget {
  final String label, value, current;
  final void Function(String) onTap;
  const _Chip(this.label, this.value, this.current, this.onTap);

  @override
  Widget build(BuildContext context) {
    final active = value == current;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? cGreen : cSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? cGreen : cLine),
        ),
        child: Text(label,
            style: manrope(12, FontWeight.w700,
                color: active ? Colors.white : cInk2)),
      ),
    );
  }
}
