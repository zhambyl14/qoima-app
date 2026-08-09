import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/error_text.dart';
import '../../core/lang.dart';
import '../../theme/qoima_design.dart';

/// Модератордың курьерлік ТАПСЫРЫСТАРЫ (0060).
///
/// НЕГЕ КЕРЕК: курьер модераторға бағынады, бірақ модераторда тек курьерлердің
/// ТІЗІМІ бар еді — олардың нақты жұмысы көрінбейтін. Ең ауыр салдары: курьер
/// тапсырысты алып жоғалып кетсе (телефоны өшік, ауырып қалды), оны ЕШКІМ
/// босата алмайтын — дүкенге `guard_courier_order_lock` тыйым салады, ал
/// модераторда мұндай экран болмаған. Тапсырыс мәңгі «курьерде» болып қалатын.
class CourierOrdersTab extends StatefulWidget {
  const CourierOrdersTab({super.key});

  @override
  State<CourierOrdersTab> createState() => _CourierOrdersTabState();
}

class _CourierOrdersTabState extends State<CourierOrdersTab> {
  final _sb = Supabase.instance.client;
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  int _filter = 0; // 0 бос · 1 жұмыста · 2 тұрып қалған · 3 бәрі

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _sb.rpc('superadmin_courier_orders');
      if (!mounted) return;
      setState(() {
        _all = res is List
            ? res.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : [];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Күй топтары ───────────────────────────────────────────────────────────
  static bool _isFree(Map<String, dynamic> o) =>
      o['status'] == 'confirmed' && (o['courierUid'] as String? ?? '').isEmpty;

  static bool _inWork(Map<String, dynamic> o) =>
      (o['courierUid'] as String? ?? '').isNotEmpty &&
      o['courierStatus'] != 'delivered';

  /// «Тұрып қалған» — курьер алғанына 2 сағаттан асты, әлі жеткізілмеген,
  /// немесе расталған тапсырысты 2 сағат бойы ешкім алмады. Модератор дәл
  /// осыларға араласуы керек.
  static bool _stuck(Map<String, dynamic> o) {
    final since = _takenOrCreated(o);
    if (since == null) return false;
    final old = DateTime.now().difference(since) > const Duration(hours: 2);
    return old && (_isFree(o) || _inWork(o));
  }

  static DateTime? _takenOrCreated(Map<String, dynamic> o) {
    final raw = (o['takenAt'] as String?) ?? (o['createdAt'] as String?);
    return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  }

  List<Map<String, dynamic>> get _list => switch (_filter) {
        0 => _all.where(_isFree).toList(),
        1 => _all.where(_inWork).toList(),
        2 => _all.where(_stuck).toList(),
        _ => _all,
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

  Future<void> _release(Map<String, dynamic> o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cSurface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Снять курьера с заказа?', 'Курьерді тапсырыстан алу?'),
            style: manrope(16, FontWeight.w800, color: cInk)),
        content: Text(
            tr('Заказ вернётся в общий список — его сможет взять другой курьер. Текущий курьер получит уведомление.',
                'Тапсырыс жалпы тізімге оралады — оны басқа курьер ала алады. Қазіргі курьерге хабарлама барады.'),
            style: manrope(13, FontWeight.w600, color: cInk2, height: 1.4)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Отмена', 'Болдырмау'),
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cRed, foregroundColor: Colors.white),
              child: Text(tr('Снять', 'Алу'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _sb.rpc('superadmin_release_order',
          params: {'p_order': o['id'], 'p_reason': ''});
      await _load();
      _snack(tr('Заказ освобождён', 'Тапсырыс босатылды'), cGreen);
    } catch (e) {
      _snack(friendlyError(e), cRed);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: cGreen, strokeWidth: 2));
    }
    final list = _list;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(width: 7),
            Expanded(
              child: _FilterChip(
                label: switch (i) {
                  0 => tr('Свободные', 'Бос'),
                  1 => tr('В работе', 'Жұмыста'),
                  2 => tr('Зависли', 'Тұрып қалған'),
                  _ => tr('Все', 'Бәрі'),
                },
                count: switch (i) {
                  0 => _all.where(_isFree).length,
                  1 => _all.where(_inWork).length,
                  2 => _all.where(_stuck).length,
                  _ => _all.length,
                },
                selected: _filter == i,
                danger: i == 2,
                onTap: () => setState(() => _filter = i),
              ),
            ),
          ],
        ]),
      ),
      Expanded(
        child: RefreshIndicator(
          color: cGreen,
          onRefresh: _load,
          child: list.isEmpty
              ? ListView(padding: const EdgeInsets.fromLTRB(32, 90, 32, 32), children: [
                  const Icon(Icons.inbox_outlined, size: 44, color: cInk3),
                  const SizedBox(height: 12),
                  Text(tr('Пусто', 'Бос'),
                      textAlign: TextAlign.center,
                      style: manrope(14.5, FontWeight.w700, color: cInk3)),
                ])
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                  children: list
                      .map((o) => _OrderRow(
                            order: o,
                            stuck: _stuck(o),
                            onRelease:
                                _inWork(o) ? () => _release(o) : null,
                          ))
                      .toList(),
                ),
        ),
      ),
    ]);
  }
}

