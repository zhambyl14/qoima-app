import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/qoima_design.dart';

/// Тауар суреттерін толық экранда ашады: свайппен ауыстыру, екі саусақпен
/// және екі рет басып зумдау. Жабылғанда соңғы көрілген беттің индексін
/// қайтарады — шақырушы өз галереясын соған синхрондайды.
Future<int?> openPhotoGallery(
  BuildContext context, {
  required List<String> images,
  int initialIndex = 0,
  String heroTagPrefix = '',
}) {
  return Navigator.of(context).push<int>(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => PhotoGalleryViewer(
      images: images,
      initialIndex: initialIndex,
      heroTagPrefix: heroTagPrefix,
    ),
    transitionsBuilder: (_, anim, __, child) =>
        FadeTransition(opacity: anim, child: child),
  ));
}

class PhotoGalleryViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  // Бос болмаса — әр суретке '$heroTagPrefix$i' Hero тегі беріледі.
  final String heroTagPrefix;
  const PhotoGalleryViewer({
    super.key,
    required this.images,
    this.initialIndex = 0,
    this.heroTagPrefix = '',
  });

  @override
  State<PhotoGalleryViewer> createState() => _PhotoGalleryViewerState();
}

class _PhotoGalleryViewerState extends State<PhotoGalleryViewer> {
  late final PageController _pageCtrl =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  // Ағымдағы бет зумда тұрса — PageView свайпы өшеді (сурет ішінде жылжу
  // мен бет ауыстыру бір-біріне кедергі болмауы үшін).
  bool _zoomed = false;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop(_index);

  @override
  Widget build(BuildContext context) {
    final count = widget.images.length;
    // Қара фонда статус-бар иконкалары ақ болуы үшін.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _close();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(children: [
            PageView.builder(
              controller: _pageCtrl,
              physics: _zoomed
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              itemCount: count,
              onPageChanged: (i) => setState(() {
                _index = i;
                _zoomed = false;
              }),
              itemBuilder: (_, i) => _ZoomablePhoto(
                url: widget.images[i],
                heroTag: widget.heroTagPrefix.isEmpty
                    ? null
                    : '${widget.heroTagPrefix}$i',
                onZoomChanged: (z) {
                  if (z != _zoomed) setState(() => _zoomed = z);
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(children: [
                  if (count > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('${_index + 1} / $count',
                          style: manrope(13, FontWeight.w700,
                              color: Colors.white)),
                    ),
                  const Spacer(),
                  Material(
                    color: Colors.white.withValues(alpha: 0.14),
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon:
                          const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: _close,
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ZoomablePhoto extends StatefulWidget {
  final String url;
  final String? heroTag;
  final ValueChanged<bool> onZoomChanged;
  const _ZoomablePhoto({
    required this.url,
    required this.heroTag,
    required this.onZoomChanged,
  });

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto>
    with SingleTickerProviderStateMixin {
  static const _doubleTapScale = 2.5;

  final _ctrl = TransformationController();
  late final AnimationController _anim = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 220))
    ..addListener(() {
      if (_matrixAnim != null) _ctrl.value = _matrixAnim!.value;
    });
  Animation<Matrix4>? _matrixAnim;
  Offset _tapPos = Offset.zero;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_reportZoom);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_reportZoom);
    _ctrl.dispose();
    _anim.dispose();
    super.dispose();
  }

  bool get _isZoomed => _ctrl.value.getMaxScaleOnAxis() > 1.01;

  void _reportZoom() => widget.onZoomChanged(_isZoomed);

  // Екі рет басу: зумда болса — бастапқы күйге, болмаса — басқан нүктеге
  // қарай _doubleTapScale есе үлкейту.
  void _onDoubleTap() {
    final Matrix4 target;
    if (_isZoomed) {
      target = Matrix4.identity();
    } else {
      final p = _tapPos;
      target = Matrix4.identity()
        ..translateByDouble(
            -p.dx * (_doubleTapScale - 1), -p.dy * (_doubleTapScale - 1), 0, 1)
        ..scaleByDouble(_doubleTapScale, _doubleTapScale, 1, 1);
    }
    _matrixAnim = Matrix4Tween(begin: _ctrl.value, end: target)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    Widget image = Image.network(
      widget.url,
      fit: BoxFit.contain,
      loadingBuilder: (_, child, progress) => progress == null
          ? child
          : const Center(
              child: CircularProgressIndicator(color: cGreen, strokeWidth: 2)),
      errorBuilder: (_, __, ___) => const Center(
        child:
            Icon(Icons.broken_image_outlined, color: Colors.white38, size: 56),
      ),
    );
    if (widget.heroTag != null) {
      image = Hero(tag: widget.heroTag!, child: image);
    }
    return GestureDetector(
      onDoubleTapDown: (d) => _tapPos = d.localPosition,
      onDoubleTap: _onDoubleTap,
      child: InteractiveViewer(
        transformationController: _ctrl,
        minScale: 1,
        maxScale: 5,
        child: SizedBox.expand(child: image),
      ),
    );
  }
}
