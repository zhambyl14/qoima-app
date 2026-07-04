import 'package:flutter/material.dart';
import '../../../core/l10n_ext.dart';
import '../../../data/models/return_model.dart';
import '../../../data/services/return_service.dart';
import '../../../theme/qoima_design.dart';

import '../../../core/lang.dart';
class AdminReturnAnalyticsScreen extends StatefulWidget {
  final String adminUid;
  const AdminReturnAnalyticsScreen({super.key, required this.adminUid});

  @override
  State<AdminReturnAnalyticsScreen> createState() =>
      _AdminReturnAnalyticsScreenState();
}

class _AdminReturnAnalyticsScreenState
    extends State<AdminReturnAnalyticsScreen> {
  DateRange _range = DateRange.forMonth(DateTime.now());
  bool _loading = false;
  ReturnAnalytics? _analytics;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ReturnService().computeAnalytics(
        adminUid: widget.adminUid,
        range: _range,
      );
      if (mounted) setState(() => _analytics = result);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: cGreen,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          // Period chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _PeriodChip(
                label: tr('Месяц', 'Ай'),
                active: _isMonth(),
                onTap: () {
                  setState(() => _range = DateRange.forMonth(DateTime.now()));
                  _load();
                },
              ),
              const SizedBox(width: 8),
              _PeriodChip(
                label: tr('Неделя', 'Апта'),
                active: _isWeek(),
                onTap: () {
                  setState(() => _range = DateRange.forWeek(DateTime.now()));
                  _load();
                },
              ),
              const SizedBox(width: 8),
              _PeriodChip(
                label: tr('Год', 'Жыл'),
                active: _isYear(),
                onTap: () {
                  setState(() => _range = DateRange.forYear(DateTime.now()));
                  _load();
                },
              ),
            ]),
          ),
          const SizedBox(height: 16),

          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: Center(
                  child: CircularProgressIndicator(color: cGreen)),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 60),
              child: Center(
                  child: Text(_error!,
                      style: manrope(14, FontWeight.w500, color: cRed),
                      textAlign: TextAlign.center)),
            )
          else if (_analytics != null)
            _AnalyticsContent(analytics: _analytics!),
        ],
      ),
    );
  }

  bool _isMonth() {
    final now = DateTime.now();
    return _range.from == DateTime(now.year, now.month, 1);
  }

  bool _isWeek() {
    final monday = DateTime.now()
        .subtract(Duration(days: DateTime.now().weekday - 1));
    final from = DateTime(monday.year, monday.month, monday.day);
    return _range.from == from;
  }

  bool _isYear() {
    final now = DateTime.now();
    return _range.from == DateTime(now.year, 1, 1);
  }
}

class _AnalyticsContent extends StatelessWidget {
  final ReturnAnalytics analytics;
  const _AnalyticsContent({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final a = analytics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // KPI row
        Row(children: [
          Expanded(
            child: _KpiCard(
              icon: Icons.assignment_return_outlined,
              tone: 'amber',
              value: '${a.totalReturns}',
              label: context.l10n.returnsTitle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _KpiCard(
              icon: Icons.percent_rounded,
              tone: a.returnRate > 10 ? 'red' : 'green',
              value: '${a.returnRate.toStringAsFixed(1)}%',
              label: context.l10n.returnRate,
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: _KpiCard(
              icon: Icons.shopping_bag_outlined,
              tone: 'blue',
              value: '${a.totalSales}',
              label: tr('Продаж за период', 'Кезеңдегі сатылым'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _KpiCard(
              icon: Icons.check_circle_outline_rounded,
              tone: 'green',
              value: '${a.perSellerClosed.values.fold(0, (s, v) => s + v)}',
              label: tr('Завершено', 'Аяқталды'),
            ),
          ),
        ]),

        const SizedBox(height: 20),

        // Reason breakdown
        Text(context.l10n.returnReasonBreakdown,
            style: manrope(15, FontWeight.w700, color: cInk)),
        const SizedBox(height: 10),
        if (a.reasonBreakdown.isEmpty)
          Text(context.l10n.returnNoReturns,
              style: manrope(13, FontWeight.w500, color: cInk3))
        else
          ...ReturnReason.values.map((reason) {
            final count = a.reasonBreakdown[reason] ?? 0;
            if (count == 0) return const SizedBox.shrink();
            final pct = a.totalReturns > 0
                ? count / a.totalReturns
                : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                        child: Text(reason.label(context),
                            style:
                                manrope(13, FontWeight.w600, color: cInk))),
                    Text('$count',
                        style: manrope(13, FontWeight.w700, color: cGreen)),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 6,
                      backgroundColor: cLine,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(cGreen),
                    ),
                  ),
                ],
              ),
            );
          }),

