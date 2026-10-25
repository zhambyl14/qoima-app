import 'package:flutter/material.dart';
import '../../core/feature_flags.dart';
import '../../core/lang.dart';
import '../../data/models/order_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/store_model.dart';
import '../../theme/qoima_design.dart';

/// Тауар карточкасындағы «қайтаруға бола ма» белгісі (0073).
/// • product.nonReturnable → қызғылт-сары/қызыл карточка: «Бұл тауар қайтарылмайды»
///   + тауар ескертпесі + дүкеннің жалпы қайтару ережесі.
/// • әйтпесе — шағын жасыл «Қайтаруға болады (N күн)» (N = OrderModel.returnWindow).
/// Функция суперадминнен өшірулі болса — ештеңе көрсетпейді (жаңа тапсырыс
/// снапшотталмайды, сондықтан «қайтарылмайды» деп қорқыту жалған болар еді).
class ReturnabilityBadge extends StatelessWidget {
  final ProductModel product;
  final StoreModel store;
  const ReturnabilityBadge({
    super.key,
    required this.product,
    required this.store,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FeatureFlags.instance,
      builder: (context, _) {
        if (!FeatureFlags.instance.isOn(FeatureFlags.nonReturnable)) {
          return const SizedBox.shrink();
        }
        return product.nonReturnable ? _blocked() : _returnable();
      },
    );
  }

  Widget _returnable() {
    final days = OrderModel.returnWindow.inDays;
    final note = store.returnPolicyNote.trim();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Align(
          alignment: Alignment.centerLeft,
          child: QPill(
            tr('Можно вернуть ($days дн.)', 'Қайтаруға болады ($days күн)'),
            tone: 'green',
            icon: const Icon(Icons.replay_rounded, size: 13, color: cGreenDeep),
          ),
        ),
        if (note.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(note, style: manrope(12, FontWeight.w500, color: cInk2)),
        ],
      ]),
    );
  }

  Widget _blocked() {
    final pNote = product.returnNote.trim();
    final sNote = store.returnPolicyNote.trim();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cAmberTint,
        borderRadius: BorderRadius.circular(kR16),
        border: Border.all(color: cAmber.withValues(alpha: 0.45)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.block_rounded, size: 20, color: cRedInk),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                tr('Этот товар возврату не подлежит',
                    'Бұл тауар қайтарылмайды'),
                style: manrope(14, FontWeight.w800, color: cRedInk)),
            if (pNote.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(pNote, style: manrope(12.5, FontWeight.w600, color: cInk)),
            ],
            if (sNote.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(sNote, style: manrope(12, FontWeight.w500, color: cInk2)),
            ],
            const SizedBox(height: 4),
            Text(
                tr('После покупки вернуть его нельзя — оформляя заказ, вы соглашаетесь с этим.',
                    'Сатып алғаннан кейін қайтаруға болмайды — тапсырыс беру арқылы осымен келісесіз.'),
                style: manrope(11.5, FontWeight.w500, color: cInk3)),
          ]),
        ),
      ]),
    );
  }
}
