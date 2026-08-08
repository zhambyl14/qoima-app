import 'package:flutter/material.dart';
import '../../core/error_text.dart';
import '../../core/kz_cities.dart';
import '../../core/lang.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/store_moderation_repository.dart';
import '../../theme/qoima_design.dart';

/// Superadmin — курьерлерді басқару.
///
/// Курьер дүкенге емес, тікелей модераторға бағынады: тіркелген соң
/// 'pending' күйінде тұрады да, осы экраннан бекітілгенше бірде-бір
/// тапсырысты (демек, клиенттің мекенжайы мен телефонын) көрмейді.
class CouriersScreen extends StatefulWidget {
  const CouriersScreen({super.key});

  @override
  State<CouriersScreen> createState() => _CouriersScreenState();
}

class _CouriersScreenState extends State<CouriersScreen> {
  final _repo = StoreModerationRepository();
  int _tab = 0; // 0 Күтуде · 1 Белсенді · 2 Бұғатталған

  static const _statuses = ['pending', 'active', 'blocked'];

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

  Future<void> _set(UserModel c, String status, {String? city}) async {
    try {
      await _repo.setCourierStatus(c.uid, status, city: city);
      _snack(
          status == 'active'
              ? tr('Курьер допущен к заказам', 'Курьерге тапсырыс ашылды')
              : status == 'blocked'
                  ? tr('Доступ приостановлен', 'Рұқсат тоқтатылды')
                  : tr('Возвращён в ожидание', 'Күту күйіне қайтарылды'),
          status == 'blocked' ? cAmber : cGreen);
    } catch (e) {
      _snack(friendlyError(e), cRed);
    }
  }

  Future<void> _changeCity(UserModel c) async {
    final city = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CityPickerSheet(current: c.city),
    );
    if (city == null) return;
    await _set(c, c.courierStatus.isEmpty ? 'pending' : c.courierStatus,
        city: city);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: StreamBuilder<List<UserModel>>(
        stream: _repo.watchCouriers(),
        builder: (context, snap) {
          final all = snap.data ?? [];
          final counts = {
            for (final s in _statuses)
              s: all.where((c) => _statusOf(c) == s).length,
          };
          final list =
              all.where((c) => _statusOf(c) == _statuses[_tab]).toList();
          return Column(children: [
            QGradientHeader(
              title: tr('Курьеры', 'Курьерлер'),
              subtitle: tr('${all.length} всего', 'барлығы ${all.length}'),
              compact: true,
              showBack: true,
              bottom: [
                const SizedBox(height: 12),
                Row(children: [
                  for (var i = 0; i < _statuses.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: _Chip(
                        label: switch (i) {
                          0 => tr('Ожидают', 'Күтуде'),
                          1 => tr('Активные', 'Белсенді'),
                          _ => tr('Блок', 'Бұғат'),
                        },
                        count: counts[_statuses[i]] ?? 0,
                        selected: _tab == i,
                        onTap: () => setState(() => _tab = i),
                      ),
                    ),
                  ],
                ]),
              ],
            ),
            Expanded(
              child: snap.connectionState == ConnectionState.waiting
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: cGreen, strokeWidth: 2))
                  : list.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                                _tab == 0
                                    ? tr('Новых заявок нет', 'Жаңа өтінім жоқ')
                                    : tr('Пусто', 'Бос'),
                                textAlign: TextAlign.center,
                                style: manrope(14, FontWeight.w600,
                                    color: cInk3)),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                          children: list
                              .map((c) => _CourierCard(
                                    courier: c,
                                    status: _statusOf(c),
                                    onApprove: () => _set(c, 'active'),
                                    onBlock: () => _set(c, 'blocked'),
                                    onCity: () => _changeCity(c),
                                  ))
                              .toList(),
                        ),
            ),
          ]);
        },
      ),
    );
  }

  /// Ескі жолдарда courier_status бос болуы мүмкін — оларды «күтуде» санаймыз
  /// (әдепкі — рұқсат БЕРІЛМЕГЕН).
  static String _statusOf(UserModel c) =>
      c.courierStatus.isEmpty ? 'pending' : c.courierStatus;
}

class _Chip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({
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
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.16),
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

class _CourierCard extends StatelessWidget {
  final UserModel courier;
  final String status;
  final VoidCallback onApprove, onBlock, onCity;
  const _CourierCard({
    required this.courier,
    required this.status,
    required this.onApprove,
    required this.onBlock,
    required this.onCity,
  });

  @override
  Widget build(BuildContext context) => Container(
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
              icon: Icon(Icons.delivery_dining_rounded,
                  color: status == 'active'
                      ? cGreen
                      : status == 'blocked'
                          ? cRed
                          : cAmber,
                  size: 20),
              tone: status == 'active'
                  ? 'green'
                  : status == 'blocked'
                      ? 'red'
                      : 'amber',
              size: 42,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(courier.name.isEmpty ? '—' : courier.name,
                        style: manrope(15, FontWeight.w800, color: cInk),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(courier.email,
                        style: manrope(12, FontWeight.w600, color: cInk3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ]),
            ),
          ]),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onCity,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.location_city_outlined,
                    size: 16, color: cInk3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      courier.city.isEmpty
                          ? tr('Город не указан', 'Қала көрсетілмеген')
                          : trValue(courier.city),
                      style: manrope(13, FontWeight.w700,
                          color: courier.city.isEmpty ? cRed : cInk)),
                ),
                Text(tr('изменить', 'өзгерту'),
                    style: manrope(11.5, FontWeight.w700, color: cGreen)),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Text(
              tr('Курьер видит только заказы магазинов этого города',
                  'Курьер тек осы қаладағы дүкендердің тапсырысын көреді'),
              style: manrope(11, FontWeight.w600, color: cInk3)),
          const SizedBox(height: 12),
          Row(children: [
            if (status != 'active')
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: courier.city.isEmpty ? null : onApprove,
                  icon: const Icon(Icons.check_rounded, size: 17),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  label: Text(tr('Допустить', 'Рұқсат беру'),
                      style: manrope(13, FontWeight.w800,
                          color: Colors.white)),
                ),
              ),
            if (status == 'active')
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onBlock,
                  icon: const Icon(Icons.block_rounded, size: 17, color: cRed),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: cLine),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  label: Text(tr('Приостановить', 'Тоқтату'),
                      style: manrope(13, FontWeight.w800, color: cRed)),
                ),
              ),
          ]),
        ]),
      );
}

// ── Қала таңдау парағы ────────────────────────────────────────────────────────
class _CityPickerSheet extends StatelessWidget {
  final String current;
  const _CityPickerSheet({required this.current});

  @override
  Widget build(BuildContext context) => Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7),
        decoration: const BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                color: cLine, borderRadius: BorderRadius.circular(2)),
          ),
          Text(tr('Город работы', 'Жұмыс қаласы'),
              style: manrope(16, FontWeight.w800, color: cInk)),
          const SizedBox(height: 14),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: kzCities.map((c) {
                final selected = c == current;
                return ListTile(
                  onTap: () => Navigator.pop(context, c),
                  title: Text(trValue(c),
                      style: manrope(14.5, FontWeight.w700,
                          color: selected ? cGreenDeep : cInk)),
                  trailing: selected
                      ? const Icon(Icons.check_circle_rounded,
                          color: cGreen, size: 20)
                      : null,
                );
              }).toList(),
            ),
          ),
        ]),
      );
}
