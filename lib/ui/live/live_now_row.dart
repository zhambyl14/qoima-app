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
  StreamSubscription<List<LiveSession>>? _sub;
  Timer? _staleTimer;
  List<LiveSession> _all = const [];
  Map<String, StoreModel> _stores = const {};
  Set<String> _hidden = const {};

  @override
  void initState() {
    super.initState();
    // Гостьқа RLS ештеңе қайтармайды — ағынды ашпаймыз да.
    if (Supabase.instance.client.auth.currentUser == null) return;
    _client.getHiddenStoreIds().then((ids) {
      if (mounted) setState(() => _hidden = ids);
    }).catchError((_) {});
    _sub = _live.watchLiveSessions().listen(
      (list) {
        if (!mounted) return;
        setState(() => _all = list);
        _loadStores(list);
      },
      onError: (_) {},
    );
    // heartbeat-і тоқтаған эфирді 30 сек сайын қатардан алып тастау.
    _staleTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _all.isNotEmpty) setState(() {});
    });
  }

  /// Жаңа дүкен пайда болғанда ғана жүктейміз (әр heartbeat-те емес).
  Future<void> _loadStores(List<LiveSession> list) async {
    final missing = list
        .where((s) => s.isLive && !_stores.containsKey(s.adminUid))
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
    _sub?.cancel();
    _staleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: FeatureFlags.instance,
        builder: (_, __) =>
            FeatureFlags.instance.isOn(FeatureFlags.liveShopping)
                ? _buildRow()
                : const SizedBox.shrink(),
      );

  Widget _buildRow() {
    final visible = _all
        .where((s) =>
            s.isFreshLive &&
            !_hidden.contains(s.adminUid) &&
            _stores.containsKey(s.adminUid))
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
