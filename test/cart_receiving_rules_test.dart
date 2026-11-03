import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qoima/core/locale_context.dart';
import 'package:qoima/data/models/cart_item_model.dart';
import 'package:qoima/data/models/order_model.dart';
import 'package:qoima/ui/client/cart_receiving_rules.dart';

CartItemModel _line(String admin, {String store = 'Магазин', String id = 'p'}) =>
    CartItemModel(
      productId: '$id-$admin',
      productName: 'Товар',
      batchId: 'b1',
      size: '40',
      qty: 1,
      price: 10000,
      adminUid: admin,
      storeName: store,
      imageUrl: '',
      warehouseId: 'w-$admin',
    );

void main() {
  setUp(() => LocaleContext.currentLang = 'ru');

  group('normCity (сервердегі 0088 нормализациясымен бірдей)', () {
    test('регистр мен шеткі бос орын ескерілмейді', () {
      expect(normCity('  Алматы '), 'алматы');
      expect(normCity('АСТАНА'), normCity('астана'));
      expect(normCity(null), '');
    });

    // Сервер (0088) шет бос белгілерін regexp тізімімен алады. Тізім Dart
    // trim() жиынымен ДӘЛ сәйкес болмаса, қосымша Броньді көрсетіп, сервер
    // бас тартады (немесе керісінше). Тізімді миграция файлынан оқимыз.
    test('0088 v_ws тізімі Dart trim() жиынымен дәл сәйкес', () {
      final sql = File('supabase/migrations/0088_city_prepay_guard.sql')
          .readAsStringSync();
      final m = RegExp(r"v_ws constant text :=\s*'\[([^\]]*)\]'").firstMatch(sql);
      expect(m, isNotNull, reason: 'v_ws not found in 0088');
      final body = m!.group(1)!;
      // \t \n \v \f \r, литерал бос орын, \uXXXX және \uXXXX-\uXXXX аралықтары.
      const simple = {'t': 0x09, 'n': 0x0A, 'v': 0x0B, 'f': 0x0C, 'r': 0x0D};
      final tok = RegExp(r'\\u([0-9a-fA-F]{4})-\\u([0-9a-fA-F]{4})|\\u([0-9a-fA-F]{4})|\\([tnvfr])| ');
      final sqlSet = <int>{};
      var consumed = 0;
      for (final t in tok.allMatches(body)) {
        consumed += t.end - t.start;
        if (t.group(1) != null) {
          final a = int.parse(t.group(1)!, radix: 16);
          final b = int.parse(t.group(2)!, radix: 16);
          for (var c = a; c <= b; c++) {
            sqlSet.add(c);
          }
        } else if (t.group(3) != null) {
          sqlSet.add(int.parse(t.group(3)!, radix: 16));
        } else if (t.group(4) != null) {
          sqlSet.add(simple[t.group(4)!]!);
        } else {
          sqlSet.add(0x20);
        }
      }
      expect(consumed, body.length, reason: 'unparsed token in v_ws: $body');
      final dartSet = <int>{
        for (var c = 0; c <= 0xFFFF; c++)
          if (c < 0xD800 || c > 0xDFFF)
            if (String.fromCharCode(c).trim().isEmpty) c,
      };
      expect(sqlSet, dartSet);
      for (final c in dartSet) {
        final ws = String.fromCharCode(c);
        expect(normCity('$wsАлматы$ws'), 'алматы');
      }
    });
  });

  group('pickupAvailability', () {
    const cities = {'a1': 'Алматы', 'a2': 'Астана', 'a3': '', 'a4': '  алматы '};

    test('клиент қаласы белгісіз → бұрынғыдай бәрі ашық', () {
      final r = pickupAvailability(
          clientCity: '  ', items: [_line('a2')], storeCityByAdmin: cities);
      expect(r.allowed, isTrue);
      expect(r.foreignStores, isEmpty);
    });

    test('бір қала (регистр/бос орын әртүрлі) → ашық', () {
      final r = pickupAvailability(
          clientCity: 'АЛМАТЫ',
          items: [_line('a1'), _line('a4')],
          storeCityByAdmin: cities);
      expect(r.allowed, isTrue);
    });

    test('басқа қаладағы дүкен → тек жеткізу', () {
      final r = pickupAvailability(
          clientCity: 'Алматы',
          items: [_line('a2', store: 'Астана Shop')],
          storeCityByAdmin: cities);
      expect(r.allowed, isFalse);
      expect(r.foreignStores.single.adminUid, 'a2');
      expect(r.foreignStores.single.city, 'Астана');
    });

    test('аралас себет (бір дүкен өз қалада, біреуі басқа) → тек жеткізу', () {
      final r = pickupAvailability(
          clientCity: 'Алматы',
          items: [_line('a1'), _line('a2'), _line('a2', id: 'q')],
          storeCityByAdmin: cities);
      expect(r.allowed, isFalse);
      // Бір дүкеннің бірнеше жолы — бір рет.
      expect(r.foreignStores.map((s) => s.adminUid), ['a2']);
    });

    test('дүкен қаласы бос не әлі жүктелмеген → белгісіз, бөгемейміз', () {
      final r = pickupAvailability(
          clientCity: 'Алматы',
          items: [_line('a3'), _line('unknown')],
          storeCityByAdmin: cities);
      expect(r.allowed, isTrue);
    });

    test('бос себет → ашық', () {
      expect(
          pickupAvailability(
                  clientCity: 'Алматы', items: const [], storeCityByAdmin: cities)
              .allowed,
          isTrue);
    });

    test('permits: жеткізу мен null әрқашан, Бронь/Самовывоз тек ашық болса',
        () {
      final blocked = pickupAvailability(
          clientCity: 'Алматы', items: [_line('a2')], storeCityByAdmin: cities);
      expect(blocked.permits(OrderModel.typeDelivery), isTrue);
      expect(blocked.permits(null), isTrue);
      expect(blocked.permits(OrderModel.typeSmartReservation), isFalse);
      expect(blocked.permits(OrderModel.typeClickCollect), isFalse);
      expect(PickupAvailability.open.permits(OrderModel.typeSmartReservation),
          isTrue);
    });

    test('isPickupOrderType', () {
      expect(isPickupOrderType(OrderModel.typeSmartReservation), isTrue);
      expect(isPickupOrderType(OrderModel.typeClickCollect), isTrue);
      expect(isPickupOrderType(OrderModel.typeDelivery), isFalse);
      expect(isPickupOrderType(null), isFalse);
    });
  });

  group('pickupBlockedText', () {
    const cities = {'a1': 'Алматы', 'a2': 'Астана', 'a5': 'Шымкент'};

    test('бір дүкен — атымен және қаласымен (ru / kk)', () {
      final r = pickupAvailability(
          clientCity: 'Алматы',
          items: [_line('a2', store: 'Nomad')],
          storeCityByAdmin: cities);
      expect(pickupBlockedText(r),
          'Магазин «Nomad» в другом городе (Астана) — доступна только доставка с полной оплатой');
      LocaleContext.currentLang = 'kk';
      expect(pickupBlockedText(r),
          '«Nomad» дүкені басқа қалада (Астана) — тек толық төлеммен жеткізу қолжетімді');
    });

    test('бірнеше дүкен — жалпы мәтін', () {
      final r = pickupAvailability(
          clientCity: 'Алматы',
          items: [_line('a2'), _line('a5')],
          storeCityByAdmin: cities);
      expect(pickupBlockedText(r),
          'Магазин в другом городе — доступна только доставка с полной оплатой');
      expect(pickupBlockedText(r), isNot(contains('10%')));
    });
  });
}
