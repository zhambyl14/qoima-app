import 'package:flutter/material.dart';
import '../../core/lang.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';

/// Жасырылған дүкендерді басқару (Профиль → Скрытые магазины).
///
/// App Store Guideline 1.2 — блоктың қайтымды болуы: клиент кез келген
/// уақытта дүкенді қайта аша алады.
class HiddenStoresScreen extends StatefulWidget {
  const HiddenStoresScreen({super.key});

  @override
  State<HiddenStoresScreen> createState() => _HiddenStoresScreenState();
}

class _HiddenStoresScreenState extends State<HiddenStoresScreen> {
  final _service = ClientService();
  List<Map<String, dynamic>> _stores = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final stores = await _service.getHiddenStores();
      if (mounted) {
        setState(() {
          _stores = stores;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unhide(Map<String, dynamic> s) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.unhideStore(s['adminUid'] as String? ?? '');
      if (!mounted) return;
      setState(() => _stores.remove(s));
      messenger.showSnackBar(SnackBar(
        content: Text(tr('Магазин снова виден', 'Дүкен қайта көрінеді')),
        backgroundColor: cGreen,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: Text(tr('Не удалось выполнить действие', 'Әрекет орындалмады')),
        backgroundColor: cRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          // ── Header ─────────────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(gradient: kGrad),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 20, 16),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 38,
                    height: 38,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.chevron_left_rounded,
                        color: Colors.white, size: 24),
                  ),
                ),
                Expanded(
                  child: Text(tr('Скрытые магазины', 'Жасырылған дүкендер'),
                      style: manrope(20, FontWeight.w800,
                          color: Colors.white, letterSpacing: -0.4)),
                ),
              ]),
            ),
          ),

          // ── Body ───────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: cGreen, strokeWidth: 2))
                : _stores.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.visibility_outlined,
                                size: 56, color: cInk3),
                            const SizedBox(height: 12),
                            Text(
                                tr('Нет скрытых магазинов',
                                    'Жасырылған дүкендер жоқ'),
                                style: manrope(15, FontWeight.w600,
                                    color: cInk2)),
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 40),
                              child: Text(
                                tr('Скрыть магазин можно на его странице (⋮ → Скрыть магазин)',
                                    'Дүкенді оның парақшасында жасыруға болады (⋮ → Дүкенді жасыру)'),
                                textAlign: TextAlign.center,
                                style: manrope(12.5, FontWeight.w500,
                                    color: cInk3),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                        itemCount: _stores.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final s = _stores[i];
                          final name =
                              (s['storeName'] as String?)?.trim() ?? '';
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 15, vertical: 13),
                            decoration: BoxDecoration(
                              color: cSurface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: cLine),
                            ),
                            child: Row(children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: cLine2,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                    Icons.visibility_off_outlined,
                                    color: cInk2,
                                    size: 20),
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Text(
                                    name.isEmpty
                                        ? tr('Магазин', 'Дүкен')
                                        : name,
                                    style: manrope(14.5, FontWeight.w700,
                                        color: cInk)),
                              ),
                              TextButton(
                                onPressed: () => _unhide(s),
                                child: Text(tr('Показать', 'Көрсету'),
                                    style: manrope(13.5, FontWeight.w700,
                                        color: cGreen)),
                              ),
                            ]),
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}
