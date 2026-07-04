import 'package:flutter/material.dart';
import '../../../core/app_user.dart';
import '../../../core/l10n_ext.dart';
import '../../../data/models/return_model.dart';
import '../../../data/services/return_service.dart';
import '../../../theme/qoima_design.dart';
import 'admin_return_detail_screen.dart';
import 'admin_return_analytics_screen.dart';
import 'make_offline_return_screen.dart';

import '../../../core/lang.dart';
class AdminReturnsScreen extends StatefulWidget {
  const AdminReturnsScreen({super.key});

  @override
  State<AdminReturnsScreen> createState() => _AdminReturnsScreenState();
}

class _AdminReturnsScreenState extends State<AdminReturnsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late final Stream<List<ReturnModel>> _stream =
      ReturnService().watchAllReturns(AppUser.current.uid);

  // Filter: null = all
  ReturnStatus? _filter;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const MakeOfflineReturnScreen())),
        backgroundColor: cGreen,
        elevation: 0,
        icon: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
        label: Text(tr('Офлайн возврат', 'Офлайн қайтару'),
            style: manrope(14.5, FontWeight.w700, color: Colors.white)),
      ),
      body: Column(children: [
        Container(
          decoration: const BoxDecoration(gradient: kGrad),
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: Row(children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(context.l10n.returnsTitle,
                        style: manrope(22, FontWeight.w800,
                            color: Colors.white, letterSpacing: -0.5)),
                  ]),
                ),
                const SizedBox(height: 8),
                TabBar(
                  controller: _tabs,
                  isScrollable: false,
                  indicatorColor: Colors.white,
                  labelStyle: manrope(13.5, FontWeight.w700, color: Colors.white),
                  unselectedLabelStyle: manrope(13.5, FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.65)),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white.withValues(alpha: 0.65),
                  tabs: [
                    Tab(text: context.l10n.returnTabList),
                    Tab(text: context.l10n.returnTabAnalytics),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _ReturnsListTab(stream: _stream, filter: _filter,
                  onFilterChanged: (f) => setState(() => _filter = f)),
              AdminReturnAnalyticsScreen(adminUid: AppUser.current.uid),
            ],
          ),
        ),
      ]),
    );
  }
}

// ── List tab ──────────────────────────────────────────────────────────────────
class _ReturnsListTab extends StatelessWidget {
  final Stream<List<ReturnModel>> stream;
  final ReturnStatus? filter;
  final ValueChanged<ReturnStatus?> onFilterChanged;

  const _ReturnsListTab({
    required this.stream,
    required this.filter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ReturnModel>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: cGreen));
        }
        final all = snap.data ?? [];
        final shown = filter == null
            ? all
            : all.where((r) => r.status == filter).toList();

        return Column(children: [
          // Filter chips
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              children: [
                _FilterChip(
                  label: context.l10n.returnFilterAll,
                  active: filter == null,
                  onTap: () => onFilterChanged(null),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: context.l10n.returnFilterNew,
                  active: filter == ReturnStatus.requested,
                  count: all.where((r) => r.status == ReturnStatus.requested).length,
                  onTap: () => onFilterChanged(ReturnStatus.requested),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: context.l10n.returnFilterProcessing,
                  active: filter == ReturnStatus.approved,
                  count: all
                      .where((r) => r.status == ReturnStatus.approved)
                      .length,
                  onTap: () => onFilterChanged(ReturnStatus.approved),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: context.l10n.returnFilterReceived,
                  active: filter == ReturnStatus.received,
                  count: all
                      .where((r) => r.status == ReturnStatus.received)
                      .length,
                  onTap: () => onFilterChanged(ReturnStatus.received),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: context.l10n.returnFilterCompleted,
                  active: filter == ReturnStatus.refunded,
                  count: all.where((r) => r.status == ReturnStatus.refunded).length,
                  onTap: () => onFilterChanged(ReturnStatus.refunded),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: context.l10n.returnFilterRejected,
                  active: filter == ReturnStatus.rejected,
                  count: all.where((r) => r.status == ReturnStatus.rejected).length,
                  onTap: () => onFilterChanged(ReturnStatus.rejected),
                ),
              ],
            ),
          ),

          // List
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.assignment_return_outlined,
                            size: 56, color: cInk3),
                        const SizedBox(height: 12),
                        Text(context.l10n.returnNoReturns,
                            style: manrope(16, FontWeight.w500, color: cInk2)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: shown.length,
                    itemBuilder: (_, i) => _ReturnCard(ret: shown[i]),
                  ),
          ),
        ]);
      },
    );
  }
}

// ── Return card ───────────────────────────────────────────────────────────────
class _ReturnCard extends StatelessWidget {
  final ReturnModel ret;
  const _ReturnCard({required this.ret});

  @override
  Widget build(BuildContext context) {
    final d = ret.createdAt;
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => AdminReturnDetailScreen(ret: ret))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cLine),
          boxShadow: kShadowSm,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(ret.id,
                    style: manrope(14, FontWeight.w800, color: cInk)),
                const Spacer(),
                QPill(ret.status.label(context), tone: ret.status.tone),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                QPill(ret.type.label(context), tone: ret.type.tone),
                const SizedBox(width: 8),
                Text(dateStr,
                    style: manrope(12, FontWeight.w500, color: cInk3)),
              ]),
              if (ret.clientName.isNotEmpty || ret.clientPhone.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.person_outline, size: 14, color: cInk3),
                  const SizedBox(width: 4),
                  Text(
                    ret.clientName.isNotEmpty
                        ? ret.clientName
                        : ret.clientPhone,
                    style: manrope(12.5, FontWeight.w500, color: cInk2),
                  ),
                ]),
              ],
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: Text(
                    ret.items.isEmpty
                        ? '—'
                        : ret.items
                            .map((i) => i.productTitle)
                            .join(', '),
                    style: manrope(12.5, FontWeight.w500, color: cInk2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${ret.totalAmount.toStringAsFixed(0)} ₸',
                  style: manrope(14.5, FontWeight.w800, color: cInk),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Filter chip ───────────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final int? count;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.active,
    this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: active ? cInk : cSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? cInk : cLine),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: manrope(12.5, FontWeight.w700,
                    color: active ? Colors.white : cInk2)),
            if ((count ?? 0) > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: active
                      ? Colors.white.withValues(alpha: 0.2)
                      : cGreenTint,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$count',
                    style: manrope(10.5, FontWeight.w800,
                        color: active ? Colors.white : cGreenDeep)),
              ),
            ],
          ]),
        ),
      );
}
