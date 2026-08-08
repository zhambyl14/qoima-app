import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/error_text.dart';
import '../../core/lang.dart';
import '../../data/models/order_model.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/courier_service.dart';
import '../../theme/qoima_design.dart';
import 'courier_order_card.dart';

/// Курьердің басты экраны: «Жаңа тапсырыстар» · «Менікі» · «Профиль».
///
/// Курьер модераторға бағынады, дүкенге емес — сондықтан бұл бөлек shell
/// (AdminShell/MainShell-мен ортақ ештеңесі жоқ: қойма, тауар, аналитика
/// оған қажет емес әрі көрінбеуі керек).
class CourierShell extends StatefulWidget {
  const CourierShell({super.key});

  @override
  State<CourierShell> createState() => _CourierShellState();
}

class _CourierShellState extends State<CourierShell> {
  final _service = CourierService();
  int _tab = 0;

  List<OrderModel> _available = [];
  List<OrderModel> _mine = [];
  CourierStats _stats = const CourierStats();
  bool _loading = true;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Тапсырыстар RPC арқылы келеді (realtime stream емес — курьер бөтен
    // дүкеннің жолын тыңдай алмайды). Сондықтан жеңіл поллинг: 25 секунд —
    // жаңа тапсырысты байқауға жеткілікті, батареяны жемейді.
    _poll = Timer.periodic(const Duration(seconds: 25), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final results = await Future.wait([
        _service.getAvailableOrders(),
        _service.getMyOrders(),
        _service.getStats(),
      ]);
      if (!mounted) return;
      setState(() {
        _available = results[0] as List<OrderModel>;
        _mine = results[1] as List<OrderModel>;
        _stats = results[2] as CourierStats;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

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

  Future<void> _run(Future<void> Function() action, String okMsg) async {
    try {
      await action();
      await _refresh();
      _snack(okMsg, cGreen);
    } catch (e) {
      _snack(friendlyError(e), cRed);
    }
  }

  /// Белсенді миссиялар: әлі жеткізілмегендер + жеткізілсе де клиент
  /// таңдамаған өлшемі әлі курьерде жүргендер (қоймаға апару керек).
  List<OrderModel> get _activeMine => _mine
      .where((o) =>
          o.status == OrderModel.statusConfirmed || o.returnLegPending)
      .toList();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppUser>();
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: _tab == 0
              ? tr('Новые заказы', 'Жаңа тапсырыстар')
              : _tab == 1
                  ? tr('Мои доставки', 'Менің жеткізулерім')
                  : tr('Профиль', 'Профиль'),
          subtitle: user.city.isEmpty
              ? tr('Курьер', 'Курьер')
              : '${tr('Курьер', 'Курьер')} · ${trValue(user.city)}',
          action: QHeaderBtn(Icons.refresh_rounded, onTap: _refresh),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: cGreen, strokeWidth: 2))
              : RefreshIndicator(
                  color: cGreen,
                  onRefresh: _refresh,
                  child: switch (_tab) {
                    0 => _buildAvailable(),
                    1 => _buildMine(),
                    _ => _buildProfile(user),
                  },
                ),
        ),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: cSurface,
        indicatorColor: cGreenTint,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _available.isNotEmpty,
              label: Text('${_available.length}'),
              child: const Icon(Icons.inbox_outlined),
            ),
            selectedIcon: const Icon(Icons.inbox_rounded, color: cGreenDeep),
            label: tr('Новые', 'Жаңа'),
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _activeMine.isNotEmpty,
              label: Text('${_activeMine.length}'),
              child: const Icon(Icons.local_shipping_outlined),
            ),
            selectedIcon:
                const Icon(Icons.local_shipping_rounded, color: cGreenDeep),
            label: tr('Мои', 'Менікі'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline_rounded),
            selectedIcon: const Icon(Icons.person_rounded, color: cGreenDeep),
            label: tr('Профиль', 'Профиль'),
          ),
        ],
      ),
    );
  }

  // ── Таб 1: бос тапсырыстар ─────────────────────────────────────────────────
  Widget _buildAvailable() {
    if (_available.isEmpty) {
      return _emptyList(
        Icons.inbox_outlined,
        tr('Свободных заказов нет', 'Бос тапсырыс жоқ'),
        tr('Как только магазин подтвердит оплату — заказ появится здесь',
            'Дүкен төлемді растаған бойда тапсырыс осында шығады'),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: _available
          .map((o) => CourierOrderCard(
                order: o,
                onTake: () => _run(() => _service.takeOrder(o.id),
                    tr('Заказ ваш — забирайте со склада', 'Тапсырыс сіздікі — қоймадан алыңыз')),
              ))
          .toList(),
    );
  }

  // ── Таб 2: менің жеткізулерім ──────────────────────────────────────────────
  Widget _buildMine() {
    if (_mine.isEmpty) {
      return _emptyList(
        Icons.local_shipping_outlined,
        tr('Пока пусто', 'Әзірге бос'),
        tr('Возьмите заказ во вкладке «Новые»',
            '«Жаңа» табынан тапсырыс алыңыз'),
      );
    }
    final active = _activeMine;
    final done = _mine.where((o) => o.status != OrderModel.statusConfirmed);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        if (active.isNotEmpty) ...[
          QSecLabel(tr('В работе', 'Жұмыста')),
          const SizedBox(height: 8),
          ...active.map((o) => CourierOrderCard(
                order: o,
                onPickup: (code) => _run(
                    () => _service.pickupOrder(o.id, code),
                    tr('Забрано со склада', 'Қоймадан алынды')),
                onDeliver: (swaps) => _run(
                    () => _service.completeOrder(o.id, swappedIndexes: swaps),
                    tr('Доставлено ✓', 'Жеткізілді ✓')),
                onReturn: (reason) => _run(
                    () => _service.returnOrder(o.id, reason),
                    tr('Заказ возвращён на склад', 'Тапсырыс қоймаға оралды')),
                onDrop: () => _run(() => _service.dropOrder(o.id),
                    tr('Заказ освобождён', 'Тапсырыс босатылды')),
              )),
          const SizedBox(height: 14),
        ],
        if (done.isNotEmpty) ...[
          QSecLabel(tr('История', 'Тарих')),
          const SizedBox(height: 8),
          ...done.map((o) => CourierOrderCard(order: o)),
        ],
      ],
    );
  }

  // ── Таб 3: профиль + табыс ─────────────────────────────────────────────────
  Widget _buildProfile(AppUser user) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cLine),
              boxShadow: kShadowSm,
            ),
            child: Row(children: [
              QIconTile(
                icon: const Icon(Icons.delivery_dining_rounded,
                    color: cGreen, size: 22),
                tone: 'green',
                size: 46,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name,
                          style: manrope(16, FontWeight.w800, color: cInk)),
                      Text(user.phone,
                          style:
                              manrope(12.5, FontWeight.w600, color: cInk3)),
                    ]),
              ),
              QPill(trValue(user.city), tone: 'green'),
            ]),
          ),
          const SizedBox(height: 18),
          QSecLabel(tr('Мой заработок', 'Менің табысым')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _StatTile(
                    label: tr('Сегодня', 'Бүгін'),
                    count: _stats.todayCount,
                    fee: _stats.todayFee,
                    tone: 'green')),
            const SizedBox(width: 10),
            Expanded(
                child: _StatTile(
                    label: tr('Неделя', 'Апта'),
                    count: _stats.weekCount,
                    fee: _stats.weekFee,
                    tone: 'blue')),
          ]),
          const SizedBox(height: 10),
          _StatTile(
              label: tr('Всего', 'Барлығы'),
              count: _stats.totalCount,
              fee: _stats.totalFee,
              tone: 'amber',
              wide: true),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: cBg, borderRadius: BorderRadius.circular(13)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline_rounded, color: cInk3, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('Сумма — это оплата доставки и примерки по выполненным заказам. Расчёт с модератором.',
                      'Сома — орындалған тапсырыстардың жеткізу мен өлшеп көру ақысы. Есеп айырысу модератормен.'),
                  style:
                      manrope(11.5, FontWeight.w600, color: cInk3, height: 1.4),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 22),
          QMenuItem(
            icon: Icons.logout_rounded,
            tone: 'red',
            title: tr('Выйти', 'Шығу'),
            danger: true,
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  title: Text(tr('Выйти из аккаунта?', 'Аккаунттан шығу керек пе?'),
                      style: manrope(16, FontWeight.w800, color: cInk)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(tr('Отмена', 'Болдырмау'),
                            style:
                                manrope(14, FontWeight.w600, color: cInk2))),
                    ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: cRed,
                            foregroundColor: Colors.white),
                        child: Text(tr('Выйти', 'Шығу'))),
                  ],
                ),
              );
              if (ok == true) await AuthService().signOut();
            },
          ),
        ],
      );

  Widget _emptyList(IconData icon, String title, String hint) => ListView(
        padding: const EdgeInsets.fromLTRB(32, 80, 32, 32),
        children: [
          Icon(icon, size: 46, color: cInk3),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center,
              style: manrope(15.5, FontWeight.w800, color: cInk2)),
          const SizedBox(height: 6),
          Text(hint,
              textAlign: TextAlign.center,
              style: manrope(12.5, FontWeight.w600, color: cInk3, height: 1.4)),
        ],
      );
}

class _StatTile extends StatelessWidget {
  final String label;
  final int count;
  final double fee;
  final String tone;
  final bool wide;
  const _StatTile({
    required this.label,
    required this.count,
    required this.fee,
    required this.tone,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: cLine),
          boxShadow: kShadowSm,
        ),
        child: Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: manrope(12, FontWeight.w600, color: cInk3)),
                  const SizedBox(height: 4),
                  Text(money(fee),
                      style: manrope(wide ? 22 : 18, FontWeight.w800,
                          color: cInk)),
                  Text(
                      tr('$count доставок', '$count жеткізу'),
                      style: manrope(11.5, FontWeight.w600, color: cInk3)),
                ]),
          ),
          QIconTile(
            icon: Icon(Icons.payments_rounded,
                color: tone == 'green'
                    ? cGreen
                    : tone == 'blue'
                        ? cBlue
                        : cAmber,
                size: 18),
            tone: tone,
            size: 38,
          ),
        ]),
      );
}
