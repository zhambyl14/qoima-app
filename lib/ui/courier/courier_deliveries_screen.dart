import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_config.dart';
import '../../core/app_user.dart';
import '../../data/models/courier_delivery_model.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/qoima_design.dart';

class CourierDeliveriesScreen extends StatefulWidget {
  const CourierDeliveriesScreen({super.key});

  @override
  State<CourierDeliveriesScreen> createState() =>
      _CourierDeliveriesScreenState();
}

class _CourierDeliveriesScreenState extends State<CourierDeliveriesScreen> {
  final _service = FirestoreService();
  String _filter = 'new'; // new | active | done

  List<CourierDeliveryModel> _applyFilter(List<CourierDeliveryModel> all) {
    switch (_filter) {
      case 'new':
        return all
            .where((d) => d.status == CourierDeliveryModel.statusNew)
            .toList();
      case 'active':
        return all
            .where((d) =>
                d.status == CourierDeliveryModel.statusAssigned ||
                d.status == CourierDeliveryModel.statusPicked)
            .toList();
      case 'done':
        return all
            .where((d) =>
                d.status == CourierDeliveryModel.statusDelivered ||
                d.status == CourierDeliveryModel.statusCancelled)
            .toList();
      default:
        return all;
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = context.read<AppUser>().name;

    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        // ── Header ──────────────────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(gradient: kGrad),
          child: SafeArea(
            bottom: false,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => Navigator.maybePop(context),
                    child: Container(
                      width: 38, height: 38,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.chevron_left_rounded,
                          color: Colors.white, size: 22),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Доставки',
                            style: manrope(23, FontWeight.w800,
                                color: Colors.white, letterSpacing: -0.5)),
                        Text('Курьер · ${name.isNotEmpty ? name : "Владелец"}',
                            style: manrope(13, FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.78))),
                      ],
                    ),
                  ),
                ]),
              ),

              // Today stats card
              StreamBuilder<List<CourierDeliveryModel>>(
                stream: _service.watchCourierDeliveries(),
                builder: (_, snap) {
                  final all = snap.data ?? [];
                  final now = DateTime.now();
                  final todayAll = all.where((d) {
                    final c = d.createdAt;
                    return c.year == now.year &&
                        c.month == now.month &&
                        c.day == now.day;
                  }).toList();
                  final todayCount = todayAll.length;
                  final earned = todayAll
                      .where((d) =>
                          d.status == CourierDeliveryModel.statusDelivered)
                      .fold<double>(0, (a, b) => a + b.amount);

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Доставок сегодня',
                                  style: manrope(12, FontWeight.w600,
                                      color: Colors.white
                                          .withValues(alpha: 0.75))),
                              Text('$todayCount',
                                  style: manrope(24, FontWeight.w800,
                                      color: Colors.white)),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 36, color: Colors.white24),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Заработано',
                                  style: manrope(12, FontWeight.w600,
                                      color: Colors.white
                                          .withValues(alpha: 0.75))),
                              Text(
                                earned > 0 ? money(earned) : 'Бесплатно',
                                style: manrope(20, FontWeight.w800,
                                    color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  );
                },
              ),

              // Status filter chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(children: [
                  _FilterChip(
                      label: 'Новые',
                      value: 'new',
                      current: _filter,
                      onTap: (v) => setState(() => _filter = v)),
                  const SizedBox(width: 8),
                  _FilterChip(
                      label: 'В работе',
                      value: 'active',
                      current: _filter,
                      onTap: (v) => setState(() => _filter = v)),
                  const SizedBox(width: 8),
                  _FilterChip(
                      label: 'Доставлено',
                      value: 'done',
                      current: _filter,
                      onTap: (v) => setState(() => _filter = v)),
                ]),
              ),
            ]),
          ),
        ),

        // ── Body ────────────────────────────────────────────────────────────
        Expanded(
          child: StreamBuilder<List<CourierDeliveryModel>>(
            stream: _service.watchCourierDeliveries(),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: cGreen));
              }
              final shown = _applyFilter(snap.data ?? []);

              if (shown.isEmpty) {
                return Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 72, height: 72,
                          decoration: const BoxDecoration(
                              color: cLine2, shape: BoxShape.circle),
                          child: const Icon(Icons.local_shipping_outlined,
                              size: 34, color: cInk3),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _filter == 'new'
                              ? 'Нет новых доставок'
                              : _filter == 'active'
                                  ? 'Нет активных доставок'
                                  : 'Нет завершённых',
                          style: manrope(15, FontWeight.w500, color: cInk2),
                        ),
                      ]),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                itemCount: shown.length,
                itemBuilder: (_, i) => _DeliveryCard(
                  delivery: shown[i],
                  service: _service,
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ── Delivery card ──────────────────────────────────────────────────────────────
class _DeliveryCard extends StatefulWidget {
  final CourierDeliveryModel delivery;
  final FirestoreService service;
  const _DeliveryCard({required this.delivery, required this.service});

  @override
  State<_DeliveryCard> createState() => _DeliveryCardState();
}

class _DeliveryCardState extends State<_DeliveryCard> {
  bool _loading = false;

  CourierDeliveryModel get d => widget.delivery;

  String get _statusTone {
    switch (d.status) {
      case CourierDeliveryModel.statusNew:
        return 'amber';
      case CourierDeliveryModel.statusAssigned:
      case CourierDeliveryModel.statusPicked:
        return 'blue';
      case CourierDeliveryModel.statusDelivered:
        return 'green';
      case CourierDeliveryModel.statusCancelled:
        return 'red';
      default:
        return 'gray';
    }
  }

  String get _statusLabel {
    switch (d.status) {
      case CourierDeliveryModel.statusNew:
        return 'Новая';
      case CourierDeliveryModel.statusAssigned:
        return 'Принято';
      case CourierDeliveryModel.statusPicked:
        return 'Забрал';
      case CourierDeliveryModel.statusDelivered:
        return 'Доставлено';
      case CourierDeliveryModel.statusCancelled:
        return 'Отменено';
      default:
        return d.status;
    }
  }

  String? get _nextStatus {
    switch (d.status) {
      case CourierDeliveryModel.statusNew:
        return CourierDeliveryModel.statusAssigned;
      case CourierDeliveryModel.statusAssigned:
        return CourierDeliveryModel.statusPicked;
      case CourierDeliveryModel.statusPicked:
        return CourierDeliveryModel.statusDelivered;
      default:
        return null;
    }
  }

  String? get _nextLabel {
    switch (d.status) {
      case CourierDeliveryModel.statusNew:
        return 'Принять';
      case CourierDeliveryModel.statusAssigned:
        return 'Забрал товар';
      case CourierDeliveryModel.statusPicked:
        return 'Доставлено';
      default:
        return null;
    }
  }

  Future<void> _advance() async {
    final next = _nextStatus;
    if (next == null || _loading) return;
    setState(() => _loading = true);
    try {
      await widget.service.updateCourierDeliveryStatus(d.id, next);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shortId = d.orderNumber > 0
        ? '#${d.orderNumber.toString().padLeft(5, '0')}'
        : d.orderId.isNotEmpty
            ? '#${d.orderId.substring(0, 6).toUpperCase()}'
            : '#—';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: QCard(
        padding: const EdgeInsets.all(14),
        border: Border.all(color: cGreen.withValues(alpha: 0.2), width: 1.5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header row
          Row(children: [
            Text(shortId, style: manrope(16, FontWeight.w800, color: cInk)),
            const Spacer(),
            QPill(_statusLabel, tone: _statusTone),
          ]),
          const SizedBox(height: 8),

          // Client info
          Row(children: [
            const Icon(Icons.person_outline, size: 15, color: cInk3),
            const SizedBox(width: 6),
            Text(d.clientName.isNotEmpty ? d.clientName : '—',
                style: manrope(13.5, FontWeight.w600, color: cInk2)),
          ]),
          const SizedBox(height: 4),

          // Delivery address
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.location_on_outlined, size: 15, color: cGreen),
            const SizedBox(width: 6),
            Expanded(
                child: Text(d.address.isNotEmpty ? d.address : '—',
                    style: manrope(13, FontWeight.w500, color: cInk))),
          ]),

          // Pickup warehouses
          if (d.warehouseAddresses.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...d.warehouseAddresses.map((a) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(children: [
                    const Icon(Icons.storefront_outlined,
                        size: 14, color: cInk3),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text('Забрать: $a',
                            style: manrope(12, FontWeight.w500, color: cInk3))),
                  ]),
                )),
          ],

          const Divider(height: 14, color: cLine),

          // Fee + action button row
          Row(children: [
            Text(
              d.amount > 0
                  ? money(d.amount)
                  : AppConfig.deliveryFee > 0
                      ? money(AppConfig.deliveryFee)
                      : 'Бесплатно',
              style: manrope(18, FontWeight.w800, color: cInk),
            ),
            const Spacer(),
            if (_nextStatus != null)
              SizedBox(
                height: 40,
                child: ElevatedButton(
                  onPressed: _loading ? null : _advance,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text(_nextLabel!,
                          style:
                              manrope(13, FontWeight.w700, color: Colors.white)),
                ),
              ),
          ]),
        ]),
      ),
    );
  }
}

// ── Filter chip ────────────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label, value, current;
  final void Function(String) onTap;
  const _FilterChip(
      {required this.label,
      required this.value,
      required this.current,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = value == current;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? Colors.white
              : Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(label,
            style: manrope(
              12.5, FontWeight.w700,
              color: active ? cGreen : Colors.white.withValues(alpha: 0.9),
            )),
      ),
    );
  }
}
