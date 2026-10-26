import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../data/models/live_models.dart';
import '../../theme/qoima_design.dart';

// Live экрандарына ортақ шағын виджеттер: LIVE белгісі, көрермен саны,
// чат қабаты, ұшатын жүректер, ұзақтық форматы.

/// «12:05» / «1:02:05».
String formatLiveDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Видео үстіндегі қара мөлдір төсеніш (мәтін кез келген кадрда оқылсын).
const Color kLiveScrim = Color(0x8C000000);

/// Қызыл «LIVE» белгісі (нүктесі соғып тұрады).
class LiveBadge extends StatefulWidget {
  final bool compact;
  const LiveBadge({super.key, this.compact = false});

  @override
  State<LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final small = widget.compact;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 6 : 9, vertical: small ? 2 : 4),
      decoration: BoxDecoration(
        color: cRed,
        borderRadius: BorderRadius.circular(kRPill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        FadeTransition(
          opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
          child: Container(
            width: small ? 5 : 7,
            height: small ? 5 : 7,
            decoration: const BoxDecoration(
                color: Colors.white, shape: BoxShape.circle),
          ),
        ),
        SizedBox(width: small ? 4 : 5),
        Text('LIVE',
            style: manrope(small ? 9.5 : 11.5, FontWeight.w800,
                color: Colors.white, letterSpacing: 0.6)),
      ]),
    );
  }
}

/// Көрермен саны (көз белгісі + сан) — қара мөлдір капсула.
class LiveViewersChip extends StatelessWidget {
  final int count;
  const LiveViewersChip({super.key, required this.count});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
            color: kLiveScrim, borderRadius: BorderRadius.circular(kRPill)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.visibility_rounded, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text('$count',
              style: manrope(11.5, FontWeight.w700, color: Colors.white)),
        ]),
      );
}

/// Видео үстіндегі дөңгелек батырма.
class LiveRoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final Color background;
  final double size;
  const LiveRoundButton({
    super.key,
    required this.icon,
    this.onTap,
    this.color = Colors.white,
    this.background = kLiveScrim,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: background,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: color, size: size * 0.5)),
        ),
      );
}

/// Чат қабаты: соңғы хабарлар, жоғарғы жағы біртіндеп сөнеді.
class LiveChatOverlay extends StatelessWidget {
  final List<LiveMessage> messages;
  final double maxHeight;

  /// Хабарды ұзақ басқанда (шағым / модерация). Тек 'chat' хабарларға.
  final void Function(LiveMessage message)? onMessageLongPress;
  const LiveChatOverlay(
      {super.key,
      required this.messages,
      this.maxHeight = 220,
      this.onMessageLongPress});

  @override
  Widget build(BuildContext context) {
    // Тек соңғы 30 — ұзын тізімді көрсетудің мәні жоқ, жоғары сөнеді.
    final list = messages.length > 30
        ? messages.sublist(messages.length - 30)
        : messages;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ShaderMask(
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.white, Colors.white],
          stops: [0, 0.3, 1],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: ListView.builder(
          reverse: true,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const ClampingScrollPhysics(),
          itemCount: list.length,
          itemBuilder: (_, i) {
            final m = list[list.length - 1 - i];
            return _LiveMessageRow(
              message: m,
              onLongPress: (onMessageLongPress != null &&
                      m.kind == LiveMessage.kindChat &&
                      !m.isHost)
                  ? () => onMessageLongPress!(m)
                  : null,
            );
          },
        ),
      ),
    );
  }
}

class _LiveMessageRow extends StatelessWidget {
  final LiveMessage message;
  final VoidCallback? onLongPress;
  const _LiveMessageRow({required this.message, this.onLongPress});

  String get _name => message.userName.isNotEmpty
      ? message.userName
      : tr('Покупатель', 'Сатып алушы');

