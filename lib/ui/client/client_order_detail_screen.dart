import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_user.dart';
import '../../core/error_text.dart';
import '../../core/lang.dart';
import '../../core/order_helpers.dart';
import '../../data/models/cart_item_model.dart';
import '../../data/models/order_model.dart';
import '../../data/models/return_model.dart';
import '../../data/models/review_model.dart';
import '../../data/services/client_service.dart';
import '../../data/services/return_service.dart';
import '../../theme/qoima_design.dart';
import '../shared/order_money_card.dart';
import 'client_shell.dart';
import 'order_timeline.dart';
import 'returns/client_return_form_screen.dart';
import 'reviews_section.dart';

/// Аяқталған тапсырыстың ЖЕКЕ беті.
///
/// НЕГЕ БӨЛЕК ЭКРАН: бұрын әр тапсырыс карточкасының ішінде «Толығырақ»
/// жиналмалы блок пен «Қайтару жасау» батырмасы тұратын. Тізім солай ұзарып,
/// клиент «менде қандай тапсырыстар болды» дегенді бір қарап шыға алмайтын.
/// Енді тізімде — ықшам карточка (нөмір, баға, мини фото), ал БАРЛЫҚ егжей-
/// тегжей (есеп-қисап, таймлайн, қайтару, қайта тапсырыс) осында.
///
/// [Navigator.pop] нәтижесі: `true` — клиент «Себетке өту» деді (ата-экран
/// себет табына ауыстырады).
class ClientOrderDetailScreen extends StatefulWidget {
  final OrderModel order;
  const ClientOrderDetailScreen({super.key, required this.order});

  @override
  State<ClientOrderDetailScreen> createState() =>
      _ClientOrderDetailScreenState();
}

class _ClientOrderDetailScreenState extends State<ClientOrderDetailScreen> {
  final ClientService _service = ClientService();

  late OrderModel _order = widget.order;
  StreamSubscription<List<OrderModel>>? _orderSub;
  StreamSubscription<List<String>>? _favSub;

  Set<String> _favIds = {};
  ReturnStatus? _returnStatus;
  bool _returnLoaded = false;
  bool _reordering = false;
  String? _warehouseNote;
  // Клиенттің ӨЗІ қойған бағалары (productId → rating) — бағаланған тауар
  // жұлдызы енді ӨЗГЕРТІЛМЕЙДІ, тек көрсетіледі.
  Map<String, int> _myRatings = {};

  OrderModel get o => _order;

  @override
  void initState() {
    super.initState();
    // Статус экран ашық тұрғанда өзгеруі мүмкін (дүкен возратты растады т.б.).
    _orderSub =
        _service.watchClientOrders(AppUser.current.uid).listen((orders) {
      for (final x in orders) {
        if (x.id == _order.id && mounted) {
          setState(() => _order = x);
          return;
        }
      }
    });
    _favSub = _service.watchFavoriteIds().listen((ids) {
      if (mounted) setState(() => _favIds = ids.toSet());
    });
    _loadReturnStatus();
    _loadWarehouseNote();
    _loadMyRatings();
  }

