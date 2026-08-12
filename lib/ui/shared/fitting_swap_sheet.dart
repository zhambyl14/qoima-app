import 'package:flutter/material.dart';
import '../../core/lang.dart';
import '../../data/models/order_model.dart';
import '../../theme/qoima_design.dart';

/// Дүкен/сатушы тапсырысты ӨЗІ (курьерсіз) береді, әрі тапсырыста «өлшеп
/// көру» (примерка — бір позицияда 2 өлшем: негізгі + қосалқы) бар болса —
/// осы парақша ашылады: клиент нақты қай өлшемді алғанын сұрайды.
///
/// НЕГЕ КЕРЕК: бұрын бұл сұралмайтын, жүйе әрдайым «клиент негізгі өлшемді
/// алды» деп есептейтін. Егер клиент іс жүзінде ҚОСАЛҚЫ өлшемді алса —
/// қойма/сатылым қате есептелетін (курьер арқылы жеткізгенде бұл дұрыс
/// сұралатын, ал дүкен өзі бергенде жоқ еді).
///
/// Қайтарады: swap болған позициялардың `order.items` ішіндегі индекстері
/// (тапсырыста примерка болмаса — тексерместен бос тізім қайтарады, парақша
/// ашылмайды). Пайдаланушы болдырмаса — null.
Future<List<int>?> showFittingSwapSheet(
    BuildContext context, OrderModel order) async {
  final fittingIdx = <int>[];
  for (var i = 0; i < order.items.length; i++) {
    if (order.items[i].hasAltSize) fittingIdx.add(i);
  }
  if (fittingIdx.isEmpty) return const [];

  return showModalBottomSheet<List<int>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FittingSwapSheet(order: order, fittingIdx: fittingIdx),
  );
}

class _FittingSwapSheet extends StatefulWidget {
  final OrderModel order;
  final List<int> fittingIdx;
  const _FittingSwapSheet({required this.order, required this.fittingIdx});

  @override
  State<_FittingSwapSheet> createState() => _FittingSwapSheetState();
}

class _FittingSwapSheetState extends State<_FittingSwapSheet> {
  /// index → қосалқы өлшем алынды ма (true = своп).
  final Map<int, bool> _tookAlt = {};

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: const BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
                color: cLine, borderRadius: BorderRadius.circular(2)),
          ),
          Text(tr('Какой размер взял клиент?', 'Клиент қай өлшемді алды?'),
              style: manrope(17, FontWeight.w800, color: cInk)),
          const SizedBox(height: 4),
          Text(
              tr('В заказе была примерка — выберите итоговый размер по каждой позиции',
                  'Тапсырыста өлшеп көру болды — әр позиция бойынша соңғы өлшемді таңдаңыз'),
              style:
                  manrope(12.5, FontWeight.w500, color: cInk2, height: 1.35)),
          const SizedBox(height: 14),
          ...widget.fittingIdx.map((i) {
            final item = widget.order.items[i];
            final tookAlt = _tookAlt[i] ?? false;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cBg,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.productName,
                        style: manrope(13.5, FontWeight.w800, color: cInk),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 9),
                    Row(children: [
                      Expanded(
                        child: _SizeChoice(
                          size: item.size,
                          label: tr('Заказанный', 'Тапсырыс берген'),
                          selected: !tookAlt,
                          onTap: () => setState(() => _tookAlt[i] = false),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: _SizeChoice(
                          size: item.altSize,
                          label: tr('Запасной', 'Қосалқы'),
                          selected: tookAlt,
                          onTap: () => setState(() => _tookAlt[i] = true),
                        ),
                      ),
                    ]),
                  ]),
            );
          }),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: cAmberTint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cAmber.withValues(alpha: 0.5)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded,
                  color: cAmberInk, size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    tr('Незабранный размер сразу вернётся на склад',
                        'Алынбаған өлшем қоймаға бірден оралады'),
                    style: manrope(12, FontWeight.w700, color: cInk2)),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          QPrimaryButton(
            label: tr('Подтвердить', 'Растау'),
            onPressed: () => Navigator.pop(context,
                widget.fittingIdx.where((i) => _tookAlt[i] == true).toList()),
            height: 50,
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Отмена', 'Болдырмау'),
                style: manrope(14, FontWeight.w600, color: cInk3)),
          ),
        ]),
      ),
    );
  }
}

class _SizeChoice extends StatelessWidget {
  final String size, label;
  final bool selected;
  final VoidCallback onTap;
  const _SizeChoice({
    required this.size,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? cGreen : cSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? cGreen : cLine, width: selected ? 2 : 1.5),
          ),
          child: Column(children: [
            Text(size,
                style: manrope(18, FontWeight.w800,
                    color: selected ? Colors.white : cInk)),
            Text(label,
                style: manrope(10.5, FontWeight.w700,
                    color: selected ? Colors.white70 : cInk3)),
          ]),
        ),
      );
}
