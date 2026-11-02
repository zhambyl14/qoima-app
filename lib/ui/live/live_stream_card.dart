import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/live_models.dart';
import '../../theme/qoima_design.dart';
import 'live_navigation.dart';
import 'live_widgets.dart';

/// Бір эфир карточкасы (басты бет қатары мен «Барлық эфирлер» торы).
/// [width] null болса — берілген орынды толтырады (тор).
class LiveStreamCard extends StatelessWidget {
  final LiveSession session;
  final String storeName;
  final String fallbackImage; // эфир мұқабасы жоқта — дүкен логотипі
  final double? width;
  const LiveStreamCard({
    super.key,
    required this.session,
    required this.storeName,
    this.fallbackImage = '',
    this.width = 132,
  });

  @override
  Widget build(BuildContext context) {
    final img = session.coverUrl.isNotEmpty ? session.coverUrl : fallbackImage;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        openLiveSession(context, session.id);
      },
      child: Container(
        width: width,
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
                  storeName,
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
