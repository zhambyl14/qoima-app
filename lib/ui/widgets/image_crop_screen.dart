import 'dart:ui' as ui;

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

  // Cover масштабындағы базалық өлшем әдейі 18%-ға ҮЛКЕНІРЕК алынады
  // (_overscan): бұрын кіші қабырға viewport-пен ДӘЛ теңеліп, сол осьте
  // жылжу орны мүлде қалмайтын (мыс. тік фотода — солға/оңға жылжытуға
  // болмайтын, тек ортасы кесілетін). Артық жиек — жылжыту үшін бос орын;
  // minScale соған сай төмендетілген — «нақты cover» күйіне де оралуға
  // болады.
  static const double _overscan = 1.18;
  double get _baseW =>
      (_imgW! <= _imgH! ? _side : _side * _imgW! / _imgH!) * _overscan;
  double get _baseH =>
      (_imgH! <= _imgW! ? _side : _side * _imgH! / _imgW!) * _overscan;

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
      final args = <String, dynamic>{
        'raw': widget.raw,
        'x': crop.x,
        'y': crop.y,
        'size': crop.size,
        'out': widget.outputSize,
      };
      var bytes = await compute(_cropWorker, args);
      // `image` оқи алмаса (HEIC) бұрын кесілмеген түпнұсқа қайтатын еді.
      if (bytes == null) {
        final png = await _engineDecodeToPng(widget.raw);
        if (png == null) throw StateError('decode failed');
        bytes = await compute(_cropWorker, {...args, 'raw': png});
      }
      if (bytes == null) throw StateError('decode failed');
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
                              minScale: 1 / _overscan,
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
              Text(tr('Двигайте фото в любую сторону и масштабируйте — квадрат 1:1', 'Фотоны кез келген жаққа жылжытып, масштабтаңыз — 1:1 шаршы'),
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
/// `image` пакеті оқи алмаса — null (шақырушы engine декодеріне ауысады).
Uint8List? _cropWorker(Map<String, dynamic> args) {
  final raw = args['raw'] as Uint8List;
  final out = args['out'] as int;
  final decoded = _decodeUpright(raw);
  if (decoded == null) return null;

  var x = args['x'] as int;
  var y = args['y'] as int;
  var size = args['size'] as int;
  // Шектерге қысамыз (жылжыту дәлдігінен ±1px ауытқу болуы мүмкін).
  size = size.clamp(1, decoded.width < decoded.height
      ? decoded.width
      : decoded.height);
  x = x.clamp(0, decoded.width - size);
  y = y.clamp(0, decoded.height - size);

  return _encodeSquare(decoded, x, y, size, out, kProductPhotoQuality);
}

// ── Авто-центр кесу: камера да, галерея да осыны қолданады ─────────────────────

/// Тауар фотосының тіркелген өлшемі мен сапасы (бір жерде ғана).
const int kProductPhotoSize = 1080;
const int kProductPhotoQuality = 85;

/// Суретті ТІК күйінде декодтайды. JPEG декодері EXIF бағытын өзі қолданады;
/// басқа форматта тег қалса, осында сіңіреміз. bakeOrientation әрқашан толық
/// көшірме жасайды, сондықтан тег бар кезде ғана шақырамыз.
img.Image? _decodeUpright(Uint8List raw) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(raw);
  } catch (_) {
    return null; // бүлінген файл: decodeImage null емес, қате лақтыра алады
  }
  if (decoded == null) return null;
  final ifd = decoded.exif.imageIfd;
  if (!ifd.hasOrientation || ifd.orientation == 1) return decoded;
  return img.bakeOrientation(decoded);
}

Uint8List _encodeSquare(
    img.Image src, int x, int y, int side, int out, int quality) {
  final cropped = img.copyCrop(src, x: x, y: y, width: side, height: side);
  final resized = img.copyResize(cropped,
      width: out, height: out, interpolation: img.Interpolation.average);
  // EXIF-ті алып тастаймыз: бағыты пиксельге сіңді, ал GPS пен құрылғы
  // деректері витринаға жарияланатын суретке шықпауы керек.
  resized.exif.clear();
  return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
}

/// [width]×[height] суреттің ортасынан алынатын шаршының қабырғасы.
///
/// [previewAspect] — камера превьюінің пропорциясы. Әдетте суреттікімен бірдей,
/// сонда шаршы қысқа қабырғаға тең. Бірақ кей құрылғыда сурет 4:3, превью 16:9
/// болады: превью сенсордың ортаңғы бөлігі ғана, яғни кадрда көрінгені суреттің
/// қысқа қабырғасынан КІШІ. Кадрда не көрінсе, сол сақталуы үшін соған кішірейтеміз.
int centerCropSide(int width, int height, {double? previewAspect}) {
  final short = width < height ? width : height;
  final long = width < height ? height : width;
  if (short <= 0) return 1;
  var side = short.toDouble();
  if (previewAspect != null && previewAspect > 0) {
    final p = previewAspect < 1 ? 1 / previewAspect : previewAspect;
    final q = long / short;
    if (p > q) side = short * q / p;
  }
  final s = side.round();
  return s < 1 ? 1 : (s > short ? short : s);
}

/// Суретті ортасынан 1:1 кесіп, [size]×[size] JPEG қайтарады (EXIF бағыты
/// ескеріледі). Оқылмаса — null. Таза функция: UI-ға да, платформаға да тәуелді
/// емес, сондықтан тікелей тестіленеді. Экранда [autoCenterCropAsync] қолданыңыз.
Uint8List? autoCenterCrop(
  Uint8List raw, {
  int size = kProductPhotoSize,
  int quality = kProductPhotoQuality,
  double? previewAspect,
}) {
  final decoded = _decodeUpright(raw);
  if (decoded == null) return null;
  final side = centerCropSide(decoded.width, decoded.height,
      previewAspect: previewAspect);
  return _encodeSquare(decoded, (decoded.width - side) ~/ 2,
      (decoded.height - side) ~/ 2, side, size, quality);
}

Uint8List? _autoCropIsolate((Uint8List, int, int, double?) a) =>
    autoCenterCrop(a.$1, size: a.$2, quality: a.$3, previewAspect: a.$4);

/// [autoCenterCrop] фондық isolate-та (UI тоқтамайды). `image` пакеті оқи
/// алмаған формат (мыс. Android-тағы HEIC) engine арқылы тағы бір рет сыналады.
Future<Uint8List?> autoCenterCropAsync(
  Uint8List raw, {
  int size = kProductPhotoSize,
  int quality = kProductPhotoQuality,
  double? previewAspect,
}) async {
  final out =
      await compute(_autoCropIsolate, (raw, size, quality, previewAspect));
  if (out != null) return out;
  final png = await _engineDecodeToPng(raw);
  if (png == null) return null;
  return compute(_autoCropIsolate, (png, size, quality, previewAspect));
}

/// Flutter engine декодері (EXIF-ті де, HEIC-ті де біледі) → PNG bytes.
Future<Uint8List?> _engineDecodeToPng(Uint8List raw) async {
  try {
    final codec = await ui.instantiateImageCodec(raw);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}
