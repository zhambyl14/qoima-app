import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/lang.dart';
import '../../data/models/courier_change_request_model.dart';
import '../../data/services/courier_service.dart';
import '../../theme/qoima_design.dart';
import '../courier/courier_profile_screen.dart'
    show courierFieldLabel, courierFieldValue;
import '../shared/error_view.dart';
import 'reject_reason_sheet.dart';

/// Superadmin — курьерлердің деректерді өзгерту сұраныстары (0074).
///
/// Әр сұраныста ескі → жаңа мән (diff) көрсетіледі. Бекіту өзгерісті SQL-де
/// бір транзакцияда қолданады (`review_courier_change`): телефон бос па,
/// аты/қала дұрыс па — сервер қайта тексереді.
class CourierChangeRequestsScreen extends StatefulWidget {
  const CourierChangeRequestsScreen({super.key});

  @override
  State<CourierChangeRequestsScreen> createState() =>
      _CourierChangeRequestsScreenState();
}

class _CourierChangeRequestsScreenState
    extends State<CourierChangeRequestsScreen> {
  final _service = CourierService();
  StreamSubscription<List<CourierChangeRequest>>? _reqSub;
  StreamSubscription<List<CourierProfile>>? _profSub;

  List<CourierChangeRequest> _all = const [];
  Map<String, CourierProfile> _couriers = const {};
  bool _loading = true;
  Object? _error;
  int _tab = 0; // 0 Күтуде · 1 Мақұлданған · 2 Қабылданбаған
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    _reqSub?.cancel();
    _profSub?.cancel();
    _reqSub = _service.watchAllChangeRequests().listen((list) {
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
        _error = null;
      });
    }, onError: (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    });
    _profSub = _service.watchCourierProfiles().listen((list) {
      if (!mounted) return;
      setState(() => _couriers = {for (final c in list) c.uid: c});
    }, onError: (_) {});
  }

  Future<void> _retry() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _subscribe();
  }

  @override
  void dispose() {
    _reqSub?.cancel();
    _profSub?.cancel();
    super.dispose();
  }

  List<CourierChangeRequest> get _filtered => switch (_tab) {
        1 => _all.where((r) => r.isApproved).toList(),
        2 => _all.where((r) => r.isRejected || r.isCancelled).toList(),
        _ => _all.where((r) => r.isPending).toList(),
      };

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _approve(CourierChangeRequest r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
            tr('Одобрить изменения?', 'Өзгерістерді мақұлдау керек пе?'),
            style: manrope(16, FontWeight.w800, color: cInk)),
        content: Text(
            r.changes.containsKey('phone')
                ? tr('Номер для входа курьера изменится сразу.',
                    'Курьердің кіру нөмірі бірден өзгереді.')
                : tr('Данные курьера обновятся сразу.',
                    'Курьердің деректері бірден жаңарады.'),
            style: manrope(13.5, FontWeight.w500, color: cInk2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Отмена', 'Болдырмау'),
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cGreen, foregroundColor: Colors.white),
              child: Text(tr('Одобрить', 'Мақұлдау'))),
        ],
      ),
    );
    if (ok != true) return;
    await _review(r, approve: true);
  }

  Future<void> _reject(CourierChangeRequest r) async {
    final reason = await showRejectReasonSheet(
      context,
      title: tr('Отклонить запрос', 'Сұранысты қабылдамау'),
      subtitle: _nameOf(r),
      reasons: const [
        'Не удалось подтвердить личность',
        'Номер принадлежит другому человеку',
        'Город не обслуживается',
        'Некорректное имя',
      ],
    );
    if (reason == null || reason.trim().isEmpty) return;
    await _review(r, approve: false, rejectReason: reason.trim());
  }

  Future<void> _review(CourierChangeRequest r,
      {required bool approve, String rejectReason = ''}) async {
    HapticFeedback.mediumImpact();
    setState(() => _busy.add(r.id));
    try {
      await _service.reviewChange(r.id,
          approve: approve, rejectReason: rejectReason);
      _snack(
          approve
              ? tr('Изменения применены', 'Өзгерістер қолданылды')
              : tr('Запрос отклонён', 'Сұраныс қабылданбады'),
          approve ? cGreen : cAmber);
    } catch (e) {
      _snack(courierDataErrorText(e), cRed);
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  String _nameOf(CourierChangeRequest r) {
    final c = _couriers[r.courierUid];
    if (c == null) return '—';
    return c.name.isEmpty ? c.phone : c.name;
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _all.where((r) => r.isPending).length;
    final list = _filtered;
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Запросы курьеров', 'Курьер сұраныстары'),
          subtitle:
              tr('$pendingCount на рассмотрении', '$pendingCount қаралуда'),
          compact: true,
          showBack: true,
          bottom: [
            const SizedBox(height: 12),
            Row(children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 7),
                Expanded(
                  child: _TabChip(
                    label: switch (i) {
                      0 => tr('Ожидают', 'Күтуде'),
                      1 => tr('Одобрены', 'Мақұлданған'),
                      _ => tr('Отклонены', 'Қабылданбаған'),
                    },
                    count: switch (i) {
                      0 => pendingCount,
                      1 => _all.where((r) => r.isApproved).length,
                      _ =>
                        _all.where((r) => r.isRejected || r.isCancelled).length,
                    },
                    selected: _tab == i,
                    onTap: () => setState(() => _tab = i),
                  ),
                ),
              ],
            ]),
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: cGreen, strokeWidth: 2))
              : _error != null
                  ? AppErrorView(error: _error, onRetry: _retry)
                  : list.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                                _tab == 0
                                    ? tr('Новых запросов нет',
                                        'Жаңа сұраныс жоқ')
                                    : tr('Пусто', 'Бос'),
                                textAlign: TextAlign.center,
                                style:
                                    manrope(14, FontWeight.w600, color: cInk3)),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final r = list[i];
                            return _RequestCard(
                              req: r,
                              courierName: _nameOf(r),
                              busy: _busy.contains(r.id),
                              onApprove: () => _approve(r),
                              onReject: () => _reject(r),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _TabChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color:
                selected ? Colors.white : Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            Text('$count',
                style: manrope(15, FontWeight.w800,
                    color: selected ? cGreenDeep : Colors.white)),
            Text(label,
                style: manrope(10.5, FontWeight.w700,
                    color: selected
                        ? cGreenDeep
                        : Colors.white.withValues(alpha: 0.85))),
          ]),
        ),
      );
}

