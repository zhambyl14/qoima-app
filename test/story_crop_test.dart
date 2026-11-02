import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qoima/ui/admin/my_store/story_crop.dart';

Uint8List _jpg(int w, int h) {
  final i = img.Image(width: w, height: h);
  img.fill(i, color: img.ColorRgb8(40, 160, 90));
  return Uint8List.fromList(img.encodeJpg(i, quality: 95));
}

void main() {
  group('storyCropRect (9:16)', () {
    test('кең сурет: ені қиылады, биіктігі сол күйі', () {
      final r = storyCropRect(1600, 900);
      expect(r.h, 900);
      expect(r.w, 506); // 900 * 9 / 16
      expect(r.x, (1600 - 506) ~/ 2);
      expect(r.y, 0);
    });

    test('тар сурет: биіктігі қиылады', () {
      final r = storyCropRect(900, 2400);
      expect(r.w, 900);
      expect(r.h, 1600); // 900 * 16 / 9
      expect(r.x, 0);
      expect(r.y, (2400 - 1600) ~/ 2);
    });

    test('дәл 9:16 — кесілмейді', () {
      final r = storyCropRect(1080, 1920);
      expect((r.x, r.y, r.w, r.h), (0, 0, 1080, 1920));
    });

    test('шаршы және өте жіңішке сурет шекте қалады', () {
      final sq = storyCropRect(1000, 1000);
      expect(sq.w, 563);
      expect(sq.h, 1000);
      final thin = storyCropRect(1, 5000);
      expect(thin.w, 1);
      expect(thin.h, greaterThanOrEqualTo(1));
      expect(thin.h, lessThanOrEqualTo(5000));
      final zero = storyCropRect(0, 0);
      expect(zero.w, 1);
    });
  });

  group('autoStoryCrop', () {
    test('альбомдық сурет 9:16 болады, кішісін үлкейтпейді', () {
      final out = autoStoryCrop(_jpg(320, 180))!;
      final d = img.decodeJpg(out)!;
      expect(d.height, 180);
      expect(d.width, 101);
      expect((d.width / d.height - 9 / 16).abs(), lessThan(0.01));
    });

    test('үлкен сурет 1080×1920-ға кішірейеді', () {
      final out = autoStoryCrop(_jpg(2400, 3200))!;
      final d = img.decodeJpg(out)!;
      expect(d.width, kStoryWidth);
      expect(d.height, kStoryHeight);
    });

    test('бүлінген деректер — null', () {
      expect(autoStoryCrop(Uint8List.fromList([1, 2, 3, 4])), isNull);
      expect(autoStoryCrop(Uint8List(0)), isNull);
    });
  });
}
