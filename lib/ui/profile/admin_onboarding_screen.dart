import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/warehouse_context.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/app_theme.dart';

class AdminOnboardingScreen extends StatefulWidget {
  const AdminOnboardingScreen({super.key});
  @override
  State<AdminOnboardingScreen> createState() => _AdminOnboardingScreenState();
}

class _AdminOnboardingScreenState extends State<AdminOnboardingScreen> {
  final _nameCtrl    = TextEditingController();
  final _addressCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; });
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() { _loading = false; _error = 'Қойма атауын енгізіңіз'; });
      return;
    }
    try {
      final service = FirestoreService();
      await service.createWarehouse(
        name:    name,
        address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        isMain:  true,
      );
      if (mounted) {
        await context.read<WarehouseContext>().reload();
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Spacer(),

            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.warehouse_rounded,
                  color: AppTheme.primary, size: 40),
            ),
            const SizedBox(height: 24),
            const Text('Қошқелдіңіз! 🎉',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            const Text(
              'Бастау үшін алғашқы қоймаңызды жасаңыз',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: AppTheme.textSecondary),
            ),

            const Spacer(),

            // Қойма атауы
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'Қойма атауы',
                hintText: 'Мысалы: Негізгі қойма',
                prefixIcon: const Icon(Icons.warehouse_outlined,
                    color: AppTheme.primary, size: 20),
                filled: true, fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
              ),
            ),
            const SizedBox(height: 12),

            // Мекенжай
            TextField(
              controller: _addressCtrl,
              style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'Мекенжай (міндетті емес)',
                hintText: 'Алматы, Абай к-сі 10',
                prefixIcon: const Icon(Icons.location_on_outlined,
                    color: AppTheme.primary, size: 20),
                filled: true, fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppTheme.dangerLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3))),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: AppTheme.danger, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!,
                      style: const TextStyle(color: AppTheme.danger, fontSize: 13))),
                ]),
              ),
            ],

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _create,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Қойма жасау',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }
}
