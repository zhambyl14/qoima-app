import 'package:flutter/material.dart';
import '../../data/models/warehouse_model.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/app_theme.dart';

class WarehousesScreen extends StatelessWidget {
  const WarehousesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = FirestoreService();
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: StreamBuilder<List<WarehouseModel>>(
        stream: service.watchWarehouses(),
        builder: (context, snap) {
          final warehouses = snap.data ?? [];
          // WarehouseContext is now self-updating via its own Firestore stream
          // subscription (see warehouse_context.dart). No manual refresh needed.

          return CustomScrollView(slivers: [
            SliverToBoxAdapter(
                child: Container(
              decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Color(0xFF1E3A8A), Color(0xFF2D4FB5)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight)),
              child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    child: Row(children: [
                      GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.arrow_back_ios_new,
                                  color: Colors.white, size: 16))),
                      const SizedBox(width: 12),
                      const Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Қоймалар',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700)),
                            Text('Қойма желісін басқару',
                                style: TextStyle(
                                    color: Colors.white60, fontSize: 12)),
                          ])),
                      GestureDetector(
                          onTap: () => _showAddSheet(context, service),
                          child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.add,
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
                      const Text('Қойма жоқ',
                          style: TextStyle(
                              fontSize: 16,
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      const Text('+ батырмасын басып қосыңыз',
                          style: TextStyle(
                              fontSize: 13, color: AppTheme.textHint)),
                    ]),
              ))
            else
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) =>
                        _WarehouseCard(wh: warehouses[i], service: service),
                    childCount: warehouses.length,
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }

  void _showAddSheet(BuildContext context, FirestoreService service) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddWarehouseSheet(service: service),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ]),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: wh.isMain
                  ? AppTheme.primary.withValues(alpha: 0.1)
                  : AppTheme.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.warehouse_rounded,
                color: wh.isMain ? AppTheme.primary : AppTheme.textHint,
                size: 22)),
        title: Row(children: [
          Text(wh.name,
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppTheme.textPrimary)),
          if (wh.isMain) ...[
            const SizedBox(width: 8),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(4)),
                child: const Text('НЕГ.',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700))),
          ],
        ]),
        subtitle: wh.address != null && wh.address!.isNotEmpty
            ? Text(wh.address!,
                style: const TextStyle(color: AppTheme.textHint, fontSize: 12))
            : null,
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: AppTheme.textHint, size: 20),
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
                  title: const Text('Қойманы жою'),
                  content: Text(
                    '«${wh.name}» қойманы жоямыз ба?\n\n'
                    'Бұл қоймадағы өнімдердің байланысы жоғалады.',
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Болдырмау')),
                    ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.danger,
                            foregroundColor: Colors.white),
                        child: const Text('Жою')),
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
                  title: const Text('Сенімдісіз бе?',
                      style: TextStyle(color: AppTheme.danger)),
                  content: const Text(
                    'Бұл әрекетті болдырмау мүмкін емес. '
                    'Қойма түпкілікті жойылады.',
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Болдырмау')),
                    ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.danger,
                            foregroundColor: Colors.white),
                        child: const Text('Иә, жою')),
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
              const PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline,
                        size: 16, color: AppTheme.danger),
                    SizedBox(width: 8),
                    Text('Жою', style: TextStyle(color: AppTheme.danger)),
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
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
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
              const Text('Жаңа қойма',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 16),
              _Field(
                  ctrl: _nameCtrl,
                  label: 'Қойма атауы *',
                  hint: 'Мысалы: ТРЦ Mega',
                  icon: Icons.warehouse_outlined),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressCtrl,
                style:
                    const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Мекен-жай *',
                  hintText: 'Алматы, Абай к-сі 10',
                  hintStyle: const TextStyle(color: AppTheme.textHint),
                  prefixIcon: const Icon(Icons.location_on_outlined,
                      color: AppTheme.primary, size: 20),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: AppTheme.primary, width: 1.5)),
                  errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.danger)),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Мекенжай міндетті!';
                  }
                  if (v.trim().length < 5) return 'Толық мекенжай енгізіңіз';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _Field(
                  ctrl: _noteCtrl,
                  label: 'Ескерту',
                  hint: 'Қосымша ақпарат',
                  icon: Icons.notes_rounded),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style:
                        const TextStyle(color: AppTheme.danger, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
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
                              setState(() => _error = 'Атауын енгізіңіз');
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
                        : const Text('Сақтау',
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
        style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: const TextStyle(color: AppTheme.textHint),
          prefixIcon: Icon(icon, color: AppTheme.primary, size: 20),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppTheme.primary, width: 1.5)),
        ),
      );
}
