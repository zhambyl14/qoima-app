import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/warehouse_context.dart';
import '../../../data/models/store_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';
import 'ms_widgets.dart';

/// «Витрина қоймалары» — клиентке интернет-дүкенде қай қоймалардан тауар
/// көрсетілетінін баптайды (StoreModel.visibleWarehouseIds).
class AdminStoreVisibilityScreen extends StatefulWidget {
  const AdminStoreVisibilityScreen({super.key});

  @override
  State<AdminStoreVisibilityScreen> createState() =>
      _AdminStoreVisibilityScreenState();
}

class _AdminStoreVisibilityScreenState
    extends State<AdminStoreVisibilityScreen> {
  final _service = FirestoreService();

  StoreModel? _store;
  Set<String> _visible = {};
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;

  // Қойма бойынша нақты бос қалдық (totalAvailable) пен тауар саны.
  Map<String, int> _pairsByWh = {};
  Map<String, int> _productsByWh = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = await _service.getStore();
    try {
      final (batchesMap, _) = await _service.getAllBatchesGrouped();
      final pairs = <String, int>{};
      final prods = <String, Set<String>>{};
      batchesMap.forEach((pid, batches) {
        for (final b in batches) {
          if (b.warehouseId.isEmpty) continue;
          pairs[b.warehouseId] = (pairs[b.warehouseId] ?? 0) + b.totalAvailable;
          if (b.totalAvailable > 0) {
            (prods[b.warehouseId] ??= <String>{}).add(pid);
          }
        }
      });
      _pairsByWh = pairs;
      _productsByWh = {for (final e in prods.entries) e.key: e.value.length};
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _store = store;
      _visible = (store?.visibleWarehouseIds ?? const []).toSet();
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_store == null) return;
    setState(() => _saving = true);
    try {
      await _service.saveStore(_store!.copyWith(
        visibleWarehouseIds: _visible.toList(),
        updatedAt: DateTime.now(),
      ));
      if (mounted) {
        setState(() => _dirty = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Сақталды'),
          backgroundColor: cGreen,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final warehouses = context.watch<WarehouseContext>().all;

    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: 'Витрина қоймалары',
          subtitle: 'Клиентке қай қоймалар көрінеді',
          showBack: true,
          action: _dirty
              ? TextButton(
                  onPressed: _saving ? null : _save,
                  child: Text('Сақтау',
                      style: manrope(14.5, FontWeight.w700, color: Colors.white)),
                )
              : null,
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: cGreen))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                        'Қосулы қоймалардағы тауарлар ғана интернет-дүкенде сатып алушыларға көрсетіледі.',
                        style: manrope(13, FontWeight.w500, color: cInk2)),
                    const SizedBox(height: 14),
                    if (warehouses.isEmpty)
                      QCard(
                        child: Row(children: [
                          const Icon(Icons.warehouse_outlined, color: cInk3, size: 20),
                          const SizedBox(width: 10),
                          Expanded(child: Text('Қойма жоқ',
                              style: manrope(13.5, FontWeight.w600, color: cInk2))),
                        ]),
                      )
                    else
                      ...warehouses.map((wh) {
                        final on = _visible.contains(wh.id);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                          decoration: BoxDecoration(
                            color: cSurface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: on ? cGreen : cLine, width: on ? 1.5 : 1),
                          ),
                          child: Row(children: [
                            QIconTile(
                              icon: Icon(Icons.warehouse_outlined,
                                  color: on ? cGreen : cInk3, size: 20),
                              tone: on ? 'green' : 'ink',
                              size: 42,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(wh.name, style: manrope(14.5, FontWeight.w700, color: cInk)),
                                Text('${_pairsByWh[wh.id] ?? 0} дана · ${_productsByWh[wh.id] ?? 0} тауар',
                                    style: manrope(12, FontWeight.w500, color: cInk3)),
                              ]),
                            ),
                            MSToggle(
                              on: on,
                              onTap: () => setState(() {
                                _dirty = true;
                                if (on) {
                                  _visible.remove(wh.id);
                                } else {
                                  _visible.add(wh.id);
                                }
                              }),
                            ),
                          ]),
                        );
                      }),
                    const SizedBox(height: 24),
                    if (_dirty)
                      QPrimaryButton(label: 'Сақтау', isLoading: _saving, onPressed: _saving ? null : _save),
                  ]),
                ),
        ),
      ]),
    );
  }
}

