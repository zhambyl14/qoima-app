import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/lang.dart';
import '../../data/models/promo_model.dart';
import '../../data/models/store_model.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';
import 'store_public_screen.dart';

/// «Промо» бөліміндегі «Менің промокодтарым» табы: клиенттің барлық
/// дүкендерден жиналған referral-сыйлықтары (0044), дүкен бойынша топталған.
///
/// Бұрын жеке экран (MyBonusesScreen) еді — енді PromoScreen ішіндегі таб,
/// себебі «бонус» пен «досыңды шақыру» бір-бірінің жалғасы: шақырасың →
/// бонус аласың. Оларды екі бөлек жерде іздеу түсініксіз болатын.
class BonusesTab extends StatefulWidget {
  const BonusesTab({super.key});

  @override
  State<BonusesTab> createState() => _BonusesTabState();
}

class _BonusesTabState extends State<BonusesTab>
    with AutomaticKeepAliveClientMixin {
  final _service = ClientService();
  bool _loading = true;
  Map<StoreModel, List<PromoModel>> _byStore = {};

  @override
  bool get wantKeepAlive => true;

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
      if (mounted) {
        setState(() {
          _byStore = grouped;
          _loading = false;
        });
      }
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
    super.build(context);
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: cGreen, strokeWidth: 2));
    }
    if (_byStore.isEmpty) {
      return RefreshIndicator(
        color: cGreen,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(32, 60, 32, 32),
          children: [
            const Icon(Icons.card_giftcard_outlined, color: cInk3, size: 40),
            const SizedBox(height: 12),
            Text(
                tr('Бонусов пока нет — пригласите друга в магазин, где вы уже покупали',
                    'Әзірге бонус жоқ — өзіңіз сатып алған дүкенге досыңызды шақырыңыз'),
                textAlign: TextAlign.center,
                style: manrope(13.5, FontWeight.w600, color: cInk3)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: cGreen,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          for (final entry in _byStore.entries) ...[
            GestureDetector(
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => StorePublicScreen(store: entry.key))),
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
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.storefront_rounded,
                              color: cGreenDeep,
                              size: 14))
                      : const Icon(Icons.storefront_rounded,
                          color: cGreenDeep, size: 14),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(entry.key.storeName,
                      style: manrope(14.5, FontWeight.w800, color: cInk),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const Icon(Icons.chevron_right_rounded, color: cInk3, size: 18),
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
                      border:
                          Border.all(color: cGreen.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.card_giftcard_rounded,
                          color: cGreen, size: 22),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.code,
                                  style: manrope(14.5, FontWeight.w800,
                                      color: cGreenDeep)),
                              Text(
                                  r.isPercent
                                      ? '−${r.value.toStringAsFixed(0)}%'
                                      : '−${money(r.value)}',
                                  style: manrope(12, FontWeight.w600,
                                      color: cGreen)),
                            ]),
                      ),
                      const Icon(Icons.copy_rounded, size: 16, color: cGreen),
                    ]),
                  ),
                )),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
