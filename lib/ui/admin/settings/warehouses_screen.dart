import 'package:flutter/material.dart';
import '../../../data/models/warehouse_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';

import '../../../core/lang.dart';
class WarehousesScreen extends StatefulWidget {
  const WarehousesScreen({super.key});
  @override
  State<WarehousesScreen> createState() => _WarehousesScreenState();
}

class _WarehousesScreenState extends State<WarehousesScreen> {
  final _service = FirestoreService();
  late Future<int> _stockFuture;

  @override
  void initState() {
    super.initState();
    _stockFuture = _countStock();
  }

  Future<int> _countStock() async {
    try {
      final (batchesMap, _) = await _service.getAllBatchesGrouped();
      int total = 0;
      for (final batches in batchesMap.values) {
        for (final batch in batches) {
          total += batch.totalAvailable;
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: StreamBuilder<List<WarehouseModel>>(
        stream: _service.watchWarehouses(),
        builder: (context, snap) {
          final warehouses = snap.data ?? [];

          return CustomScrollView(slivers: [
            SliverToBoxAdapter(
                child: Container(
              decoration: const BoxDecoration(gradient: kGrad),
              child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
                    child: Row(children: [
                      GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                              width: 38,
                              height: 38,
                              margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(12)),
                              child: const Icon(Icons.chevron_left_rounded,
                                  color: Colors.white, size: 22))),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(tr('Склады', 'Қоймалар'),
                                style: manrope(23, FontWeight.w800,
                                    color: Colors.white, letterSpacing: -0.5)),
                            FutureBuilder<int>(
                              future: _stockFuture,
                              builder: (_, snap) {
                                final total = snap.data;
                                final sub = total != null
                                    ? tr('${warehouses.length} склада · $total шт.', '${warehouses.length} қойма · $total дана')
                                    : tr('${warehouses.length} склада', '${warehouses.length} қойма');
                                return Text(sub,
                                    style: manrope(13, FontWeight.w500,
                                        color: Colors.white.withValues(alpha: 0.78)));
                              },
                            ),
                          ])),
                      GestureDetector(
                          onTap: () => _showAddSheet(context, _service),
                          child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(12)),
                              child: const Icon(Icons.add_rounded,
                                  color: Colors.white, size: 22))),
                    ]),
                  )),
            )),
            if (warehouses.isEmpty)
              SliverFillRemaining(
                  child: Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.warehouse_outlined,
                          size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(tr('Складов нет', 'Қойма жоқ'),
                          style: TextStyle(
                              fontSize: 16,
                              color: cInk2,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      Text(tr('Нажмите «+», чтобы добавить', '+ батырмасын басып қосыңыз'),
                          style: TextStyle(
                              fontSize: 13, color: cInk3)),
                    ]),
              ))
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) =>
                        _WarehouseCard(wh: warehouses[i], service: _service),
                    childCount: warehouses.length,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverToBoxAdapter(
                  child: GestureDetector(
                    onTap: () => _showAddSheet(context, _service),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: cGreenTint,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: cGreen.withValues(alpha: 0.4),
                            width: 1.5,
                            style: BorderStyle.solid),
                      ),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_rounded,
                                color: cGreen, size: 20),
                            const SizedBox(width: 8),
                            Text(tr('Добавить склад', 'Қойма қосу'),
                                style: manrope(14, FontWeight.w700,
                                    color: cGreen)),
                          ]),
                    ),
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }

  void _showAddSheet(BuildContext context, FirestoreService svc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddWarehouseSheet(service: svc),
    );
  }
}

