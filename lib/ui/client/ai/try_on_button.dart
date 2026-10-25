import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/feature_flags.dart';
import '../../../core/lang.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/store_model.dart';
import '../../../theme/qoima_design.dart';
import '../../shared/require_login.dart';
import 'try_on_eligibility.dart';
import 'try_on_screen.dart';

/// «Онлайн киіп көру» батырмасы. Тауар жарамаса немесе суперадмин функцияны
/// өшірсе — ештеңе көрсетпейді.
class TryOnButton extends StatelessWidget {
  final ProductModel product;
  final StoreModel store;

  const TryOnButton({super.key, required this.product, required this.store});

  Future<void> _open(BuildContext context) async {
    HapticFeedback.selectionClick();
    final ok = await requireLogin(
      context,
      reasonRu: 'Войдите, чтобы примерить одежду онлайн',
      reasonKk: 'Киімді онлайн киіп көру үшін кіріңіз',
    );
    if (!ok || !context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TryOnScreen(product: product, store: store),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isTryOnEligible(product)) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: FeatureFlags.instance,
      builder: (context, _) {
        if (!FeatureFlags.instance.isOn(FeatureFlags.aiTryOn)) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: QSoftButton(
            label: tr('Примерить онлайн', 'Онлайн киіп көру'),
            icon: const Icon(Icons.auto_awesome, size: 18, color: cGreenDeep),
            onPressed: () => _open(context),
          ),
        );
      },
    );
  }
}
