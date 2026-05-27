import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/warehouse_context.dart';
import '../../data/models/store_model.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/app_theme.dart';

const List<String> _kzCities = [
  'Алматы', 'Астана', 'Шымкент', 'Қарағанды', 'Атырау',
  'Ақтөбе', 'Тараз', 'Павлодар', 'Өскемен', 'Семей',
  'Ақтау', 'Қостанай', 'Орал', 'Петропавл', 'Қызылорда',
];

class StoreSettingsScreen extends StatefulWidget {
  const StoreSettingsScreen({super.key});

  @override
  State<StoreSettingsScreen> createState() => _StoreSettingsScreenState();
}

class _StoreSettingsScreenState extends State<StoreSettingsScreen> {
  final _service  = FirestoreService();
  final _formKey  = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _descCtrl  = TextEditingController();

  StoreModel? _store;
  String? _selectedCity;
  bool _isPublished = false;
  List<String> _visibleWarehouseIds = [];
  bool _isLoading   = false;
  bool _isDirty     = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = await _service.getStore();
    if (!mounted) return;
    if (store != null) {
      _nameCtrl.text  = store.storeName;
      _phoneCtrl.text = store.phone;
      _descCtrl.text  = store.description;
      setState(() {
        _store               = store;
        _selectedCity        = store.city.isNotEmpty ? store.city : null;
        _isPublished         = store.isPublished;
        _visibleWarehouseIds = List<String>.from(store.visibleWarehouseIds);
      });
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final now  = DateTime.now();
      final name = _nameCtrl.text.trim();
      final updated = StoreModel(
        adminUid:            context.read<AppUser>().uid,
        storeName:           name,
        storeSlug:           StoreModel.generateSlug(name),
        logoUrl:             _store?.logoUrl ?? '',
        city:                _selectedCity ?? '',
        phone:               _phoneCtrl.text.trim(),
        description:         _descCtrl.text.trim(),
        visibleWarehouseIds: _visibleWarehouseIds,
        isPublished:         _isPublished,
        createdAt:           _store?.createdAt ?? now,
        updatedAt:           now,
      );
      await _service.saveStore(updated);
      if (mounted) {
        setState(() { _store = updated; _isDirty = false; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Сақталды'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _markDirty() => setState(() => _isDirty = true);

  @override
  Widget build(BuildContext context) {
    final warehouses = context.watch<WarehouseContext>().all;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Менің дүкенім'),
        actions: [
          if (_isDirty)
            TextButton(
              onPressed: _isLoading ? null : _save,
              child: const Text('Сақтау',
                  style: TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          onChanged: _markDirty,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Section: Мой магазин ───────────────────────────────────
              _SectionHeader('Менің дүкенім'),
              const SizedBox(height: 12),

              _SettingsCard(children: [
                // Store name
                _FieldLabel('Дүкен атауы *'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      hintText: 'Мысалы: Alina Shoes',
                      prefixIcon: Icon(Icons.store_outlined)),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Міндетті';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // City
                _FieldLabel('Қала'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _selectedCity,
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.location_city_outlined),
                      hintText: 'Қаланы таңдаңыз'),
                  items: _kzCities
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    setState(() { _selectedCity = v; _isDirty = true; });
                  },
                ),
                const SizedBox(height: 14),

                // Phone
                _FieldLabel('Телефон *'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                      hintText: '87001234567',
                      prefixIcon: Icon(Icons.phone_outlined),
                      prefixText: '+7 '),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Телефон нөмірін енгізіңіз';
                    if (v.trim().length < 10) return 'Телефон нөмірі дұрыс емес';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Description
                _FieldLabel('Сипаттама (120 таңба)'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 3,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    hintText: 'Дүкен туралы қысқаша...',
                    alignLabelWithHint: true,
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(bottom: 48),
                      child: Icon(Icons.notes_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Published toggle
                Row(children: [
                  const Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Жарияланған',
                          style: TextStyle(fontWeight: FontWeight.w600,
                              fontSize: 14, color: AppTheme.textPrimary)),
                      SizedBox(height: 2),
                      Text('Сатып алушылар дүкенді көреді',
                          style: TextStyle(fontSize: 11,
                              color: AppTheme.textSecondary)),
                    ],
                  )),
                  Switch(
                    value: _isPublished,
                    activeThumbColor: AppTheme.success,
                    onChanged: (v) => setState(() { _isPublished = v; _isDirty = true; }),
                  ),
                ]),
              ]),
              const SizedBox(height: 20),

              // ── Section: Видимость складов ─────────────────────────────
              _SectionHeader('Қойма көрінуі'),
              const SizedBox(height: 6),
              const Text('Сатып алушыларға қандай қоймалардан тауар көрсету керек?',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              const SizedBox(height: 10),

              if (warehouses.isEmpty)
                const _EmptyNote('Қойма жоқ')
              else
                _SettingsCard(
                  children: warehouses.map((wh) {
                    final visible = _visibleWarehouseIds.contains(wh.id);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        const Icon(Icons.warehouse_outlined,
                            color: AppTheme.primary, size: 18),
                        const SizedBox(width: 10),
                        Expanded(child: Text(wh.name,
                            style: const TextStyle(fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textPrimary))),
                        Switch(
                          value: visible,
                          activeThumbColor: AppTheme.primary,
                          onChanged: (v) {
                            setState(() {
                              _isDirty = true;
                              if (v) {
                                _visibleWarehouseIds.add(wh.id);
                              } else {
                                _visibleWarehouseIds.remove(wh.id);
                              }
                            });
                          },
                        ),
                      ]),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 20),

              // ── Section: Preview ───────────────────────────────────────
              _SectionHeader('Сатып алушыларға арналған ақпарат'),
              const SizedBox(height: 10),
              _StorePreviewCard(
                storeName:    _nameCtrl.text.isNotEmpty
                    ? _nameCtrl.text
                    : 'Дүкен атауы',
                city:         _selectedCity ?? '',
                phone:        _phoneCtrl.text,
                description:  _descCtrl.text,
                isPublished:  _isPublished,
              ),
              const SizedBox(height: 32),

              // ── Save button ────────────────────────────────────────────
              if (_isDirty)
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _save,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0),
                    child: _isLoading
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Сақтау',
                            style: TextStyle(fontWeight: FontWeight.w700,
                                fontSize: 15)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Store preview card ─────────────────────────────────────────────────────────
class _StorePreviewCard extends StatelessWidget {
  final String storeName, city, phone, description;
  final bool isPublished;
  const _StorePreviewCard({
    required this.storeName,
    required this.city,
    required this.phone,
    required this.description,
    required this.isPublished,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isPublished
                ? AppTheme.success.withValues(alpha: 0.3)
                : AppTheme.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.storefront_rounded,
                color: AppTheme.primary, size: 26)),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(storeName, style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary)),
              if (city.isNotEmpty)
                Text(city, style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
            ],
          )),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: (isPublished ? AppTheme.success : AppTheme.textHint)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6)),
            child: Text(
              isPublished ? 'Жарияланған' : 'Жарияланбаған',
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  color: isPublished ? AppTheme.success : AppTheme.textHint),
            ),
          ),
        ]),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(description, style: const TextStyle(
              fontSize: 13, color: AppTheme.textSecondary)),
        ],
        if (phone.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.phone_outlined, size: 14,
                color: AppTheme.textHint),
            const SizedBox(width: 4),
            Text('+7 $phone', style: const TextStyle(
                fontSize: 12, color: AppTheme.textSecondary)),
          ]),
        ],
      ]),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary));
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary));
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 10, offset: const Offset(0, 2))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );
}

class _EmptyNote extends StatelessWidget {
  final String text;
  const _EmptyNote(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 13, color: AppTheme.textHint));
}
