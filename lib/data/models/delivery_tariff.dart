import 'dart:convert';

/// Жеткізу тарифі (0050) — superadmin «Реквизиты» экранында өзгертеді,
/// app_settings-те сақталады, `delivery_tariff()` RPC арқылы оқылады
/// (қонақ та себетте ақыны көруі керек — сондықтан публичті RPC).
///
/// ПРИНЦИП: жеткізу ЕШҚАШАН тегін емес, бірақ арзан. «Тегін жеткізу»
/// негізсіз бас тартуларды көбейтеді де, жол шығыны жабылмайды.
class DeliveryTariff {
  /// Қала ішіндегі базалық ақы.
  final double baseFee;

  /// Үлкен чекке арналған төмендетілген ақы ([reducedFrom]-нан бастап).
  final double reducedFee;

  /// Осы сомадан асқанда [reducedFee] қолданылады (0 = өшірулі).
  final double reducedFrom;

  /// Бір баруда 2-ші, 3-ші дүкеннен алу — базадан пайызбен (әр дүкен = жеке
  /// қоймаға соғу, сондықтан толық ақы емес, бірақ тегін де емес).
  final int extraStorePercent;

  /// «Өлшеп көру» қосқаны үшін (курьер қосымша өлшем алып барады).
  final double fittingFee;

  /// Бір тапсырыста қанша позицияға қосымша өлшем сұрауға болады.
  final int fittingMaxItems;

  /// Курьермен ҚАЙТАРУ (возврат) ақысы. Клиент курьерге төлейді; қайтарылатын
  /// тауар сомасынан ЕШҚАШАН шегерілмейді (0052).
  final double returnFee;

  /// Курьерлік қызмет ІСКЕ ҚОСЫЛҒАН қалалар (0055) — модератор басқарады.
  ///
  /// ⚠️ БОС ТІЗІМ = ШЕКТЕУ ЖОҚ (барлық қалада қосулы). Серверде де
  /// (`courier_city_enabled`) дәл сол ереже — екеуі бір ақиқатты айтуы керек.
  final List<String> courierCities;

  const DeliveryTariff({
    this.baseFee = 690,
    this.reducedFee = 390,
    this.reducedFrom = 15000,
    this.extraStorePercent = 50,
    this.fittingFee = 300,
    this.fittingMaxItems = 2,
    this.returnFee = 1500,
    this.courierCities = const [],
  });

  static double _num(Map<String, String> m, String k, double fallback) =>
      double.tryParse(m[k] ?? '') ?? fallback;

  static List<String> _cities(Map<String, String> m) {
    final raw = (m['delivery_courier_cities'] ?? '').trim();
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Осы қалада платформа курьері жұмыс істей ме.
  bool courierWorksIn(String city) {
    final c = city.trim().toLowerCase();
    if (c.isEmpty) return false;
    if (courierCities.isEmpty) return true; // шектеу қойылмаған
    return courierCities.any((e) => e.trim().toLowerCase() == c);
  }

  factory DeliveryTariff.fromMap(Map<String, String> m) {
    const d = DeliveryTariff();
    return DeliveryTariff(
      baseFee: _num(m, 'delivery_base_fee', d.baseFee),
      reducedFee: _num(m, 'delivery_reduced_fee', d.reducedFee),
      reducedFrom: _num(m, 'delivery_reduced_from', d.reducedFrom),
      extraStorePercent:
          _num(m, 'delivery_extra_store_percent', d.extraStorePercent.toDouble())
              .round(),
      fittingFee: _num(m, 'delivery_fitting_fee', d.fittingFee),
      fittingMaxItems:
          _num(m, 'delivery_fitting_max_items', d.fittingMaxItems.toDouble())
              .round(),
      returnFee: _num(m, 'delivery_return_fee', d.returnFee),
      courierCities: _cities(m),
    );
  }

  Map<String, String> toMap() => {
        'delivery_base_fee': baseFee.toStringAsFixed(0),
        'delivery_reduced_fee': reducedFee.toStringAsFixed(0),
        'delivery_reduced_from': reducedFrom.toStringAsFixed(0),
        'delivery_extra_store_percent': '$extraStorePercent',
        'delivery_fitting_fee': fittingFee.toStringAsFixed(0),
        'delivery_fitting_max_items': '$fittingMaxItems',
        'delivery_return_fee': returnFee.toStringAsFixed(0),
        'delivery_courier_cities': jsonEncode(courierCities),
      };

  DeliveryTariff copyWith({
    double? baseFee,
    double? reducedFee,
    double? reducedFrom,
    int? extraStorePercent,
    double? fittingFee,
    int? fittingMaxItems,
    double? returnFee,
    List<String>? courierCities,
  }) =>
      DeliveryTariff(
        baseFee: baseFee ?? this.baseFee,
        reducedFee: reducedFee ?? this.reducedFee,
        reducedFrom: reducedFrom ?? this.reducedFrom,
        extraStorePercent: extraStorePercent ?? this.extraStorePercent,
        fittingFee: fittingFee ?? this.fittingFee,
        fittingMaxItems: fittingMaxItems ?? this.fittingMaxItems,
        returnFee: returnFee ?? this.returnFee,
        courierCities: courierCities ?? this.courierCities,
      );

  /// Бүкіл тапсырыс сомасына («барлық суб-тапсырыс» қосындысы) қатысты
  /// бір баруға түсетін базалық ақы.
  double feeForTotal(double orderTotal) =>
      (reducedFrom > 0 && orderTotal >= reducedFrom) ? reducedFee : baseFee;

  /// Суб-тапсырыстың (әр қойма — жеке тапсырыс) үлесі. Бірінші қойма толық
  /// ақы төлейді, қалғаны [extraStorePercent] пайызбен.
  ///
  /// Бүтінге дейін дөңгелектенеді — клиентке «345,5 ₸» көрсетілмеуі үшін.
  double feeForSubOrder({required double orderTotal, required int index}) {
    final base = feeForTotal(orderTotal);
    if (index <= 0) return base;
    return (base * extraStorePercent / 100).roundToDouble();
  }

  /// Бүкіл себет үшін жалпы жеткізу ақысы ([storeCount] — қойма саны).
  double totalFee({required double orderTotal, required int storeCount}) {
    var sum = 0.0;
    for (var i = 0; i < storeCount; i++) {
      sum += feeForSubOrder(orderTotal: orderTotal, index: i);
    }
    return sum;
  }
}
