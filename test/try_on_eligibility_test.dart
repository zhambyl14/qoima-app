import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qoima/core/locale_context.dart';
import 'package:qoima/data/models/category_data.dart';
import 'package:qoima/data/models/product_model.dart';
import 'package:qoima/ui/client/ai/try_on_eligibility.dart';

ProductModel _p({
  String categoryKey = 'shoes',
  String type = 'Кроссовки',
  String audience = 'Мужские',
  List<String> images = const ['https://res.cloudinary.com/x/1.jpg'],
  String description = '',
  String descriptionKk = '',
  String season = '',
}) =>
    ProductModel(
      id: 'p1',
      name: 'Тест',
      brand: 'Brand',
      type: type,
      material: '',
      category: audience,
      color: 'Белый',
      articul: 'QM-1',
      status: ProductModel.statusInStock,
      images: images,
      categoryKey: categoryKey,
      description: description,
      descriptionKk: descriptionKk,
      season: season,
    );

/// Сервердегі TRYON_RULES блогын оқиды (формат: бір категория = бір жол).
Map<String, TryOnRule> _parseServerRules() {
  final src = File('supabase/functions/virtual-tryon/index.ts')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final b = src.indexOf('// TRYON_RULES_BEGIN');
  final e = src.indexOf('// TRYON_RULES_END');
  expect(b, greaterThan(0), reason: 'TRYON_RULES_BEGIN табылмады');
  expect(e, greaterThan(b), reason: 'TRYON_RULES_END табылмады');
  final kindByWire = {for (final k in TryOnKind.values) k.wire: k};
  TryOnKind? kind(String raw) {
    if (raw == 'null') return null;
    final k = kindByWire[raw.replaceAll('"', '')];
    expect(k, isNotNull, reason: 'белгісіз түр: $raw');
    return k;
  }

  final lineRe = RegExp(
      r'^\s*(\w+):\s*\{\s*all:\s*(null|"[a-z-]+")(?:,\s*types:\s*\{(.*)\})?\s*\},\s*$');
  final pairRe = RegExp(r'"([^"]+)":\s*(null|"[a-z-]+")');
  final out = <String, TryOnRule>{};
  for (final line in src.substring(b, e).split('\n').skip(1)) {
    if (line.trim().isEmpty) continue;
    final m = lineRe.firstMatch(line);
    expect(m, isNotNull, reason: 'оқылмаған жол: $line');
    final types = <String, TryOnKind?>{};
    final body = m!.group(3);
    if (body != null) {
      for (final pm in pairRe.allMatches(body)) {
        types[pm.group(1)!] = kind(pm.group(2)!);
      }
    }
    out[m.group(1)!] = TryOnRule(kind(m.group(2)!), types);
  }
  return out;
}

