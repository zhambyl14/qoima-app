import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/error_text.dart';
import '../../core/lang.dart';
import '../../data/models/order_model.dart';
import '../../data/services/kazpost_service.dart';
import '../../theme/qoima_design.dart';

/// Казпочта тапсырысы — админ мен сатушы көретін БІР карточка: жөнелту бланкісі
/// және дүкеннің әрекеттері.
///
/// Бланкі әр күйде көрінеді: дүкен оны почтада қолмен толтырады, сондықтан әр
/// жолды бөлек көшіруге және бәрін бірге алуға болады. Статусты тек сервер
/// RPC-лері өзгертеді (0081) — мұнда тек шақырамыз.
class KazpostStoreCard extends StatefulWidget {
  final OrderModel order;
  final VoidCallback onChanged;

  const KazpostStoreCard({
    super.key,
    required this.order,
    required this.onChanged,
  });

  @override
  State<KazpostStoreCard> createState() => _KazpostStoreCardState();
}

class _KazpostStoreCardState extends State<KazpostStoreCard> {
  final _service = KazpostService();
  bool _busy = false;

  OrderModel get o => widget.order;

  void _snack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  void _copy(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    _snack(message);
  }

  // Почта бланкісіне бірден қоюға болатын дайын блок.
  void _copyAll() {
    final lines = <String>[
      if (o.postRecipientName.isNotEmpty)
        '${tr('Кому', 'Кімге')}: ${o.postRecipientName}',
      if (o.postRecipientPhone.isNotEmpty)
        '${tr('Телефон', 'Телефон')}: ${o.postRecipientPhone}',
      if (o.postIndex.isNotEmpty) '${tr('Индекс', 'Индекс')}: ${o.postIndex}',
      if (o.clientCity.isNotEmpty)
        '${tr('Город', 'Қала')}: ${trValue(o.clientCity)}',
      if (o.address.isNotEmpty) '${tr('Адрес', 'Мекенжай')}: ${o.address}',
    ];
    _copy(lines.join('\n'),
        tr('Адрес получателя скопирован', 'Алушының мекенжайы көшірілді'));
  }

