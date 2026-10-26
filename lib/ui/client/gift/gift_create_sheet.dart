import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/app_user.dart';
import '../../../core/error_text.dart';
import '../../../core/feature_flags.dart';
import '../../../core/lang.dart';
import '../../../data/models/batch_model.dart';
import '../../../data/models/delivery_tariff.dart';
import '../../../data/models/order_model.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/store_model.dart';
import '../../../data/services/app_settings_service.dart';
import '../../../data/services/client_service.dart';
import '../../../data/services/gift_service.dart';
import '../../../theme/qoima_design.dart';
import '../../shared/require_login.dart';
import '../payment_instructions_sheet.dart';
import 'gift_exchange_sheet.dart' show sortGiftSizes;
import 'gift_share_screen.dart';

/// «Сыйлау»: тауарды сыйлыққа сатып алу (өлшем міндетті емес).
///
/// Өлшем: «Өлшемін білемін» — баға сол өлшемдікі, қойма бірден брондалады;
/// әйтпесе — ең қымбат өлшемнің бағасы, өлшемді алушы таңдайды. Қайтарылмайтын
/// тауарда өлшем міндетті. Курьер болса «өлшеп көру» ақысын сыйлаушы төлейді.
///
/// Ағын: кіру тексерісі → әдемі парақша (алушы аты, тілек, өлшем, жеткізу) →
/// `create_gift_order` (сервер бағаны өзі есептейді) → төлем нұсқаулығы →
/// сыйлау бетінде «Жіберу» батырмасы.
Future<void> showGiftSheet(
  BuildContext context, {
  required ProductModel product,
  required StoreModel store,
}) async {
  if (!FeatureFlags.instance.isOn(FeatureFlags.giftLinks)) {
    _snack(context, tr('Функция временно отключена', 'Функция уақытша өшірулі'),
        error: true);
    return;
  }
  final ok = await requireLogin(
    context,
    reasonRu: 'Чтобы подарить товар, войдите в аккаунт.',
    reasonKk: 'Тауарды сыйлау үшін аккаунтқа кіріңіз.',
  );
  if (!ok || !context.mounted) return;
  if (!context.read<AppUser>().isClient) {
    _snack(
        context,
        tr('Подарки доступны только покупателям',
            'Сыйлық тек сатып алушыларға қолжетімді'),
        error: true);
    return;
  }

  final order = await showModalBottomSheet<OrderModel>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _GiftSheet(product: product, store: store),
  );
  if (order == null || !context.mounted) return;

  // Төлем нұсқаулығы: карта/QR + чек тіркеу. Жабылса да тапсырыс сақталады.
  final attached = await showPaymentInstructionsSheet(
    context,
    amount: order.depositAmount,
    orders: [order],
  );
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) =>
        GiftShareScreen(order: order, receiptPending: attached != true),
  ));
}

void _snack(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? cRed : cGreen,
      behavior: SnackBarBehavior.floating,
    ));
}

class _GiftSheet extends StatefulWidget {
  final ProductModel product;
  final StoreModel store;
  const _GiftSheet({required this.product, required this.store});