class _RequestCard extends StatelessWidget {
  final CourierChangeRequest req;
  final String courierName;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  const _RequestCard({
    required this.req,
    required this.courierName,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final (tone, statusLabel) = switch (req.status) {
      'approved' => ('green', tr('Одобрен', 'Мақұлданды')),
      'rejected' => ('red', tr('Отклонён', 'Қабылданбады')),
      'cancelled' => ('gray', tr('Отозван', 'Қайтарылды')),
      _ => ('amber', tr('Ожидает', 'Күтуде')),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cLine),
        boxShadow: kShadowSm,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          QIconTile(
            icon: const Icon(Icons.delivery_dining_rounded,
                color: cGreen, size: 20),
            tone: 'green',
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(courierName,
                  style: manrope(15, FontWeight.w800, color: cInk),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(_date(req.createdAt),
                  style: manrope(11.5, FontWeight.w600, color: cInk3)),
            ]),
          ),
          QPill(statusLabel, tone: tone),
        ]),
        const SizedBox(height: 12),
        // Diff: ескі → жаңа.
        for (final e in req.changes.entries)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(courierFieldLabel(e.key),
                  style: manrope(11, FontWeight.w700, color: cInk3)),
              const SizedBox(height: 4),
              Text(courierFieldValue(e.key, req.oldValues[e.key] ?? ''),
                  style: manrope(13, FontWeight.w600, color: cRedInk)
                      .copyWith(decoration: TextDecoration.lineThrough)),
              Row(children: [
                const Icon(Icons.arrow_downward_rounded,
                    size: 14, color: cInk3),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(courierFieldValue(e.key, e.value),
                      style: manrope(13.5, FontWeight.w800, color: cGreenDeep)),
                ),
              ]),
            ]),
          ),
        if (req.changes.containsKey('phone'))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
                tr('Телефон — это номер для входа курьера',
                    'Телефон — курьердің кіру нөмірі'),
                style: manrope(11, FontWeight.w600, color: cAmberInk)),
          ),
        if (req.reason.isNotEmpty)
          Text('«${req.reason}»',
              style: manrope(12.5, FontWeight.w600, color: cInk2)),
        if (req.isRejected && req.rejectReason.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                '${tr('Причина отказа', 'Бас тарту себебі')}: ${trValue(req.rejectReason)}',
                style: manrope(12, FontWeight.w600, color: cRedInk)),
          ),
        if (req.isPending) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : onReject,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: cLine),
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(tr('Отклонить', 'Қабылдамау'),
                    style: manrope(13, FontWeight.w800, color: cRed)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: busy ? null : onApprove,
                style: ElevatedButton.styleFrom(
                  backgroundColor: cGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(tr('Одобрить', 'Мақұлдау'),
                        style:
                            manrope(13, FontWeight.w800, color: Colors.white)),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}
