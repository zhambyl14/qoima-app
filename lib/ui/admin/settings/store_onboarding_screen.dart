import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/app_user.dart';
import '../../../core/kz_cities.dart';
import '../../../data/models/store_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';

import '../../../core/lang.dart';
class StoreOnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const StoreOnboardingScreen({super.key, required this.onDone});

  @override
  State<StoreOnboardingScreen> createState() => _StoreOnboardingScreenState();
}

class _StoreOnboardingScreenState extends State<StoreOnboardingScreen> {
  final _service = FirestoreService();
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  String? _selectedCity;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _descCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      final name = _nameCtrl.text.trim();
      final store = StoreModel(
        adminUid: context.read<AppUser>().uid,
        storeName: name,
        storeSlug: StoreModel.generateSlug(name),
        logoUrl: '',
        city: _selectedCity ?? '',
        phone: _phoneCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        visibleWarehouseIds: const [],
        isPublished: false,
        createdAt: now,
        updatedAt: now,
      );
      await _service.saveStore(store);
      if (mounted) widget.onDone();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                // ── Icon + title ───────────────────────────────────────────
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                        color: cGreen.withValues(alpha: 0.1),
                        shape: BoxShape.circle),
                    child: const Icon(Icons.storefront_rounded,
                        color: cGreen, size: 36),
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text(tr('Создайте свой магазин', 'Дүкеніңізді жасаңыз'),
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: cInk,
                          letterSpacing: -0.3)),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(tr('Предварительная настройка витрины для покупателей', 'Сатып алушылар үшін витрина алдын ала баптау'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13, color: cInk2)),
                ),
                const SizedBox(height: 32),

                // ── Store name ─────────────────────────────────────────────
                _Label(tr('Название магазина *', 'Дүкен атауы *')),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: tr('Например: Alina Shoes', 'Мысалы: Alina Shoes'),
                    prefixIcon: Icon(Icons.store_outlined),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return tr('Название обязательно', 'Атауы міндетті');
                    if (v.trim().length < 2) return tr('Минимум 2 символа', 'Кем дегенде 2 таңба');
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // ── City ───────────────────────────────────────────────────
                _Label(tr('Город', 'Қала')),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _selectedCity,
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.location_city_outlined),
                    hintText: tr('Выберите город', 'Қаланы таңдаңыз'),
                  ),
                  items: kzCities
                      .map((c) => DropdownMenuItem(value: c, child: Text(trValue(c))))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedCity = v),
                ),
                const SizedBox(height: 16),

                // ── Phone ──────────────────────────────────────────────────
                _Label('Телефон'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    hintText: '87001234567',
                    prefixIcon: Icon(Icons.phone_outlined),
                    prefixText: '+7 ',
                  ),
                ),
                const SizedBox(height: 16),

                // ── Address ────────────────────────────────────────────────
                _Label(tr('Адрес *', 'Мекен-жай *')),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _addressCtrl,
                  decoration: InputDecoration(
                    hintText: tr('Например: Алматы, пр. Абая 52', 'Мысалы: Алматы, Абай д-лы 52'),
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return tr('Адрес обязателен', 'Мекен-жай міндетті');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // ── Description ────────────────────────────────────────────
                _Label(tr('Описание (120 символов)', 'Сипаттама (120 таңба)')),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 3,
                  maxLength: 120,
                  decoration: InputDecoration(
                    hintText: tr('Кратко о магазине...', 'Дүкен туралы қысқаша...'),
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(bottom: 48),
                      child: Icon(Icons.notes_rounded),
                    ),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 24),

                // ── Buttons ────────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _create,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: cGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text(tr('Создать магазин', 'Дүкен жасау'),
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: TextButton(
                    onPressed: _isLoading ? null : widget.onDone,
                    child: Text(tr('Пропустить', 'Өткізіп жіберу'),
                        style: TextStyle(
                            color: cInk2, fontSize: 14)),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: cInk));
}