  Future<void> _openTrackingSheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _TrackingSheet(order: o, service: _service),
    );
    if (saved != true || !mounted) return;
    _snack(tr('Трек-номер сохранён', 'Трек-нөмір сақталды'), color: cGreen);
    widget.onChanged();
  }

  Future<void> _complete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Посылка вручена?', 'Сәлемдеме табысталды ма?')),
        content: Text(tr(
            'Заказ будет завершён, и для покупателя начнётся срок возврата. Подтверждайте, только если посылка вручена.',
            'Тапсырыс аяқталады да, сатып алушы үшін қайтару мерзімі басталады. Сәлемдеме табысталған болса ғана растаңыз.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Нет', 'Жоқ'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cGreen, foregroundColor: Colors.white),
              child: Text(tr('Да, вручено', 'Иә, табысталды'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _service.completeOrder(o.id);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _snack(tr('Заказ завершён', 'Тапсырыс аяқталды'), color: cGreen);
      widget.onChanged();
    } catch (e) {
      if (mounted) _snack(friendlyError(e), color: cRed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      if (o.postRecipientName.isNotEmpty)
        _slipRow(tr('Получатель', 'Алушы'), o.postRecipientName),
      if (o.postRecipientPhone.isNotEmpty)
        _slipRow(tr('Телефон', 'Телефон'), o.postRecipientPhone),
      if (o.postIndex.isNotEmpty) _slipRow(tr('Индекс', 'Индекс'), o.postIndex),
      if (o.clientCity.isNotEmpty)
        _slipRow(tr('Город', 'Қала'), trValue(o.clientCity)),
      if (o.address.isNotEmpty) _slipRow(tr('Адрес', 'Мекенжай'), o.address),
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cPurpleTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cPurple.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.local_post_office_rounded,
              size: 17, color: cPurpleInk),
          const SizedBox(width: 8),
          Expanded(
            child: Text(tr('Отправка Казпочтой', 'Казпочтамен жөнелту'),
                style: manrope(13.5, FontWeight.w800, color: cInk)),
          ),
          TextButton.icon(
            onPressed: rows.isEmpty ? null : _copyAll,
            style: TextButton.styleFrom(
              foregroundColor: cPurpleInk,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.copy_all_rounded, size: 16),
            label: Text(tr('Копировать всё', 'Бәрін көшіру'),
                style: manrope(12, FontWeight.w800, color: cPurpleInk)),
          ),
        ]),
        const SizedBox(height: 4),
        ...rows,
        const Divider(height: 18, color: cLine),
        Row(children: [
          Expanded(
            child: Text(tr('Стоимость почты', 'Почта ақысы'),
                style: manrope(12.5, FontWeight.w700, color: cInk2)),
          ),
          Text(money(o.kazpostFee),
              style: manrope(13.5, FontWeight.w800, color: cInk)),
        ]),
        const SizedBox(height: 2),
        Text(
            tr('Входит в перевод клиента. На почте её оплачиваете вы.',
                'Клиент аударымының ішінде. Почтада оны сіз төлейсіз.'),
            style: manrope(11.5, FontWeight.w600, color: cInk2, height: 1.3)),
        ..._stateBlock(),
      ]),
    );
  }

  List<Widget> _stateBlock() {
    final confirmed = o.status == OrderModel.statusConfirmed;

    if (confirmed && o.postStatus.isEmpty) {
      return [
        const SizedBox(height: 12),
        Text(
            tr('Сдайте посылку на почте и введите трек-номер с квитанции: покупатель получит уведомление.',
                'Сәлемдемені почтаға тапсырып, түбіртектегі трек-нөмірді енгізіңіз: сатып алушыға хабарлама барады.'),
            style: manrope(11.5, FontWeight.w600, color: cInk2, height: 1.3)),
        const SizedBox(height: 8),
        QPrimaryButton(
          label: tr(
              'Отправил — ввести трек-номер', 'Жібердім — трек-нөмір енгізу'),
          height: 46,
          icon: const Icon(Icons.local_shipping_rounded,
              color: Colors.white, size: 18),
          onPressed: _openTrackingSheet,
        ),
      ];
    }

    if (confirmed && o.postInTransit) {
      final shipped = o.postShippedAt;
      return [
        const SizedBox(height: 12),
        _trackingRow(),
        if (shipped != null) ...[
          const SizedBox(height: 4),
          Text(
              tr('Отправлено ${_dateTime(shipped)}',
                  'Жіберілді: ${_dateTime(shipped)}'),
              style: manrope(11.5, FontWeight.w600, color: cInk2)),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : _openTrackingSheet,
            style: TextButton.styleFrom(
              foregroundColor: cPurpleInk,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.edit_outlined, size: 15),
            label: Text(tr('Изменить трек', 'Тректі өзгерту'),
                style: manrope(12, FontWeight.w800, color: cPurpleInk)),
          ),
        ),
        if (o.storeCanClosePost) ...[
          const SizedBox(height: 4),
          QPrimaryButton(
            label: tr('Вручено покупателю', 'Сатып алушыға табысталды'),
            height: 46,
            isLoading: _busy,
            icon: const Icon(Icons.check_circle_outline_rounded,
                color: Colors.white, size: 18),
            onPressed: _complete,
          ),
        ] else
          Text(_closeHint(shipped),
              style: manrope(11.5, FontWeight.w600, color: cInk2, height: 1.3)),
      ];
    }

    // Аяқталған/қайтарылған: тек тарих, әрекет жоқ. Күтудегі тапсырыста (төлем
    // әлі расталмаған) трек те жоқ — бланкінің өзі ғана қалады.
    final delivered = o.postDeliveredAt;
    if (o.postTracking.isEmpty && delivered == null) return const [];
    return [
      const SizedBox(height: 12),
      if (o.postTracking.isNotEmpty) _trackingRow(),
      if (delivered != null) ...[
        const SizedBox(height: 4),
        Row(children: [
          const Icon(Icons.task_alt_rounded, size: 15, color: cGreen),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
                tr('Вручено ${_dateTime(delivered)}',
                    'Табысталды: ${_dateTime(delivered)}'),
                style: manrope(12, FontWeight.w700, color: cGreenDeep)),
          ),
        ]),
      ],
    ];
  }

  // Дүкен ерте жаба алмайды: әйтпесе клиент алмай тұрып қайтару мерзімі
  // басталып кетер еді (0081).
  String _closeHint(DateTime? shipped) {
    if (shipped == null) {
      return tr(
          'Получение подтверждает покупатель. Сами закрыть заказ можно через 7 дней после отправки.',
          'Алғанын сатып алушы растайды. Тапсырысты өзіңіз жібергеннен кейін 7 күннен соң жаба аласыз.');
    }
    final at = _dateTime(shipped.add(OrderModel.postStoreCloseAfter));
    return tr(
        'Получение подтверждает покупатель. Если он не подтвердит, закрыть заказ можно будет самим через 7 дней после отправки: с $at.',
        'Алғанын сатып алушы растайды. Растамаса, тапсырысты өзіңіз жібергеннен кейін 7 күннен соң жаба аласыз: $at бастап.');
  }

  Widget _trackingRow() => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _copy(o.postTracking,
            tr('Трек-номер скопирован', 'Трек-нөмір көшірілді')),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Text(tr('Трек', 'Трек'),
                style: manrope(12, FontWeight.w600, color: cInk2)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(o.postTracking,
                  style: manrope(14, FontWeight.w800,
                      color: cInk, letterSpacing: 0.6)),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.copy_outlined, size: 15, color: cInk3),
          ]),
        ),
      );

  Widget _slipRow(String label, String value) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _copy(value, tr('Скопировано', 'Көшірілді')),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 82,
              child: Text(label,
                  style: manrope(12, FontWeight.w600, color: cInk2)),
            ),
            Expanded(
              child: Text(value,
                  style: manrope(12.5, FontWeight.w700, color: cInk)),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.copy_outlined, size: 14, color: cInk3),
          ]),
        ),
      );

  static String _dateTime(DateTime d) {
    final l = d.toLocal();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(l.day)}.${p(l.month)}.${l.year} ${p(l.hour)}:${p(l.minute)}';
  }
}

