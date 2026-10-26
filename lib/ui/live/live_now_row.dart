import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/feature_flags.dart';
import '../../core/lang.dart';
import '../../data/models/live_models.dart';
import '../../data/models/store_model.dart';
import '../../data/services/client_service.dart';
import '../../data/services/live_service.dart';
import '../../theme/qoima_design.dart';
import 'live_navigation.dart';
import 'live_widgets.dart';

/// Басты беттегі «Қазір эфирде» көлденең қатары.
/// Тірі эфир жоқ болса (не гость — RLS бермейді) ештеңе көрсетпейді.
class LiveNowRow extends StatefulWidget {
  const LiveNowRow({super.key});

  @override
  State<LiveNowRow> createState() => _LiveNowRowState();
}

class _LiveNowRowState extends State<LiveNowRow> {
  final _live = LiveService();
  final _client = ClientService();
  Timer? _pollTimer;
  bool _polling = false;
  List<LiveSession> _all = const [];
  Map<String, StoreModel> _stores = const {};
  Set<String> _hidden = const {};

  bool get _flagOn => FeatureFlags.instance.isOn(FeatureFlags.liveShopping);

  @override
  void initState() {
    super.initState();
    // Гостьқа RLS ештеңе қайтармайды — сұраныс жасамаймыз да.
    if (Supabase.instance.client.auth.currentUser == null) return;
    // Функция өшік болса ешқандай сұраныс жоқ; қосылғанда (flag өзгергенде) басталады.
    FeatureFlags.instance.addListener(_syncPolling);
    ClientService.hiddenStoresVersion.addListener(_loadHidden);
    _syncPolling();
  }

  /// Жалауша қосулы болса ғана 30 с сайын polling; өшсе тоқтап, қатар жасырылады.
  void _syncPolling() {
    if (!mounted) return;
    if (_flagOn) {
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
      final list = await _live.getLiveSessions();
      if (!mounted) return;
      setState(() => _all = list);
      await _loadStores(list);
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
    final visible = _all
        .where((s) =>
            !_hidden.contains(s.adminUid) && _stores.containsKey(s.adminUid))
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();
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
              Text(tr('Сейчас в эфире', 'Қазір эфирде'),
                  style: manrope(16, FontWeight.w800, color: cInk)),
            ]),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 186,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: visible.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final s = visible[i];
                return _LiveCard(session: s, store: _stores[s.adminUid]!);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveCard extends StatelessWidget {
  final LiveSession session;
  final StoreModel store;
  const _LiveCard({required this.session, required this.store});

  @override
  Widget build(BuildContext context) {
    final img = session.coverUrl.isNotEmpty ? session.coverUrl : store.logoUrl;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        openLiveSession(context, session.id);
      },
      child: Container(
        width: 132,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kR16),
          gradient: kGrad,
          boxShadow: kShadowSm,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          if (img.isNotEmpty)
            Image.network(
              img,
              fit: BoxFit.cover,
              cacheWidth: 300,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          // Мәтін оқылсын деп астына қараңғы градиент.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x33000000),
                  Color(0x00000000),
                  Color(0xB3000000)
                ],
                stops: [0, 0.4, 1],
              ),
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Row(children: [
              const LiveBadge(compact: true),
              const Spacer(),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.visibility_rounded,
                    size: 12, color: Colors.white),
                const SizedBox(width: 3),
                Text('${session.viewerCount}',
                    style: manrope(11, FontWeight.w700, color: Colors.white)),
              ]),
            ]),
          ),
          Positioned(
            left: 9,
            right: 9,
            bottom: 9,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: manrope(12.5, FontWeight.w800,
                      color: Colors.white, height: 1.2),
                ),
                const SizedBox(height: 3),
                Text(
                  store.storeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: manrope(11, FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