void main() {
  tearDown(() => LocaleContext.currentLang = 'ru');

  group('ережелер кестесі', () {
    test('29 категорияның БӘРІ жіктелген (артық та, кем де жоқ)', () {
      final keys = kCategories.map((c) => c.key).toSet();
      expect(keys.length, 29);
      expect(kTryOnRules.keys.toSet(), keys);
    });

    test('киілмейтін категорияның ешбір түрі жарамайды', () {
      for (final c in kCategories) {
        final rule = kTryOnRules[c.key]!;
        for (final t in kTypesByCategory[c.key] ?? const <String>[]) {
          final k = rule.kindFor(t);
          final allowedException = rule.all == null && rule.types.isNotEmpty;
          if (rule.all == null && !allowedException) {
            expect(k, isNull, reason: '${c.key}/$t');
          }
        }
      }
    });

    test('киілетін категорияда кемінде бір түр жарайды', () {
      const wearable = {
        'shoes', 'tshirt', 'outer', 'pants', 'dress', 'caps', 'acc', //
        'jewelry', 'sport', 'phones',
      };
      for (final c in kCategories) {
        final any = (kTypesByCategory[c.key] ?? const <String>[])
            .any((t) => kTryOnRules[c.key]!.kindFor(t) != null);
        expect(any, wearable.contains(c.key), reason: c.key);
      }
    });

    test('Dart кестесі серверлікімен ДӘЛ бірдей', () {
      final server = _parseServerRules();
      expect(server.keys.toSet(), kTryOnRules.keys.toSet());
      for (final key in kTryOnRules.keys) {
        final d = kTryOnRules[key]!;
        final s = server[key]!;
        expect(s.all, d.all, reason: '$key.all');
        expect(s.types, d.types, reason: '$key.types');
      }
    });

    test('FASHN-ды түрлер серверде де дәл осы', () {
      final src =
          File('supabase/functions/virtual-tryon/index.ts').readAsStringSync();
      final m = RegExp(r'FASHN_KINDS = new Set<TryOnKind>\(\[(.*?)\]\)')
          .firstMatch(src);
      expect(m, isNotNull);
      final server = RegExp(r'"([a-z-]+)"')
          .allMatches(m!.group(1)!)
          .map((x) => x.group(1)!)
          .toSet();
      final dart = TryOnKind.values
          .where((k) => k.fashnSupported)
          .map((k) => k.wire)
          .toSet();
      expect(server, dart);
    });
  });

  group('isTryOnEligible', () {
    test('киім, аяқ киім, бас киім, көзілдірік, сөмке, әшекей, сағат — иә', () {
      expect(isTryOnEligible(_p(categoryKey: 'shoes', type: 'Кеды')), isTrue);
      expect(isTryOnEligible(_p(categoryKey: 'tshirt', type: 'Поло')), isTrue);
      expect(isTryOnEligible(_p(categoryKey: 'outer', type: 'Пальто')), isTrue);
      expect(isTryOnEligible(_p(categoryKey: 'pants', type: 'Джинсы')), isTrue);
      expect(isTryOnEligible(_p(categoryKey: 'dress', type: 'Юбка')), isTrue);
      expect(isTryOnEligible(_p(categoryKey: 'caps', type: 'Кепка')), isTrue);
      expect(isTryOnEligible(_p(categoryKey: 'acc', type: 'Очки')), isTrue);
      expect(isTryOnEligible(_p(categoryKey: 'acc', type: 'Сумка')), isTrue);
      expect(
          isTryOnEligible(_p(categoryKey: 'jewelry', type: 'Кольцо')), isTrue);
      expect(isTryOnEligible(_p(categoryKey: 'jewelry', type: 'Часы')), isTrue);
      expect(isTryOnEligible(_p(categoryKey: 'phones', type: 'Смарт-часы')),
          isTrue);
    });

    test('түрлері: сағат = watch, сөмке = bag, көзілдірік = eyewear', () {
      TryOnKind? k(String c, String t) =>
          tryOnKindFor(categoryKey: c, type: t, audience: 'Женские');
      expect(k('jewelry', 'Часы'), TryOnKind.watch);
      expect(k('jewelry', 'Серьги'), TryOnKind.jewelry);
      expect(k('acc', 'Рюкзак'), TryOnKind.bag);
      expect(k('acc', 'Очки'), TryOnKind.eyewear);
      expect(k('dress', 'Платье'), TryOnKind.onePieces);
      expect(k('dress', 'Юбка'), TryOnKind.bottoms);
      expect(k('dress', 'Свой вариант'), TryOnKind.auto);
      expect(k('acc', 'Свой вариант'), TryOnKind.accessory);
    });

    test('электроника, азық, кітап, жиһаз, жабдық, әмиян, іш киім — жоқ', () {
      expect(isTryOnEligible(_p(categoryKey: 'electronics', type: 'Телевизор')),
          isFalse);
      expect(isTryOnEligible(_p(categoryKey: 'phones', type: 'Смартфон')),
          isFalse);
      expect(
          isTryOnEligible(_p(categoryKey: 'grocery', type: 'Снеки')), isFalse);
      expect(
          isTryOnEligible(_p(categoryKey: 'books', type: 'Учебная')), isFalse);
      expect(isTryOnEligible(_p(categoryKey: 'furniture', type: 'Диван')),
          isFalse);
      expect(isTryOnEligible(_p(categoryKey: 'sport', type: 'Мяч')), isFalse);
      expect(isTryOnEligible(_p(categoryKey: 'sport', type: 'Свой вариант')),
          isFalse);
      expect(isTryOnEligible(_p(categoryKey: 'sport', type: 'Топ')), isTrue);
      expect(isTryOnEligible(_p(categoryKey: 'acc', type: 'Кошелек')), isFalse);
      expect(isTryOnEligible(_p(categoryKey: 'underwear', type: 'Пижама')),
          isFalse);
      expect(isTryOnEligible(_p(categoryKey: 'kids', type: 'Детская одежда')),
          isFalse);
    });

    test('Детские аудиториясы ешқашан', () {
      expect(isTryOnEligible(_p(categoryKey: 'shoes', audience: 'Детские')),
          isFalse);
      expect(isTryOnEligible(_p(categoryKey: 'tshirt', audience: 'Детские')),
          isFalse);
    });

    test('categoryKey бос ескі тауар = аяқ киім (енді жарайды)', () {
      expect(isTryOnEligible(_p(categoryKey: '', type: 'Кроссовки')), isTrue);
    });

    test('жарамды сурет жоқ — түйме жоқ (сервер https талап етеді)', () {
      expect(isTryOnEligible(_p(images: const [])), isFalse);
      expect(isTryOnEligible(_p(images: const ['http://x/1.jpg'])), isFalse);
      expect(
          isTryOnEligible(
              _p(images: const ['http://x/1.jpg', 'https://x/2.jpg'])),
          isTrue);
    });

    test('түр атауындағы бос орын елеусіз', () {
      expect(
          isTryOnEligible(_p(categoryKey: 'jewelry', type: ' Часы ')), isTrue);
    });
  });

  group('сипаттама тіл бойынша', () {
    test('ru -> орысша, kk -> қазақша', () {
      final p = _p(
          description: 'Удобные кроссовки', descriptionKk: 'Ыңғайлы кроссовка');
      LocaleContext.currentLang = 'ru';
      expect(p.localizedDescription, 'Удобные кроссовки');
      LocaleContext.currentLang = 'kk';
      expect(p.localizedDescription, 'Ыңғайлы кроссовка');
    });

    test('тіл ауысқанда сол объект жаңа мәтін береді (қайта ашудың қажеті жоқ)',
        () {
      final p = _p(description: 'ru мәтін', descriptionKk: 'kk мәтін');
      final seen = <String>[];
      for (final lang in ['ru', 'kk', 'ru']) {
        LocaleContext.currentLang = lang;
        seen.add(p.localizedDescription);
      }
      expect(seen, ['ru мәтін', 'kk мәтін', 'ru мәтін']);
    });

    test('таңдалған тілде бос болса — екінші тілге түседі', () {
      final onlyRu = _p(description: 'Только русский');
      final onlyKk = _p(descriptionKk: 'Тек қазақша');
      LocaleContext.currentLang = 'kk';
      expect(onlyRu.localizedDescription, 'Только русский');
      LocaleContext.currentLang = 'ru';
      expect(onlyKk.localizedDescription, 'Тек қазақша');
    });

    test('бос/бос орын — hasDescription false', () {
      expect(_p().hasDescription, isFalse);
      expect(
          _p(description: '   ', descriptionKk: ' ').hasDescription, isFalse);
      expect(_p(descriptionKk: 'x').hasDescription, isTrue);
    });

    test('маусым қатары: бірнеше мән, тілге қарай аударылады', () {
      final p = _p(season: 'Лето,Зима');
      expect(p.seasonList, ['Лето', 'Зима']);
      LocaleContext.currentLang = 'ru';
      expect(p.seasonLabel, 'Лето, Зима');
      LocaleContext.currentLang = 'kk';
      expect(p.seasonLabel, 'Жаз, Қыс');
      expect(_p().seasonList, isEmpty);
    });
  });
}
