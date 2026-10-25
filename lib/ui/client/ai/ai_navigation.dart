import 'package:flutter/material.dart';

import '../../../core/error_text.dart';
import '../../../core/lang.dart';
import '../../../data/models/catalog_hit.dart';
import '../../../data/services/client_service.dart';
import '../../../theme/qoima_design.dart';
import '../client_product_detail.dart';

/// AI табқан тауардың толық карточкасын ашады (дүкен мен тауарды DB-дан
/// алып). Қайтарады: true — қолданушы карточкада «себетке өту» таңдады
/// (ClientProductDetail `pop(true)` келісімі), әйтпесе null/false.
Future<bool?> openCatalogHit(BuildContext context, CatalogHit hit) async {
  final svc = ClientService();
  try {
    final store = await svc.getStoreByAdminUid(hit.adminUid);
    final product = await svc.getProductById(hit.adminUid, hit.productId);
    if (!context.mounted) return null;
    if (store == null || product == null || product.storefrontHidden) {
      aiSnack(context, tr('Товар недоступен', 'Тауар қолжетімсіз'),
          error: true);
      return null;
    }
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ClientProductDetail(product: product, store: store),
      ),
    );
  } catch (e) {
    if (context.mounted) aiSnack(context, friendlyError(e), error: true);
    return null;
  }
}

/// Жүзбелі snackbar (жасыл/қызыл).
void aiSnack(BuildContext context, String msg,
    {bool error = false, SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? cRed : cGreen,
      content: Text(msg),
      action: action,
    ));
}

/// Өлшем таңдау чиптері (стилист пен көмекші ортақ).
class SizeChips extends StatelessWidget {
  final List<String> sizes;
  final String? selected;
  final ValueChanged<String> onSelect;

  const SizeChips({
    super.key,
    required this.sizes,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final s in sizes)
          GestureDetector(
            onTap: () => onSelect(s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: s == selected ? cGreen : cSurface,
                borderRadius: BorderRadius.circular(kR12),
                border: Border.all(color: s == selected ? cGreen : cLine),
              ),
              child: Text(
                s,
                style: manrope(12.5, FontWeight.w700,
                    color: s == selected ? Colors.white : cInk2),
              ),
            ),
          ),
      ],
    );
  }
}
