import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  Timer? _pollTimer;
  bool _polling = false;
  LiveSession? _session;
  // initState-те жасалады: lazy болса, гост/өшік жағдайда dispose() ішінде
  // (деактивацияланған элементте) тикер жасалып, debug-та қате шығатын.
  late final AnimationController _pulse;

  bool get _flagOn => FeatureFlags.instance.isOn(FeatureFlags.liveShopping);

  /// Анимация тек баннер көрініп тұрғанда айналады (бос кадр жемейді).
  void _syncPulse() {
    final visible = _session != null && _flagOn;
    if (visible && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!visible && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    if (widget.adminUid.isEmpty ||
        Supabase.instance.client.auth.currentUser == null) {
      return;
    }
    // Realtime емес, 30 с polling: дүкен бетін ашқан әр қолданушының
    // ағыны live_sessions жолының әр like/heartbeat-ін қабылдамасын.
    FeatureFlags.instance.addListener(_syncPolling);
    _syncPolling();
  }

  void _syncPolling() {
    if (!mounted) return;
    if (_flagOn) {
      if (_pollTimer == null) {
        _poll();
        _pollTimer =
            Timer.periodic(const Duration(seconds: 30), (_) => _poll());
      }
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
      _syncPulse();
    }
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      final s = await LiveService().getLiveSessionForStore(widget.adminUid);
      if (!mounted) return;
      setState(() => _session = s);
      _syncPulse();
    } catch (_) {
      // Желі қатесі — баннер жай көрінбейді / келесі тактіде қайталанады.
    } finally {
      _polling = false;
    }
  }

  @override
  void dispose() {
    FeatureFlags.instance.removeListener(_syncPolling);
    _pollTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: FeatureFlags.instance,
        builder: (_, __) => _flagOn ? _buildBanner() : const SizedBox.shrink(),
      );

  Widget _buildBanner() {
    final s = _session;
    if (s == null) return const SizedBox.shrink();
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
