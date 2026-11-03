import 'package:flutter/material.dart';

import '../../../core/app_user.dart';
import '../../../core/error_text.dart';
import '../../../core/lang.dart';
import '../../../data/models/story_model.dart';
import '../../../data/services/stories_service.dart';
import '../../../theme/qoima_design.dart';
import '../report_sheet.dart';
import 'story_ring.dart';

/// Бір сторис 5 секунд көрсетіледі.
const kStoryDuration = Duration(seconds: 5);

/// «5 мин назад» / «5 мин бұрын».
String storyAgo(DateTime createdAt, DateTime now) {
  final d = now.difference(createdAt);
  if (d.inMinutes < 1) return tr('только что', 'жаңа ғана');
  if (d.inMinutes < 60) {
    return tr('${d.inMinutes} мин назад', '${d.inMinutes} мин бұрын');
  }
  return tr('${d.inHours} ч назад', '${d.inHours} сағ бұрын');
}

/// Сторисқа шағым батырмасы кімге көрінеді (UGC: App Store 1.2).
///
/// Дүкеннің ӨЗ қызметкеріне (иесі не осы дүкеннің сатушысы) — жоқ: өз
/// сторисіне шағым мағынасыз, сервер де бас тартады (0086 cannot_report_own).
/// Қалғанына — бар; гость басса парақ алдымен кіруді сұрайды.
bool canReportStory({
  required String storeUid,
  required String viewerUid,
  required String viewerOwnerUid,
  required String viewerRole,
}) {
  if (storeUid.isEmpty) return false;
  if (viewerUid.isNotEmpty && viewerUid == storeUid) return false;
  final staffRole = viewerRole == 'admin' || viewerRole == 'seller';
  if (staffRole && viewerOwnerUid.isNotEmpty && viewerOwnerUid == storeUid) {
    return false;
  }
  return true;
}

/// Сторисқа шағым әрекеті (тест өз нұсқасын береді).
typedef StoryReportAction = Future<void> Function(
    BuildContext context, StoryModel story, StoryViewerGroup group);

Future<void> _defaultReport(
        BuildContext context, StoryModel story, StoryViewerGroup group) =>
    showReportSheet(
      context,
      targetType: 'story',
      targetId: story.id,
      // Модератор көретін атау/дүкен/суретті сервер өзі қояды; бұл — парақтың
      // тақырыбы ғана.
      targetName: story.caption.trim().isNotEmpty
          ? story.caption.trim()
          : group.storeName,
      adminUid: group.storeUid,
      storeName: group.storeName,
    );

/// Суретті салу: [onReady] — сурет көрінген (не қате болған) сәтте шақырылады,
/// таймер сонда басталады. Тест желісіз өз нұсқасын береді.
typedef StoryImageBuilder = Widget Function(
    BuildContext context, String url, VoidCallback onReady);

/// Көрсетілетін бір дүкен. [stories] берілсе — дайын тізім (дүкен беті),
/// null болса — ашылғанда `stories_for_store` арқылы жүктеледі (басты бет).
class StoryViewerGroup {
  final String storeUid;
  final String storeName;
  final String logoUrl;
  final List<StoryModel>? stories;
  const StoryViewerGroup({
    required this.storeUid,
    required this.storeName,
    this.logoUrl = '',
    this.stories,
  });
}

/// Толық экранды сторис көрермені (тік). Дүкен ретімен бірінен соң бірі ойнайды.
///
/// Басқару: оң жарты — келесі, сол жарты — алдыңғы, басып ұстау — кідірту,
/// төмен сырғыту — жабу. Сурет жүктелгенше таймер жүрмейді.
/// [showStoreButton] = true болса «Дүкенге өту» шығады және басылғанда экран
/// дүкеннің `storeUid`-імен жабылады (шақырушы дүкенді ашады).
class StoryViewerScreen extends StatefulWidget {
  final List<StoryViewerGroup> groups;
  final int initialGroup;
  final bool showStoreButton;

