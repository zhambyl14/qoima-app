import 'package:flutter/material.dart';
import '../../../data/models/warehouse_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';

class SellersScreen extends StatefulWidget {
  const SellersScreen({super.key});
  @override
  State<SellersScreen> createState() => _SellersScreenState();
}

class _SellersScreenState extends State<SellersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  final _service = FirestoreService();

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: CustomScrollView(slivers: [
        // ── Header ──────────────────────────────────────────────────────
        SliverToBoxAdapter(
            child: Container(
          decoration: const BoxDecoration(gradient: kGrad),
          child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                child: Column(children: [
                  Row(children: [
                    GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                            width: 38,
                            height: 38,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.chevron_left_rounded,
                                color: Colors.white, size: 22))),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Продавцы',
                              style: manrope(23, FontWeight.w800,
                                  color: Colors.white, letterSpacing: -0.5)),
                          StreamBuilder<List<Map<String, dynamic>>>(
                            stream: _service.watchActiveSellers(),
                            builder: (_, s) => StreamBuilder<
                                List<Map<String, dynamic>>>(
                              stream: _service.watchPendingRequests(),
                              builder: (_, p) => Text(
                                '${s.data?.length ?? 0} активных · ${p.data?.length ?? 0} запросов',
                                style: manrope(13, FontWeight.w500,
                                    color:
                                        Colors.white.withValues(alpha: 0.78)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  // Pill tabs
                  AnimatedBuilder(
                    animation: _tab,
                    builder: (_, __) => Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(13)),
                      child: Row(
                        children: ['Активные', 'Запросы']
                            .asMap()
                            .entries
                            .map((e) {
                          final active = _tab.index == e.key;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => _tab.animateTo(e.key),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 9),
                                decoration: BoxDecoration(
                                    color: active
                                        ? Colors.white
                                        : Colors.transparent,
                                    borderRadius:
                                        BorderRadius.circular(10)),
                                child: Text(e.value,
                                    textAlign: TextAlign.center,
                                    style: manrope(
                                        13,
                                        FontWeight.w700,
                                        color: active
                                            ? cGreenDeep
                                            : Colors.white.withValues(
                                                alpha: 0.85))),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ]),
              )),
        )),

        // ── Tab content ──────────────────────────────────────────────────
        SliverFillRemaining(
            child: TabBarView(
          controller: _tab,
          children: [
            _ActiveTab(service: _service),
            _PendingTab(service: _service),
          ],
        )),
      ]),
    );
  }
}

// ── Белсенді сатушылар ──────────────────────────────────────────────────────
class _ActiveTab extends StatelessWidget {
  final FirestoreService service;
  const _ActiveTab({required this.service});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: service.watchActiveSellers(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: cGreen));
        }
        final sellers = snap.data ?? [];
        if (sellers.isEmpty) {
          return Center(
              child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.group_outlined, size: 56, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              const Text('Белсенді сатушы жоқ',
                  style: TextStyle(
                      fontSize: 15,
                      color: cInk2,
                      fontWeight: FontWeight.w500)),
            ],
          ));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: sellers.length,
          itemBuilder: (_, i) =>
              _ActiveSellerCard(seller: sellers[i], service: service),
        );
      },
    );
  }
}

class _ActiveSellerCard extends StatelessWidget {
  final Map<String, dynamic> seller;
  final FirestoreService service;
  const _ActiveSellerCard({required this.seller, required this.service});

  @override
  Widget build(BuildContext context) {
    final uid = seller['uid'] as String? ?? '';
    final name = seller['name'] as String? ?? '';
    final email = seller['email'] as String? ?? '';
    final whId = seller['assignedWarehouseId'] as String? ?? '';
    final initials = name
        .trim()
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .take(2)
        .join();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cLine),
          boxShadow: kShadowSm),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: cGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle),
            child: Center(
                child: Text(initials.isEmpty ? '?' : initials,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: cGreen)))),
        title: Text(name,
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: cInk)),
        subtitle:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(email,
              style: const TextStyle(color: cInk3, fontSize: 12)),
          StreamBuilder<List<WarehouseModel>>(
            stream: service.watchWarehouses(),
            builder: (_, snap) {
              final warehouses = snap.data ?? [];
              if (warehouses.isEmpty) return const SizedBox.shrink();
              return DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: warehouses.any((w) => w.id == whId) ? whId : null,
                  hint: const Text('Қойма таңдаңыз',
                      style: TextStyle(fontSize: 12, color: cInk3)),
                  isDense: true,
                  style: const TextStyle(
                      fontSize: 12,
                      color: cInk,
                      fontWeight: FontWeight.w500),
                  icon: const Icon(Icons.arrow_drop_down,
                      size: 18, color: cInk3),
                  items: warehouses
                      .map((wh) => DropdownMenuItem(
                            value: wh.id,
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.warehouse_outlined,
                                  size: 12, color: cGreen),
                              const SizedBox(width: 4),
                              Text(wh.name,
                                  style: const TextStyle(fontSize: 12)),
                            ]),
                          ))
                      .toList(),
                  onChanged: (newId) async {
                    if (newId == null || newId == whId) return;
                    await service.reassignSellerWarehouse(uid, newId);
                  },
                ),
              );
            },
          ),
        ]),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: cInk3, size: 20),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (val) async {
            if (val == 'remove') {
              final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        title: const Text('Сатушыны жою'),
                        content: Text('«$name» сатушыны жоямыз ба?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Болдырмау')),
                          ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: cRed,
                                  foregroundColor: Colors.white),
                              child: const Text('Жою')),
                        ],
                      ));
              if (ok == true) await service.removeSeller(uid);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
                value: 'remove',
                child: Row(children: [
                  Icon(Icons.person_remove_outlined,
                      size: 16, color: cRed),
                  SizedBox(width: 8),
                  Text('Жою', style: TextStyle(color: cRed)),
                ])),
          ],
        ),
      ),
    );
  }
}