        const SizedBox(height: 20),

        // Top returned products
        Text(context.l10n.returnTopProducts,
            style: manrope(15, FontWeight.w700, color: cInk)),
        const SizedBox(height: 10),
        if (a.topReturnedProducts.isEmpty)
          Text(context.l10n.returnNoReturns,
              style: manrope(13, FontWeight.w500, color: cInk3))
        else
          ...a.topReturnedProducts.take(5).toList().asMap().entries.map(
                (e) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: cSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cLine),
                  ),
                  child: Row(children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: e.key == 0 ? cAmber : cGreenTint,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text('${e.key + 1}',
                            style: manrope(12, FontWeight.w800,
                                color: e.key == 0
                                    ? Colors.white
                                    : cGreenDeep)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(e.value.title,
                          style:
                              manrope(13.5, FontWeight.w600, color: cInk),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text(tr('${e.value.count} шт.', '${e.value.count} дана'),
                        style: manrope(13, FontWeight.w700, color: cGreen)),
                  ]),
                ),
              ),

        const SizedBox(height: 20),

        // Per-seller breakdown
        Text(context.l10n.returnPerSellerTitle,
            style: manrope(15, FontWeight.w700, color: cInk)),
        const SizedBox(height: 10),
        if (a.perSellerClosed.isEmpty)
          Text(context.l10n.returnNoReturns,
              style: manrope(13, FontWeight.w500, color: cInk3))
        else
          ...(a.perSellerClosed.entries.toList()
                ..sort((x, y) => y.value.compareTo(x.value)))
              .asMap()
              .entries
              .map(
                (e) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: cSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cLine),
                  ),
                  child: Row(children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: e.key == 0 ? cGreenTint : cLine2,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text('${e.key + 1}',
                            style: manrope(12, FontWeight.w800,
                                color:
                                    e.key == 0 ? cGreenDeep : cInk2)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        e.value.key.isNotEmpty ? e.value.key : '—',
                        style: manrope(13.5, FontWeight.w600, color: cInk),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(tr('${e.value.value} шт.', '${e.value.value} дана'),
                        style: manrope(13, FontWeight.w700, color: cGreen)),
                  ]),
                ),
              ),
      ],
    );
  }
}

// ── KPI card ──────────────────────────────────────────────────────────────────
class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String tone;
  final String value;
  final String label;

  const _KpiCard({
    required this.icon,
    required this.tone,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => QCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            QIconTile(
              icon: Icon(icon, color: _color(), size: 18),
              tone: tone,
              size: 36,
            ),
            const SizedBox(height: 8),
            Text(value,
                style: manrope(22, FontWeight.w800,
                    color: cInk, letterSpacing: -0.5)),
            const SizedBox(height: 2),
            Text(label,
                style: manrope(12, FontWeight.w600, color: cInk3),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      );

  Color _color() {
    switch (tone) {
      case 'red':    return cRed;
      case 'amber':  return cAmber;
      case 'blue':   return cBlue;
      default:       return cGreen;
    }
  }
}

// ── Period chip ───────────────────────────────────────────────────────────────
class _PeriodChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _PeriodChip(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: active ? cInk : cSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? cInk : cLine),
          ),
          child: Text(label,
              style: manrope(13, FontWeight.w700,
                  color: active ? Colors.white : cInk2)),
        ),
      );
}
