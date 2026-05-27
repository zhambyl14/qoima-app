import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/warehouse_context.dart';
import '../../data/models/warehouse_model.dart';
import '../../theme/app_theme.dart';

/// Returns false if admin has no current warehouse and user dismissed without picking.
/// Call before any warehouse-dependent action. Resolves immediately if warehouse is already set.
Future<bool> ensureWarehouseSelected(BuildContext context) async {
  if (!context.read<AppUser>().isAdmin) return true;
  final wCtx = context.read<WarehouseContext>();
  if (wCtx.current != null) return true;
  if (wCtx.all.isEmpty) return false;

  final picked = await showModalBottomSheet<WarehouseModel>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _MandatoryWarehousePicker(warehouses: wCtx.all),
  );

  if (picked != null && context.mounted) {
    context.read<WarehouseContext>().switchTo(picked);
    return true;
  }
  return false;
}

class _MandatoryWarehousePicker extends StatelessWidget {
  final List<WarehouseModel> warehouses;
  const _MandatoryWarehousePicker({required this.warehouses});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        const Icon(Icons.warehouse_rounded, color: AppTheme.primary, size: 36),
        const SizedBox(height: 12),
        const Text('Қойманы таңдаңыз',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 4),
        const Text('Жалғастыру үшін қойма таңдаңыз',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        const SizedBox(height: 16),
        ...warehouses.map((wh) => ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.warehouse_outlined,
                color: AppTheme.primary, size: 20),
          ),
          title: Text(wh.name,
              style: const TextStyle(fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
          subtitle: wh.address != null && wh.address!.isNotEmpty
              ? Text(wh.address!,
                  style: const TextStyle(color: AppTheme.textHint, fontSize: 12))
              : null,
          trailing: wh.isMain
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(4)),
                  child: const Text('НЕГ.',
                      style: TextStyle(color: Colors.white, fontSize: 9,
                          fontWeight: FontWeight.w700)))
              : null,
          onTap: () => Navigator.pop(context, wh),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        )),
        const SizedBox(height: 8),
      ]),
    );
  }
}
