import 'package:flutter/material.dart';
import '../../data/models/warehouse_model.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/app_theme.dart';

class SellersScreen extends StatefulWidget {
  const SellersScreen({super.key});
  @override
  State<SellersScreen> createState() => _SellersScreenState();
}

class _SellersScreenState extends State<SellersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab =
      TabController(length: 2, vsync: this);
  final _service = FirestoreService();

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(slivers: [
        // ── Header ──────────────────────────────────────────────────────
        SliverToBoxAdapter(child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFF1E3A8A), Color(0xFF2D4FB5)],
                begin: Alignment.topLeft, end: Alignment.bottomRight)),
          child: SafeArea(bottom: false, child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 16))),
                const SizedBox(width: 12),
                const Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Сатушылар', style: TextStyle(color: Colors.white,
                      fontSize: 20, fontWeight: FontWeight.w700)),
                  Text('Жалданбал сатушылар тізімі',
                      style: TextStyle(color: Colors.white60, fontSize: 12)),
                ])),
              ]),
            ),
            const SizedBox(height: 12),
            TabBar(
              controller: _tab,
              indicatorColor: Colors.white,
              indicatorWeight: 2.5,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w400, fontSize: 13),
              tabs: const [
                Tab(text: 'Белсенді'),
                Tab(text: 'Күтуде'),
              ],
            ),
          ])),
        )),

        // ── Tab content ──────────────────────────────────────────────────
        SliverFillRemaining(child: TabBarView(
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
              child: CircularProgressIndicator(color: AppTheme.primary));
        }
        final sellers = snap.data ?? [];
        if (sellers.isEmpty) {
          return Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.group_outlined, size: 56, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              const Text('Белсенді сатушы жоқ',
                  style: TextStyle(fontSize: 15,
                      color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
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
  const _ActiveSellerCard(
      {required this.seller, required this.service});

  @override
  Widget build(BuildContext context) {
    final uid      = seller['uid']   as String? ?? '';
    final name     = seller['name']  as String? ?? '';
    final email    = seller['email'] as String? ?? '';
    final whId     = seller['assignedWarehouseId'] as String? ?? '';
    final initials = name.trim().split(' ')
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').take(2).join();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8, offset: const Offset(0, 2))]),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle),
          child: Center(child: Text(initials.isEmpty ? '?' : initials,
              style: const TextStyle(fontWeight: FontWeight.w700,
                  fontSize: 14, color: AppTheme.primary)))),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600,
            fontSize: 14, color: AppTheme.textPrimary)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(email, style: const TextStyle(color: AppTheme.textHint, fontSize: 12)),
          if (whId.isNotEmpty)
            _WarehouseName(service: service, warehouseId: whId),
        ]),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: AppTheme.textHint, size: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (val) async {
            if (val == 'warehouse') {
              _showWarehousePicker(context, uid, whId);
            } else if (val == 'remove') {
              final ok = await showDialog<bool>(context: context,
                builder: (_) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  title: const Text('Сатушыны жою'),
                  content: Text('«$name» сатушыны жоямыз ба?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false),
                        child: const Text('Болдырмау')),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.danger,
                          foregroundColor: Colors.white),
                      child: const Text('Жою')),
                  ],
                ));
              if (ok == true) await service.removeSeller(uid);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'warehouse',
              child: Row(children: [
                Icon(Icons.warehouse_outlined, size: 16, color: AppTheme.primary),
                SizedBox(width: 8),
                Text('Қойма тағайындау'),
              ])),
            const PopupMenuItem(value: 'remove',
              child: Row(children: [
                Icon(Icons.person_remove_outlined, size: 16, color: AppTheme.danger),
                SizedBox(width: 8),
                Text('Жою', style: TextStyle(color: AppTheme.danger)),
              ])),
          ],
        ),
      ),
    );
  }

  Future<void> _showWarehousePicker(
      BuildContext context, String sellerUid, String currentWhId) async {
    final warehouses = await service.getWarehouses();
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _WarehousePicker(
          warehouses: warehouses,
          currentId: currentWhId,
          onSelect: (wh) async {
            await service.reassignSellerWarehouse(sellerUid, wh.id);
            if (context.mounted) Navigator.pop(context);
          }),
    );
  }
}