  @override
  Widget build(BuildContext context) {
    final m = message;
    if (m.kind == LiveMessage.kindSystem) {
      final text = switch (m.body) {
        LiveMessage.sysStarted => tr('Эфир начался 🔴', 'Эфир басталды 🔴'),
        LiveMessage.sysEnded => tr('Эфир завершён', 'Эфир аяқталды'),
        _ => m.body,
      };
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(text, style: manrope(12, FontWeight.w700, color: cAmber)),
      );
    }
    if (m.kind == LiveMessage.kindCart) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: cGreen.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(kR12),
            ),
            child: Text(
              tr('🛒 $_name добавил(а) в корзину: ${m.body}',
                  '🛒 $_name себетке қосты: ${m.body}'),
              style: manrope(12, FontWeight.w700, color: Colors.white),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onLongPress: onLongPress,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: kLiveScrim,
              borderRadius: BorderRadius.circular(kR12),
            ),
            child: Text.rich(TextSpan(children: [
              TextSpan(
                text: m.isHost ? '${tr('Магазин', 'Дүкен')} · ' : '$_name  ',
                style: manrope(12.5, FontWeight.w800,
                    color: m.isHost ? cGreenBright : const Color(0xFFFFD27A)),
              ),
              TextSpan(
                text: m.body,
                style: manrope(12.5, FontWeight.w500, color: Colors.white),
              ),
            ])),
          ),
        ),
      ),
    );
  }
}

/// Ұшатын жүректер. `GlobalKey<LiveHeartsState>` арқылы `burst()` шақырылады.
class LiveHearts extends StatefulWidget {
  const LiveHearts({super.key});

  @override
  State<LiveHearts> createState() => LiveHeartsState();
}

class LiveHeartsState extends State<LiveHearts> {
  final _rnd = Random();
  final List<int> _ids = [];
  int _next = 0;

  /// [count] жүрек ұшырады (бір мезетте ≤ 24 — әлсіз телефонды қинамау үшін).
  void burst([int count = 1]) {
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < count && _ids.length < 24; i++) {
        _ids.add(_next++);
      }
    });
  }

  void _remove(int id) {
    if (!mounted) return;
    setState(() => _ids.remove(id));
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: SizedBox(
          width: 90,
          height: 300,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final id in _ids)
                _FloatingHeart(
                  key: ValueKey(id),
                  drift: _rnd.nextDouble() * 50 - 25,
                  color: [
                    cRed,
                    const Color(0xFFFF6FA3),
                    cAmber,
                    cGreenBright
                  ][id % 4],
                  onDone: () => _remove(id),
                ),
            ],
          ),
        ),
      );
}

class _FloatingHeart extends StatefulWidget {
  final double drift;
  final Color color;
  final VoidCallback onDone;
  const _FloatingHeart(
      {super.key,
      required this.drift,
      required this.color,
      required this.onDone});

  @override
  State<_FloatingHeart> createState() => _FloatingHeartState();
}

class _FloatingHeartState extends State<_FloatingHeart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800))
    ..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final t = Curves.easeOut.transform(_c.value);
          return Positioned(
            bottom: t * 260,
            left: 30 + sin(_c.value * pi * 2) * 10 + widget.drift * t,
            child: Opacity(
              opacity: (1 - _c.value).clamp(0.0, 1.0),
              child: Transform.scale(scale: 0.6 + 0.6 * t, child: child),
            ),
          );
        },
        child: Icon(Icons.favorite_rounded, color: widget.color, size: 28),
      );
}

/// Эфир аяқталғандағы статистика тақтасы (хост үшін).
class LiveSummaryCard extends StatelessWidget {
  final Duration duration;
  final int peakViewers;
  final int likes;
  final int cartAdds;
  const LiveSummaryCard({
    super.key,
    required this.duration,
    required this.peakViewers,
    required this.likes,
    required this.cartAdds,
  });

  @override
  Widget build(BuildContext context) {
    Widget cell(IconData icon, String value, String label, Color tone) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            decoration: BoxDecoration(
              color: cSurface,
              borderRadius: BorderRadius.circular(kR16),
              border: Border.all(color: cLine),
              boxShadow: kShadowSm,
            ),
            child: Column(children: [
              Icon(icon, color: tone, size: 22),
              const SizedBox(height: 6),
              Text(value, style: manrope(18, FontWeight.w800, color: cInk)),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  style: manrope(11.5, FontWeight.w600, color: cInk3)),
            ]),
          ),
        );
    return Column(children: [
      Row(children: [
        cell(Icons.timer_outlined, formatLiveDuration(duration),
            tr('Длительность', 'Ұзақтығы'), cGreen),
        const SizedBox(width: 10),
        cell(Icons.visibility_rounded, '$peakViewers',
            tr('Пик зрителей', 'Ең көп көрермен'), cBlue),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        cell(Icons.favorite_rounded, '$likes', tr('Лайки', 'Лайктар'), cRed),
        const SizedBox(width: 10),
        cell(Icons.shopping_bag_outlined, '$cartAdds',
            tr('В корзину', 'Себетке'), cAmber),
      ]),
    ]);
  }
}