  /// Тек тест үшін.
  final StoriesService? service;
  final DateTime Function()? now;
  final Duration storyDuration;
  final StoryImageBuilder? imageBuilder;
  final StoryReportAction? onReport;

  const StoryViewerScreen({
    super.key,
    required this.groups,
    this.initialGroup = 0,
    this.showStoreButton = false,
    this.service,
    this.now,
    this.storyDuration = kStoryDuration,
    this.imageBuilder,
    this.onReport,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final StoriesService _svc = widget.service ?? StoriesService();

  int _gi = 0;
  int _si = 0;
  final Map<int, List<StoryModel>> _stories = {};
  bool _loading = true;
  Object? _error;
  bool _paused = false;
  bool _closing = false;
  String _readyId = ''; // суреті көрінген сторис — таймер сонда ғана жүреді
  int _openToken = 0;

  DateTime _now() => (widget.now ?? DateTime.now)();

  List<StoryModel> get _cur => _stories[_gi] ?? const [];
  StoryModel? get _story => _si >= 0 && _si < _cur.length ? _cur[_si] : null;
  StoryViewerGroup get _group => widget.groups[_gi];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.storyDuration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _next();
      });
    if (widget.groups.isEmpty) {
      _closeSoon();
      return;
    }
    // Кадрдан кейін: precacheImage/MediaQuery initState ішінде жарамсыз.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _open(widget.initialGroup.clamp(0, widget.groups.length - 1));
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _closeSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _close());
  }

  void _close([String? storeUid]) {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop(storeUid);
  }

  /// Дүкенді ашу: тізімді алып, мерзімі өткенін тастап, бірінші стористі бастау.
  /// Бос қалса (бәрі өтіп кетсе) — келесі дүкенге не жабу.
  Future<void> _open(int gi, {bool last = false}) async {
    final token = ++_openToken;
    _ctrl.stop();
    setState(() {
      _gi = gi;
      _loading = true;
      _error = null;
    });
    try {
      final g = widget.groups[gi];
      // Жүктелетін топ — клиент жасырған дүкен болса бос (келесіге өтеді).
      final raw = g.stories ?? await _svc.storiesForViewer(g.storeUid);
      if (!mounted || token != _openToken) return;
      final now = _now();
      final list = raw.where((s) => !s.isExpiredAt(now)).toList();
      if (list.isEmpty) {
        _advanceGroup();
        return;
      }
      _stories[gi] = list;
      _si = last ? list.length - 1 : 0;
      _loading = false;
      _begin();
    } catch (e) {
      if (!mounted || token != _openToken) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  void _advanceGroup() {
    if (_gi + 1 < widget.groups.length) {
      _open(_gi + 1);
    } else {
      _close();
    }
  }

  /// Ағымдағы стористі басынан бастау (таймер сурет көрінгенде жүреді).
  void _begin() {
    _ctrl.stop();
    _ctrl.value = 0;
    _readyId = '';
    if (mounted) setState(() {});
    final s = _story;
    if (s == null) return;
    // «Көрілді» белгісі — құрылғыда ғана (дөңгелек сұр болады).
    _svc.markSeen(_group.storeUid, s.createdAt).catchError((_) {});
    // Келесі сурет алдын ала жүктелсін — ауысқанда күтпеу үшін.
    final list = _cur;
    if (_si + 1 < list.length && mounted) {
      precacheImage(NetworkImage(list[_si + 1].imageUrl), context,
              onError: (_, __) {})
          .catchError((_) {});
    }
  }

  void _imageReady(String id) {
    if (id != _story?.id || _readyId == id || !mounted) return;
    _readyId = id;
    if (!_paused) _ctrl.forward(from: 0);
  }

  void _next() {
    if (_closing || _loading) return;
    final list = _cur;
    final now = _now();
    var i = _si + 1;
    while (i < list.length && list[i].isExpiredAt(now)) {
      i++; // экран ұзақ ашық тұрғанда мерзімі өткендерді өткізіп жіберу
    }
    if (i < list.length) {
      _si = i;
      _begin();
    } else {
      _advanceGroup();
    }
  }

  void _prev() {
    if (_closing || _loading) return;
    final list = _cur;
    final now = _now();
    var i = _si - 1;
    while (i >= 0 && list[i].isExpiredAt(now)) {
      i--;
    }
    if (i >= 0) {
      _si = i;
      _begin();
    } else if (_gi > 0) {
      _open(_gi - 1);
    } else {
      _begin(); // ең бірінші сторис — басынан қайта
    }
  }

  void _pause() {
    if (_paused) return;
    _paused = true;
    _ctrl.stop();
  }

  void _resume() {
    if (!_paused) return;
    _paused = false;
    final s = _story;
    if (s == null) return;
    // Кідіртіп қойғанда сторис ескіріп кетуі мүмкін.
    if (s.isExpiredAt(_now())) {
      _next();
      return;
    }
    if (_readyId == s.id) _ctrl.forward();
  }

  /// Ағымдағы қолданушы (тестте AppUser құрылмауы мүмкін → гость).
  static AppUser? _viewer() {
    try {
      return AppUser.current;
    } catch (_) {
      return null;
    }
  }

  bool _canReport(StoryViewerGroup g) {
    final me = _viewer();
    return canReportStory(
      storeUid: g.storeUid,
      viewerUid: me?.uid ?? '',
      viewerOwnerUid: me?.ownerUid ?? '',
      viewerRole: me?.role ?? '',
    );
  }

  /// Шағым: сторис кідіреді, парақ жабылған соң жалғасады.
  Future<void> _report() async {
    final story = _story;
    if (story == null || _closing) return;
    final wasPaused = _paused;
    _pause();
    try {
      await (widget.onReport ?? _defaultReport)(context, story, _group);
    } finally {
      if (mounted && !wasPaused) _resume();
    }
  }

  void _onTapUp(TapUpDetails d, double width) {
    if (d.localPosition.dx < width / 2) {
      _prev();
    } else {
      _next();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, box) => Stack(fit: StackFit.expand, children: [
          if (_error != null)
            _errorView()
          else if (_loading || _story == null)
            const Center(
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
          else
            _content(box.maxWidth),
          // Жабу — ақпарат жолағында (қасындағы жерлерде ештеңе жоқ).
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: IconButton(
                key: const ValueKey('story-close'),
                tooltip: tr('Закрыть', 'Жабу'),
                onPressed: () => _close(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white70, size: 40),
            const SizedBox(height: 12),
            Text(friendlyError(_error),
                textAlign: TextAlign.center,
                style: manrope(14, FontWeight.w600, color: Colors.white)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => _open(_gi),
              child: Text(tr('Повторить', 'Қайталау'),
                  style: manrope(14, FontWeight.w800, color: Colors.white)),
            ),
          ]),
        ),
      );

  Widget _content(double width) {
    final story = _story!;
    final g = _group;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => _onTapUp(d, width),
      onLongPressStart: (_) => _pause(),
      onLongPressEnd: (_) => _resume(),
      onLongPressCancel: _resume,
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 300) _close();
      },
      child: Stack(fit: StackFit.expand, children: [
        KeyedSubtree(
          key: ValueKey(story.id),
          child: (widget.imageBuilder ?? _networkImage)(
              context, story.imageUrl, () => _imageReady(story.id)),
        ),
        // Жоғарғы және астыңғы қараңғы градиент — мәтін оқылсын.
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x99000000),
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0xB3000000),
                ],
                stops: [0, 0.2, 0.65, 1],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 52, 0),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _ProgressBars(count: _cur.length, index: _si, animation: _ctrl),
              const SizedBox(height: 10),
              Row(children: [
                StoreAvatar(size: 34, logoUrl: g.logoUrl),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.storeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: manrope(14, FontWeight.w800,
                              color: Colors.white)),
                      Text(storyAgo(story.createdAt, _now()),
                          style: manrope(11.5, FontWeight.w600,
                              color: Colors.white70)),
                    ],
                  ),
                ),
                if (_canReport(g))
                  IconButton(
                    key: const ValueKey('story-report'),
                    tooltip: tr('Пожаловаться', 'Шағымдану'),
                    onPressed: _report,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.outlined_flag_rounded,
                        color: Colors.white, size: 22),
                  ),
              ]),
            ]),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (story.caption.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text(story.caption.trim(),
                        key: const ValueKey('story-caption'),
                        textAlign: TextAlign.center,
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        style: manrope(15, FontWeight.w600,
                            color: Colors.white, height: 1.35)),
                  ),
                if (widget.showStoreButton)
                  GestureDetector(
                    key: const ValueKey('story-open-store'),
                    onTap: () => _close(g.storeUid),
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(kRPill),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.storefront_rounded,
                            size: 18, color: cGreenDeep),
                        const SizedBox(width: 8),
                        Text(tr('Перейти в магазин', 'Дүкенге өту'),
                            style: manrope(14, FontWeight.w800,
                                color: cGreenDeep)),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

