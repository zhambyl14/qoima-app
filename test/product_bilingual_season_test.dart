import 'package:flutter_test/flutter_test.dart';
import 'package:qoima/core/locale_context.dart';
import 'package:qoima/data/models/product_model.dart';
import 'package:qoima/data/models/season_utils.dart';
import 'package:qoima/data/services/client_service.dart';

ProductModel _p({
  String season = '',
  String description = '',
  String descriptionKk = '',
  String keywords = '',
}) =>
    ProductModel(
      id: 'p1',
      name: 'Кроссовки',
      brand: 'Nike',
      type: 'Кроссовки',
      material: '',
      category: 'Мужские',
      color: 'Белый',
      articul: 'QM-1',
      status: ProductModel.statusInStock,
      images: const [],
      season: season,
      description: description,
      descriptionKk: descriptionKk,
      keywords: keywords,
    );

void main() {
  tearDown(() => LocaleContext.currentLang = 'ru');

  group('seasons', () {
    test('parse: legacy single value', () {
      expect(parseSeasons('Лето'), ['Лето']);
      expect(parseSeasons(''), isEmpty);
      expect(parseSeasons(null), isEmpty);
    });

    test('join: canonical order, no spaces, dedupe', () {
      expect(joinSeasons(['Весна', 'Лето']), 'Лето,Весна');
      expect(joinSeasons(['Зима', 'Лето', 'Зима']), 'Лето,Зима');
      expect(joinSeasons(const []), '');
      expect(ProductModel.joinSeasons(['Осень', 'Весна', 'Лето']),
          'Лето,Осень,Весна');
    });

    test('parse tolerates spaces and keeps unknown values last', () {
      expect(parseSeasons(' Зима , Лето ,Межсезонье'),
          ['Лето', 'Зима', 'Межсезонье']);
    });

    test('join/parse round-trip is stable', () {
      final s = joinSeasons(['Весна', 'Зима']);
      expect(joinSeasons(parseSeasons(s)), s);
      expect(s, 'Зима,Весна');
    });

    test('membership: multi and legacy', () {
      expect(seasonsContain('Лето,Зима', 'Зима'), isTrue);
      expect(seasonsContain('Лето,Зима', 'Осень'), isFalse);
      expect(seasonsContain('Лето', 'Лето'), isTrue);
      expect(seasonsContain('', 'Лето'), isFalse);
      // «Зима» — «Зимой» ішкі жолы емес, тек толық мән
      expect(seasonsContain('Зимний', 'Зима'), isFalse);
    });

    test('filter: any season matches; empty selection = everything', () {
      expect(seasonsMatchFilter('Лето,Зима', ['Зима']), isTrue);
      expect(seasonsMatchFilter('Лето,Зима', ['Осень', 'Весна']), isFalse);
      expect(seasonsMatchFilter('Лето,Зима', ['Осень', 'Лето']), isTrue);
      expect(seasonsMatchFilter('Лето', const []), isTrue);
      expect(seasonsMatchFilter('', ['Лето']), isFalse);
      expect(
          seasonsMatchFilter('', ['Лето'], includeUnspecified: true), isTrue);
    });

    test('ProductModel helpers', () {
      final p = _p(season: 'Лето,Зима');
      expect(p.seasonList, ['Лето', 'Зима']);
      expect(p.hasSeason('Зима'), isTrue);
      expect(p.hasSeason('Весна'), isFalse);
      expect(p.matchesSeasons(['Весна', 'Лето']), isTrue);
      expect(p.matchesSeasons(['Весна']), isFalse);
      expect(_p(season: 'Осень').matchesSeasons(['Осень']), isTrue);
    });

    test('seasonLabel follows app language', () {
      final p = _p(season: 'Лето,Зима');
      LocaleContext.currentLang = 'ru';
      expect(p.seasonLabel, 'Лето, Зима');
      LocaleContext.currentLang = 'kk';
      expect(p.seasonLabel, 'Жаз, Қыс');
      expect(_p().seasonLabel, '');
    });
  });

  group('bilingual description', () {
    test('descriptionFor picks language with fallback', () {
      final both = _p(description: 'Удобные', descriptionKk: 'Ыңғайлы');
      expect(both.descriptionFor('ru'), 'Удобные');
      expect(both.descriptionFor('kk'), 'Ыңғайлы');
      final ruOnly = _p(description: 'Удобные');
      expect(ruOnly.descriptionFor('kk'), 'Удобные');
      final kkOnly = _p(descriptionKk: 'Ыңғайлы');
      expect(kkOnly.descriptionFor('ru'), 'Ыңғайлы');
      expect(_p().descriptionFor('kk'), '');
      expect(
          _p(description: '  ', descriptionKk: 'Ыңғайлы').descriptionFor('ru'),
          'Ыңғайлы');
      expect(both.descriptionFor('xx'), 'Удобные');
    });

    test('localizedDescription uses current app language', () {
      final p = _p(description: 'Удобные', descriptionKk: 'Ыңғайлы');
      LocaleContext.currentLang = 'ru';
      expect(p.localizedDescription, 'Удобные');
      LocaleContext.currentLang = 'kk';
      expect(p.localizedDescription, 'Ыңғайлы');
      expect(p.hasDescription, isTrue);
      expect(_p().hasDescription, isFalse);
    });

    test('fromMap / toMap / copyWith / json', () {
      final p = ProductModel.fromMap({
        'id': 'x',
        'description': 'ру',
        'description_kk': 'қаз',
        'season': 'Лето,Зима',
      });
      expect(p.descriptionKk, 'қаз');
      expect(p.toMap()['description_kk'], 'қаз');
      expect(p.copyWith(descriptionKk: 'жаңа').descriptionKk, 'жаңа');
      expect(p.copyWith(name: 'n').descriptionKk, 'қаз');
      expect(ProductModel.fromJson(p.toJson()).descriptionKk, 'қаз');
      expect(ProductModel.fromMap({'id': 'y'}).descriptionKk, '');
    });

    test('toMap omits empty description_kk (un-migrated DB keeps working)', () {
      expect(
          _p(description: 'ру').toMap().containsKey('description_kk'), isFalse);
      expect(_p(descriptionKk: '   ').toMap().containsKey('description_kk'),
          isFalse);
      expect(
          _p(descriptionKk: 'a').toMap().containsKey('description_kk'), isTrue);
    });

    test('toMap clips description_kk to the DB limit', () {
      final long = 'a' * (ProductModel.descriptionMaxLength + 50);
      expect(
          (_p(descriptionKk: long).toMap()['description_kk'] as String).length,
          ProductModel.descriptionMaxLength);
    });

    test('descriptionKkPatch: untouched / set / clear', () {
      expect(ProductModel.descriptionKkPatch('', ''), isNull);
      expect(ProductModel.descriptionKkPatch('  ', ' '), isNull);
      expect(ProductModel.descriptionKkPatch('', ' қаз '), 'қаз');
      expect(ProductModel.descriptionKkPatch('қаз', ''), '');
      expect(ProductModel.descriptionKkPatch('қаз', 'жаңа'), 'жаңа');
    });
  });

  group('client search haystack', () {
    final kzOnly = _p(descriptionKk: 'жылы күрте', season: 'Лето,Зима');

    test('finds by Kazakh description', () {
      expect(productGroupMatches(ProductGroup([kzOnly]), 'жылы'), isTrue);
    });

    test('finds by any of several seasons in either language', () {
      final g = ProductGroup([kzOnly]);
      LocaleContext.currentLang = 'kk';
      expect(productGroupMatches(g, 'қыс'), isTrue);
      expect(productGroupMatches(g, 'жаз'), isTrue);
      expect(productGroupMatches(g, 'зима'), isTrue);
      expect(productGroupMatches(g, 'көктем'), isFalse);
    });
  });
}
