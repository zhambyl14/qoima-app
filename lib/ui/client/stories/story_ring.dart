import 'package:flutter/material.dart';

import '../../../theme/qoima_design.dart';

/// Логотип айналасындағы сторис шеңбері: көрілмеген — жасыл, көрілген — сұр.
/// [radius] null болса — дөңгелек, әйтпесе жұмсақ төртбұрыш (дүкен бетіндегі
/// логотип сияқты). Ішкі суреттің өлшемі = [size].
class StoryRing extends StatelessWidget {
  final double size;
  final bool unseen;
  final double? radius;
  final String logoUrl;

  const StoryRing({
    super.key,
    required this.size,
    required this.unseen,
    this.radius,
    this.logoUrl = '',
  });

  static const _ringWidth = 2.5;
  static const _gap = 2.0;

  @override
  Widget build(BuildContext context) {
    const pad = _ringWidth + _gap;
    final outer = size + pad * 2;
    final r = radius;
    final outerR = r == null ? null : r + pad;
    return Container(
      key: ValueKey(unseen ? 'story-ring-unseen' : 'story-ring-seen'),
      width: outer,
      height: outer,
      padding: const EdgeInsets.all(_ringWidth),
      decoration: BoxDecoration(
        shape: r == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: outerR == null ? null : BorderRadius.circular(outerR),
        gradient: unseen ? kGrad : null,
        color: unseen ? null : cInk3.withValues(alpha: 0.35),
      ),
      child: Container(
        padding: const EdgeInsets.all(_gap),
        decoration: BoxDecoration(
          shape: r == null ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: r == null ? null : BorderRadius.circular(r + _gap),
          color: cSurface,
        ),
        child: StoreAvatar(size: size, radius: radius, logoUrl: logoUrl),
      ),
    );
  }
}

/// Дүкен логотипі (жоқ не жүктелмесе — витрина белгісі).
class StoreAvatar extends StatelessWidget {
  final double size;
  final double? radius;
  final String logoUrl;
  const StoreAvatar(
      {super.key, required this.size, this.radius, this.logoUrl = ''});

  @override
  Widget build(BuildContext context) {
    final fallback =
        Icon(Icons.storefront_rounded, color: cGreenDeep, size: size * 0.5);
    final child = logoUrl.isEmpty
        ? fallback
        : Image.network(logoUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: (size * 3).round(),
            errorBuilder: (_, __, ___) => fallback);
    final box = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: cGreenTint,
      child: child,
    );
    return radius == null
        ? ClipOval(child: box)
        : ClipRRect(borderRadius: BorderRadius.circular(radius!), child: box);
  }
}
