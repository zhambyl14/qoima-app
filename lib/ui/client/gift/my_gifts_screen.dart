import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_user.dart';
import '../../../core/error_text.dart';
import '../../../core/lang.dart';
import '../../../data/models/order_model.dart';
import '../../../data/services/gift_service.dart';
import '../../../theme/qoima_design.dart';
import '../../shared/error_view.dart';
import '../client_order_detail_screen.dart';
import '../client_product_card.dart' show ClientEmptyState;
import '../payment_instructions_sheet.dart';
import 'gift_receive_screen.dart';
import 'gift_share_screen.dart';

/// «Сыйлықтар»: жіберілгендер және маған келгендер.
class MyGiftsScreen extends StatefulWidget {
  /// 0 — жіберілген, 1 — маған келген.
  final int initialTab;
  const MyGiftsScreen({super.key, this.initialTab = 0});

  @override
  State<MyGiftsScreen> createState() => _MyGiftsScreenState();
}

class _MyGiftsScreenState extends State<MyGiftsScreen> {
  final _gifts = GiftService();
  StreamSubscription<List<OrderModel>>? _sentSub;
  StreamSubscription<List<OrderModel>>? _recvSub;

  late int _tab = widget.initialTab.clamp(0, 1);
  List<OrderModel> _sent = const [];
  List<OrderModel> _received = const [];
  bool _sentLoaded = false;
  bool _recvLoaded = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    _sentSub?.cancel();
    _recvSub?.cancel();
    _error = null;
    _sentSub = _gifts.watchMyGiftsSent().listen((v) {
      if (mounted) {
        setState(() {
          _sent = v;
          _sentLoaded = true;
        });
      }
    }, onError: (Object e) {
      if (mounted) setState(() => _error = e);
    });
    _recvSub = _gifts.watchGiftsReceived().listen((v) {
      if (mounted) {
        setState(() {
          _received = v;
          _recvLoaded = true;
        });
      }
    }, onError: (Object e) {
      if (mounted) setState(() => _error = e);
    });
  }

  @override
  void dispose() {
    _sentSub?.cancel();
    _recvSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = _tab == 0 ? _sent : _received;
    final loaded = _tab == 0 ? _sentLoaded : _recvLoaded;
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Подарки', 'Сыйлықтар'),
          subtitle: tr('Отправленные и полученные', 'Жіберілген және келген'),
          showBack: true,
          compact: true,
          bottom: [
            _tabs(),
          ],
        ),
        Expanded(
          child: _error != null
              ? AppErrorView(
                  error: _error, onRetry: () async => setState(_subscribe))
              : !loaded
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: cGreen, strokeWidth: 2))
                  : list.isEmpty
                      ? ClientEmptyState(
                          icon: Icons.card_giftcard_rounded,
                          message: _tab == 0
                              ? tr(
                                  'Вы пока ничего не дарили.\nОткройте товар и нажмите «Подарить».',
                                  'Әзірге ешкімге сыйлаған жоқсыз.\nТауарды ашып, «Сыйлау» батырмасын басыңыз.')
                              : tr(
                                  'Подарков для вас пока нет.\nОткройте ссылку от друга — подарок появится здесь.',
                                  'Сізге әзірге сыйлық жоқ.\nДосыңыздың сілтемесін ашыңыз — сыйлық осында шығады.'),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                          itemCount: list.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, i) => _tab == 0
                              ? _SentCard(order: list[i])
                              : _ReceivedCard(order: list[i]),
                        ),
        ),
      ]),
    );
  }

  Widget _tabs() => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(kRPill),
        ),
        child: Row(children: [
          _seg(0, tr('Отправленные', 'Жіберілген'), _sent.length),
          _seg(1, tr('Мне подарили', 'Маған келген'), _received.length),
        ]),
      );

  Widget _seg(int i, String label, int count) {
    final active = _tab == i;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _tab = i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(kRPill),
          ),
          child: Text(
            count > 0 ? '$label · $count' : label,
            textAlign: TextAlign.center,
            style: manrope(13, FontWeight.w700,
                color: active ? cGreenDeep : Colors.white),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
class _SentCard extends StatelessWidget {
  final OrderModel order;
  const _SentCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final o = order;
    final item = o.items.isNotEmpty ? o.items.first : null;
    final cancelled = o.status == OrderModel.statusCancelled ||
        o.status == OrderModel.statusReturned;
    final awaitingPay = !cancelled &&
        (o.status == OrderModel.statusPending ||
            o.status == OrderModel.statusRejected ||
            o.status == OrderModel.statusReserved);
    final needsReceipt = awaitingPay && o.receiptUrl.isEmpty;

    // Күй белгісі
    String label;
    String tone;
    if (cancelled) {
      label = tr('Отменён', 'Бас тартылды');
      tone = 'red';
    } else if (needsReceipt) {
      label = o.status == OrderModel.statusRejected
          ? tr('Чек отклонён', 'Чек қабылданбады')
          : tr('Ждёт оплаты', 'Төлемді күтуде');
      tone = o.status == OrderModel.statusRejected ? 'red' : 'amber';
    } else if (awaitingPay) {
      label = tr('Магазин проверяет оплату', 'Дүкен төлемді тексеріп жатыр');
      tone = 'blue';
    } else if (o.isGiftExpired) {
      label = tr('Срок истёк', 'Мерзімі өтті');
      tone = 'red';
    } else if (o.isGiftAwaitingRecipient) {
      label = tr('Ждёт получателя', 'Алушыны күтеді');
      tone = 'amber';
    } else if (o.status == OrderModel.statusCompleted) {
      label = tr('Вручён', 'Тапсырылды');
      tone = 'green';
    } else if (o.status == OrderModel.statusReady) {
      label = tr('Готов к выдаче', 'Беруге дайын');
      tone = 'green';
    } else {
      label = tr('Получатель выбрал размер', 'Алушы өлшем таңдады');
      tone = 'purple';
    }

    final days = o.giftExpiresAt?.difference(DateTime.now()).inDays;

    return QCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(kR12),
          onTap: () => _openOrder(context),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 68,
              height: 68,
              child: QShoeImage(imageUrl: item?.imageUrl, height: 68),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item?.productName ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: manrope(15, FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (o.giftRecipientName.isNotEmpty)
                          tr('Для: ${o.giftRecipientName}',
                              'Кімге: ${o.giftRecipientName}'),
                        o.storeName,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: manrope(12, FontWeight.w500, color: cInk2),
                    ),
                    const SizedBox(height: 6),
                    QPill(label, tone: tone),
                  ]),
            ),
          ]),
        ),
        if (o.isGiftClaimed && item != null && item.size.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
              tr('Размер: ${trValue(item.size)}',
                  'Өлшемі: ${trValue(item.size)}'),
              style: manrope(13, FontWeight.w600)),
        ],
        if (o.isGiftReadyToClaim && days != null && days >= 0) ...[
          const SizedBox(height: 8),
          Text(
            days <= 3
                ? tr('Осталось дней: $days — напомните получателю',
                    'Қалған күн: $days — алушыға еске салыңыз')
                : tr('Действует ещё $days дн.', '$days күн жарамды'),
            style: manrope(12, FontWeight.w600,
                color: days <= 3 ? cAmberInk : cInk3),
          ),
        ],
        const SizedBox(height: 12),
        if (needsReceipt)
          QPrimaryButton(
            label: tr('Оплатить и прикрепить чек', 'Төлеп, чекті тіркеу'),
            height: 46,
            onPressed: () => showPaymentInstructionsSheet(context,
                amount: o.depositAmount, orders: [o]),
          )
        // төлем тексеріліп жатса да сілтеме қайта жіберіледі (жабылып қалса жоғалмасын)
        else if (o.isGiftAwaitingRecipient && !o.isGiftExpired)
          Row(children: [
            Expanded(
              child: QPrimaryButton(
                label: tr('Отправить ссылку', 'Сілтемені жіберу'),
                icon: const Icon(Icons.ios_share_rounded,
                    color: Colors.white, size: 18),
                height: 46,
                onPressed: () => shareGiftLink(context, o),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 46,
              child: QSoftButton(
                label: '',
                height: 46,
                icon: const Icon(Icons.link_rounded, color: cGreen, size: 20),
                onPressed: () => copyGiftLink(context, o),
              ),
            ),
          ])
        else if (o.isGiftExpired)
          QSoftButton(
            label:
                tr('Запросить возврат у магазина', 'Дүкеннен қайтаруды сұрау'),
            tone: 'amber',
            icon: const Icon(Icons.support_agent_rounded,
                color: cAmberInk, size: 20),
            onPressed: () => _contactStore(context),
          )
        else
          QSoftButton(
            label: tr('Открыть заказ', 'Тапсырысты ашу'),
            onPressed: () => _openOrder(context),
          ),
      ]),
    );
  }

  void _openOrder(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ClientOrderDetailScreen(order: order)));

  Future<void> _contactStore(BuildContext context) async {
    final phone = order.storePhone.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(tr(
              'Телефон магазина не указан', 'Дүкеннің телефоны көрсетілмеген')),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      return;
    }
    try {
      await launchUrl(Uri(scheme: 'tel', path: phone));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(friendlyError(e)),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
class _ReceivedCard extends StatelessWidget {
  final OrderModel order;
  const _ReceivedCard({required this.order});

  static String _d(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final o = order;
    final item = o.items.isNotEmpty ? o.items.first : null;
    final hidePrice = o.hideGiftPriceFor(AppUser.current.uid);

    // Төленген, бірақ алушы әлі ештеңе таңдамаған сыйлық — басты әрекет осы.
    final toClaim = o.isGiftReadyToClaim &&
        !o.isGiftClaimed &&
        !o.isGiftExpired &&
        o.giftToken.isNotEmpty;

    String label;
    String tone;
    switch (o.status) {
      case OrderModel.statusCompleted:
        label = tr('Получен', 'Алынды');
        tone = 'green';
      case OrderModel.statusReady:
        label = tr('Готов к выдаче', 'Беруге дайын');
        tone = 'green';
      case OrderModel.statusCancelled:
      case OrderModel.statusReturned:
        label = tr('Отменён', 'Бас тартылды');
        tone = 'red';
      default:
        label = toClaim
            ? tr('Ждёт вашего выбора', 'Таңдауыңызды күтуде')
            : o.byPlatformCourier
                ? tr('Магазин собирает, затем курьер',
                    'Дүкен жинайды, сосын курьер')
                : tr('Магазин готовит подарок',
                    'Дүкен сыйлықты дайындап жатыр');
        tone = toClaim ? 'amber' : 'blue';
    }

    return QCard(
      padding: const EdgeInsets.all(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(kR12),
        onTap: () => toClaim
            ? openGiftPage(context, o.giftToken)
            : Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ClientOrderDetailScreen(order: o))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 68,
              height: 68,
              child: QShoeImage(imageUrl: item?.imageUrl, height: 68),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item?.productName ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: manrope(15, FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (o.giftGiverName.isNotEmpty)
                          tr('От: ${o.giftGiverName}',
                              'Кімнен: ${o.giftGiverName}'),
                        o.storeName,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: manrope(12, FontWeight.w500, color: cInk2),
                    ),
                    const SizedBox(height: 6),
                    QPill(label, tone: tone),
                  ]),
            ),
          ]),
          if (toClaim) ...[
            const SizedBox(height: 12),
            QPrimaryButton(
              label: tr('Получить подарок', 'Сыйлықты алу'),
              icon: const Icon(Icons.card_giftcard_rounded,
                  color: Colors.white, size: 20),
              height: 48,
              onPressed: () => openGiftPage(context, o.giftToken),
            ),
            const SizedBox(height: 6),
            Text(
                tr('Выберите размер, способ получения (магазин или курьер) и укажите свой телефон.',
                    'Өлшемді, алу тәсілін (дүкен немесе курьер) таңдап, телефоныңызды жазыңыз.'),
                style: manrope(12, FontWeight.w500, color: cInk3)),
          ],
          if (item != null && item.size.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
                tr('Размер: ${trValue(item.size)}',
                    'Өлшемі: ${trValue(item.size)}'),
                style: manrope(13, FontWeight.w600)),
          ],
          if (!hidePrice && item != null) ...[
            const SizedBox(height: 4),
            Text(
                tr('Стоимость: ${money(item.price)}',
                    'Құны: ${money(item.price)}'),
                style: manrope(12, FontWeight.w500, color: cInk3)),
          ],
          // 0070: қосымша төлем (қымбатырақ тауар таңдалса) — дүкенде беру кезінде
          if (o.hasGiftExtraDue) ...[
            const SizedBox(height: 4),
            Text(
                tr('Доплата в магазине: ${money(o.giftExtraDue)}',
                    'Дүкенде қосымша төлем: ${money(o.giftExtraDue)}'),
                style: manrope(12.5, FontWeight.w800, color: cAmberInk)),
          ],
          // Сыйлық = тек ауыстыру: алынған соң 14 күн ішінде дүкенде
          if (o.status == OrderModel.statusCompleted) ...[
            const SizedBox(height: 6),
            Text(
                o.giftExchangeOpen
                    ? tr(
                        'Не подошёл? Обменяйте в магазине до ${_d(o.returnDeadline)} (только обмен, без возврата денег)',
                        'Келмеді ме? ${_d(o.returnDeadline)} дейін дүкенде ауыстырыңыз (тек ауыстыру, ақша қайтарылмайды)')
                    : tr('Срок обмена истёк', 'Ауыстыру мерзімі өтті'),
                style: manrope(12, FontWeight.w600, color: cInk2)),
          ],
          if (!o.byPlatformCourier &&
              o.pickupCode.isNotEmpty &&
              o.status != OrderModel.statusCompleted &&
              o.status != OrderModel.statusCancelled) ...[
            const SizedBox(height: 8),
            Text(
                tr('Код получения: ${o.pickupCode}',
                    'Алу коды: ${o.pickupCode}'),
                style: manrope(14, FontWeight.w800, color: cGreenDeep)),
          ],
        ]),
      ),
    );
  }
}

/// Сілтеме арқылы сыйлық бетін тікелей ашу (тізімнен қайта көру үшін).
Future<void> openGiftPage(BuildContext context, String token) =>
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => GiftReceiveScreen(token: token)));
