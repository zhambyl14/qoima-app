import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/error_text.dart';
import '../../core/lang.dart';
import '../../data/models/order_model.dart';
import '../../data/models/return_model.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/courier_service.dart';
import '../../theme/qoima_design.dart';
import '../support/support_entry.dart';
import 'courier_order_card.dart';
import 'courier_return_card.dart';

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
  // Возврат та — курьердің жұмысы: клиенттен алып, дүкенге апару. Ол
  // жеткізумен БІРДЕЙ тізімде тұрады (бұрын мүлде көрінбейтін).
  List<ReturnModel> _availableReturns = [];
  List<ReturnModel> _myReturns = [];
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
        _service.getAvailableReturns(),
        _service.getMyReturns(),
      ]);
      if (!mounted) return;
      setState(() {
        _available = results[0] as List<OrderModel>;
        _mine = results[1] as List<OrderModel>;
        _stats = results[2] as CourierStats;
        _availableReturns = results[3] as List<ReturnModel>;
        _myReturns = results[4] as List<ReturnModel>;
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

  /// Аяқталмаған возвраттар (клиенттен алу / дүкенге апару).
  List<ReturnModel> get _activeReturns =>
      _myReturns.where((r) => !r.courierDelivered).toList();

  /// Қоймаға апарылмаған өлшемдер — курьердің «жабылмаған борышы».
  List<OrderModel> get _pendingLegs =>
      _mine.where((o) => o.returnLegPending).toList();

  int get _availableCount => _available.length + _availableReturns.length;
  int get _activeCount => _activeMine.length + _activeReturns.length;

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
          action: Row(mainAxisSize: MainAxisSize.min, children: [
            // Қолдау чаты (feature_support_chat өшік болса жасырын).
            const SupportHeaderButton(),
            QHeaderBtn(Icons.refresh_rounded, onTap: _refresh),
          ]),
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
              isLabelVisible: _availableCount > 0,
              label: Text('$_availableCount'),
              child: const Icon(Icons.inbox_outlined),
            ),
            selectedIcon: const Icon(Icons.inbox_rounded, color: cGreenDeep),
            label: tr('Новые', 'Жаңа'),
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _activeCount > 0,
              label: Text('$_activeCount'),
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

  /// Тапсырыстарды БІР ТӨЛЕМ (бір клиенттің бір себеті) бойынша топтайды.
  ///
  /// Кілт — `cartGroupId`, ол бос болса тапсырыстың өз id-і (жалғыз мүшелі
  /// топ). Реті бұзылмайды: топ бірінші кездескен орнында тұрады.
  List<List<OrderModel>> _groupByCart(List<OrderModel> orders) {
    final byKey = <String, List<OrderModel>>{};
    for (final o in orders) {
      final key = o.cartGroupId.isEmpty ? o.id : o.cartGroupId;
      byKey.putIfAbsent(key, () => []).add(o);
    }
    return byKey.values.toList();
  }

  // ── Таб 1: бос жұмыс (жеткізу + возврат) ───────────────────────────────────
  Widget _buildAvailable() {
    if (_available.isEmpty && _availableReturns.isEmpty) {
      return _emptyList(
        Icons.inbox_outlined,
        tr('Свободных заказов нет', 'Бос тапсырыс жоқ'),
        tr('Как только магазин подтвердит оплату или возврат — работа появится здесь',
            'Дүкен төлемді немесе қайтарымды растаған бойда жұмыс осында шығады'),
      );
    }
    final groups = _groupByCart(_available);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        if (_available.isNotEmpty) ...[
          QSecLabel(tr('Доставки', 'Жеткізулер')),
          const SizedBox(height: 8),
          ...groups.map((g) => g.length == 1
              ? CourierOrderCard(
                  order: g.first,
                  onTake: () => _run(() => _service.takeOrder(g.first.id),
                      tr('Заказ ваш — забирайте со склада',
                          'Тапсырыс сіздікі — қоймадан алыңыз')),
                )
              // Бір клиент — бірнеше дүкен. Жарты топты алу мағынасыз
              // (мекенжай біреу), сондықтан бір ғана батырма.
              : _CartGroup(
                  orders: g,
                  onTakeAll: () => _run(
                      () => _service.takeGroup(g.first.cartGroupId),
                      tr('Заказ ваш — объедьте склады',
                          'Тапсырыс сіздікі — қоймаларды аралаңыз')),
                )),
          const SizedBox(height: 14),
        ],
        // Возврат та — жұмыс. Бұрын курьерге мүлде көрінбейтін.
        if (_availableReturns.isNotEmpty) ...[
          QSecLabel(tr('Возвраты — забрать у клиента',
              'Қайтарымдар — клиенттен алу')),
          const SizedBox(height: 8),
          ..._availableReturns.map((r) => CourierReturnCard(
                ret: r,
                onTake: () => _run(() => _service.takeReturn(r.id),
                    tr('Возврат ваш — заберите у клиента',
                        'Қайтарым сіздікі — клиенттен алыңыз')),
              )),
        ],
      ],
    );
  }

  // ── Таб 2: менің жұмысым ───────────────────────────────────────────────────
  Widget _buildMine() {
    if (_mine.isEmpty && _myReturns.isEmpty) {
      return _emptyList(
        Icons.local_shipping_outlined,
        tr('Пока пусто', 'Әзірге бос'),
        tr('Возьмите заказ во вкладке «Новые»',
            '«Жаңа» табынан тапсырыс алыңыз'),
      );
    }
    final active = _activeMine;
    final done = _mine.where((o) =>
        o.status != OrderModel.statusConfirmed && !o.returnLegPending);
    final doneReturns = _myReturns.where((r) => r.courierDelivered);
    final legs = _pendingLegs;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        // ── Ең үстінде: қоймаға апарылмаған өлшемдер ────────────────────────
        //  Бұл миссияның ЕҢ ОҢАЙ ҰМЫТЫЛАТЫН бөлігі — тауар курьерде қалып,
        //  дүкеннің қоймасы шындықты көрсетпей тұрады. Сондықтан бірінші орында.
        if (legs.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(13),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: cAmberTint,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: cAmber, width: 1.5),
            ),
            child: Row(children: [
              const Icon(Icons.assignment_return_rounded,
                  color: cAmber, size: 22),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          tr('У вас ${legs.length} размер(ов) для склада',
                              'Сізде қоймаға апаратын ${legs.length} өлшем бар'),
                          style: manrope(13, FontWeight.w800, color: cInk)),
                      Text(
                          tr('Отвезите их продавцу — иначе товар числится потерянным',
                              'Оларды сатушыға апарыңыз — әйтпесе тауар жоғалған болып саналады'),
                          style:
                              manrope(11.5, FontWeight.w600, color: cInk2)),
                    ]),
              ),
            ]),
          ),
        ],
        if (active.isNotEmpty) ...[
          QSecLabel(tr('В работе', 'Жұмыста')),
          const SizedBox(height: 8),
          // Бір себеттен шыққандары бірге тұрады: курьер әр дүкенге өз
          // кодымен соғады, бірақ клиентке БІР рет барады.
          ..._groupByCart(active).map((g) => _CartGroup(
                orders: g,
                children: g.map(_activeCard).toList(),
              )),
          const SizedBox(height: 14),
        ],
        if (_activeReturns.isNotEmpty) ...[
          QSecLabel(tr('Возвраты в работе', 'Жұмыстағы қайтарымдар')),
          const SizedBox(height: 8),
          ..._activeReturns.map((r) => CourierReturnCard(
                ret: r,
                onPickup: (fee) => _run(
                    () => _service.pickupReturn(r.id, feeCollected: fee),
                    tr('Забрано у клиента', 'Клиенттен алынды')),
                onDeliver: () => _run(() => _service.deliverReturn(r.id),
                    tr('Сдано в магазин ✓', 'Дүкенге тапсырылды ✓')),
              )),
          const SizedBox(height: 14),
        ],
        if (done.isNotEmpty || doneReturns.isNotEmpty) ...[
          QSecLabel(tr('История', 'Тарих')),
          const SizedBox(height: 8),
          ...done.map((o) => CourierOrderCard(order: o)),
          ...doneReturns.map((r) => CourierReturnCard(ret: r)),
        ],
      ],
    );
  }

  /// Жұмыстағы тапсырыс карточкасы (әрекеттерімен) — топта да, жеке де сол.
  Widget _activeCard(OrderModel o) => CourierOrderCard(
        order: o,
        onPickup: (code) => _run(() => _service.pickupOrder(o.id, code),
            tr('Забрано со склада', 'Қоймадан алынды')),
        onDeliver: (swaps, feeCollected) => _run(
            () => _service.completeOrder(o.id,
                swappedIndexes: swaps, feeCollected: feeCollected),
            tr('Доставлено ✓', 'Жеткізілді ✓')),
        onReturn: (reason, feeCollected) => _run(
            () => _service.returnOrder(o.id, reason, feeCollected: feeCollected),
            tr('Заказ возвращён на склад', 'Тапсырыс қоймаға оралды')),
        onDrop: () => _run(() => _service.dropOrder(o.id),
            tr('Заказ освобождён', 'Тапсырыс босатылды')),
      );

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
          // ── Ақшаның ТОЛЫҚ жіктелуі: қайдан келгені әр тиынға дейін ────────
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: cSurface,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: cLine),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Из чего складывается', 'Неден құралады'),
                  style: manrope(12, FontWeight.w800, color: cInk3)),
              const SizedBox(height: 8),
              _MoneyLine(
                  label: tr('Доставки клиентам', 'Клиенттерге жеткізу'),
                  value: money(_stats.deliveryFee)),
              _MoneyLine(
                  label: tr('Перевозка возвратов', 'Қайтарым тасымалы'),
                  value: money(_stats.returnFee)),
              if (_stats.uncollected > 0)
                _MoneyLine(
                    label: tr('Клиент не заплатил', 'Клиент төлемеді'),
                    value: money(_stats.uncollected),
                    color: cRed),
              const Divider(height: 16, color: cLine),
              _MoneyLine(
                  label: tr('Получено на руки', 'Қолға тигені'),
                  value: money(_stats.totalFee),
                  color: cGreen,
                  bold: true),
            ]),
          ),
          if (_stats.pendingLegs > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cAmberTint,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: cAmber.withValues(alpha: 0.6)),
              ),
              child: Row(children: [
                const Icon(Icons.assignment_return_rounded,
                    color: cAmber, size: 17),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                      tr('${_stats.pendingLegs} размер(ов) ещё нужно отвезти на склад',
                          '${_stats.pendingLegs} өлшемді әлі қоймаға апару керек'),
                      style: manrope(12, FontWeight.w800, color: cInk)),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: cBg, borderRadius: BorderRadius.circular(13)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline_rounded, color: cInk3, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  // ⚠️ ТҮЗЕТУ: бұрын «жеткізу мен өлшеп көру ақысы» деп
                  // жазылған — «өлшеп көру» ақысы курьердікі ЕМЕС, ол
                  // дүкеннің қызметі (екінші жұп оның қоймасынан шығады).
                  tr('Клиент платит вам за доставку напрямую — эти деньги сразу ваши. Товар он оплачивает магазину отдельно, вы к этим деньгам не прикасаетесь.',
                      'Жеткізу ақысын клиент сізге тікелей төлейді — ол ақша бірден сіздікі. Тауар ақысын ол дүкенге бөлек төлейді, сіз оған тимейсіз.'),
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

/// БІР КЛИЕНТТІҢ, БІР ТӨЛЕМНЕН шыққан бірнеше дүкендегі тапсырысы (0057).
///
/// НЕГЕ КЕРЕК: себет дүкен/қойма бойынша бөлінеді, сондықтан «екі дүкеннен
/// алдым» деген бір заказ базада екі жол болып жатады. Курьерге бұрын олар
/// екі БӨТЕН тапсырыс болып көрінетін де:
///   · біреуін бір курьер, екіншісін екінші курьер алып кетуі мүмкін еді
///     (клиент бір заказын екі бөлек адамнан алатын);
///   · курьер екінші дүкенге соғу керегін мүлде білмей қалуы мүмкін еді.
/// Енді олар бір карточкада тұрады: жоғарыда клиент пен маршрут, ішінде әр
/// дүкен өз жолымен (әрқайсысының өз pickup коды сақталады — қоймаға нақты
/// келгеннің дәлелі әр дүкенде бөлек).
class _CartGroup extends StatelessWidget {
  final List<OrderModel> orders;

  /// «Жаңа» табында — бүкіл топты бірден алу. Берілмесе (менің табым) —
  /// ішіндегі [children] карточкалары өз әрекеттерін көрсетеді.
  final VoidCallback? onTakeAll;
  final List<Widget>? children;

  const _CartGroup({required this.orders, this.onTakeAll, this.children});

  @override
  Widget build(BuildContext context) {
    final fee = orders.fold<double>(0, (s, o) => s + o.deliveryFee);
    final stores = orders.map((o) => o.storeName).toSet().length;
    // Топтың қай бөлігі әлі қоймадан алынбаған — курьер санмен көреді.
    final picked = orders
        .where((o) => o.courierStatus != OrderModel.courierAssigned)
        .length;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cBlueTint,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cBlue.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 10),
          child: Row(children: [
            const Icon(Icons.alt_route_rounded, color: cBlue, size: 20),
            const SizedBox(width: 9),
            Expanded(
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    tr('Один клиент · $stores магазина',
                        'Бір клиент · $stores дүкен'),
                    style: manrope(13.5, FontWeight.w800, color: cInk)),
                Text(
                    tr('Заберите со всех складов и отвезите за одну поездку',
                        'Барлық қоймадан алып, бір баруда жеткізіңіз'),
                    style: manrope(11, FontWeight.w600, color: cInk2)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(money(fee),
                  style: manrope(15, FontWeight.w800, color: cGreenDeep)),
              Text(tr('всего вам', 'сізге барлығы'),
                  style: manrope(9.5, FontWeight.w700, color: cInk3)),
            ]),
          ]),
        ),
        if (onTakeAll == null && picked < orders.length)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
            child: Text(
                tr('Со складов забрано: $picked из ${orders.length}',
                    'Қоймалардан алынғаны: ${orders.length}-дің $picked-і'),
                style: manrope(11.5, FontWeight.w800, color: cBlue)),
          ),
        ...?children,
        if (onTakeAll != null) ...[
          // «Жаңа» табында ішкі карточкалар әрекетсіз — тек шолу үшін.
          ...orders.map((o) => CourierOrderCard(order: o)),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: onTakeAll,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(
                  tr('Взять все ${orders.length} заказа',
                      '${orders.length} тапсырысты да алу'),
                  style: manrope(14, FontWeight.w800, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: cBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Табыс жіктелуінің бір жолы.
class _MoneyLine extends StatelessWidget {
  final String label, value;
  final Color? color;
  final bool bold;
  const _MoneyLine({
    required this.label,
    required this.value,
    this.color,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(
            child: Text(label,
                style: manrope(12, FontWeight.w600, color: cInk2),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Text(value,
              style: manrope(bold ? 14 : 12.5,
                  bold ? FontWeight.w800 : FontWeight.w700,
                  color: color ?? cInk)),
        ]),
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
