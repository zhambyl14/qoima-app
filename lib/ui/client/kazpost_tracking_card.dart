import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/contact_utils.dart';
import '../../core/error_text.dart';
import '../../core/lang.dart';
import '../../data/models/order_model.dart';
import '../../data/services/client_service.dart';
import '../../data/services/kazpost_service.dart';
import '../../theme/qoima_design.dart';

/// Казпочта сәлемдемесі: бағыт, алушы, трек және клиенттің екі әрекеті (0081).
///
/// «Алдым» батырмасы маңызды: қайтару мерзімі дәл осы сәттен басталады, әрі
/// дүкен жібергеніне 7 күн толмай тапсырысты өзі жаба алмайды.
class KazpostTrackingCard extends StatefulWidget {
  final OrderModel order;
  const KazpostTrackingCard({super.key, required this.order});

  @override
  State<KazpostTrackingCard> createState() => _KazpostTrackingCardState();
}

class _KazpostTrackingCardState extends State<KazpostTrackingCard> {
  // Трекингтің сілтеме пішімін тексере алмадық, сондықтан тек басты бет:
  // клиент көшірілген нөмірді сайттың өзінде енгізеді.
  static const _postSite = 'https://post.kz/';

  OrderModel get o => widget.order;

  // Тапсырыста дүкеннің қаласы сақталмайды, сондықтан бөлек оқимыз.
  String _storeCity = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadStoreCity();
  }

  Future<void> _loadStoreCity() async {
    try {
      final store = await ClientService().getStoreByAdminUid(o.adminUid);
      final city = store?.city.trim() ?? '';
      if (city.isNotEmpty && mounted) setState(() => _storeCity = city);
    } catch (_) {}
  }

  void _snack(ScaffoldMessengerState messenger, String text, Color color) =>
      messenger.showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ));

  Future<void> _copyTracking() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: o.postTracking));
    _snack(
        messenger, tr('Трек-номер скопирован', 'Трек-нөмір көшірілді'), cGreen);
  }

  Future<void> _openTracking() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: o.postTracking));
    _snack(
        messenger,
        tr('Трек-номер скопирован — вставьте его на сайте post.kz',
            'Трек-нөмір көшірілді — оны post.kz сайтына қойыңыз'),
        cGreen);
    try {
      await openExternalUrl(_postSite);
    } catch (e) {
      _snack(messenger, friendlyError(e), cRed);
    }
  }

  Future<void> _confirmReceived() async {
    final policy = o.returnPolicy;
    final days = policy?.days ?? OrderModel.returnWindow.inDays;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Посылка у вас?', 'Сәлемдеме сізде ме?'),
            style: manrope(17, FontWeight.w700, color: cInk)),
        content: Text(
            policy?.isNoReturns == true || o.allItemsNonReturnable
                ? tr(
                    'Подтверждайте, только когда посылка уже у вас. Возврат по этому заказу не предусмотрен.',
                    'Сәлемдеме қолыңызға тигенде ғана растаңыз. Бұл тапсырыс бойынша қайтару қарастырылмаған.')
                : tr(
                    'Подтверждайте, только когда посылка уже у вас. Срок возврата ($days дн.) начнётся прямо сейчас.',
                    'Сәлемдеме қолыңызға тигенде ғана растаңыз. Қайтару мерзімі ($days күн) дәл қазір басталады.'),
            style: manrope(14, FontWeight.w500, color: cInk2, height: 1.4)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Ещё нет', 'Әлі жоқ'),
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Да, получил', 'Иә, алдым'),
                  style: manrope(14, FontWeight.w700, color: cGreenDeep))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await KazpostService().completeOrder(o.id);
      _snack(messenger, tr('Заказ получен', 'Тапсырыс алынды'), cGreen);
    } catch (e) {
      _snack(messenger, friendlyError(e), cRed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _dateOnly(DateTime d) {
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}.${l.month.toString().padLeft(2, '0')}.${l.year}';
  }

  @override
  Widget build(BuildContext context) {
    // Болдырылған тапсырыста бұл ақпараттың мәні жоқ, таймлайн бәрін айтады.
    if (o.status == OrderModel.statusCancelled) return const SizedBox.shrink();

    final hasTrack = o.postTracking.isNotEmpty;
    final from = _storeCity.isNotEmpty ? trValue(_storeCity) : o.storeName;
    final to = o.clientCity.trim().isEmpty ? '' : trValue(o.clientCity.trim());
    final deliveredAt = o.postDeliveredAt;
    final address = [
      if (to.isNotEmpty) to,
      if (o.address.trim().isNotEmpty) o.address.trim(),
    ].join(', ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: cBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cLine),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.local_post_office_rounded,
              size: 16, color: cGreenDeep),
          const SizedBox(width: 7),
          Text(tr('Казпочта', 'Казпочта'),
              style: manrope(13, FontWeight.w800, color: cInk)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(to.isEmpty ? from : '$from → $to',
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: manrope(12, FontWeight.w700, color: cInk2)),
          ),
        ]),
        const SizedBox(height: 10),
        if (o.postRecipientName.isNotEmpty || o.postRecipientPhone.isNotEmpty)
          _InfoLine(
              tr('Получатель', 'Алушы'),
              [o.postRecipientName, o.postRecipientPhone]
                  .where((e) => e.isNotEmpty)
                  .join(', ')),
        if (o.postIndex.isNotEmpty)
          _InfoLine(tr('Индекс', 'Индекс'), o.postIndex),
        if (address.isNotEmpty) _InfoLine(tr('Адрес', 'Мекенжай'), address),
        if (hasTrack)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _copyTracking,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Трек-номер', 'Трек-нөмір'),
                            style:
                                manrope(11.5, FontWeight.w600, color: cInk3)),
                        Text(o.postTracking,
                            style: manrope(14.5, FontWeight.w800,
                                color: cInk, letterSpacing: 0.5)),
                      ]),
                ),
                const Icon(Icons.copy_rounded, size: 17, color: cGreenDeep),
                const SizedBox(width: 4),
                Text(tr('Копировать', 'Көшіру'),
                    style: manrope(12, FontWeight.w700, color: cGreenDeep)),
              ]),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              o.status == OrderModel.statusConfirmed
                  ? tr(
                      'Оплата подтверждена. Магазин отправит посылку и укажет трек-номер.',
                      'Төлем расталды. Дүкен сәлемдемені жіберіп, трек-нөмірін көрсетеді.')
                  : tr('Магазин отправит посылку после подтверждения оплаты.',
                      'Дүкен сәлемдемені төлем расталған соң жібереді.'),
              style: manrope(12, FontWeight.w600, color: cInk2, height: 1.35),
            ),
          ),
        if (deliveredAt != null) ...[
          const SizedBox(height: 8),
          Text(
              o.postClosedByClient
                  ? tr('Получена ${_dateOnly(deliveredAt)}',
                      '${_dateOnly(deliveredAt)} алынды')
                  : tr('Заказ закрыт ${_dateOnly(deliveredAt)}',
                      'Тапсырыс ${_dateOnly(deliveredAt)} жабылды'),
              style: manrope(12, FontWeight.w700, color: cGreenDeep)),
        ],
        if (hasTrack) ...[
          const SizedBox(height: 12),
          QSoftButton(
            label: tr('Отследить на post.kz', 'post.kz сайтында бақылау'),
            height: 44,
            icon: const Icon(Icons.open_in_new_rounded,
                size: 17, color: cGreenDeep),
            onPressed: _openTracking,
          ),
        ],
        if (o.postInTransit) ...[
          const SizedBox(height: 8),
          QPrimaryButton(
            label: tr('Я получил посылку', 'Сәлемдемені алдым'),
            height: 48,
            isLoading: _busy,
            onPressed: _busy ? null : _confirmReceived,
          ),
        ],
      ]),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label, value;
  const _InfoLine(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: manrope(11.5, FontWeight.w600, color: cInk3)),
          Text(value, style: manrope(13, FontWeight.w700, color: cInk)),
        ]),
      );
}