Widget _networkImage(BuildContext context, String url, VoidCallback onReady) =>
    _StoryImage(url: url, onReady: onReady);

/// Үстіндегі сегменттелген прогресс: өткендер толық, ағымдағысы таймермен.
class _ProgressBars extends StatelessWidget {
  final int count;
  final int index;
  final Animation<double> animation;
  const _ProgressBars(
      {required this.count, required this.index, required this.animation});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      for (var i = 0; i < count; i++) ...[
        if (i > 0) const SizedBox(width: 4),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 3,
              child: i == index
                  ? AnimatedBuilder(
                      animation: animation,
                      builder: (_, __) => LinearProgressIndicator(
                        key: const ValueKey('story-progress-current'),
                        value: animation.value,
                        backgroundColor: Colors.white30,
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : LinearProgressIndicator(
                      value: i < index ? 1 : 0,
                      backgroundColor: Colors.white30,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
            ),
          ),
        ),
      ],
    ]);
  }
}

/// Желіден сурет: жүктелу/қате күйлері бар. Бірінші кадр (не қате) шыққанда
/// [onReady] — таймер сонда басталады.
class _StoryImage extends StatelessWidget {
  final String url;
  final VoidCallback onReady;
  const _StoryImage({required this.url, required this.onReady});

  void _ready() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => onReady());

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      gaplessPlayback: false,
      frameBuilder: (_, child, frame, sync) {
        if (frame == null && !sync) {
          return const Center(
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2));
        }
        _ready();
        return child;
      },
      errorBuilder: (_, __, ___) {
        // Қате болса да таймер жүреді — қолданушы келесіге өте алады.
        _ready();
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.broken_image_outlined,
                color: Colors.white54, size: 44),
            const SizedBox(height: 8),
            Text(tr('Не удалось загрузить фото', 'Сурет жүктелмеді'),
                style: manrope(13, FontWeight.w600, color: Colors.white70)),
          ]),
        );
      },
    );
  }
}

/// Дүкен бетінде логотипті басқанда: бір дүкеннің дайын стористерін ашады.
Future<void> openStoriesOf(
  BuildContext context, {
  required String storeUid,
  required String storeName,
  required String logoUrl,
  required List<StoryModel> stories,
  StoriesService? service,
}) async {
  if (stories.isEmpty) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => StoryViewerScreen(
      groups: [
        StoryViewerGroup(
            storeUid: storeUid,
            storeName: storeName,
            logoUrl: logoUrl,
            stories: stories),
      ],
      service: service,
    ),
  ));
}
