import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/feature_flags.dart';
import '../../core/lang.dart';
import '../../data/models/live_models.dart';
import '../../data/services/live_service.dart';
import '../../theme/qoima_design.dart';
import 'live_navigation.dart';
import 'live_widgets.dart';

/// Дүкен бетіндегі «🔴 Қазір эфирде — қосылу» баннері.
/// Дүкен эфирде болмаса — ештеңе көрсетпейді (SizedBox.shrink).
class LiveStoreBanner extends StatefulWidget {
  final String adminUid;
  const LiveStoreBanner({super.key, required this.adminUid});

  @override
  State<LiveStoreBanner> createState() => _LiveStoreBannerState();
}

class _LiveStoreBannerState extends State<LiveStoreBanner>
    with SingleTickerProviderStateMixin {
  StreamSubscription<LiveSession?>? _sub;
  Timer? _staleTimer;
  LiveSession? _session;
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200));

  /// Анимация тек баннер көрініп тұрғанда айналады (бос кадр жемейді).
  void _syncPulse() {
    final visible = _session?.isFreshLive ?? false;
    if (visible && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!visible && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.adminUid.isNotEmpty) {
      _sub = LiveService().watchStoreLive(widget.adminUid).listen(
        (s) {
          if (!mounted) return;
          setState(() => _session = s);
          _syncPulse();
        },
        // Гость / желі қатесі — баннер жай көрінбейді.
        onError: (_) {},
      );
    }
    // heartbeat тоқтаған эфир ағында «live» болып қалуы мүмкін — жиі тексереміз.
    _staleTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || _session == null) return;
      setState(() {});
      _syncPulse();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _staleTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: FeatureFlags.instance,
        builder: (_, __) =>
            FeatureFlags.instance.isOn(FeatureFlags.liveShopping)
                ? _buildBanner()
                : const SizedBox.shrink(),
      );

  Widget _buildBanner() {
    final s = _session;
    if (s == null || !s.isFreshLive) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, child) => Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kR16),
            boxShadow: [
              BoxShadow(
                color: cRed.withValues(alpha: 0.18 + 0.22 * _pulse.value),
                blurRadius: 10 + 8 * _pulse.value,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(kR16),
            onTap: () {
              HapticFeedback.selectionClick();
              openLiveSession(context, s.id);
            },
            child: Ink(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFF4D5E), cRed, Color(0xFFD81B3C)]),
                borderRadius: BorderRadius.circular(kR16),
              ),
              child: Row(children: [
                const LiveBadge(),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          tr('Сейчас в эфире — присоединиться',
                              'Қазір эфирде — қосылу'),
                          style: manrope(14, FontWeight.w800,
                              color: Colors.white)),
                      const SizedBox(height: 2),
                      Text(
                        s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: manrope(12, FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.9)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.visibility_rounded,
                      size: 14, color: Colors.white),
                  const SizedBox(width: 3),
                  Text('${s.viewerCount}',
                      style: manrope(12, FontWeight.w700, color: Colors.white)),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded,
                      color: Colors.white, size: 22),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
