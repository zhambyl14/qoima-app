import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_user.dart';
import '../../core/feature_flags.dart';
import '../../core/lang.dart';
import '../../data/models/live_models.dart';
import '../../data/models/store_model.dart';
import '../../data/services/client_service.dart';
import '../../data/services/follow_service.dart';
import '../../data/services/live_service.dart';
import '../../theme/qoima_design.dart';
import 'live_all_screen.dart';
import 'live_stream_card.dart';
import 'live_widgets.dart';

/// Басты беттегі «Қазір эфирде» көлденең қатары.
/// Тірі эфир жоқ болса (не гость — RLS бермейді) ештеңе көрсетпейді.
///
/// 0084: жалауша `store_follow` қосулы болса — басты бетте ТЕК жазылған
/// дүкендердің эфирі («Жазылған дүкендердің эфирі»); қалғаны бөлек «Барлық
/// эфирлер» бетінде. Жалауша өшік болса — бұрынғы мінез (барлық эфир) өзгеріссіз.
class LiveNowRow extends StatefulWidget {
  /// Тек тест үшін.
  final FollowService? follow;
  final LiveService? live;
  const LiveNowRow({super.key, this.follow, this.live});

  @override
  State<LiveNowRow> createState() => _LiveNowRowState();
}

class _LiveNowRowState extends State<LiveNowRow> {
  late final LiveService _live = widget.live ?? LiveService();
  FollowService get _follow => widget.follow ?? FollowService.instance;
  final _client = ClientService();
  Timer? _pollTimer;
  bool _polling = false;
  List<LiveSession> _all = const [];
  Map<String, StoreModel> _stores = const {};
  List<HomeLiveSession> _home = const [];
  bool _lastFollowMode = false;
  Set<String> _hidden = const {};

  bool get _flagOn => FeatureFlags.instance.isOn(FeatureFlags.liveShopping);
  bool get _followMode => FeatureFlags.instance.isOn(FeatureFlags.storeFollow);

  @override
  void initState() {
    super.initState();
    // Гостьқа RLS ештеңе қайтармайды — сұраныс жасамаймыз да.
    if (Supabase.instance.client.auth.currentUser == null &&
        AppUser.current.uid.isEmpty) {
      return;
    }
    // Функция өшік болса ешқандай сұраныс жоқ; қосылғанда (flag өзгергенде) басталады.
    FeatureFlags.instance.addListener(_syncPolling);
    ClientService.hiddenStoresVersion.addListener(_loadHidden);
    _syncPolling();
  }

  /// Жалауша қосулы болса ғана 30 с сайын polling; өшсе тоқтап, қатар жасырылады.
  void _syncPolling() {
    if (!mounted) return;
    if (_flagOn) {
      // Жазылу жалаушасы ауысса дереккөз де ауысады — бірден қайта оқимыз.
      if (_followMode != _lastFollowMode && _pollTimer != null) _poll();
      _lastFollowMode = _followMode;
      if (_pollTimer == null) {
        _loadHidden();
        _poll();
        _pollTimer =
            Timer.periodic(const Duration(seconds: 30), (_) => _poll());
      }
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  Future<void> _loadHidden() async {
    try {
      final ids = await _client.getHiddenStoreIds();
      if (mounted) setState(() => _hidden = ids);
    } catch (_) {}
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      if (_followMode) {
        // followed белгісі эфирдің өзімен келеді — жазылу тізімі бөлек керек емес.
        final list = await _follow.liveSessionsForHome();
        if (!mounted) return;
        setState(() => _home = list);
      } else {
        final list = await _live.getLiveSessions();
        if (!mounted) return;
        setState(() => _all = list);
        await _loadStores(list);
      }
    } catch (_) {
      // Желі қатесі — келесі тактіде қайталаймыз.
    } finally {
      _polling = false;
    }
  }

  /// Жаңа дүкен пайда болғанда ғана жүктейміз (әр polling-те емес).
  Future<void> _loadStores(List<LiveSession> list) async {
    final missing = list
        .where((s) => !_stores.containsKey(s.adminUid))
        .map((s) => s.adminUid)
        .toSet()
        .toList();
    if (missing.isEmpty) return;
    try {
      final got = await _client.getStoresByAdminUids(missing);
      if (mounted) setState(() => _stores = {..._stores, ...got});
    } catch (_) {}
  }

  @override
  void dispose() {
    FeatureFlags.instance.removeListener(_syncPolling);
    ClientService.hiddenStoresVersion.removeListener(_loadHidden);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: FeatureFlags.instance,
        builder: (_, __) => _flagOn ? _buildRow() : const SizedBox.shrink(),
      );

  Widget _buildRow() {
    if (_followMode) return _buildFollowedRow();
    final visible = _all
        .where((s) =>
            !_hidden.contains(s.adminUid) && _stores.containsKey(s.adminUid))
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return _section(
      title: tr('Сейчас в эфире', 'Қазір эфирде'),
      cards: [
        for (final s in visible)
          LiveStreamCard(
            session: s,
            storeName: _stores[s.adminUid]!.storeName,
            fallbackImage: _stores[s.adminUid]!.logoUrl,
          ),
      ],
    );
  }

  /// Тек жазылған дүкендер (сервер оларды алдымен береді). Жазылған жоқ болса
  /// бөлім мүлде жоқ — «Барлық эфирлер» кіру нүктесі басты бет тақырыбында.
  Widget _buildFollowedRow() {
    final visible = _home
        .where((h) => h.followed && !_hidden.contains(h.session.adminUid))
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return _section(
      title: tr('Эфиры ваших магазинов', 'Жазылған дүкендердің эфирі'),
      showAll: true,
      cards: [
        for (final h in visible)
          LiveStreamCard(
            session: h.session,
            storeName: h.storeName,
            fallbackImage: h.storeLogoUrl,
          ),
      ],
    );
  }

  Widget _section(
      {required String title,
      required List<Widget> cards,
      bool showAll = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const LiveBadge(compact: true),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: manrope(16, FontWeight.w800, color: cInk)),
              ),
              if (showAll)
                GestureDetector(
                  key: const ValueKey('live-all-link'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => LiveAllScreen(follow: widget.follow))),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(tr('Все эфиры', 'Барлық эфирлер'),
                          style:
                              manrope(12.5, FontWeight.w700, color: cGreen)),
                      const Icon(Icons.chevron_right_rounded,
                          size: 18, color: cGreen),
                    ]),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 186,
            child: ListView.separated(
              key: const ValueKey('live-row'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: cards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => cards[i],
            ),
          ),
        ],
      ),
    );
  }
}