class _WarehousePicker extends StatelessWidget {
  final List<WarehouseModel> warehouses;
  final String currentId;
  final void Function(WarehouseModel) onSelect;
  const _WarehousePicker(
      {required this.warehouses,
      required this.currentId,
      required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(
            child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        const Text('Қойма тағайындау',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: cInk)),
        const SizedBox(height: 12),
        ...warehouses.map((wh) => ListTile(
              leading: Icon(Icons.warehouse_outlined,
                  color: wh.id == currentId
                      ? cGreen
                      : cInk3),
              title: Text(wh.name),
              trailing: wh.id == currentId
                  ? const Icon(Icons.check_rounded, color: cGreen)
                  : null,
              onTap: () => onSelect(wh),
            )),
      ]),
    );
  }
}

// ── Күтуде тұрған өтінімдер ─────────────────────────────────────────────────
class _PendingTab extends StatelessWidget {
  final FirestoreService service;
  const _PendingTab({required this.service});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: service.watchPendingRequests(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: cGreen));
        }
        final requests = snap.data ?? [];
        if (requests.isEmpty) {
          return Center(
              child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.hourglass_empty_rounded,
                  size: 56, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              const Text('Күтуде өтінім жоқ',
                  style: TextStyle(
                      fontSize: 15,
                      color: cInk2,
                      fontWeight: FontWeight.w500)),
            ],
          ));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          itemBuilder: (_, i) =>
              _PendingCard(request: requests[i], service: service),
        );
      },
    );
  }
}

class _PendingCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final FirestoreService service;
  const _PendingCard({required this.request, required this.service});

  Future<void> _doApprove(BuildContext context, wh) async {
    final requestId = request['id'] as String? ?? '';
    final uid = request['sellerId'] as String? ?? '';
    try {
      await service.approveJoinRequest(
          requestId: requestId, sellerId: uid, warehouseId: wh.id);
      // Stream автоматты жаңартылады — картаны жоймаймыз
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Қате: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = request['sellerName'] as String? ?? '';
    final email = request['sellerEmail'] as String? ?? '';
    final initials = name
        .trim()
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .take(2)
        .join();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cAmber.withValues(alpha: 0.44), width: 1.5),
          boxShadow: kShadowSm),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: const Color(0xFFFBBF24).withValues(alpha: 0.12),
                  shape: BoxShape.circle),
              child: Center(
                  child: Text(initials.isEmpty ? '?' : initials,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Color(0xFFD97706))))),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: cInk)),
                Text(email,
                    style: const TextStyle(
                        color: cInk3, fontSize: 12)),
              ])),
          const SizedBox(width: 8),
          // Қабылдау
          GestureDetector(
            onTap: () async {
              final warehouses = await service.getWarehouses();
              if (!context.mounted) return;
              if (warehouses.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Алдымен қойма жасаңыз'),
                  behavior: SnackBarBehavior.floating,
                ));
                return;
              }
              showModalBottomSheet(
                context: context,
                shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(20))),
                builder: (_) => _WarehousePicker(
                  warehouses: warehouses,
                  currentId: '',
                  onSelect: (wh) {
                    // Алдымен жабамыз, содан кейін операция
                    Navigator.pop(context);
                    _doApprove(context, wh);
                  },
                ),
              );
            },
            child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: cGreen,
                    borderRadius: BorderRadius.circular(8)),
                child: const Text('Қабылдау',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700))),
          ),
          const SizedBox(width: 6),
          // Бас тарту
          GestureDetector(
            onTap: () async {
              await service.rejectJoinRequest(
                  requestId: request['id'] as String? ?? '',
                  sellerId: request['sellerId'] as String? ?? '');
            },
            child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: cRedTint,
                    borderRadius: BorderRadius.circular(8)),
                child: const Text('Бас тарту',
                    style: TextStyle(
                        color: cRed,
                        fontSize: 12,
                        fontWeight: FontWeight.w700))),
          ),
        ]),
      ),
    );
  }
}

