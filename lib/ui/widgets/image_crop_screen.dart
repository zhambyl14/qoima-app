import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../theme/qoima_design.dart';

import '../../core/lang.dart';
/// Шаршы (1:1) кадрды ҚОЛМЕН таңдау экраны: суретті саусақпен жылжытып,
/// екі саусақпен масштабтауға болады — шеттерін не төбесін кесіп, керек
/// бөлігін қалдырады. Нәтиже: [outputSize]×[outputSize] JPG bytes
/// (Navigator.pop арқылы), бас тартылса — null.
class ImageCropScreen extends StatefulWidget {
  final Uint8List raw;
  final int outputSize;
  final String? title;

  const ImageCropScreen({
    super.key,
    required this.raw,
    this.outputSize = 1080,
    this.title,
  });

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  final _tc = TransformationController();
  int? _imgW, _imgH; // суреттің нақты пиксель өлшемдері
  bool _busy = false;
  double _side = 0; // viewport қабырғасы (экранға тәуелді)

  @override
  void initState() {
    super.initState();
    // Өлшемдерді жылдам аламыз (engine декодері, толық декодсыз).
    decodeImageFromList(widget.raw).then((image) {
      if (!mounted) return;
      setState(() {
        _imgW = image.width;
        _imgH = image.height;
      });
      image.dispose();
    }).catchError((_) {
      if (mounted) Navigator.pop(context); // декод болмады — бас тартамыз
    });
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  // Cover масштабындағы базалық өлшем: кіші қабырға viewport-қа тең.
  double get _baseW =>
      _imgW! <= _imgH! ? _side : _side * _imgW! / _imgH!;
  double get _baseH =>
      _imgH! <= _imgW! ? _side : _side * _imgH! / _imgW!;

  /// Бірінші layout кезінде суретті центрлейміз.
  void _centerIfNeeded(double side) {
    if (_side == side) return;
    _side = side;
    _tc.value = Matrix4.identity()
      ..translateByDouble(
          -(_baseW - side) / 2, -(_baseH - side) / 2, 0, 1);
  }

  Future<void> _confirm() async {
    if (_busy || _imgW == null) return;
    setState(() => _busy = true);
    try {
      final m = _tc.value;
      final s = m.getMaxScaleOnAxis();
      final tx = m.storage[12];
      final ty = m.storage[13];
      // Көрініп тұрған аймақ (base координатында) → сурет пикселіне көшеміз.
      final k = _imgW! / _baseW;
      final crop = (
        x: (-tx / s * k).round(),
        y: (-ty / s * k).round(),
        size: (_side / s * k).round(),
      );
      final bytes = await compute(_cropWorker, <String, dynamic>{
        'raw': widget.raw,
        'x': crop.x,
        'y': crop.y,
        'size': crop.size,
        'out': widget.outputSize,
      });
      if (mounted) Navigator.pop(context, bytes);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('Не удалось обрезать фото', 'Фотоны қиып алу мүмкін болмады')),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _imgW != null && _imgH != null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(children: [
              IconButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 26),
              ),
              Expanded(
                child: Text(widget.title ?? tr('Кадрирование', 'Кадрлау'),
                    textAlign: TextAlign.center,
                    style:
                        manrope(16, FontWeight.w700, color: Colors.white)),
              ),
              const SizedBox(width: 42), // симметрия үшін
            ]),
          ),

          // ── Кадр аймағы ─────────────────────────────────────────────────
          Expanded(
            child: Center(
              child: !ready
                  ? const CircularProgressIndicator(
                      color: cGreen, strokeWidth: 2)
                  : LayoutBuilder(builder: (context, box) {
                      final side = box.maxWidth < box.maxHeight
                          ? box.maxWidth
                          : box.maxHeight;
                      _centerIfNeeded(side);
                      return SizedBox(
                        width: side,
                        height: side,
                        child: Stack(children: [
                          ClipRect(
                            child: InteractiveViewer(
                              transformationController: _tc,
                              constrained: false,
                              boundaryMargin: EdgeInsets.zero,
                              minScale: 1.0,
                              maxScale: 6.0,
                              child: SizedBox(
                                width: _baseW,
                                height: _baseH,
                                child: Image.memory(widget.raw,
                                    fit: BoxFit.fill,
                                    gaplessPlayback: true),
                              ),
                            ),
                          ),
                          // 3×3 тор + жиек (кадр бағдары)
                          const Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(painter: _GridPainter()),
                            ),
                          ),
                        ]),
                      );
                    }),
            ),
          ),

          // ── Hint + батырмалар ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
            child: Column(children: [
              Text(tr('Двигайте и масштабируйте фото — квадрат 1:1', 'Фотоны жылжытып, масштабтаңыз — 1:1 шаршы'),
                  style: manrope(12.5, FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.7))),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      onPressed:
                          _busy ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(tr('Отмена', 'Болдырмау'),
                          style: manrope(14.5, FontWeight.w700,
                              color: Colors.white)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: (_busy || !ready) ? null : _confirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : Text(tr('Готово', 'Дайын'),
                              style: manrope(14.5, FontWeight.w700,
                                  color: Colors.white)),
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── 3×3 тор сызғышы ────────────────────────────────────────────────────────────
class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final thin = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 0.8;
    for (var i = 1; i < 3; i++) {
      final dx = size.width * i / 3;
      final dy = size.height * i / 3;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), thin);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), thin);
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.8),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Ауыр кесу жұмысы (isolate-та): decode → copyCrop → resize → JPG.
Uint8List _cropWorker(Map<String, dynamic> args) {
  final raw = args['raw'] as Uint8List;
  final out = args['out'] as int;
  final decoded = img.decodeImage(raw);
  if (decoded == null) return raw;

  var x = args['x'] as int;
  var y = args['y'] as int;
  var size = args['size'] as int;
  // Шектерге қысамыз (жылжыту дәлдігінен ±1px ауытқу болуы мүмкін).
  size = size.clamp(1, decoded.width < decoded.height
      ? decoded.width
      : decoded.height);
  x = x.clamp(0, decoded.width - size);
  y = y.clamp(0, decoded.height - size);

  final cropped =
      img.copyCrop(decoded, x: x, y: y, width: size, height: size);
  final resized = img.copyResize(cropped,
      width: out, height: out, interpolation: img.Interpolation.average);
  return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
}