/// Трек енгізу/түзету. RPC осы парақшаның ішінде шақырылады: сервер нөмірді
/// қабылдамаса, терілген мәтін жоғалмай, қатенің өзі көрінеді.
class _TrackingSheet extends StatefulWidget {
  final OrderModel order;
  final KazpostService service;

  const _TrackingSheet({required this.order, required this.service});

  @override
  State<_TrackingSheet> createState() => _TrackingSheetState();
}

class _TrackingSheetState extends State<_TrackingSheet> {
  late final _ctrl = TextEditingController(text: widget.order.postTracking);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _ctrl.text.trim();
    if (value.isEmpty || _saving) return;
    // Өзгермесе серверге бармаймыз.
    if (value == widget.order.postTracking) {
      Navigator.pop(context, false);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.markShipped(widget.order.id, value);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.order.postTracking.isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: cLine, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 16),
              Text(
                  editing
                      ? tr('Изменить трек-номер', 'Трек-нөмірді өзгерту')
                      : tr('Трек-номер посылки', 'Сәлемдеменің трек-нөмірі'),
                  style: manrope(16, FontWeight.w800, color: cInk)),
              const SizedBox(height: 4),
              Text(
                  editing
                      ? tr('Покупатель увидит исправленный номер в заказе.',
                          'Сатып алушы түзетілген нөмірді тапсырыста көреді.')
                      : tr(
                          'Номер указан в квитанции почты. Покупатель увидит его в заказе.',
                          'Нөмір почта түбіртегінде жазылған. Сатып алушы оны тапсырыста көреді.'),
                  style: manrope(12.5, FontWeight.w500,
                      color: cInk2, height: 1.35)),
              const SizedBox(height: 14),
              TextField(
                controller: _ctrl,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 30,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                ],
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _submit(),
                style: manrope(15, FontWeight.w700,
                    color: cInk, letterSpacing: 0.6),
                decoration: InputDecoration(
                  hintText: 'RR123456789KZ',
                  counterText: '',
                  errorText: _error,
                  errorMaxLines: 3,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 14),
              ListenableBuilder(
                listenable: _ctrl,
                builder: (_, __) => QPrimaryButton(
                  label: tr('Сохранить', 'Сақтау'),
                  height: 48,
                  isLoading: _saving,
                  onPressed: _ctrl.text.trim().isEmpty ? null : _submit,
                ),
              ),
            ]),
      ),
    );
  }
}
