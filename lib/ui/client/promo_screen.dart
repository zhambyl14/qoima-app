import 'package:flutter/material.dart';
import '../../core/lang.dart';
import '../../data/models/store_model.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';
import 'my_bonuses_screen.dart';
import 'referral_screen.dart';

/// «Промо» — клиенттің жеңілдіктер орталығы. Екі таб:
///   · Менің промокодтарым — жиналған referral-сыйлықтар (0044)
///   · Досыңды шақыр      — өзім САТЫП АЛҒАН дүкендер тізімі (0049)
///
/// НЕГЕ ОСЫ ЖЕРДЕ: бұрын «Досыңды шақыр» тек дүкен бетінің ішінде тұратын —
/// клиент оны іздеп табуы керек еді. Әрі кез келген дүкеннің кодын алуға
/// болатын: сол дүкеннен бір рет те зат алмаған адам оның жеңілдігін
/// таратып, өзі бонус алатын — әділетсіз әрі дүкенге зиян. Енді тізімде
/// клиент шынымен сатып алған дүкендер ғана тұрады (сервер де тексереді).
class PromoScreen extends StatefulWidget {
  /// 0 — бонустар, 1 — досыңды шақыр.
  final int initialTab;
  const PromoScreen({super.key, this.initialTab = 0});

  @override
  State<PromoScreen> createState() => _PromoScreenState();
}

class _PromoScreenState extends State<PromoScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 2, vsync: this, initialIndex: widget.initialTab);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: cBg,
        body: Column(children: [
          QGradientHeader(
            title: tr('Промо', 'Промо'),
            subtitle: tr('Бонусы и приглашения', 'Бонустар мен шақырулар'),
            showBack: true,
            bottom: [
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TabBar(
                  controller: _tabs,
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  labelColor: cGreenDeep,
                  unselectedLabelColor: Colors.white,
                  labelStyle: manrope(13, FontWeight.w800),
                  unselectedLabelStyle: manrope(13, FontWeight.w700),
                  tabs: [
                    Tab(height: 36, text: tr('Мои промокоды', 'Промокодтарым')),
                    Tab(height: 36, text: tr('Пригласить', 'Досыңды шақыр')),
                  ],
                ),
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [BonusesTab(), _InviteTab()],
            ),
          ),
        ]),
      );
}

// ── «Досыңды шақыр» табы ──────────────────────────────────────────────────────
class _InviteTab extends StatefulWidget {
  const _InviteTab();

  @override
  State<_InviteTab> createState() => _InviteTabState();
}

class _InviteTabState extends State<_InviteTab>
    with AutomaticKeepAliveClientMixin {
  final _service = ClientService();
  bool _loading = true;
  List<({StoreModel store, int percent})> _stores = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final percents = await _service.getMyReferralStores();
      final stores = await _service.getStoresByAdminUids(percents.keys.toList());
      final list = <({StoreModel store, int percent})>[];
      percents.forEach((uid, pct) {
        final s = stores[uid];
        if (s != null) list.add((store: s, percent: pct));
      });
      list.sort((a, b) => b.percent.compareTo(a.percent));
      if (mounted) {
        setState(() {
          _stores = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: cGreen, strokeWidth: 2));
    }
    return RefreshIndicator(
      color: cGreen,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cGreenTint,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cGreen.withValues(alpha: 0.28)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.volunteer_activism_rounded,
                  color: cGreenDeep, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr('Приглашать можно в магазины, где вы уже покупали — вы знаете их и рекомендуете честно.',
                      'Өзіңіз сатып алған дүкенге ғана шақыра аласыз — оны білесіз, сондықтан адал ұсынасыз.'),
                  style: manrope(12.5, FontWeight.w600,
                      color: cGreenDeep, height: 1.4),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          if (_stores.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 0),
              child: Column(children: [
                const Icon(Icons.storefront_outlined, color: cInk3, size: 40),
                const SizedBox(height: 12),
                Text(
                    tr('Пока нечего предложить друзьям. Сделайте первый заказ — и магазин появится здесь.',
                        'Досыңызға ұсынатын дүкен әзірге жоқ. Бірінші тапсырысыңызды жасаңыз — дүкен осында шығады.'),
                    textAlign: TextAlign.center,
                    style: manrope(13.5, FontWeight.w600, color: cInk3)),
              ]),
            )
          else ...[
            QSecLabel(tr('Ваши магазины', 'Сіздің дүкендер')),
            const SizedBox(height: 8),
            ..._stores.map((e) => _StoreInviteCard(
                  store: e.store,
                  percent: e.percent,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ReferralScreen(store: e.store))),
                )),
          ],
        ],
      ),
    );
  }
}

class _StoreInviteCard extends StatelessWidget {
  final StoreModel store;
  final int percent;
  final VoidCallback onTap;
  const _StoreInviteCard({
    required this.store,
    required this.percent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cLine),
            boxShadow: kShadowSm,
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cGreenTint,
                borderRadius: BorderRadius.circular(13),
              ),
              clipBehavior: Clip.antiAlias,
              child: store.logoUrl.isNotEmpty
                  ? Image.network(store.logoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.storefront_rounded,
                          color: cGreenDeep,
                          size: 20))
                  : const Icon(Icons.storefront_rounded,
                      color: cGreenDeep, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(store.storeName,
                        style: manrope(14.5, FontWeight.w800, color: cInk),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    QPill(tr('Другу и вам −$percent%', 'Досыңа да, саған да −$percent%'),
                        tone: 'green'),
                  ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: cInk3, size: 20),
          ]),
        ),
      );
}