// ── Қойма картасы ─────────────────────────────────────────────────────────────
class _WarehouseCard extends StatelessWidget {
  final WarehouseModel wh;
  final FirestoreService service;
  const _WarehouseCard({required this.wh, required this.service});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cLine),
          boxShadow: kShadowSm),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        leading: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: wh.isMain ? cGreenTint : cBlueTint,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(Icons.storefront_outlined,
                color: wh.isMain ? cGreen : cBlue,
                size: 22)),
        title: Row(children: [
          Expanded(
            child: Text(wh.name,
                style: manrope(15, FontWeight.w700, color: cInk)),
          ),
          if (wh.isMain) ...[
            const SizedBox(width: 8),
            QPill(tr('Главный', 'Негізгі'), tone: 'green'),
          ],
        ]),
        subtitle: wh.address != null && wh.address!.isNotEmpty
            ? Text(wh.address!,
                style: manrope(12.5, FontWeight.w500, color: cInk3))
            : null,
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: cInk3, size: 20),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (val) async {
            if (val == 'delete' && !wh.isMain) {
              // Қадам 1: растау
              final ok1 = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  title: Text(tr('Удалить склад', 'Қойманы жою')),
                  content: Text(
                    tr('Удалить склад «${wh.name}»?\n\n'
                            'Связь товаров с этим складом будет потеряна.',
                        '«${wh.name}» қойманы жоямыз ба?\n\n'
                            'Бұл қоймадағы өнімдердің байланысы жоғалады.'),
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(tr('Отмена', 'Болдырмау'))),
                    ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: cRed,
                            foregroundColor: Colors.white),
                        child: Text(tr('Удалить', 'Жою'))),
                  ],
                ),
              );
              if (ok1 != true || !context.mounted) return;

              // Қадам 2: түпкілікті растау
              final ok2 = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  title: Text(tr('Вы уверены?', 'Сенімдісіз бе?'),
                      style: TextStyle(color: cRed)),
                  content: Text(
                    tr('Это действие нельзя отменить. '
                            'Склад будет удалён безвозвратно.',
                        'Бұл әрекетті болдырмау мүмкін емес. '
                            'Қойма түпкілікті жойылады.'),
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(tr('Отмена', 'Болдырмау'))),
                    ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: cRed,
                            foregroundColor: Colors.white),
                        child: Text(tr('Да, удалить', 'Иә, жою'))),
                  ],
                ),
              );
              if (ok2 == true && context.mounted) {
                await service.deleteWarehouseDeep(wh.id);
              }
            }
          },
          itemBuilder: (_) => [
            if (!wh.isMain)
              PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline,
                        size: 16, color: cRed),
                    SizedBox(width: 8),
                    Text(tr('Удалить', 'Жою'), style: TextStyle(color: cRed)),
                  ])),
          ],
        ),
      ),
    );
  }
}

// ── Қойма қосу bottom sheet ───────────────────────────────────────────────────
class _AddWarehouseSheet extends StatefulWidget {
  final FirestoreService service;
  const _AddWarehouseSheet({required this.service});
  @override
  State<_AddWarehouseSheet> createState() => _AddWarehouseSheetState();
}

class _AddWarehouseSheetState extends State<_AddWarehouseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24),
      child: Form(
        key: _formKey,
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text(tr('Новый склад', 'Жаңа қойма'),
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: cInk)),
              const SizedBox(height: 16),
              _Field(
                  ctrl: _nameCtrl,
                  label: tr('Название склада *', 'Қойма атауы *'),
                  hint: tr('Например: ТРЦ Mega', 'Мысалы: ТРЦ Mega'),
                  icon: Icons.warehouse_outlined),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressCtrl,
                style:
                    const TextStyle(fontSize: 14, color: cInk),
                decoration: InputDecoration(
                  labelText: tr('Адрес *', 'Мекен-жай *'),
                  hintText: tr('Алматы, ул. Абая 10', 'Алматы, Абай к-сі 10'),
                  hintStyle: const TextStyle(color: cInk3),
                  prefixIcon: const Icon(Icons.location_on_outlined,
                      color: cGreen, size: 20),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: cLine)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: cLine)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: cGreen, width: 1.5)),
                  errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: cRed)),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return tr('Адрес обязателен!', 'Мекенжай міндетті!');
                  }
                  if (v.trim().length < 5) return tr('Введите полный адрес', 'Толық мекенжай енгізіңіз');
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _Field(
                  ctrl: _noteCtrl,
                  label: tr('Примечание', 'Ескерту'),
                  hint: tr('Дополнительная информация', 'Қосымша ақпарат'),
                  icon: Icons.notes_rounded),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style:
                        const TextStyle(color: cRed, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: cGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0),
                    onPressed: _loading
                        ? null
                        : () async {
                            if (!(_formKey.currentState?.validate() ?? false)) {
                              return;
                            }
                            final name = _nameCtrl.text.trim();
                            if (name.isEmpty) {
                              setState(() => _error = tr('Введите название', 'Атауын енгізіңіз'));
                              return;
                            }
                            setState(() {
                              _loading = true;
                              _error = null;
                            });
                            try {
                              await widget.service.createWarehouse(
                                name: name,
                                address: _addressCtrl.text.trim(),
                                note: _noteCtrl.text.trim().isEmpty
                                    ? null
                                    : _noteCtrl.text.trim(),
                              );
                              if (context.mounted) Navigator.pop(context);
                            } catch (e) {
                              setState(() {
                                _error = e.toString();
                                _loading = false;
                              });
                            }
                          },
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text(tr('Сохранить', 'Сақтау'),
                            style: TextStyle(fontWeight: FontWeight.w700)),
                  )),
            ]),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint;
  final IconData icon;
  const _Field(
      {required this.ctrl,
      required this.label,
      required this.hint,
      required this.icon});

  @override
  Widget build(BuildContext context) => TextField(
        controller: ctrl,
        style: const TextStyle(fontSize: 14, color: cInk),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: const TextStyle(color: cInk3),
          prefixIcon: Icon(icon, color: cGreen, size: 20),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: cLine)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: cLine)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: cGreen, width: 1.5)),
        ),
      );
}

