import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/lang.dart';
import '../../data/models/promo_model.dart';
import '../../data/models/store_model.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';
import 'store_public_screen.dart';

/// Клиенттің барлық дүкендерден жиналған referral-сыйлықтары (0044) — әр
/// бонус қай дүкенге тиесілі екенін көрсетіп, дүкен бойынша топталады.
class MyBonusesScreen extends StatefulWidget {
  const MyBonusesScreen({super.key});

  @override
  State<MyBonusesScreen> createState() => _MyBonusesScreenState();
}

class _MyBonusesScreenState extends State<MyBonusesScreen> {
  final _service = ClientService();
  bool _loading = true;
  Map<StoreModel, List<PromoModel>> _byStore = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rewards = (await _service.getMyReferralRewards())
          .where((p) => p.value > 0 && p.adminUid.isNotEmpty)
          .toList();
      final adminUids = {for (final r in rewards) r.adminUid}.toList();
      final stores = await _service.getStoresByAdminUids(adminUids);
      final grouped = <StoreModel, List<PromoModel>>{};
      for (final r in rewards) {
        final store = stores[r.adminUid];
        if (store == null) continue; // дүкен жабылған/өшірілген болуы мүмкін
        grouped.putIfAbsent(store, () => []).add(r);
      }
      if (mounted) setState(() { _byStore = grouped; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copy(String code) {
    Clipboard.setData(ClipboardData(text: code));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(tr('Код скопирован', 'Код көшірілді')),
        backgroundColor: cGreen,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final total = _byStore.values.fold<int>(0, (a, l) => a + l.length);
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Мои бонусы', 'Менің бонустарым'),
          subtitle: total == 0
              ? tr('Пока нет бонусов', 'Әзірге бонус жоқ')
              : tr('$total активных промокодов', '$total белсенді промокод'),
          showBack: true,
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: cGreen, strokeWidth: 2))
              : _byStore.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.card_giftcard_outlined,
                                color: cInk3, size: 40),
                            const SizedBox(height: 12),
                            Text(
                                tr(
                                    'Бонусов пока нет — пригласите друга в любом магазине',
                                    'Әзірге бонус жоқ — кез келген дүкенде досыңызды шақырыңыз'),
                                textAlign: TextAlign.center,
                                style:
                                    manrope(13.5, FontWeight.w600, color: cInk3)),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                      children: [
                        for (final entry in _byStore.entries) ...[
                          GestureDetector(
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        StorePublicScreen(store: entry.key))),
                            child: Row(children: [
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: cGreenTint,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: entry.key.logoUrl.isNotEmpty
                                    ? Image.network(entry.key.logoUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(
                                                Icons.storefront_rounded,
                                                color: cGreenDeep, size: 14))
                                    : const Icon(Icons.storefront_rounded,
                                        color: cGreenDeep, size: 14),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(entry.key.storeName,
                                    style: manrope(14.5, FontWeight.w800,
                                        color: cInk),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              const Icon(Icons.chevron_right_rounded,
                                  color: cInk3, size: 18),
                            ]),
                          ),
                          const SizedBox(height: 8),
                          ...entry.value.map((r) => GestureDetector(
                                onTap: () => _copy(r.code),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: cGreenTint,
                                    borderRadius: BorderRadius.circular(15),
                                    border: Border.all(
                                        color: cGreen.withValues(alpha: 0.3)),
                                  ),
                                  child: Row(children: [
                                    const Icon(Icons.card_giftcard_rounded,
                                        color: cGreen, size: 22),
                                    const SizedBox(width: 11),
                                    Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(r.code,
                                                style: manrope(14.5,
                                                    FontWeight.w800,
                                                    color: cGreenDeep)),
                                            Text(
                                                r.isPercent
                                                    ? '−${r.value.toStringAsFixed(0)}%'
                                                    : '−${money(r.value)}',
                                                style: manrope(12,
                                                    FontWeight.w600,
                                                    color: cGreen)),
                                          ]),
                                    ),
                                    const Icon(Icons.copy_rounded,
                                        size: 16, color: cGreen),
                                  ]),
                                ),
                              )),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
        ),
      ]),
    );
  }
}