class _OrderRow extends StatelessWidget {
  final Map<String, dynamic> order;
  final bool stuck;
  final VoidCallback? onRelease;

  const _OrderRow({
    required this.order,
    required this.stuck,
    this.onRelease,
  });

  String get _stateLabel {
    final cs = order['courierStatus'] as String? ?? '';
    if (order['status'] == 'completed') return tr('Доставлен', 'Жеткізілді');
    if (order['status'] == 'cancelled') return tr('Отменён', 'Болдырылмады');
    if (cs == 'picked_up') return tr('Везёт клиенту', 'Клиентке апара жатыр');
    if (cs == 'assigned') return tr('Едет на склад', 'Қоймаға бара жатыр');
    if (order['status'] == 'confirmed') return tr('Ждёт курьера', 'Курьерді күтуде');
    return tr('Ждёт оплаты', 'Төлемді күтуде');
  }

  String get _age {
    final raw = (order['takenAt'] as String?) ?? (order['createdAt'] as String?);
    final t = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return tr('${d.inMinutes} мин', '${d.inMinutes} мин');
    if (d.inHours < 24) return tr('${d.inHours} ч', '${d.inHours} сағ');
    return tr('${d.inDays} дн', '${d.inDays} күн');
  }

  @override
  Widget build(BuildContext context) {
    final courier = order['courierName'] as String? ?? '';
    final city = order['city'] as String? ?? '';
    final clientCity = order['clientCity'] as String? ?? '';
    final otherCity = clientCity.isNotEmpty &&
        city.isNotEmpty &&
        clientCity.toLowerCase() != city.toLowerCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: stuck ? cRed.withValues(alpha: 0.5) : cLine,
            width: stuck ? 1.5 : 1),
        boxShadow: kShadowSm,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('№${order['orderNumber']}',
              style: manrope(14, FontWeight.w800, color: cInk)),
          const SizedBox(width: 8),
          QPill(trValue(city), tone: 'blue'),
          const Spacer(),
          Text('${(order['deliveryFee'] as num?)?.toInt() ?? 0} ₸',
              style: manrope(13.5, FontWeight.w800, color: cGreenDeep)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Icon(stuck ? Icons.warning_amber_rounded : Icons.schedule_rounded,
              size: 14, color: stuck ? cRed : cInk3),
          const SizedBox(width: 5),
          Expanded(
            child: Text('$_stateLabel · $_age',
                style: manrope(12, FontWeight.w700,
                    color: stuck ? cRed : cInk2)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
            '${order['storeName']} → ${order['clientName']}'
            '${otherCity ? ' · ${tr('ДРУГОЙ ГОРОД', 'БАСҚА ҚАЛА')}' : ''}',
            style: manrope(12, FontWeight.w600, color: cInk2),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        if (courier.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(children: [
              const Icon(Icons.delivery_dining_rounded,
                  size: 14, color: cInk3),
              const SizedBox(width: 5),
              Text(courier,
                  style: manrope(12, FontWeight.w700, color: cInk2)),
            ]),
          ),
        if (onRelease != null) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 38,
            child: OutlinedButton.icon(
              onPressed: onRelease,
              icon: const Icon(Icons.person_remove_outlined, size: 16),
              label: Text(tr('Снять курьера', 'Курьерді алу'),
                  style: manrope(12.5, FontWeight.w800, color: cRed)),
              style: OutlinedButton.styleFrom(
                foregroundColor: cRed,
                side: BorderSide(color: cRed.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11)),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final bool danger;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final tone = danger && count > 0 ? cRed : cGreen;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? tone : cSurface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: selected ? tone : cLine),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$count',
              style: manrope(14, FontWeight.w800,
                  color: selected ? Colors.white : tone)),
          Text(label,
              textAlign: TextAlign.center,
              style: manrope(10, FontWeight.w700,
                  color: selected ? Colors.white : cInk3)),
        ]),
      ),
    );
  }
}
