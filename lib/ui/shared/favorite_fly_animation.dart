import 'dart:math' show pi, sin;
import 'package:flutter/material.dart';
import '../../theme/qoima_design.dart';

/// Таңдаулыға қосқанда «профильге ұшу» анимациясының нысанасы (профиль
/// табының иконка орны). ClientShell осы кілтті профиль иконкасына тағады —
/// кез келген экрандағы карточка сол жерге қарай ұша алады.
class FavoriteFlyTarget {
  FavoriteFlyTarget._();
  static final GlobalKey key = GlobalKey();
}

/// Тауар суретін (немесе жүрекше белгісін) карточкадан профиль табына қарай
/// «ұшырады»: жолда кішіреп, солғындап жоғалады. Тек ҚОСҚАНДА шақырылады
/// (өшіргенде емес) — «таңдаулыға түсті» деген көрнекі растау.
void flyToFavorites(BuildContext context, GlobalKey sourceKey,
    {String imageUrl = ''}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final sourceBox =
      sourceKey.currentContext?.findRenderObject() as RenderBox?;
  final targetBox = FavoriteFlyTarget.key.currentContext?.findRenderObject()
      as RenderBox?;
  if (overlay == null || sourceBox == null || targetBox == null) return;
  if (!sourceBox.attached || !targetBox.attached) return;

  final start = sourceBox.localToGlobal(sourceBox.size.center(Offset.zero));
  final end = targetBox.localToGlobal(targetBox.size.center(Offset.zero));

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _FlyingFavorite(
      start: start,
      end: end,
      imageUrl: imageUrl,
      // Анимация біткенде — тек әлі overlay-де тұрса ғана өшіреміз (экран
      // ауысып кетсе entry.remove() қайта шақырылып, exception бермесін).
      onDone: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _FlyingFavorite extends StatefulWidget {
  final Offset start;
  final Offset end;
  final String imageUrl;
  final VoidCallback onDone;
  const _FlyingFavorite({
    required this.start,
    required this.end,
    required this.imageUrl,
    required this.onDone,
  });

  @override
  State<_FlyingFavorite> createState() => _FlyingFavoriteState();
}

class _FlyingFavoriteState extends State<_FlyingFavorite>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _t = CurvedAnimation(parent: _ctrl, curve: Curves.easeInCubic);
    _ctrl.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 46.0;
    // ⚠️ [Positioned] Overlay-дің Stack-іне ТІКЕЛЕЙ бала болуы керек: арасында
    // RenderObject жасайтын виджет (IgnorePointer т.б.) тұрса, Flutter
    // «Incorrect use of ParentDataWidget» лақтырып, бүкіл экран қатып қалады.
    // Сондықтан IgnorePointer — Positioned-тің ІШІНДЕ.
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final v = _t.value;
        final dx = widget.start.dx + (widget.end.dx - widget.start.dx) * v;
        // Жоғары қарай доғамен ұшады (тегіс сызықтан гөрі көрнекі).
        final arc = sin(v * pi) * 46;
        final dy =
            widget.start.dy + (widget.end.dy - widget.start.dy) * v - arc;
        final scale = 1.0 - 0.78 * v;
        final opacity = v < 0.75 ? 1.0 : (1 - v) / 0.25;
        return Positioned(
          left: dx - size / 2,
          top: dy - size / 2,
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: scale.clamp(0.05, 1.0),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.imageUrl.isEmpty ? cRed : Colors.white,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: kShadowSm,
                    image: widget.imageUrl.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(widget.imageUrl),
                            fit: BoxFit.cover)
                        : null,
                  ),
                  child: widget.imageUrl.isEmpty
                      ? const Icon(Icons.favorite_rounded,
                          color: Colors.white, size: 20)
                      : null,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
