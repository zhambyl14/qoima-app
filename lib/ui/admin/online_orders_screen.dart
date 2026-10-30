import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/app_user.dart';
import '../../core/contact_utils.dart';
import '../../core/order_helpers.dart';
import '../../data/models/order_model.dart';
import '../../data/services/cloudinary_service.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/qoima_design.dart';
import '../client/gift/gift_widgets.dart';
import '../client/reservation_timer_widget.dart';
import '../shared/courier_info_banner.dart';
import '../shared/fitting_swap_sheet.dart';
import '../shared/kazpost_store_card.dart';
import '../shared/order_item_row.dart';
import '../shared/order_money_card.dart';
import '../shared/prompt_text_dialog.dart';

import '../../core/lang.dart';
import '../../core/error_text.dart';

class OnlineOrdersScreen extends StatefulWidget {
  /// Push deep-link арқылы ашылғанда: осы orderId-ды тізімнен тауып,
  /// «Заказ найден» баннерінде бірден көрсетеміз (order_number емес, id
  /// бойынша — push data-да id келеді).
  final String? openOrderId;
  const OnlineOrdersScreen({super.key, this.openOrderId});

  @override
  State<OnlineOrdersScreen> createState() => _OnlineOrdersScreenState();
}

class _OnlineOrdersScreenState extends State<OnlineOrdersScreen> {
  final _service = FirestoreService();
  final _codeCtrl = TextEditingController();
  String _filter = 'active';

  // Ағынды бір рет жасаймыз — фильтр басқан сайын (setState) тізім спиннермен
  // қайта жүктелмеуі үшін. Экрандағы үш StreamBuilder осы бір ағынды бөліседі.
  late final Stream<List<OrderModel>> _ordersStream =
      _service.watchOnlineOrders();

  OrderModel? _lookupResult;
  bool _lookupLoading = false;
  String? _lookupError;