  Future<void> _loadMyRatings() async {
    try {
      final reviews = await _service.getMyReviews();
      if (mounted) {
        setState(() {
          _myRatings = {for (final r in reviews) r.productId: r.rating};
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _orderSub?.cancel();
    _favSub?.cancel();
    super.dispose();
  }

  /// Бұл тапсырыс бойынша қайтару бар ма. БАС ТАРТЫЛҒАН (rejected) қайтару
  /// есептелмейді — одан кейін клиент қайта өтініш бере алады
  /// (client_orders_screen.dart-тағы ережемен бірдей).
  Future<void> _loadReturnStatus() async {
    try {
      // ⚠️ timeout: ағын ешқашан мән бермесе (желі үзілді), `_returnLoaded`
      // мәңгі false болып қалады да, «Қайтару жасау» батырмасы ЕШҚАШАН
      // шықпайды. Мерзімі шектеулі әрекет үшін бұл — нақты шығын.
      final list = await ReturnService()
          .watchClientReturns(AppUser.current.uid)
          .first
          .timeout(const Duration(seconds: 10));
      ReturnStatus? found;
      for (final r in list) {
        if (r.orderId == _order.id && r.status != ReturnStatus.rejected) {
          found = r.status; // тізім createdAt бойынша кему ретімен
          break;
        }
      }
      if (mounted) {
        setState(() {
          _returnStatus = found;
          _returnLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _returnLoaded = true);
    }
  }

  Future<void> _loadWarehouseNote() async {
    if (o.isDelivery || o.warehouseId.isEmpty || o.adminUid.isEmpty) return;
    try {
      final wh = await _service.getWarehouseById(o.adminUid, o.warehouseId);
      final note = wh?.note?.trim() ?? '';
      if (note.isNotEmpty && mounted) setState(() => _warehouseNote = note);
    } catch (_) {}
  }

  // ── Қайта тапсырыс ─────────────────────────────────────────────────────────

  /// Тапсырыстағы жолдарды ҚАЗІРГІ баға/партиямен себетке салады.
  /// [goToCart] — сәтті болса себет табына өту.
  Future<void> _reorder({required bool goToCart}) async {
    if (_reordering) return;
    setState(() => _reordering = true);
    try {
      final res = await _service.resolveReorder(o);
      if (!mounted) return;
      if (res.items.isEmpty) {
        _snack(
            tr('Этих товаров сейчас нет в наличии',
                'Бұл тауарлар қазір қоймада жоқ'),
            cRed);
        return;
      }
      final cart = context.read<CartProvider>();
      for (final i in res.items) {
        cart.addItem(i);
      }
      HapticFeedback.lightImpact();
      if (res.unavailable.isEmpty) {
        _snack(
            tr('${res.items.length} товар(ов) в корзине',
                '${res.items.length} тауар себетке салынды'),
            cGreen);
      } else {
        _snack(
            tr('В корзине: ${res.items.length}. Нет в наличии: ${res.unavailable.join(', ')}',
                'Себетке: ${res.items.length}. Қоймада жоқ: ${res.unavailable.join(', ')}'),
            cAmber);
      }
      if (goToCart && mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _snack(friendlyError(e), cRed);
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }

  // ── Таңдаулы ───────────────────────────────────────────────────────────────

  Future<void> _toggleFavorite(CartItemModel item) async {
    final adding = !_favIds.contains(item.productId);
    HapticFeedback.lightImpact();
    setState(() {
      _favIds = {..._favIds};
      adding ? _favIds.add(item.productId) : _favIds.remove(item.productId);
    });
    try {
      if (adding) {
        await _service.addFavorite(
          productId: item.productId,
          productName: item.productName,
          imageUrl: item.imageUrl,
          adminUid: o.adminUid,
          storeName: o.storeName,
          price: item.price,
        );
      } else {
        await _service.removeFavorite(item.productId);
      }
    } catch (_) {
      // Тауар жойылған болуы мүмкін — күйді артқа қайтарамыз.
      if (!mounted) return;
      setState(() {
        _favIds = {..._favIds};
        adding ? _favIds.remove(item.productId) : _favIds.add(item.productId);
      });
      _snack(tr('Товар больше недоступен', 'Тауар енді қолжетімсіз'), cRed);
    }
  }

  void _snack(String msg, Color color) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ));

  // ── Тауарды бағалау ────────────────────────────────────────────────────────
  //  Тек АЛЫНҒАН тапсырыста мағыналы — RLS/RPC да сатып алушыға ғана рұқсат
  //  береді. Тауар/дүкен арнайы жүктеледі: CartItemModel-де снапшот қана бар,
  //  ал пікір формасына ағымдағы ProductModel/StoreModel керек.
  bool _ratingBusy = false;

  Future<void> _rateProduct(CartItemModel item) async {
    if (_ratingBusy) return;
    setState(() => _ratingBusy = true);
    try {
      final product = await _service.getProductById(o.adminUid, item.productId);
      final store = await _service.getStoreByAdminUid(o.adminUid);
      if (product == null || store == null) {
        if (mounted) {
          _snack(tr('Товар больше недоступен', 'Тауар енді қолжетімсіз'), cRed);
        }
        return;
      }
      final reviews = await _service.getProductReviews(product.id);
      final myUid = AppUser.current.uid;
      ReviewModel? mine;
      for (final r in reviews) {
        if (r.clientUid == myUid) {
          mine = r;
          break;
        }
      }
      if (!mounted) return;
      final result = await showWriteReviewSheet(
        context,
        product: product,
        store: store,
        clientName: AppUser.current.name,
        existing: mine,
      );
      if (result != null && mounted) {
        await _loadMyRatings();
        if (!mounted) return;
        _snack(
            result == 'deleted'
                ? tr('Отзыв удалён', 'Пікір өшірілді')
                : tr('Спасибо за отзыв!', 'Пікіріңізге рахмет!'),
            result == 'deleted' ? cInk2 : cGreen);
      }
    } catch (e) {
      if (mounted) _snack(friendlyError(e), cRed);
    } finally {
      if (mounted) setState(() => _ratingBusy = false);
    }
  }

  Future<void> _open2Gis(String address) async {
    final encoded = Uri.encodeComponent(address);
    final dgis = Uri.parse('dgis://2gis.ru/search/$encoded');
    if (await canLaunchUrl(dgis)) {
      await launchUrl(dgis);
    } else {
      await launchUrl(Uri.parse('https://2gis.kz/search/$encoded'),
          mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _callPhone(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.isEmpty) return;
    final uri = Uri.parse('tel:$digits');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  // ── Күй белгілері ──────────────────────────────────────────────────────────

  String get _statusLabel => o.status == OrderModel.statusCancelled
      ? cancelledByLabel(o, viewerUid: AppUser.current.uid)
      : orderStatusLabel(o.status);

  String get _typeLabel {
    switch (o.orderType) {
      case OrderModel.typeClickCollect:
        return tr('Самовывоз', 'Өзім барып аламын');
      case OrderModel.typeSmartReservation:
        return tr('Бронь', 'Бронь');
      case OrderModel.typeDelivery:
        return tr('Доставка', 'Жеткізу');
      default:
        return o.orderType;
    }
  }

  String get _typeTone {
    switch (o.orderType) {
      case OrderModel.typeClickCollect:
        return 'green';
      case OrderModel.typeDelivery:
        return 'amber';
      default:
        return 'blue';
    }
  }

  /// Қайтару батырмасы көрінуі керек пе (мерзімі + бұрын қайтарылмаған).
  bool get _canOpenReturn =>
      o.returnable && _returnLoaded && _returnStatus == null;

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: o.orderNumber > 0
              ? '${tr('Заказ', 'Тапсырыс')} №${o.orderNumber.toString().padLeft(5, '0')}'
              : tr('Заказ', 'Тапсырыс'),
          subtitle: _date(o.createdAt),
          compact: true,
          showBack: true,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              _statusCard(),
              const SizedBox(height: 12),
              _itemsCard(),
              const SizedBox(height: 12),
              if (o.isDelivery) ...[
                OrderMoneyCard(order: o, audience: 'client'),
                const SizedBox(height: 12),
                OrderTimeline(order: o),
                const SizedBox(height: 12),
              ] else
                ..._plainMoney(),
              if (!o.isDelivery &&
                  (o.warehouseAddress.isNotEmpty || o.storePhone.isNotEmpty))
                _pickupCard(),
              if (o.isDelivery && o.address.trim().isNotEmpty) _addressCard(),
              if (o.status == OrderModel.statusRejected &&
                  o.rejectionReason.isNotEmpty)
                _reasonCard(
                    tr('Причина отклонения', 'Қабылданбау себебі'),
                    o.rejectionReason),
              const SizedBox(height: 6),
              ..._actions(),
            ],
          ),
        ),
      ]),
    );
  }

  // ── Күй карточкасы ─────────────────────────────────────────────────────────
  Widget _statusCard() => _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            QPill(_statusLabel, tone: orderStatusTone(o.status)),
            const SizedBox(width: 8),
            QPill(_typeLabel, tone: _typeTone),
          ]),
          if (o.receiptNumber.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.receipt_long_outlined, size: 15, color: cBlue),
              const SizedBox(width: 6),
              Text('${tr('Чек', 'Чек')} №${o.receiptNumber.replaceAll('#', '')}',
                  style: manrope(12.5, FontWeight.w700, color: cBlue)),
            ]),
          ],
          const SizedBox(height: 12),
          Container(height: 1, color: cLine2),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Text(o.storeName,
                  style: manrope(15, FontWeight.w800, color: cInk),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (o.promoDiscount > 0)
                Text(money(o.total),
                    style: manrope(11.5, FontWeight.w500, color: cInk3)
                        .copyWith(decoration: TextDecoration.lineThrough)),
              Text(money(o.finalTotal),
                  style: manrope(17, FontWeight.w800, color: cInk)),
            ]),
          ]),
          if (o.completedAt != null) ...[
            const SizedBox(height: 8),
            Text(
                '${tr('Получен', 'Алынды')}: ${_date(o.completedAt!)}',
                style: manrope(11.5, FontWeight.w600, color: cInk3)),
          ],
        ]),
      );

  // ── Тауарлар ───────────────────────────────────────────────────────────────
  Widget _itemsCard() => _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Товары', 'Тауарлар'),
              style: manrope(13, FontWeight.w800, color: cInk)),
          const SizedBox(height: 10),
          for (var i = 0; i < o.items.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: 10),
              Container(height: 1, color: cLine2),
              const SizedBox(height: 10),
            ],
            _itemRow(o.items[i]),
          ],
        ]),
      );

  Widget _itemRow(CartItemModel item) {
    final fav = _favIds.contains(item.productId);
    final myRating = _myRatings[item.productId];
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 54,
        height: 54,
        child: QShoeImage(
          imageUrl: item.imageUrl.isNotEmpty ? item.imageUrl : null,
          height: 54,
          tone: item.productId.hashCode % 5,
        ),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.productName,
              style: manrope(13.5, FontWeight.w700, color: cInk),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          if (item.identityLine.isNotEmpty)
            Text(item.identityLine,
                style: manrope(11.5, FontWeight.w600, color: cInk3),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(
              '${tr('Размер', 'Өлшемі')} ${item.size} · ×${item.qty} · ${money(item.subtotal)}',
              style: manrope(12, FontWeight.w600, color: cInk2)),
        ]),
      ),
      // Тауарды бағалау — ТЕК АЛЫНҒАН тапсырыста (RPC сатып алушыға ғана
      // рұқсат береді). Осы жол клиенттің тауар бетіне кірмей-ақ пікір
      // қалдыруының ең қысқа жолы. Бағаланған болса — тек көрсету, ЕНДІ
      // ӨЗГЕРТЕ АЛМАЙДЫ (клиенттің талабы).
      if (o.status == OrderModel.statusCompleted)
        if (myRating != null)
          Padding(
            padding: const EdgeInsets.only(left: 6, top: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.star_rounded,
                  size: 18, color: Color(0xFFF6A609)),
              const SizedBox(width: 2),
              Text('$myRating',
                  style: manrope(12.5, FontWeight.w800, color: cInk2)),
            ]),
          )
        else
          GestureDetector(
            onTap: _ratingBusy ? null : () => _rateProduct(item),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(left: 6, top: 2),
              child: Icon(Icons.star_outline_rounded,
                  size: 21, color: cInk3),
            ),
          ),
      // Ұнады ма — тауарды таңдаулыға. Қайта сатып алудың ең қысқа жолы.
      GestureDetector(
        onTap: () => _toggleFavorite(item),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.only(left: 6, top: 2),
          child: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: 21, color: fav ? cRed : cInk3),
        ),
      ),
    ]);
  }

  // ── Ақша (жеткізу емес тапсырыстар үшін қарапайым кесте) ───────────────────
  List<Widget> _plainMoney() {
    final rows = <Widget>[];
    if (o.promoDiscount > 0) {
      rows.add(_moneyRow('${tr('Промокод', 'Промокод')} ${o.promoCode}',
          '−${money(o.promoDiscount)}', cGreen));
    }
    if (o.isSmartReservation && o.depositAmount > 0) {
      rows.add(_moneyRow(tr('Депозит', 'Депозит'),
          money(o.depositAmount), cGreen));
      rows.add(_moneyRow(tr('Доплата в магазине', 'Дүкенде доплата'),
          money(o.remainingAmount), cAmber));
    }
    if (rows.isEmpty) return const [];
    return [
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Расчёт', 'Есеп-қисап'),
              style: manrope(13, FontWeight.w800, color: cInk)),
          const SizedBox(height: 8),
          ...rows,
        ]),
      ),
      const SizedBox(height: 12),
    ];
  }

  Widget _moneyRow(String label, String value, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: manrope(12.5, FontWeight.w500, color: cInk2)),
          Text(value, style: manrope(12.5, FontWeight.w700, color: color)),
        ]),
      );

  // ── Алу орны ───────────────────────────────────────────────────────────────
  Widget _pickupCard() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cGreenTint,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cGreen.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Где забрать', 'Қайдан алу'),
                  style: manrope(11.5, FontWeight.w700, color: cGreenDeep)),
              const SizedBox(height: 8),
              if (o.warehouseAddress.isNotEmpty)
                _PickupRow(
                  icon: Icons.location_on_rounded,
                  value: o.warehouseAddress,
                  action: tr('Открыть карту', 'Картаны ашу'),
                  actionIcon: Icons.open_in_new_rounded,
                  onTap: () => _open2Gis(o.warehouseAddress),
                ),
              if (_warehouseNote != null && _warehouseNote!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.tips_and_updates_outlined,
                      color: cGreenDeep, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_warehouseNote!,
                        style: manrope(13, FontWeight.w700,
                            color: cGreenDeep, height: 1.3)),
                  ),
                ]),
              ],
              if (o.storePhone.isNotEmpty) ...[
                const SizedBox(height: 8),
                _PickupRow(
                  icon: Icons.phone_rounded,
                  value: o.storePhone,
                  action: tr('Позвонить', 'Қоңырау шалу'),
                  actionIcon: Icons.call_rounded,
                  onTap: () => _callPhone(o.storePhone),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _addressCard() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _card(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.local_shipping_outlined, size: 18, color: cInk2),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Адрес доставки', 'Жеткізу мекенжайы'),
                        style: manrope(11.5, FontWeight.w700, color: cInk3)),
                    const SizedBox(height: 3),
                    Text(
                        [
                          if (o.clientCity.trim().isNotEmpty) o.clientCity.trim(),
                          o.address.trim(),
                        ].join(', '),
                        style: manrope(13, FontWeight.w700, color: cInk)),
                  ]),
            ),
          ]),
        ),
      );

  Widget _reasonCard(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cRedTint,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cRed.withValues(alpha: 0.2)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.error_outline, color: cRed, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: manrope(11.5, FontWeight.w800, color: cRed)),
                    const SizedBox(height: 2),
                    Text(body,
                        style: manrope(12.5, FontWeight.w500, color: cRed)),
                  ]),
            ),
          ]),
        ),
      );

  // ── Әрекеттер ──────────────────────────────────────────────────────────────
  List<Widget> _actions() {
    final widgets = <Widget>[];

    // Қайта сатып алу — тек аяқталған/бас тартылған тапсырыста мағыналы
    // (белсенді тапсырыс әлі орындалып жатыр, оны қайталаудың қажеті жоқ).
    if (!orderIsActive(o.status)) {
      widgets.addAll([
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _reordering ? null : () => _reorder(goToCart: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: cGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13)),
            ),
            icon: _reordering
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.replay_rounded, size: 18),
            label: Text(tr('Повторить заказ', 'Қайта тапсырыс беру'),
                style: manrope(14.5, FontWeight.w800, color: Colors.white)),
          ),
        ),
        const SizedBox(height: 8),
        QSoftButton(
          label: tr('В корзину', 'Себетке салу'),
          height: 46,
          icon: const Icon(Icons.add_shopping_cart_rounded,
              size: 18, color: cGreenDeep),
          onPressed:
              _reordering ? null : () => _reorder(goToCart: false),
        ),
      ]);
    }

    // Возврат — ЕҢ СОҢЫНДА: бұл сирек әрі кері әрекет, негізгі жолды
    // (қайта сатып алу) көлеңкелеп тұрмауы керек.
    if (o.status == OrderModel.statusCompleted) {
      widgets.add(const SizedBox(height: 14));
      if (_returnStatus != null) {
        widgets.add(Center(
          child: _returnStatus == ReturnStatus.refunded
              ? QPill(tr('Возвращён', 'Қайтарылды'),
                  tone: 'green',
                  icon: const Icon(Icons.check_circle_outline_rounded,
                      size: 12, color: cGreenDeep))
              : QPill(tr('Возврат в обработке', 'Қайтару өңдеуде'),
                  tone: 'amber',
                  icon: const Icon(Icons.loop_rounded,
                      size: 12, color: Color(0xFF92400E))),
        ));
      } else if (_canOpenReturn) {
        widgets.addAll([
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ClientReturnFormScreen(order: o))),
              style: OutlinedButton.styleFrom(
                foregroundColor: cGreen,
                side: BorderSide(color: cGreen.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13)),
              ),
              icon: const Icon(Icons.assignment_return_outlined,
                  size: 17, color: cGreen),
              label: Text(tr('Оформить возврат', 'Қайтару жасау'),
                  style: manrope(13.5, FontWeight.w700, color: cGreen)),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
                tr('Осталось ${o.returnDaysLeft} дн.',
                    '${o.returnDaysLeft} күн қалды'),
                style: manrope(11.5, FontWeight.w600, color: cInk3)),
          ),
        ]);
      } else if (_returnLoaded) {
        widgets.add(Center(
          child: Text(tr('Срок возврата истёк', 'Қайтару мерзімі өтті'),
              style: manrope(11.5, FontWeight.w600, color: cInk3)),
        ));
      }
    }
    return widgets;
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cLine),
          boxShadow: kShadowSm,
        ),
        child: child,
      );
}

/// Мекенжай/телефон жолы: мән + анық әрекет белгісі (басуға болатыны көрініп
/// тұр). client_orders_screen.dart-тағы белсенді карточкамен бірдей стиль.
class _PickupRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final String action;
  final IconData actionIcon;
  final VoidCallback onTap;
  const _PickupRow({
    required this.icon,
    required this.value,
    required this.action,
    required this.actionIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(children: [
          Icon(icon, color: cGreenDeep, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value,
                style: manrope(14, FontWeight.w700,
                    color: cGreenDeep, height: 1.25),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: cGreen,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(actionIcon, color: Colors.white, size: 13),
              const SizedBox(width: 4),
              Text(action,
                  style: manrope(11.5, FontWeight.w700, color: Colors.white)),
            ]),
          ),
        ]),
      );
}