  @override
  State<_GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends State<_GiftSheet> {
  final _service = ClientService();
  final _gifts = GiftService();
  final _nameCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  Object? _loadError;
  double? _maxPrice; // кез келген өлшемге жететін ЕҢ ЖОҒАРЫ бағасы
  /// Өлшем → сол өлшемі бар ЕҢ АРЗАН партияның бағасы (сервер де соны алады).
  Map<String, double> _sizePrice = const {};
  DeliveryTariff _tariff = const DeliveryTariff();
  bool _courier = false;
  bool _hidePrice = false;
  bool _knowSize = false;
  String? _size;

  /// Қайтарылмайтын тауар: алушы ауыстыра алмайды → өлшем міндетті (0070).
  bool get _nonReturnable =>
      FeatureFlags.instance.isOn(FeatureFlags.nonReturnable) &&
      widget.product.nonReturnable;

  bool get _needSize => _knowSize || _nonReturnable;

  /// Төленетін тауар бағасы: өлшем таңдалса — сол өлшемнің бағасы.
  double? get _price => _needSize && _size != null
      ? (_sizePrice[_size] ?? _maxPrice)
      : _maxPrice;

  /// «Өлшеп көру» ақысы — курьер болса СЫЙЛАУШЫ төлейді (ақшасы дүкенге).
  double get _fittingFee =>
      (_courier && _courierAvailable && !_nonReturnable)
          ? _tariff.fittingFee
          : 0;

  List<String> get _suggestions => [
        tr('С днём рождения!', 'Туған күніңмен!'),
        tr('Поздравляю!', 'Құттықтаймын!'),
        tr('С Новым годом!', 'Жаңа жылмен!'),
        tr('Совет да любовь!', 'Той құтты болсын!'),
      ];

  bool get _courierAvailable => _tariff.courierWorksIn(widget.store.city);

  double get _courierFee => _price == null
      ? 0
      : _tariff.feeForSubOrder(orderTotal: _price!, index: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _service.getProductBatches(widget.store.adminUid, widget.product.id,
            widget.store.visibleWarehouseIds),
        AppSettingsService().getDeliveryTariff(),
      ]);
      final batches = results[0] as List<BatchModel>;
      double? maxPrice;
      final sizePrice = <String, double>{};
      for (final b in batches) {
        final avail = b.availableSizes;
        if (avail.isEmpty) continue;
        final p = effectivePrice(b);
        if (maxPrice == null || p > maxPrice) maxPrice = p;
        for (final s in avail.keys) {
          final cur = sizePrice[s];
          if (cur == null || p < cur) sizePrice[s] = p;
        }
      }
      if (!mounted) return;
      setState(() {
        _maxPrice = maxPrice;
        _sizePrice = sizePrice;
        if (_size != null && !sizePrice.containsKey(_size)) _size = null;
        _tariff = results[1] as DeliveryTariff;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack(context,
          tr('Укажите, кому подарок', 'Сыйлық кімге екенін көрсетіңіз'),
          error: true);
      return;
    }
    if (_needSize && _size == null) {
      _snack(context, tr('Выберите размер', 'Өлшемді таңдаңыз'), error: true);
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    try {
      final order = await _gifts.createGift(
        productId: widget.product.id,
        courier: _courier && _courierAvailable,
        recipientName: name,
        message: _msgCtrl.text,
        hidePrice: _hidePrice,
        size: _needSize ? _size : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop(order);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      decoration: const BoxDecoration(
        color: cBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: cLine, borderRadius: BorderRadius.circular(2)),
          ),
          Flexible(child: _body()),
        ]),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(56),
        child: Center(
            child: CircularProgressIndicator(color: cGreen, strokeWidth: 2)),
      );
    }
    if (_loadError != null || _maxPrice == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.inventory_2_outlined, size: 44, color: cInk3),
          const SizedBox(height: 12),
          Text(
            _loadError != null
                ? friendlyError(_loadError)
                : tr('Этого товара сейчас нет в наличии',
                    'Бұл тауар қазір қоймада жоқ'),
            textAlign: TextAlign.center,
            style: manrope(15, FontWeight.w600, color: cInk2),
          ),
          const SizedBox(height: 16),
          QSoftButton(
            label: tr('Закрыть', 'Жабу'),
            tone: 'gray',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ]),
      );
    }
    final price = _price!;
    final fit = _fittingFee;
    final p = widget.product;
    final useCourier = _courier && _courierAvailable;
    final sizeChosen = _needSize && _size != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const QIconTile(
              icon: Icon(Icons.card_giftcard_rounded, color: cGreen, size: 24),
              tone: 'green'),
          const SizedBox(width: 12),
          Expanded(
            child: Text(tr('Подарить', 'Сыйлау'),
                style: manrope(22, FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 14),
        // ── Тауар ──
        QCard(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            SizedBox(
              width: 72,
              height: 72,
              child: QShoeImage(
                  imageUrl: p.images.isNotEmpty ? p.images.first : null,
                  height: 72),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: manrope(15, FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(widget.store.storeName,
                      style: manrope(13, FontWeight.w500, color: cInk2)),
                  const SizedBox(height: 6),
                  QPill(
                    sizeChosen
                        ? tr('Размер: ${trValue(_size!)}',
                            'Өлшемі: ${trValue(_size!)}')
                        : tr('Размер выберет получатель',
                            'Өлшемді алушы өзі таңдайды'),
                    tone: 'green',
                    icon: const Icon(Icons.straighten_rounded,
                        size: 12, color: cGreenDeep),
                  ),
                ],
              ),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        // ── Өлшем (міндетті емес; қайтарылмайтын тауарда — міндетті) ──
        QSecLabel(tr('Размер', 'Өлшем')),
        const SizedBox(height: 8),
        if (_nonReturnable)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cAmberTint,
              borderRadius: BorderRadius.circular(kR14),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline_rounded,
                  color: cAmberInk, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('Этот товар нельзя обменять — подарите, зная размер.',
                      'Бұл тауарды ауыстыруға болмайды, өлшемін біліп сыйлаңыз.'),
                  style: manrope(12.5, FontWeight.w600, color: cAmberInk),
                ),
              ),
            ]),
          )
        else ...[
          _deliveryOption(
            selected: !_knowSize,
            icon: Icons.redeem_rounded,
            title: tr('Размер выберет получатель', 'Өлшемді алушы таңдайды'),
            sub: tr('Цена по самому дорогому размеру — подойдёт любой',
                'Ең қымбат өлшемнің бағасы — кез келгені келеді'),
            onTap: () => setState(() => _knowSize = false),
          ),
          const SizedBox(height: 8),
          _deliveryOption(
            selected: _knowSize,
            icon: Icons.straighten_rounded,
            title: tr('Знаю размер', 'Өлшемін білемін'),
            sub: tr(
                'Забронируем размер сразу. Получатель сможет поменять размер или товар',
                'Өлшемді бірден брондаймыз. Алушы өлшемді не тауарды ауыстыра алады'),
            onTap: () => setState(() => _knowSize = true),
          ),
        ],
        if (_needSize) ...[
          const SizedBox(height: 10),
          if (_sizePrice.isEmpty)
            Text(
                tr('Нет размеров в наличии', 'Қолда өлшем жоқ'),
                style: manrope(13, FontWeight.w600, color: cRedInk))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in sortGiftSizes(_sizePrice.keys, p.categoryKey))
                _sizeChip(s),
            ]),
        ],
        const SizedBox(height: 18),
        // ── Алушы ──
        QSecLabel(tr('Кому', 'Кімге')),
        const SizedBox(height: 8),
        TextField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          maxLength: 60,
          decoration: _dec(tr('Имя получателя', 'Алушының аты'),
              icon: Icons.person_outline_rounded),
        ),
        const SizedBox(height: 6),
        QSecLabel(tr('Пожелание', 'Тілек')),
        const SizedBox(height: 8),
        TextField(
          controller: _msgCtrl,
          minLines: 3,
          maxLines: 4,
          maxLength: 300,
          textCapitalization: TextCapitalization.sentences,
          decoration: _dec(tr('Тёплые слова для получателя (необязательно)',
              'Алушыға жылы сөз (міндетті емес)')),
        ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in _suggestions)
            ActionChip(
              label: Text(s, style: manrope(13, FontWeight.w600)),
              backgroundColor: cGreenTint,
              side: const BorderSide(color: cGreenTint2),
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _msgCtrl.text = s;
                  _msgCtrl.selection =
                      TextSelection.collapsed(offset: s.length);
                });
              },
            ),
        ]),
        const SizedBox(height: 14),
        // ── Бағаны жасыру ──
        QCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _hidePrice,
            activeTrackColor: cGreen,
            onChanged: (v) => setState(() => _hidePrice = v),
            title: Text(
                tr('Скрыть цену от получателя', 'Бағаны алушыдан жасыру'),
                style: manrope(14, FontWeight.w700)),
            subtitle: Text(
                tr('Получатель не увидит, сколько стоит подарок',
                    'Алушы сыйлықтың бағасын көрмейді'),
                style: manrope(12, FontWeight.w500, color: cInk2)),
          ),
        ),
        const SizedBox(height: 18),
        // ── Жеткізу ──
        QSecLabel(tr('Как получит подарок', 'Сыйлықты қалай алады')),
        const SizedBox(height: 8),
        _deliveryOption(
          selected: !useCourier,
          icon: Icons.storefront_rounded,
          title: tr('Заберёт в магазине', 'Дүкеннен өзі алады'),
          sub: tr('Бесплатно · адрес магазина покажем получателю',
              'Тегін · дүкен мекенжайын алушыға көрсетеміз'),
          onTap: () => setState(() => _courier = false),
        ),
        const SizedBox(height: 8),
        _deliveryOption(
          selected: useCourier,
          enabled: _courierAvailable,
          icon: Icons.delivery_dining_rounded,
          title: tr('Курьером до двери', 'Курьер есігіне дейін'),
          sub: _courierAvailable
              ? tr(
                  'Получатель оплатит курьеру ${money(_courierFee)} при получении · только в г. ${trValue(widget.store.city)}',
                  'Алушы алғанда курьерге ${money(_courierFee)} төлейді · тек ${trValue(widget.store.city)} қаласында')
              : tr('В городе магазина курьерской доставки пока нет',
                  'Дүкен қаласында курьерлік жеткізу әзірге жоқ'),
          onTap: () => setState(() => _courier = true),
        ),
        const SizedBox(height: 18),
        // ── Баға ──
        QCard(
          color: cGreenTint,
          border: Border.all(color: cGreenTint2),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: Text(tr('Подарок', 'Сыйлық'),
                    style: manrope(14, FontWeight.w600, color: cInk2)),
              ),
              Text(money(price), style: manrope(17, FontWeight.w800)),
            ]),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                sizeChosen
                    ? tr('Цена размера ${trValue(_size!)} — он забронирован для получателя.',
                        '${trValue(_size!)} өлшемінің бағасы — ол алушыға брондалады.')
                    : _needSize
                        ? tr('Выберите размер — цена уточнится.',
                            'Өлшемді таңдаңыз — баға нақтыланады.')
                        : tr(
                            'Цена по самому дорогому размеру — подойдёт любой размер.',
                            'Ең қымбат өлшемнің бағасы — кез келген өлшем келеді.'),
                style: manrope(12, FontWeight.w500, color: cInk2),
              ),
            ),
            if (fit > 0) ...[
              const Divider(height: 20, color: cGreenTint2),
              Row(children: [
                Expanded(
                  child: Text(
                      tr('Примерка второго размера', 'Екінші өлшемді өлшеп көру'),
                      style: manrope(13, FontWeight.w600, color: cInk2)),
                ),
                Text(money(fit),
                    style: manrope(14, FontWeight.w700, color: cInk2)),
              ]),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  tr('Курьер может привезти получателю второй размер на выбор — примерку оплачиваете вы. Если она не понадобится, сумма не возвращается.',
                      'Курьер алушыға таңдауға екінші өлшемді әкеле алады — өлшеп көруді сіз төлейсіз. Қажет болмаса, сомасы қайтарылмайды.'),
                  style: manrope(11.5, FontWeight.w500, color: cInk3),
                ),
              ),
            ],
            if (useCourier) ...[
              const Divider(height: 20, color: cGreenTint2),
              Row(children: [
                Expanded(
                  child: Text(
                      tr('Получатель оплатит курьеру',
                          'Алушы курьерге төлейді'),
                      style: manrope(13, FontWeight.w600, color: cInk2)),
                ),
                Text(money(_courierFee),
                    style: manrope(14, FontWeight.w700, color: cInk2)),
              ]),
            ],
            const Divider(height: 20, color: cGreenTint2),
            Row(children: [
              Expanded(
                child: Text(tr('Оплатить сейчас', 'Қазір төлеу'),
                    style: manrope(15, FontWeight.w700)),
              ),
              Text(money(price + fit),
                  style: manrope(20, FontWeight.w800, color: cGreenDeep)),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        QPrimaryButton(
          label: tr('Оплатить подарок', 'Сыйлықты төлеу'),
          icon: const Icon(Icons.card_giftcard_rounded,
              color: Colors.white, size: 20),
          height: 56,
          isLoading: _busy,
          onPressed: _busy ? null : _submit,
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            tr(
                'Подарок действует 30 дней. Если получатель не откроет его, '
                    'можно запросить возврат у магазина. После получения подарок '
                    'можно только обменять в магазине (14 дней), деньги не возвращаются.',
                'Сыйлық 30 күн жарамды. Алушы ашпаса, дүкеннен қайтаруды сұрауға болады. '
                    'Алынған сыйлықты тек дүкенде ауыстыруға болады (14 күн), ақша қайтарылмайды.'),
            textAlign: TextAlign.center,
            style: manrope(12, FontWeight.w500, color: cInk3),
          ),
        ),
      ]),
    );
  }

  Widget _sizeChip(String s) {
    final sel = _size == s;
    final p = _sizePrice[s];
    final showPrice = p != null && _maxPrice != null && p < _maxPrice!;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _size = s);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        constraints: const BoxConstraints(minWidth: 56),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: sel ? cGreen : cSurface,
          borderRadius: BorderRadius.circular(kR12),
          border: Border.all(color: sel ? cGreen : cLine, width: 1.4),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(trValue(s),
              style: manrope(15, FontWeight.w700,
                  color: sel ? Colors.white : cInk)),
          if (showPrice)
            Text(money(p),
                style: manrope(10.5, FontWeight.w600,
                    color: sel ? Colors.white : cInk3)),
        ]),
      ),
    );
  }

  Widget _deliveryOption({
    required bool selected,
    required IconData icon,
    required String title,
    required String sub,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(kR16),
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onTap();
              }
            : null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? cGreenTint : cSurface,
            borderRadius: BorderRadius.circular(kR16),
            border: Border.all(
                color: selected ? cGreen : cLine, width: selected ? 1.6 : 1),
          ),
          child: Row(children: [
            Icon(icon, color: selected ? cGreen : cInk3, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: manrope(14, FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(sub, style: manrope(12, FontWeight.w500, color: cInk2)),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: cGreen, size: 22),
          ]),
        ),
      ),
    );
  }

  InputDecoration _dec(String hint, {IconData? icon}) => InputDecoration(
        hintText: hint,
        hintStyle: manrope(14, FontWeight.w500, color: cInk3),
        prefixIcon: icon == null ? null : Icon(icon, color: cInk3, size: 20),
        filled: true,
        fillColor: cSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kR14),
          borderSide: const BorderSide(color: cLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kR14),
          borderSide: const BorderSide(color: cLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kR14),
          borderSide: const BorderSide(color: cGreen, width: 1.6),
        ),
      );
}