  @override
  void initState() {
    super.initState();
    final id = widget.openOrderId;
    if (id != null && id.isNotEmpty) {
      _ordersStream.first.then((all) {
        if (!mounted) return;
        final match = all.where((o) => o.id == id);
        if (match.isNotEmpty) setState(() => _lookupResult = match.first);
      });
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _lookupLoading = true;
      _lookupError = null;
      _lookupResult = null;
    });
    try {
      final order = await _service.lookupOnlineOrder(code);
      if (!mounted) return;
      setState(() {
        _lookupResult = order;
        _lookupLoading = false;
        _lookupError = order == null
            ? tr('Неверный код или заказ не найден',
                'Код қате немесе тапсырыс табылмады')
            : null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _lookupError = friendlyError(e);
          _lookupLoading = false;
        });
      }
    }
  }

  /// Тапсырыс дүкеннің НАЗАРЫН талап ете ме.
  ///
  /// ⚠️ Жеткізілген (completed) тапсырыс та белсенді бола алады: «өлшеп көру»
  /// кезінде клиент таңдамаған өлшем курьермен қоймаға қайтып келе жатыр да,
  /// оны дүкен «қабылдадым» деп растауы керек. Растамайынша қойма қалдығы
  /// шындықты көрсетпейді — сондықтан ол «Аяқталды» емес, «Белсенді».
  static bool _needsAttention(OrderModel o) =>
      o.status == OrderModel.statusPending ||
      o.status == OrderModel.statusReserved ||
      o.status == OrderModel.statusRejected ||
      o.status == OrderModel.statusConfirmed ||
      o.returnLegPending;

  List<OrderModel> _applyFilter(List<OrderModel> all) {
    switch (_filter) {
      case 'active':
        return all.where(_needsAttention).toList();
      case 'done':
        return all
            .where((o) =>
                (o.status == OrderModel.statusCompleted ||
                    o.status == OrderModel.statusReturned) &&
                !o.returnLegPending)
            .toList();
      case 'cancelled':
        return all
            .where((o) => o.status == OrderModel.statusCancelled)
            .toList();
      default:
        return all;
    }
  }

  @override
  Widget build(BuildContext context) {
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
                        width: 38,
                        height: 38,
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
                          Text(tr('Онлайн-заказы', 'Онлайн тапсырыстар'),
                              style: manrope(23, FontWeight.w800,
                                  color: Colors.white, letterSpacing: -0.5)),
                          StreamBuilder<List<OrderModel>>(
                            stream: _ordersStream,
                            builder: (_, s) {
                              final review = (s.data ?? [])
                                  .where((o) => o.isAwaitingReview)
                                  .length;
                              return Text(
                                  review > 0
                                      ? tr('Ждут проверки: $review',
                                          'Тексеруді күтуде: $review')
                                      : tr('Нет заказов на проверке',
                                          'Тексерудегі тапсырыс жоқ'),
                                  style: manrope(13, FontWeight.w500,
                                      color: Colors.white
                                          .withValues(alpha: 0.78)));
                            },
                          ),
                        ],
                      ),
                    ),
                  ]),
                ),

                // Code lookup
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Row(children: [
                    Expanded(
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          controller: _codeCtrl,
                          onSubmitted: (_) => _lookup(),
                          style: const TextStyle(
                              color: Colors.black87, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: tr('Введите код заказа...',
                                'Тапсырыс кодын енгізіңіз...'),
                            hintStyle:
                                TextStyle(color: Colors.black38, fontSize: 14),
                            prefixIcon: Icon(Icons.qr_code_scanner_rounded,
                                color: cGreen, size: 20),
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _lookupLoading ? null : _lookup,
                      child: Container(
                        height: 44,
                        width: 80,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _lookupLoading
                            ? const Center(
                                child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        color: cGreen, strokeWidth: 2)))
                            : Center(
                                child: Text(tr('Найти', 'Іздеу'),
                                    style: TextStyle(
                                        color: cGreen,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13))),
                      ),
                    ),
                  ]),
                ),

                // Filter tabs
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: StreamBuilder<List<OrderModel>>(
                    stream: _ordersStream,
                    builder: (ctx, snap) {
                      final all = snap.data ?? [];
                      final active = all.where(_needsAttention).length;
                      final done = all
                          .where((o) =>
                              o.status == OrderModel.statusCompleted &&
                              !o.returnLegPending)
                          .length;
                      final cancelled = all
                          .where((o) => o.status == OrderModel.statusCancelled)
                          .length;

                      return Row(children: [
                        _FilterChip(
                            label: tr('Активные $active', 'Белсенді $active'),
                            value: 'active',
                            current: _filter,
                            onTap: (v) => setState(() {
                                  _filter = v;
                                  _lookupResult = null;
                                })),
                        const SizedBox(width: 8),
                        _FilterChip(
                            label: tr('Завершено $done', 'Аяқталды $done'),
                            value: 'done',
                            current: _filter,
                            onTap: (v) => setState(() {
                                  _filter = v;
                                  _lookupResult = null;
                                })),
                        const SizedBox(width: 8),
                        _FilterChip(
                            label: tr(
                                'Всё ${all.length}', 'Барлығы ${all.length}'),
                            value: 'all',
                            current: _filter,
                            onTap: (v) => setState(() {
                                  _filter = v;
                                  _lookupResult = null;
                                })),
                        const SizedBox(width: 8),
                        _FilterChip(
                            label: tr('Отменено $cancelled',
                                'Бас тартылды $cancelled'),
                            value: 'cancelled',
                            current: _filter,
                            onTap: (v) => setState(() {
                                  _filter = v;
                                  _lookupResult = null;
                                })),
                      ]);
                    },
                  ),
                ),
              ])),
        ),

        // ── Body ─────────────────────────────────────────────────────────────
        Expanded(
          child: StreamBuilder<List<OrderModel>>(
            stream: _ordersStream,
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: cGreen));
              }

              final all = snap.data ?? [];

              // Мерзімі өткен тапсырыстарды on-read авто-болдырмаймыз
              for (final o in all) {
                if (o.isExpired &&
                    (o.status == OrderModel.statusRejected ||
                        o.status == OrderModel.statusReserved ||
                        (o.status == OrderModel.statusPending &&
                            o.receiptUrl.isEmpty))) {
                  _service.cancelOnlineOrder(o, actorRole: 'system').ignore();
                }
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
                children: [
                  // Code lookup result
                  if (_lookupError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cRedTint,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cRed.withValues(alpha: 0.2)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline, color: cRed, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(_lookupError!,
                                style: const TextStyle(
                                    color: cRed, fontSize: 13))),
                        GestureDetector(
                            onTap: () => setState(() {
                                  _lookupError = null;
                                  _codeCtrl.clear();
                                }),
                            child:
                                const Icon(Icons.close, color: cRed, size: 18)),
                      ]),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (_lookupResult != null) ...[
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: cGreen, width: 2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: cGreen,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(14)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.check_circle_outline,
                                color: Colors.white, size: 16),
                            const SizedBox(width: 8),
                            Text(tr('Заказ найден', 'Тапсырыс табылды'),
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            const Spacer(),
                            GestureDetector(
                                onTap: () => setState(() {
                                      _lookupResult = null;
                                      _codeCtrl.clear();
                                    }),
                                child: const Icon(Icons.close,
                                    color: Colors.white, size: 18)),
                          ]),
                        ),
                        _OrderCard(
                          order: _lookupResult!,
                          service: _service,
                          onChanged: () => setState(() {
                            _lookupResult = null;
                            _codeCtrl.clear();
                          }),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Filtered list (жоғарыда «Заказ найден» ретінде көрсетілген
                  // тапсырыс осында ҚАЙТАЛАНБАУЫ керек — екі бөлек виджет бір
                  // тапсырысты басқарса, біреуінде әрекет екіншісіне белгісіз
                  // қалып, қатар шаққанда «қуып кетуі» мүмкін еді).
                  ..._applyFilter(all)
                      .where((o) => o.id != _lookupResult?.id)
                      .map((order) => _OrderCard(
                            key: ValueKey(order.id),
                            order: order,
                            service: _service,
                            onChanged: () => setState(() {}),
                          )),

                  if (_applyFilter(all).isEmpty && _lookupResult == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 60),
                      child: Column(children: [
                        Icon(Icons.inbox_outlined,
                            size: 56, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text(
                          _filter == 'review'
                              ? tr('Нет чеков на проверке', 'Тексеруде чек жоқ')
                              : _filter == 'active'
                                  ? tr('Нет активных заказов',
                                      'Белсенді тапсырыс жоқ')
                                  : _filter == 'done'
                                      ? tr('Нет завершённых заказов',
                                          'Аяқталған тапсырыс жоқ')
                                      : _filter == 'cancelled'
                                          ? tr('Нет отменённых заказов',
                                              'Бас тартылған тапсырыс жоқ')
                                          : tr('Заказов нет', 'Тапсырыс жоқ'),
                          style: const TextStyle(fontSize: 15, color: cInk2),
                        ),
                      ]),
                    ),
                ],
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ── Order card ─────────────────────────────────────────────────────────────────
class _OrderCard extends StatefulWidget {
  final OrderModel order;
  final FirestoreService service;
  final VoidCallback onChanged;
  const _OrderCard(
      {super.key,
      required this.order,
      required this.service,
      required this.onChanged});

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _loading = false;

  /// Аяқталған/болдырылмаған тапсырыстың егжей-тегжейі ашық па. Белсенді
  /// тапсырыс ӘРҚАШАН толық ашық: онда әрекет ету керек. Ал «Аяқталды»
  /// табында жүздеген карточка бар — оларда бір қарағанда керегі: кім, қашан,
  /// қанша. Қалғанын сұрағанда ғана береміз.
  bool _expanded = false;

  late final ConfettiController _confetti;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 2));
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  OrderModel get o => widget.order;

  Color get _typeColor {
    if (o.isKazpost) return cPurple;
    switch (o.orderType) {
      case OrderModel.typeSmartReservation:
        return const Color(0xFF3B82F6);
      case OrderModel.typeClickCollect:
        return cGreen;
      case OrderModel.typeDelivery:
        return const Color(0xFFF59E0B);
      default:
        return cInk3;
    }
  }

  String get _typeLabel {
    if (o.isKazpost) return tr('КАЗПОЧТА', 'КАЗПОЧТА');
    switch (o.orderType) {
      case OrderModel.typeSmartReservation:
        return tr('БРОНЬ', 'БРОНЬ');
      case OrderModel.typeClickCollect:
        return tr('САМОВЫВОЗ', 'ӨЗІ АЛЫП КЕТЕДІ');
      case OrderModel.typeDelivery:
        return tr('ДОСТАВКА', 'ЖЕТКІЗУ');
      default:
        return o.orderType.toUpperCase();
    }
  }

  String get _statusLabel {
    // Жеткізілсе де, айналымдағы өлшем әлі қоймаға оралмаған — тапсырыс
    // ЖАБЫЛМАҒАН. Дүкен оны «Аяқталды» деп ойламауы керек.
    if (o.returnLegPending) {
      return tr('Ждём возврат размера', 'Өлшемнің қайтуын күтуде');
    }
    switch (o.status) {
      case OrderModel.statusPending:
        return o.isAwaitingReview
            ? tr('Чек на проверке', 'Чек тексеруде')
            : tr('Ожидает оплаты', 'Төлем күтілуде');
      case OrderModel.statusReserved:
        return tr('Бронь подтверждена', 'Бронь расталды');
      case OrderModel.statusRejected:
        return tr('Чек отклонён', 'Чек қабылданбады');
      case OrderModel.statusConfirmed:
        // Казпочта тапсырысын «беру» жоқ: дүкен почтаға апарады.
        if (o.isKazpost) {
          return o.postInTransit
              ? tr('Посылка в пути', 'Сәлемдеме жолда')
              : tr('Оплачено · Отправить', 'Төленді · Жіберу');
        }
        return tr('Оплачено · Готов к выдаче', 'Төленді · Беруге дайын');
      case OrderModel.statusCompleted:
        return tr('Завершён', 'Аяқталды');
      case OrderModel.statusCancelled:
        return cancelledByLabel(o, viewerUid: AppUser.current.uid);
      case OrderModel.statusReturned:
        return tr('Возврат', 'Қайтару');
      default:
        return o.status;
    }
  }

  Color get _statusColor {
    if (o.returnLegPending) return cAmber;
    switch (o.status) {
      case OrderModel.statusPending:
        return cAmber;
      case OrderModel.statusReserved:
        return const Color(0xFF3B82F6);
      case OrderModel.statusRejected:
        return cRed;
      case OrderModel.statusConfirmed:
      case OrderModel.statusCompleted:
        return cGreen;
      case OrderModel.statusCancelled:
      case OrderModel.statusReturned:
        return cRed;
      default:
        return cInk3;
    }
  }

  Future<void> _handOver() async {
    // Алушы өлшем таңдамаған сыйлықты беруге болмайды (серверде де бұғатталған).
    if (o.isGiftAwaitingRecipient) return;
    // Примерка болса — алдымен клиент нақты қай өлшемді алғанын сұраймыз
    // (курьермен жеткізгенде де осылай сұралады; дүкен өзі бергенде де
    // қойма/сатылым дұрыс есептелуі үшін керек).
    List<int> swaps = const [];
    if (o.hasFitting) {
      final result = await showFittingSwapSheet(context, o);
      if (result == null || !mounted) return;
      swaps = result;
    }

    // 🎁 Сыйлық: алушы қымбатырақ тауар таңдаса — айырманы беру кезінде аламыз
    // (gift_extra_due). Төлем тәсілі in_store_payment_method-қа жазылады.
    // Басқа құрылғыдан ауыстыру болған болуы мүмкін — экрандағы көшірмеге
    // емес, базадағы соңғы күйге қарап сұраймыз.
    var target = o;
    if (o.isGift) {
      try {
        target = await widget.service.freshGiftOrder(o);
      } catch (_) {}
      if (!mounted) return;
    }
    var extraMethod = '';
    if (target.hasGiftExtraDue) {
      final m = await askGiftExtraPayment(context, target.giftExtraDue);
      if (m == null || !mounted) return;
      extraMethod = m;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Выдача товара', 'Тауар беру')),
        content: Text(o.isSmartReservation && o.inStorePaymentMethod.isNotEmpty
            ? tr(
                'Выдать товар клиенту?\n\nДоплата: ${_payMethodLabel(o.inStorePaymentMethod)}',
                'Тауарды клиентке беру керек пе?\n\nДоплата: ${_payMethodLabel(o.inStorePaymentMethod)}')
            : tr('Выдать товар клиенту?', 'Тауарды клиентке беру керек пе?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Нет', 'Жоқ'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cGreen, foregroundColor: Colors.white),
              child: Text(tr('Да, выдать', 'Иә, беру'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await widget.service.markHandedOver(
          extraMethod.isEmpty
              ? target
              : target.copyWith(inStorePaymentMethod: extraMethod),
          swappedIndexes: swaps);
      if (mounted) {
        setState(() => _loading = false);
        _confetti.play();
        HapticFeedback.mediumImpact();
        widget.onChanged();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: cRed,
            behavior: SnackBarBehavior.floating));
      }
    }
  }

  Future<void> _handOverReserved() async {
    List<int> swaps = const [];
    if (o.hasFitting) {
      final result = await showFittingSwapSheet(context, o);
      if (result == null || !mounted) return;
      swaps = result;
    }

    final method = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: cLine, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text(
              tr('Выдача товара · Доплата ${o.remainingAmount.toStringAsFixed(0)} ₸',
                  'Тауар беру · Доплата ${o.remainingAmount.toStringAsFixed(0)} ₸'),
              style: manrope(16, FontWeight.w800, color: cInk)),
          const SizedBox(height: 4),
          Text(tr('Как клиент внёс доплату?', 'Клиент доплату қалай берді?'),
              style: manrope(13, FontWeight.w500, color: cInk2)),
          const SizedBox(height: 20),
          _PayBtn(
              label: tr('💵  Наличный', '💵  Қолма-қол'),
              color: cGreen,
              onTap: () => Navigator.pop(ctx, 'cash')),
          const SizedBox(height: 10),
          _PayBtn(
              label: '📱  Kaspi',
              color: const Color(0xFFEB3333),
              onTap: () => Navigator.pop(ctx, 'kaspi')),
        ]),
      ),
    );
    if (method == null || !mounted) return;
    setState(() => _loading = true);
    try {
      await widget.service
          .handOverWithDoplate(o, method, swappedIndexes: swaps);
      if (mounted) {
        setState(() => _loading = false);
        _confetti.play();
        HapticFeedback.mediumImpact();
        widget.onChanged();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: cRed,
            behavior: SnackBarBehavior.floating));
      }
    }
  }

  /// Чекті толық экранда көру (фото/PDF preview). Жүктелмесе — сыртқы браузерде
  /// ашуға болады (мыс. Cloudinary-де PDF жеткізуі өшірулі болса).
  void _viewReceipt() {
    final url = CloudinaryService.receiptPreviewUrl(o.receiptUrl);
    Future<void> openExternal() async {
      try {
        await openExternalUrl(o.receiptUrl);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(tr('Не удалось открыть чек', 'Чекті ашу мүмкін болмады')),
            backgroundColor: cRed,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    }

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(children: [
          InteractiveViewer(
            maxScale: 5,
            child: Center(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const Padding(
                        padding: EdgeInsets.all(60),
                        child: CircularProgressIndicator(
                            color: cGreen, strokeWidth: 2),
                      ),
                errorBuilder: (_, __, ___) => Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.receipt_long_outlined,
                        color: Colors.white54, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      tr('Не удалось показать чек здесь',
                          'Чекті мұнда көрсету мүмкін болмады'),
                      textAlign: TextAlign.center,
                      style: manrope(14, FontWeight.w600, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: openExternal,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: cGreen,
                          foregroundColor: Colors.white),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: Text(tr('Открыть в браузере', 'Браузерде ашу')),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Row(children: [
              // Сыртта ашу — әрқашан қолжетімді (PDF/жүктелмеген жағдайға).
              IconButton(
                icon:
                    const Icon(Icons.open_in_new_rounded, color: Colors.white),
                tooltip: tr('Открыть в браузере', 'Браузерде ашу'),
                onPressed: openExternal,
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  /// Дүкен иесі чекті растайды: бронь → reserved, қалғаны → confirmed.
  Future<void> _confirmPayment() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Подтвердить оплату', 'Төлемді растау')),
        content: Text(o.isSmartReservation
            ? tr('Деньги по чеку получены? Бронь будет подтверждена на 1 час.',
                'Чек бойынша ақша түсті ме? Бронь 1 сағатқа расталады.')
            : o.isKazpost
                ? tr('Деньги по чеку получены? В переводе также стоимость почты. После подтверждения отправьте посылку.',
                    'Чек бойынша ақша түсті ме? Аударымда почта ақысы да бар. Растаған соң сәлемдемені жіберіңіз.')
                : tr('Деньги по чеку получены? Заказ станет «Готов к выдаче».',
                    'Чек бойынша ақша түсті ме? Тапсырыс «Беруге дайын» болады.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Нет', 'Жоқ'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cGreen, foregroundColor: Colors.white),
              child: Text(tr('Да, оплата получена', 'Иә, төлем түсті'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _loading = true);
    try {
      if (o.isSmartReservation) {
        await widget.service.confirmReservationDeposit(o);
      } else {
        await widget.service.confirmOnlinePayment(o);
      }
      if (mounted) {
        setState(() => _loading = false);
        widget.onChanged();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: cRed,
            behavior: SnackBarBehavior.floating));
      }
    }
  }

  /// Чекті қабылдамау (себеппен) — клиентке пуш кетеді, 30 мин қайта тіркеу.
  Future<void> _rejectReceipt() async {
    final reason = await promptTextDialog(
      context,
      title: tr('Почему чек отклонён?', 'Чек неге қабылданбады?'),
      hint: tr('Например: сумма не совпадает', 'Мысалы: сома сәйкес емес'),
    );
    if (reason == null || !mounted) return;
    setState(() => _loading = true);
    try {
      await widget.service.rejectReceipt(o, reason);
      if (mounted) {
        setState(() => _loading = false);
        widget.onChanged();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: cRed,
            behavior: SnackBarBehavior.floating));
      }
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Отмена заказа', 'Тапсырысты болдырмау')),
        content: Text(tr('Заказ будет отменён, товар вернётся на склад.',
            'Тапсырыс болдырылмайды, тауар қоймаға оралады.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Отмена', 'Болдырмау'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cRed, foregroundColor: Colors.white),
              child: Text(tr('Отменить заказ', 'Тапсырысты болдырмау'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await widget.service.cancelOnlineOrder(o);
      if (mounted) {
        setState(() => _loading = false);
        widget.onChanged();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: cRed,
            behavior: SnackBarBehavior.floating));
      }
    }
  }

  /// Курьер тапсырысты өзіне бекітті/қоймадан алды — дүкен енді оны бере де,
  /// болдырмай да алмайды (тауар курьерде). Тек курьер жабады.
  bool get _lockedByCourier =>
      o.hasCourier &&
      (o.courierStatus == OrderModel.courierAssigned ||
          o.courierStatus == OrderModel.courierPickedUp);

  @override
  Widget build(BuildContext context) {
    final isActive = o.status == OrderModel.statusPending ||
        o.status == OrderModel.statusReserved ||
        o.status == OrderModel.statusRejected ||
        o.status == OrderModel.statusConfirmed;
    // Белсенді тапсырыс — әрқашан толық: сатушы онымен ЖҰМЫС ІСТЕЙДІ.
    final showDetails = isActive || _expanded;

    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: o.isAwaitingReview
                ? Border.all(color: cAmber, width: 1.5)
                : null,
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3))
            ],
          ),
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child:
                      Center(child: CircularProgressIndicator(color: cGreen)))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Type + status header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _typeColor.withValues(alpha: 0.08),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _typeColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(_typeLabel,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800)),
                      ),
                      // 🎁 Сыйлық белгісі (0070): алушы күткен/таңдаған.
                      if (o.isGift) ...[
                        const SizedBox(width: 6),
                        Flexible(child: GiftBadge(order: o)),
                      ],
                      const Spacer(),
                      if (o.isSmartReservation &&
                          (o.status == OrderModel.statusPending ||
                              o.status == OrderModel.statusReserved))
                        ReservationTimerWidget(expiresAt: o.expiresAt),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(_statusLabel,
                            style: TextStyle(
                                color: _statusColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Order number
                          if (o.orderNumber > 0)
                            Text(
                              '#${o.orderNumber.toString().padLeft(5, '0')}',
                              style: manrope(13, FontWeight.w700, color: cInk3),
                            ),

                          // Client info
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.person_outline,
                                size: 16, color: cInk3),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(
                                    o.clientName.isNotEmpty
                                        ? o.clientName
                                        : tr('Имя не указано',
                                            'Аты көрсетілмеген'),
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: cInk))),
                          ]),
                          const SizedBox(height: 2),
                          Row(children: [
                            const Icon(Icons.phone_outlined,
                                size: 14, color: cInk3),
                            const SizedBox(width: 6),
                            Text(o.clientPhone,
                                style: const TextStyle(
                                    fontSize: 12, color: cInk2)),
                            const SizedBox(width: 12),
                            GestureDetector(
                                onTap: () {
                                  Clipboard.setData(
                                      ClipboardData(text: o.clientPhone));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(tr('Телефон скопирован',
                                              'Телефон көшірілді')),
                                          behavior: SnackBarBehavior.floating,
                                          duration: Duration(seconds: 1)));
                                },
                                child: const Icon(Icons.copy_outlined,
                                    size: 14, color: cInk3)),
                          ]),

                          const Divider(height: 16),

                          // ── Аяқталған тапсырыс: бір жол қорытынды ────────
                          //  Әрекет қажет емес карточканы толық жаю — «Аяқталды»
                          //  табындағы жүздеген жазбаны оқылмайтын қабырғаға
                          //  айналдырады. Керек болса — «Подробнее».
                          if (!showDetails)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => setState(() => _expanded = true),
                              child: Row(children: [
                                Expanded(
                                  child: Text(
                                    '${o.items.length} ${tr('поз.', 'поз.')} · ${money(o.finalTotal)}',
                                    style: manrope(13, FontWeight.w700,
                                        color: cInk2),
                                  ),
                                ),
                                Text(tr('Подробнее', 'Толығырақ'),
                                    style: manrope(12, FontWeight.w800,
                                        color: cGreen)),
                                const Icon(Icons.keyboard_arrow_down_rounded,
                                    size: 18, color: cGreen),
                              ]),
                            ),

                          if (showDetails) ...[
                            // ── Позициялар: фото + бренд/түс/түрі + артикул ──
                            //  Бір атаумен қоймада бірнеше түс/модификация
                            //  тұрады — атаудың өзі жеткіліксіз.
                            ...o.items.map((item) => OrderItemRow(item: item)),

                            // 🎁 Сыйлық: алушы өлшем таңдағанша беруге болмайды —
                            // түсіндірме; таңдаған соң кімге/тілек көрсетіледі.
                            if (o.isGift) ...[
                              const SizedBox(height: 8),
                              GiftStoreNote(order: o, onChanged: widget.onChanged),
                            ],

                            // Addresses
                            if (o.warehouseAddress.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.location_on_outlined,
                                        size: 14, color: cInk3),
                                    const SizedBox(width: 4),
                                    Expanded(
                                        child: Text(o.warehouseAddress,
                                            style: const TextStyle(
                                                fontSize: 12, color: cInk2))),
                                  ]),
                            ],
                            // Жеткізу — ҚАЛАСЫМЕН: басқа қала болса жөнелту
                            // қызметі керек, оны шатастыруға болмайды.
                            // Казпочтада мекенжай бланкінің ішінде — екі рет
                            // көрсетпейміз.
                            if (o.isKazpost)
                              KazpostStoreCard(
                                order: o,
                                onChanged: widget.onChanged,
                              )
                            else if (o.isDelivery)
                              OrderDestinationCard(
                                city: o.clientCity,
                                address: o.address,
                                byCourier: o.byPlatformCourier,
                              ),

                            const Divider(height: 16),

                            // Payment summary
                            if (o.isSmartReservation) ...[
                              _PayRow(
                                  label: tr('Сумма товаров', 'Тауар сомасы'),
                                  value: '${o.total.toStringAsFixed(0)} ₸'),
                              _PayRow(
                                  label: tr('Задаток (10%)', 'Кепілпұл (10%)'),
                                  value:
                                      '${o.depositAmount.toStringAsFixed(0)} ₸',
                                  valueColor: cGreen,
                                  method: o.paymentBank),
                              _PayRow(
                                  label: tr(
                                      'Доплата в магазине', 'Дүкенде доплата'),
                                  value:
                                      '${o.remainingAmount.toStringAsFixed(0)} ₸',
                                  valueColor: cAmber,
                                  bold: true,
                                  method: o.inStorePaymentMethod),
                            ] else if (o.isDelivery) ...[
                              // Ақшаның толық жіктелуі: дүкенге не тиесілі,
                              // курьерге не тиесілі — бір қарағанда көрінеді.
                              // Төлем әдісі сол картаның ішінде («Дүкенге»
                              // блогының астында), бөлек жол керек емес.
                              OrderMoneyCard(order: o, audience: 'store'),
                              if (!o.isKazpost) ...[
                                const SizedBox(height: 10),
                                CourierInfoBanner(
                                  order: o,
                                  forStore: true,
                                  onConfirmReturnLeg: () async {
                                    try {
                                      await widget.service.confirmReturnLeg(o);
                                      widget.onChanged();
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                                content: Text(friendlyError(e)),
                                                backgroundColor: cRed,
                                                behavior:
                                                    SnackBarBehavior.floating));
                                      }
                                    }
                                  },
                                ),
                              ],
                            ] else ...[
                              // ⚠️ ТҮЗЕТУ: бұрын мұнда `o.total` (промокодқа дейінгі
                              // толық сома) көрсетілетін — админ клиенттің НАҚТЫ
                              // төлейтін сомасын көрмей, толық баға деп қателесетін.
                              // Енді `o.finalTotal` (= o.total − promoDiscount)
                              // көрсетіледі — дәл deposit_amount-пен сәйкес келеді.
                              if (o.promoDiscount > 0) ...[
                                _PayRow(
                                    label: tr('Сумма товаров', 'Тауар сомасы'),
                                    value: '${o.total.toStringAsFixed(0)} ₸'),
                                _PayRow(
                                    label: tr('Промокод ${o.promoCode}',
                                        'Промокод ${o.promoCode}'),
                                    value:
                                        '−${o.promoDiscount.toStringAsFixed(0)} ₸',
                                    valueColor: cGreen),
                              ],
                              _PayRow(
                                  label: tr(
                                      'Итого к оплате', 'Барлығы төленетіні'),
                                  value: '${o.finalTotal.toStringAsFixed(0)} ₸',
                                  valueColor: cGreen,
                                  bold: true,
                                  method: o.paymentBank),
                            ],
                          ],

                          // Action buttons.
                          // ⚠️ Курьер тапсырысты алып кеткен соң дүкен оны
                          // «Выдать»/«Отменить» ете АЛМАЙДЫ: тауар физикалық
                          // түрде курьерде. Оны тек курьер жабады (0052 —
                          // серверде де guard_courier_order_lock триггері бар).
                          // Посылка почтаға кетті: болдыруға болмайды (сервер
                          // kazpost_already_shipped қайтарады), қалған әрекет
                          // KazpostStoreCard-та.
                          if (isActive &&
                              !_lockedByCourier &&
                              !o.postInTransit) ...[
                            const SizedBox(height: 12),

                            // Pending + чек тіркелді → тексеру/растау/қабылдамау
                            if (o.isAwaitingReview) ...[
                              GestureDetector(
                                onTap: _viewReceipt,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: cAmberTint,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: cAmber.withValues(alpha: 0.4)),
                                  ),
                                  child: Row(children: [
                                    const Icon(Icons.receipt_long_rounded,
                                        color: cAmber, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        tr('Клиент прикрепил чек — нажмите, чтобы посмотреть',
                                            'Клиент чек тіркеді — көру үшін басыңыз'),
                                        style: const TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF92400E)),
                                      ),
                                    ),
                                    const Icon(Icons.open_in_full_rounded,
                                        color: cAmber, size: 16),
                                  ]),
                                ),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: _confirmPayment,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: cGreen,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(double.infinity, 44),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  elevation: 0,
                                ),
                                child: Text(
                                    tr('Подтвердить оплату', 'Төлемді растау'),
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700)),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: _rejectReceipt,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF92400E),
                                    side: BorderSide(
                                        color: cAmber.withValues(alpha: 0.6)),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                  child: Text(
                                      tr('Отклонить чек', 'Чекті қабылдамау'),
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                ),
                              ),
                            ],

                            // Pending — чек әлі тіркелмеген
                            if (o.status == OrderModel.statusPending &&
                                !o.isAwaitingReview)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 10, horizontal: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFBEB),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: cAmber.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  tr('⏳ Ожидает оплаты от клиента',
                                      '⏳ Клиенттен төлем күтілуде'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF92400E)),
                                ),
                              ),

                            // Reserved → выдать + доплата (одним шагом)
                            if (o.status == OrderModel.statusReserved)
                              ElevatedButton(
                                onPressed: _handOverReserved,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: cGreen,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(double.infinity, 44),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  elevation: 0,
                                ),
                                child: Text(
                                    tr('Выдать товар · доплата ${o.remainingAmount.toStringAsFixed(0)} ₸',
                                        'Тауар беру · доплата ${o.remainingAmount.toStringAsFixed(0)} ₸'),
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700)),
                              ),

                            // Confirmed → тауарды беру.
                            //
                            // ⚠️ ЖЕТКІЗУ тапсырысында тауарды клиентке КУРЬЕР
                            // береді, дүкен емес. Сондықтан мұнда «Выдать
                            // товар» БАСТЫ батырма болып тұрмайды: дүкеннің
                            // ісі — курьер келгенде тапсырысты дайындап,
                            // беру кодын айту. «Өзім жеткіздім» тек курьер
                            // табылмай қалған жағдайға арналған қосалқы жол.
                            if (o.status == OrderModel.statusConfirmed &&
                                o.isGiftAwaitingRecipient)
                              // Сыйлық: өлшем белгісіз, тауар брондалмаған —
                              // «дайын/беру/курьер» әрекеттері бұғатталған.
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 10, horizontal: 12),
                                decoration: BoxDecoration(
                                  color: cPurpleTint,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  o.isGiftSizeReserved
                                      ? tr('🎁 Ждём подтверждения получателя',
                                          '🎁 Алушының растауын күтеміз')
                                      : tr(
                                          '🎁 Ждём, пока получатель выберет размер',
                                          '🎁 Алушы өлшем таңдағанша күтеміз'),
                                  textAlign: TextAlign.center,
                                  style: manrope(13, FontWeight.w700,
                                      color: cPurpleInk),
                                ),
                              )
                            else if (o.status == OrderModel.statusConfirmed &&
                                !o.isKazpost)
                              // Платформа курьері келетін тапсырыс — беруді
                              // курьер жабады. Мұнда тек қосалқы жол қалады.
                              if (o.byPlatformCourier)
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: _handOver,
                                    icon: const Icon(
                                        Icons.person_pin_circle_outlined,
                                        size: 16),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: cInk2,
                                      side: const BorderSide(color: cLine),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
                                    ),
                                    label: Text(
                                        tr('Выдал сам, без курьера',
                                            'Курьерсіз өзім бердім'),
                                        style: const TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                )
                              else
                                ElevatedButton(
                                  onPressed: _handOver,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: cGreen,
                                    foregroundColor: Colors.white,
                                    minimumSize:
                                        const Size(double.infinity, 44),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    elevation: 0,
                                  ),
                                  child: Text(
                                      o.isDelivery
                                          ? tr('Доставлено клиенту',
                                              'Клиентке жеткізілді')
                                          : tr('Выдать товар', 'Тауар беру'),
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                ),

                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: _cancel,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: cRed,
                                  side: const BorderSide(color: cRed),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                ),
                                child: Text(
                                    tr('Отменить заказ',
                                        'Тапсырысты болдырмау'),
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ],
                        ]),
                  ),
                ]),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            maxBlastForce: 20,
            minBlastForce: 5,
            emissionFrequency: 0.5,
            numberOfParticles: 25,
            gravity: 0.2,
            colors: const [
              cGreen,
              cGreen,
              cAmber,
              Color(0xFF3B82F6),
              Colors.purple,
            ],
          ),
        ),
      ],
    );
  }
}

