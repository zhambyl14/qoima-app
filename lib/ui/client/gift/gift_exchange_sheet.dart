import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/error_text.dart';
import '../../../core/lang.dart';
import '../../../data/models/category_data.dart';
import '../../../data/models/order_model.dart';
import '../../../data/services/gift_service.dart';
import '../../../theme/qoima_design.dart';

/// Өлшемдерді ретке келтіру: сандар — өсу ретімен, қалғаны — категория
/// тізіміндегі ретпен (S, M, L…). Сыйлау экрандарының бәрі осыны қолданады.
List<String> sortGiftSizes(Iterable<String> input, String categoryKey) {
  final sizes = input.toSet().toList();
  final nums = sizes.map((s) => double.tryParse(s.replaceAll(',', '.'))).toList();
  if (nums.every((n) => n != null)) {
    final idx = List<int>.generate(sizes.length, (i) => i)
      ..sort((a, b) => nums[a]!.compareTo(nums[b]!));
    return [for (final i in idx) sizes[i]];
  }
  final order = categoryByKey(categoryKey).sizes;
  sizes.sort((a, b) {
    final ia = order.indexOf(a), ib = order.indexOf(b);
    if (ia == -1 && ib == -1) return a.compareTo(b);
    if (ia == -1) return 1;
    if (ib == -1) return -1;
    return ia.compareTo(ib);
  });
  return sizes;
}

/// Ауыстыру парақшасында таңдалған тауар + өлшем.
class GiftExchangeChoice {
  final GiftExchangeProduct product;
  final GiftSizeOption option;
  const GiftExchangeChoice(this.product, this.option);

  String get size => option.size;
  double get extra => option.extra;
}

/// «Басқа өлшем не басқа тауар» парақшасы (алушы да, дүкен де қолданады).
///
/// Баға ережесін ашық көрсетеді: арзанырақ тауар — айырма қайтарылмайды;
/// қымбатырақ — дүкенде қосымша төлем (курьерде мүлде рұқсат жоқ).
Future<GiftExchangeChoice?> showGiftExchangePicker(
  BuildContext context, {
  required GiftExchangeOptions options,
  String? selectedProductId,
  String? selectedSize,
}) =>
    showModalBottomSheet<GiftExchangeChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GiftExchangePicker(
        options: options,
        selectedProductId: selectedProductId,
        selectedSize: selectedSize,
      ),
    );

/// Дүкен (иесі/сатушы) кассада сыйлықты ауыстырады: нұсқаларды жүктейді →
/// парақша → растау (қосымша төлем сомасымен) → `gift_store_exchange`.
/// Сәтті болса — true.
Future<bool> showGiftStoreExchange(
    BuildContext context, OrderModel order) async {
  final svc = GiftService();
  void snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? cRed : cGreen,
        behavior: SnackBarBehavior.floating,
      ));
  }

  if (order.giftToken.isEmpty) return false;
  GiftExchangeOptions opts;
  try {
    opts = await svc.getExchangeOptions(order.giftToken);
  } catch (e) {
    if (context.mounted) snack(friendlyError(e), error: true);
    return false;
  }
  if (!context.mounted) return false;
  if (opts.locked) {
    snack(
        tr('Этот товар нельзя обменять (невозвратный)',
            'Бұл тауарды ауыстыруға болмайды (қайтарылмайды)'),
        error: true);
    return false;
  }

  final choice = await showGiftExchangePicker(context,
      options: opts,
      selectedProductId: opts.currentProductId,
      selectedSize: opts.currentSize);
  if (choice == null || !context.mounted) return false;
  if (choice.product.id == opts.currentProductId &&
      choice.size == opts.currentSize) {
    snack(tr('Выбран тот же товар и размер', 'Сол тауар мен өлшем таңдалды'),
        error: true);
    return false;
  }

  final extra = choice.extra;
  final lines = <String>[
    '${choice.product.name} · ${tr('размер', 'өлшемі')} ${trValue(choice.size)}',
    if (extra > 0)
      opts.completed
          ? tr('Получите доплату ${money(extra)} сейчас на кассе.',
              'Қазір кассада ${money(extra)} қосымша төлем алыңыз.')
          : tr('Доплата ${money(extra)} — при выдаче подарка.',
              'Қосымша төлем ${money(extra)} — сыйлықты берген кезде.')
    else
      tr('Без доплаты. Если новый товар дешевле, разница не возвращается.',
          'Қосымша төлемсіз. Жаңа тауар арзан болса, айырма қайтарылмайды.'),
    if (opts.completed)
      tr('Возвращённый товар сразу вернётся на склад.',
          'Қайтарылған тауар бірден қоймаға оралады.'),
  ];
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: cSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(tr('Обменять подарок?', 'Сыйлықты ауыстыру керек пе?'),
          style: manrope(17, FontWeight.w800)),
      content: Text(lines.join('\n\n'),
          style: manrope(14, FontWeight.w500, color: cInk2)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Отмена', 'Болдырмау'),
                style: manrope(14, FontWeight.w600, color: cInk2))),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Обменять', 'Ауыстыру'),
                style: manrope(14, FontWeight.w700, color: cGreen))),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;

  try {
    await svc.storeExchange(
        orderId: order.id, productId: choice.product.id, size: choice.size);
    if (!context.mounted) return true;
    HapticFeedback.mediumImpact();
    snack(tr('Подарок обменян', 'Сыйлық ауыстырылды'));
    return true;
  } catch (e) {
    if (context.mounted) snack(friendlyError(e), error: true);
    return false;
  }
}