class _WarehouseName extends StatelessWidget {
  final FirestoreService service;
  final String warehouseId;
  const _WarehouseName({required this.service, required this.warehouseId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<WarehouseModel>>(
      stream: service.watchWarehouses(),
      builder: (_, snap) {
        final warehouses = snap.data ?? [];
        final wh = warehouses.cast<WarehouseModel?>().firstWhere(
            (w) => w?.id == warehouseId, orElse: () => null);
        if (wh == null) return const SizedBox.shrink();
        return Row(children: [
          const Icon(Icons.warehouse_outlined, size: 11, color: AppTheme.textHint),
          const SizedBox(width: 3),
          Text(wh.name, style: const TextStyle(
              color: AppTheme.textHint, fontSize: 11)),
        ]);
      },
    );
  }
}

class _WarehousePicker extends StatelessWidget {
  final List<WarehouseModel> warehouses;
  final String currentId;
  final void Function(WarehouseModel) onSelect;
  const _WarehousePicker(
      {required this.warehouses, required this.currentId,
        required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        const Text('Қойма тағайындау',
            style: TextStyle(fontSize: 18,
                fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
        const SizedBox(height: 12),
        ...warehouses.map((wh) => ListTile(
          leading: Icon(Icons.warehouse_outlined,
              color: wh.id == currentId ? AppTheme.primary : AppTheme.textHint),
          title: Text(wh.name),
          trailing: wh.id == currentId
              ? const Icon(Icons.check_rounded, color: AppTheme.primary)
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
              child: CircularProgressIndicator(color: AppTheme.primary));
        }
        final requests = snap.data ?? [];
        if (requests.isEmpty) {
          return Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.hourglass_empty_rounded,
                  size: 56, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              const Text('Күтуде өтінім жоқ',
                  style: TextStyle(fontSize: 15,
                      color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
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
    final requestId = request['id']       as String? ?? '';
    final uid       = request['sellerId'] as String? ?? '';
    try {
      await service.approveJoinRequest(
          requestId: requestId,
          sellerId:  uid,
          warehouseId: wh.id);
      // Stream автоматты жаңартылады — картаны жоймаймыз
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Қате: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name      = request['sellerName']  as String? ?? '';
    final email     = request['sellerEmail'] as String? ?? '';
    final initials = name.trim().split(' ')
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').take(2).join();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.5)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8, offset: const Offset(0, 2))]),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
                color: const Color(0xFFFBBF24).withValues(alpha: 0.12),
                shape: BoxShape.circle),
            child: Center(child: Text(initials.isEmpty ? '?' : initials,
                style: const TextStyle(fontWeight: FontWeight.w700,
                    fontSize: 14, color: Color(0xFFD97706))))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w600,
                fontSize: 14, color: AppTheme.textPrimary)),
            Text(email, style: const TextStyle(color: AppTheme.textHint, fontSize: 12)),
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
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: AppTheme.success,
                  borderRadius: BorderRadius.circular(8)),
              child: const Text('Қабылдау',
                  style: TextStyle(color: Colors.white, fontSize: 12,
                      fontWeight: FontWeight.w700))),
          ),
          const SizedBox(width: 6),
          // Бас тарту
          GestureDetector(
            onTap: () async {
              await service.rejectJoinRequest(
                  requestId: request['id'] as String? ?? '',
                  sellerId:  request['sellerId'] as String? ?? '');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: AppTheme.dangerLight,
                  borderRadius: BorderRadius.circular(8)),
              child: const Text('Бас тарту',
                  style: TextStyle(color: AppTheme.danger, fontSize: 12,
                      fontWeight: FontWeight.w700))),
          ),
        ]),
      ),
    );
  }
}
