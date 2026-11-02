import 'package:flutter/material.dart';

import '../../../core/app_user.dart';
import '../../../core/feature_flags.dart';
import '../../../data/models/story_model.dart';
import '../../../data/services/client_service.dart';
import '../../../data/services/follow_service.dart';
import '../../../data/services/stories_service.dart';
import '../../../theme/qoima_design.dart';
import '../store_public_screen.dart';
import 'story_ring.dart';
import 'story_viewer_screen.dart';

/// Басты беттегі сторис жолағы: жазылған дүкендердің белсенді стористері.
/// Көрілмегені алдымен (жасыл шеңбер), көрілгені сұр. Жалауша `stories`
/// өшік болса, гость болса не сторис жоқ болса — ештеңе көрсетпейді.
class StoriesStrip extends StatefulWidget {
  /// Тек тест үшін.
  final StoriesService? service;
  final FollowService? follow;
  const StoriesStrip({super.key, this.service, this.follow});

  @override
  State<StoriesStrip> createState() => _StoriesStripState();
}

class _StoriesStripState extends State<StoriesStrip> {
  late final StoriesService _svc = widget.service ?? StoriesService();
  FollowService get _follow => widget.follow ?? FollowService.instance;

  List<StoryStoreGroup> _groups = const [];
  Map<String, DateTime> _seen = const {};
  String _followKey = '';
  bool _loading = false;
  bool _again = false;

  bool get _flagOn => FeatureFlags.instance.isOn(FeatureFlags.stories);

  @override
  void initState() {
    super.initState();
    FeatureFlags.instance.addListener(_maybeLoad);
    _follow.addListener(_onFollowChanged);
    ClientService.hiddenStoresVersion.addListener(_reload);
    if (AppUser.current.uid.isNotEmpty) {
      // Жазылулар басты беттің басқа бөліктерімен бір кэшті бөліседі.
      _follow.loadMyFollows().catchError((_) {});
    }
    _maybeLoad();
  }

  @override
  void dispose() {
    FeatureFlags.instance.removeListener(_maybeLoad);
    _follow.removeListener(_onFollowChanged);
    ClientService.hiddenStoresVersion.removeListener(_reload);
    super.dispose();
  }

  void _onFollowChanged() {
    final key = (_follow.followedUids.toList()..sort()).join(',');
    if (key == _followKey) return; // тек notify ауысқанда қайта сұрамаймыз
    _followKey = key;
    _reload();
  }

  void _maybeLoad() {
    if (_flagOn && _groups.isEmpty) _reload();
  }

  Future<void> _reload() async {
    // Гостьта жазылу жоқ — сервер бос қайтарады, сұрамаймыз да.
    if (!mounted || !_flagOn || AppUser.current.uid.isEmpty) return;
    if (_loading) {
      _again = true; // жүктеу кезінде жазылу өзгерсе — біткен соң қайталаймыз
      return;
    }
    _loading = true;
    try {
      final got = await _svc.storiesForFollowed();
      var hidden = const <String>{};
      try {
        hidden = await ClientService().getHiddenStoreIds();
      } catch (_) {}
      final groups = got.where((g) => !hidden.contains(g.storeUid)).toList();
      final seen = await _svc.seenUntilMany(groups.map((g) => g.storeUid));
      if (!mounted) return;
      setState(() {
        _seen = seen;
        _groups = _sorted(groups, seen);
      });
    } catch (_) {
      // Желі қатесі — жолақ жай көрінбейді, басты бет бұзылмайды.
    } finally {
      _loading = false;
      if (_again) {
        _again = false;
        _reload();
      }
    }
  }

  List<StoryStoreGroup> _sorted(
      List<StoryStoreGroup> groups, Map<String, DateTime> seen) {
    final list = List.of(groups);
    // Көрілмегені алдымен; әрқайсысында жаңасы алдымен (тұрақты сұрыптау).
    list.sort((a, b) {
      final ua = a.hasUnseen(seen[a.storeUid]) ? 0 : 1;
      final ub = b.hasUnseen(seen[b.storeUid]) ? 0 : 1;
      if (ua != ub) return ua - ub;
      return b.latestAt.compareTo(a.latestAt);
    });
    return list;
  }

  Future<void> _open(int index) async {
    final groups = _groups;
    final openStore = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryViewerScreen(
          groups: [
            for (final g in groups)
              StoryViewerGroup(
                  storeUid: g.storeUid,
                  storeName: g.storeName,
                  logoUrl: g.logoUrl),
          ],
          initialGroup: index,
          showStoreButton: true,
          service: widget.service,
        ),
      ),
    );
    if (!mounted) return;
    // Көрілген дүкендер сұрланады, ал жаңа сторис пайда болған болса — оқимыз.
    await _reload();
    if (openStore != null && openStore.isNotEmpty && mounted) {
      final store = await ClientService().getStoreByAdminUid(openStore);
      if (!mounted || store == null || !store.isPublished || store.isBlocked) {
        return;
      }
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => StorePublicScreen(store: store)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FeatureFlags.instance,
      builder: (_, __) {
        if (!_flagOn || _groups.isEmpty || AppUser.current.uid.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: SizedBox(
            height: 98,
            child: ListView.separated(
              key: const ValueKey('stories-strip'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _groups.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final g = _groups[i];
                return GestureDetector(
                  key: ValueKey('story-${g.storeUid}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _open(i),
                  child: SizedBox(
                    width: 68,
                    child: Column(children: [
                      StoryRing(
                        size: 56,
                        logoUrl: g.logoUrl,
                        unseen: g.hasUnseen(_seen[g.storeUid]),
                      ),
                      const SizedBox(height: 5),
                      Text(g.storeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: manrope(11.5, FontWeight.w600,
                              color: g.hasUnseen(_seen[g.storeUid])
                                  ? cInk
                                  : cInk3)),
                    ]),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
