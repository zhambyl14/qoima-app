import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qoima/ui/widgets/image_crop_screen.dart';

const _red = [220, 20, 20];
const _green = [20, 200, 40];
const _blue = [20, 40, 220];

/// Ортасында [side] қабырғалы жасыл шаршы, сыртында қызыл.
img.Image _target(int w, int h, int side) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(_red[0], _red[1], _red[2]));
  img.fillRect(
    image,
    x1: (w - side) ~/ 2,
    y1: (h - side) ~/ 2,
    x2: (w + side) ~/ 2 - 1,
    y2: (h + side) ~/ 2 - 1,
    color: img.ColorRgb8(_green[0], _green[1], _green[2]),
  );
  return image;
}

Uint8List _png(img.Image i) => Uint8List.fromList(img.encodePng(i));
Uint8List _jpg(img.Image i) =>
    Uint8List.fromList(img.encodeJpg(i, quality: 95));

void _expectColor(img.Image i, int x, int y, List<int> rgb) {
  final p = i.getPixel(x, y);
  const tolerance = 40;
  expect((p.r - rgb[0]).abs(), lessThan(tolerance), reason: 'r at $x,$y: $p');
  expect((p.g - rgb[1]).abs(), lessThan(tolerance), reason: 'g at $x,$y: $p');
  expect((p.b - rgb[2]).abs(), lessThan(tolerance), reason: 'b at $x,$y: $p');
}

img.Image _decode(Uint8List? bytes) {
  expect(bytes, isNotNull);
  final decoded = img.decodeJpg(bytes!);
  expect(decoded, isNotNull);
  return decoded!;
}

void main() {
  group('autoCenterCrop', () {
    test('landscape: кесілген шеттер шықпайды, нәтиже 1080x1080 JPEG', () {
      // Жасыл шаршы қысқа қабырғаға тең: нәтиже түгел жасыл болуы керек.
      final out = _decode(autoCenterCrop(_png(_target(1600, 900, 900))));
      expect(out.width, 1080);
      expect(out.height, 1080);
      for (final at in const [(8, 8), (1071, 8), (8, 1071), (1071, 1071)]) {
        _expectColor(out, at.$1, at.$2, _green);
      }
    });

    test('portrait: дәл сол, ортасынан', () {
      final out = _decode(autoCenterCrop(_png(_target(900, 1600, 900))));
      expect(out.width, 1080);
      expect(out.height, 1080);
      _expectColor(out, 8, 8, _green);
      _expectColor(out, 1071, 1071, _green);
    });

    test('шаршы сурет: ештеңе кесілмейді', () {
      final out = _decode(autoCenterCrop(_png(_target(800, 800, 400))));
      expect(out.width, 1080);
      expect(out.height, 1080);
      _expectColor(out, 8, 8, _red); // шеті қалды
      _expectColor(out, 540, 540, _green);
    });

    test('кіші сурет те 1080-ге дейін өседі', () {
      final out = _decode(autoCenterCrop(_png(_target(300, 200, 100))));
      expect(out.width, 1080);
      expect(out.height, 1080);
    });

    test('өлшем мен сапа параметрі қабылданады', () {
      final out =
          _decode(autoCenterCrop(_png(_target(400, 300, 100)), size: 256));
      expect(out.width, 256);
      expect(out.height, 256);
    });

    test('оқылмайтын файл null қайтарады, қате лақтырмайды', () {
      expect(autoCenterCrop(Uint8List.fromList(List.filled(64, 7))), isNull);
      expect(autoCenterCrop(Uint8List(0)), isNull);
    });
  });

  group('EXIF бағыты', () {
    // 1200x600: сол жақ жарты көк, оң жақ жарты жасыл. orientation=6 → сағат
    // тілімен 90°: көк ЖОҒАРЫҒА шығады, сурет 600x1200 болады.
    img.Image sideways() {
      final image = img.Image(width: 1200, height: 600);
      img.fillRect(image,
          x1: 0,
          y1: 0,
          x2: 599,
          y2: 599,
          color: img.ColorRgb8(_blue[0], _blue[1], _blue[2]));
      img.fillRect(image,
          x1: 600,
          y1: 0,
          x2: 1199,
          y2: 599,
          color: img.ColorRgb8(_green[0], _green[1], _green[2]));
      return image;
    }

    test('JPEG: orientation=6 ескеріледі (өлшем EXIF-ке тәуелсіз)', () {
      final image = sideways()..exif.imageIfd.orientation = 6;
      final out = _decode(autoCenterCrop(_jpg(image)));
      expect(out.width, 1080);
      expect(out.height, 1080);
      _expectColor(out, 540, 60, _blue);
      _expectColor(out, 540, 1020, _green);
    });

    test('JPEG: orientation жоқ болса бұрылмайды', () {
      final out = _decode(autoCenterCrop(_jpg(sideways())));
      expect(out.width, 1080);
      expect(out.height, 1080);
      _expectColor(out, 60, 540, _blue);
      _expectColor(out, 1020, 540, _green);
    });

    test('шығыста бағыт тегі қалмайды (көрсеткенде қайта бұрылмауы үшін)', () {
      final image = sideways()..exif.imageIfd.orientation = 6;
      final out = _decode(autoCenterCrop(_jpg(image)));
      expect(out.exif.imageIfd.hasOrientation, isFalse);
    });

    test('шығыста EXIF қалмайды (GPS витринаға шықпайды)', () {
      final image = _target(800, 600, 300);
      image.exif.imageIfd['Software'] = 'test-camera';
      final bytes = autoCenterCrop(_jpg(image))!;
      expect(
          img.decodeJpgExif(_jpg(image))?.imageIfd.containsKey(0x0131), isTrue,
          reason:
              'кіріс файлда тег болуы керек, әйтпесе тест ештеңе дәлелдемейді');
      expect(img.decodeJpgExif(bytes)?.imageIfd.containsKey(0x0131) ?? false,
          isFalse);
    });
  });

  group('centerCropSide', () {
    test('превью жоқ не бірдей: қысқа қабырға', () {
      expect(centerCropSide(1920, 1080), 1080);
      expect(centerCropSide(1080, 1920), 1080);
      expect(centerCropSide(1000, 1000), 1000);
      expect(centerCropSide(1920, 1080, previewAspect: 16 / 9), 1080);
      expect(centerCropSide(1080, 1920, previewAspect: 9 / 16), 1080);
    });

    test('сурет 4:3, превью 16:9: кадрда көрінгені ғана қалады', () {
      expect(centerCropSide(4000, 3000, previewAspect: 16 / 9), 2250);
      expect(centerCropSide(3000, 4000, previewAspect: 16 / 9), 2250);
    });

    test('сурет 16:9, превью 4:3: суреттен үлкен кесу мүмкін емес', () {
      expect(centerCropSide(1920, 1080, previewAspect: 4 / 3), 1080);
    });

    test('previewAspect нәтиже пиксельдеріне де әсер етеді', () {
      // 4:3 суреттің ортасындағы 2250px шаршы жасыл: 16:9 превьюде кадрға
      // дәл сол сыяды, сондықтан қызыл шет шықпауы керек.
      final out = _decode(autoCenterCrop(_png(_target(1600, 1200, 900)),
          previewAspect: 16 / 9));
      _expectColor(out, 8, 8, _green);
      _expectColor(out, 1071, 1071, _green);
    });
  });
}