class _PayRow extends StatelessWidget {
  final String label, value;
  final Color? valueColor;
  final bool bold;

  /// Төлем әдісі — сол ақшаның ЖАНЫНДА тұрады, бөлек «Оплачено через» жолы
  /// емес: әдіс — соманың қасиеті, дербес шама емес.
  final String method;

  const _PayRow(
      {required this.label,
      required this.value,
      this.valueColor,
      this.bold = false,
      this.method = ''});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: cInk2)),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                    color: valueColor ?? cInk,
                  )),
              if (method.isNotEmpty)
                Text(_payMethodLabel(method),
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: _payMethodColor(method))),
            ]),
          ],
        ),
      );
}

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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: active ? cGreen : Colors.white,
            )),
      ),
    );
  }
}

// ── Shared payment helpers ─────────────────────────────────────────────────────
// Канондық кілтке келтіреді (ескі деректер 'Kaspi'/'Halyk Bank' үшін).
String _normMethod(String m) {
  final s = m.toLowerCase();
  if (s.contains('kaspi')) return 'kaspi';
  if (s.contains('halyk')) return 'halyk';
  if (s == 'card' || s.contains('карт')) return 'card';
  if (s == 'cash' || s.contains('налич')) return 'cash';
  return s;
}

String _payMethodLabel(String method) {
  switch (_normMethod(method)) {
    case 'kaspi':
      return '📱 Kaspi';
    case 'halyk':
      return '📱 Halyk Bank';
    case 'card':
      return tr('💳 Оплата картой', '💳 Картамен төлем');
    case 'cash':
      return tr('💵 Наличный', '💵 Қолма-қол');
    default:
      return method.isNotEmpty ? method : '—';
  }
}

Color _payMethodColor(String method) {
  switch (_normMethod(method)) {
    case 'kaspi':
      return const Color(0xFFEB3333);
    case 'halyk':
      return const Color(0xFF00A550);
    case 'card':
      return const Color(0xFF3B82F6);
    default:
      return cGreen;
  }
}

class _PayBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _PayBtn(
      {required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          child: Text(label,
              style: manrope(14, FontWeight.w700, color: Colors.white)),
        ),
      );
}