class _GiftExchangePicker extends StatefulWidget {
  final GiftExchangeOptions options;
  final String? selectedProductId;
  final String? selectedSize;
  const _GiftExchangePicker({
    required this.options,
    this.selectedProductId,
    this.selectedSize,
  });

  @override
  State<_GiftExchangePicker> createState() => _GiftExchangePickerState();
}

class _GiftExchangePickerState extends State<_GiftExchangePicker> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _expanded;
  String? _selProduct;
  String? _selSize;

  GiftExchangeOptions get o => widget.options;

  @override
  void initState() {
    super.initState();
    _selProduct = widget.selectedProductId;
    _selSize = widget.selectedSize;
    _expanded = widget.selectedProductId ??
        (o.products.isNotEmpty ? o.products.first.id : null);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<GiftExchangeProduct> get _visible {
    final q = _query.trim().toLowerCase();
    return [
      for (final p in o.products)
        if (p.hasAllowed &&
            (q.isEmpty ||
                p.isCurrent ||
                p.name.toLowerCase().contains(q) ||
                p.brand.toLowerCase().contains(q)))
          p,
    ];
  }

  GiftExchangeChoice? get _choice {
    for (final p in o.products) {
      if (p.id != _selProduct) continue;
      for (final s in p.sizes) {
        if (s.size == _selSize && s.allowed) return GiftExchangeChoice(p, s);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final list = _visible;
    final choice = _choice;
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      decoration: const BoxDecoration(
        color: cBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Row(children: [
              const QIconTile(
                  icon: Icon(Icons.swap_horiz_rounded, color: cGreen, size: 22),
                  tone: 'green',
                  size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                    tr('Другой размер или товар', 'Басқа өлшем не тауар'),
                    style: manrope(19, FontWeight.w800)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: _rules(),
          ),
          if (o.products.length > 4)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: tr('Поиск товара', 'Тауар іздеу'),
                  hintStyle: manrope(14, FontWeight.w500, color: cInk3),
                  prefixIcon:
                      const Icon(Icons.search_rounded, color: cInk3, size: 20),
                  filled: true,
                  fillColor: cSurface,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(kR14),
                    borderSide: const BorderSide(color: cLine),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(kR14),
                    borderSide: const BorderSide(color: cLine),
                  ),
                ),
              ),
            ),
          Flexible(
            child: list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      tr('Нет подходящих товаров в наличии',
                          'Қолда сәйкес тауар жоқ'),
                      textAlign: TextAlign.center,
                      style: manrope(14, FontWeight.w600, color: cInk2),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _productTile(list[i]),
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(
              color: cSurface,
              border: const Border(top: BorderSide(color: cLine)),
              boxShadow: kShadowSm,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (choice != null) ...[
                Row(children: [
                  Expanded(
                    child: Text(
                      '${choice.product.name} · ${trValue(choice.size)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: manrope(13, FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    choice.extra > 0
                        ? '+${money(choice.extra)}'
                        : tr('без доплаты', 'қосымшасыз'),
                    style: manrope(13, FontWeight.w800,
                        color: choice.extra > 0 ? cAmberInk : cGreenDeep),
                  ),
                ]),
                const SizedBox(height: 8),
              ],
              QPrimaryButton(
                label: tr('Выбрать', 'Таңдау'),
                icon: const Icon(Icons.check_rounded,
                    color: Colors.white, size: 20),
                onPressed:
                    choice == null ? null : () => Navigator.pop(context, choice),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _rules() {
    final lines = <String>[
      if (o.credit != null)
        tr('Подарок оплачен на ${money(o.credit!)}.',
            'Сыйлыққа ${money(o.credit!)} төленген.'),
      tr('Товар дешевле — можно, разница не возвращается.',
          'Арзанырақ тауар — болады, айырма қайтарылмайды.'),
      if (o.allowOver)
        (o.completed
            ? tr('Товар дороже — доплата разницы сейчас на кассе.',
                'Қымбатырақ тауар — айырманы қазір кассада төлейді.')
            : tr('Товар дороже — доплата разницы в магазине при получении.',
                'Қымбатырақ тауар — айырманы дүкенде алған кезде төлейсіз.'))
      else
        tr('Курьерская доставка: только товары не дороже подарка.',
            'Курьермен жеткізу: тек сыйлықтан қымбат емес тауарлар.'),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cGreenTint,
        borderRadius: BorderRadius.circular(kR14),
        border: Border.all(color: cGreenTint2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(top: 5),
                child: Icon(Icons.circle, size: 5, color: cGreenDeep),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l,
                    style: manrope(12.5, FontWeight.w600, color: cInk2)),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _productTile(GiftExchangeProduct p) {
    final open = _expanded == p.id;
    final selectedHere = _selProduct == p.id;
    final minExtra = p.minExtra;
    final minPrice = p.minPrice;
    final sizes = sortGiftSizes(
        p.sizes.where((s) => s.allowed).map((s) => s.size), p.categoryKey);
    final byName = {for (final s in p.sizes) s.size: s};
    return Container(
      decoration: BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.circular(kR16),
        border: Border.all(
            color: selectedHere ? cGreen : cLine,
            width: selectedHere ? 1.6 : 1),
      ),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(kR16),
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _expanded = open ? null : p.id);
          },
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              SizedBox(
                width: 54,
                height: 54,
                child: QShoeImage(
                    imageUrl: p.imageUrl.isNotEmpty ? p.imageUrl : null,
                    height: 54),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: manrope(14, FontWeight.w700)),
                    const SizedBox(height: 3),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      if (p.isCurrent)
                        QPill(tr('Подарок', 'Сыйлық'), tone: 'purple'),
                      if (minPrice != null)
                        Text(
                            tr('от ${money(minPrice)}',
                                '${money(minPrice)} бастап'),
                            style: manrope(12, FontWeight.w600, color: cInk2)),
                      Text(
                        minExtra > 0
                            ? tr('доплата от ${money(minExtra)}',
                                'қосымша ${money(minExtra)} бастап')
                            : tr('входит в подарок', 'сыйлыққа кіреді'),
                        style: manrope(12, FontWeight.w700,
                            color: minExtra > 0 ? cAmberInk : cGreenDeep),
                      ),
                    ]),
                  ],
                ),
              ),
              Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: cInk3),
            ]),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in sizes)
                  _sizeChip(p, byName[s]!),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _sizeChip(GiftExchangeProduct p, GiftSizeOption s) {
    final sel = _selProduct == p.id && _selSize == s.size;
    final current = p.isCurrent && s.size == o.currentSize;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _selProduct = p.id;
          _selSize = s.size;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        constraints: const BoxConstraints(minWidth: 56),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? cGreen : cSurface,
          borderRadius: BorderRadius.circular(kR12),
          border: Border.all(
              color: sel ? cGreen : (current ? cGreenDeep : cLine),
              width: 1.4),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(trValue(s.size),
              style: manrope(14, FontWeight.w700,
                  color: sel ? Colors.white : cInk)),
          if (s.extra > 0)
            Text('+${money(s.extra)}',
                style: manrope(10.5, FontWeight.w700,
                    color: sel ? Colors.white : cAmberInk))
          else if (current)
            Text(tr('текущий', 'қазіргі'),
                style: manrope(10.5, FontWeight.w600,
                    color: sel ? Colors.white : cGreenDeep)),
        ]),
      ),
    );
  }
}
