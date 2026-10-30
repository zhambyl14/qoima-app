import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qoima/data/models/category_data.dart';
import 'package:qoima/ui/admin/products/add_product_helpers.dart';
import 'package:qoima/ui/widgets/multi_shot_camera_screen.dart';

void main() {
  group('баға тексеруі', () {
    test('сату бағасы > 0, нақты сан', () {
      expect(isValidSellingPrice('12000'), isTrue);
      expect(isValidSellingPrice('0.5'), isTrue);
      expect(isValidSellingPrice('0'), isFalse);
      expect(isValidSellingPrice(''), isFalse);
      expect(isValidSellingPrice('.'), isFalse);
      expect(isValidSellingPrice('1.2.3'), isFalse);
      expect(isValidSellingPrice('NaN'), isFalse);
      expect(isValidSellingPrice('Infinity'), isFalse);
    });

    test('сатып алу бағасы >= 0, нақты сан', () {
      expect(isValidPurchasePrice('0'), isTrue);
      expect(isValidPurchasePrice('8000'), isTrue);
      expect(isValidPurchasePrice(' 8000 '), isTrue);
      expect(isValidPurchasePrice(''), isFalse);
      expect(isValidPurchasePrice('.'), isFalse);
      expect(isValidPurchasePrice('-5'), isFalse);
    });

    test('чип мәні өріске артық нөлсіз жазылады', () {
      expect(formatPriceInput(12000), '12000');
      expect(formatPriceInput(12000.5), '12000.5');
    });
  });

  group('AddProductMemory', () {
    final valid = kCategories.first;

    test('бүлінген JSON қате лақтырмайды', () {
      for (final raw in [null, '', '{', '[1,2]', '{"prices":7}']) {
        final m = AddProductMemory.parse(raw);
        expect(m.validChoice().category, isNull, reason: '$raw');
        expect(m.lastSelling('shoes'), isNull, reason: '$raw');
      }
    });

    test('каталогта жоқ категория алынбайды', () {
      final m = AddProductMemory(category: 'no_such', type: 'x', audience: 'y');
      final c = m.validChoice();
      expect(c.category, isNull);
      expect(c.type, isNull);
      expect(c.audience, isNull);
    });

    test('ескі түр мен кімге алынбайды, категория қалады', () {
      final m = AddProductMemory(
          category: valid.key, type: 'Жоқ түр', audience: 'Жоқ топ');
      final c = m.validChoice();
      expect(c.category, valid.key);
      expect(c.type, isNull);
      expect(c.audience, isNull);
    });

    test('жарамды мәндер сақталады', () {
      final withAudience = kCategories.firstWhere((c) => c.hasAudience);
      final types = kTypesByCategory[withAudience.key] ?? const <String>[];
      final m = AddProductMemory(
        category: withAudience.key,
        audience: kProductTargetGroups.first,
        type: types.isEmpty ? null : types.first,
      );
      final c = m.validChoice();
      expect(c.category, withAudience.key);
      expect(c.audience, kProductTargetGroups.first);
      expect(c.type, types.isEmpty ? null : types.first);
    });

    test('баға әр категорияға бөлек, encode/parse айналымы', () {
      final m = const AddProductMemory()
          .remember(category: 'a', purchase: 100, selling: 200)
          .remember(category: 'b', purchase: 0, selling: 300);
      final back = AddProductMemory.parse(m.encode());
      expect(back.category, 'b');
      expect(back.lastPurchase('a'), 100);
      expect(back.lastSelling('a'), 200);
      expect(back.lastPurchase('b'), 0);
      expect(back.lastSelling('b'), 300);
      expect(back.lastSelling('c'), isNull);
      expect(back.lastSelling(null), isNull);
    });

    test('жарамсыз баға алдыңғысын өшірмейді', () {
      final m = const AddProductMemory()
          .remember(category: 'a', purchase: 100, selling: 200)
          .remember(category: 'a', purchase: null, selling: 250);
      expect(m.lastPurchase('a'), 100);
      expect(m.lastSelling('a'), 250);
    });
  });

  group('камера кадры', () {
    test('кадр панельдер арасында, шаршы', () {
      final f = cameraFrameRect(const Size(360, 780), top: 100, bottom: 200);
      expect(f.width, 360);
      expect(f.height, 360);
      expect(f.center.dy, 100 + 480 / 2);
      expect(f.center.dx, 180);
    });

    test('аласа экранда кадр биіктікке сыйғызылады', () {
      final f = cameraFrameRect(const Size(360, 500), top: 100, bottom: 200);
      expect(f.width, 200);
      expect(f.height, 200);
      expect(f.top, greaterThanOrEqualTo(100));
      expect(f.bottom, lessThanOrEqualTo(300));
    });

    test('превьюдің қысқа қабырғасы кадрға дәл тең (16:9 де, 9:16 да)', () {
      for (final a in [16 / 9, 9 / 16, 4 / 3]) {
        final s = cameraPreviewSize(360, a);
        expect(s.shortestSide, 360, reason: '$a');
        expect(s.height / s.width, closeTo(a < 1 ? 1 / a : a, 1e-9));
      }
    });

    test('рұқсат қателері танылады', () {
      for (final code in [
        'CameraAccessDenied',
        'CameraAccessDeniedWithoutPrompt',
        'CameraAccessRestricted',
        'cameraPermission',
      ]) {
        expect(isCameraPermissionError(code), isTrue, reason: code);
      }
      expect(isCameraPermissionError('cameraNotFound'), isFalse);
      expect(isCameraPermissionError('IOError'), isFalse);
    });
  });
}
