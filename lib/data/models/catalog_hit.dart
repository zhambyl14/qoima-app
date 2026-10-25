import 'cart_item_model.dart';

/// Бір өлшемнің партиясы (search_catalog.size_batches[өлшем], 0068).
/// Себет жолы ДӘЛ сол өлшемнің партиясымен құрылады — client_product_detail-дегі
/// `_batchForSize` логикасымен бірдей.
class CatalogSizeBatch {
  final String batchId;
  final String warehouseId;
  final double price; // тиімді баға (скидкамен)
  final double basePrice; // скидкасыз баға

  const CatalogSizeBatch({
    required this.batchId,
    required this.warehouseId,
    required this.price,
    required this.basePrice,
  });

  factory CatalogSizeBatch.fromMap(Map<String, dynamic> m) => CatalogSizeBatch(
        batchId: m['batch_id']?.toString() ?? '',
        warehouseId: m['warehouse_id']?.toString() ?? '',
        price: _num(m['price']),
        basePrice: _num(m['base_price']),
      );
}

double _num(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

/// `public.search_catalog` қайтаратын жол (AI көмекші / AI стилист нәтижесі).
/// [slot]/[why]/[reason] — тек AI жауабында болады.
class CatalogHit {
  final String productId;
  final String adminUid;
  final String storeName;
  final String city;
  final String name;
  final String brand;
  final String type;
  final String categoryKey;
  final String audience;
  final String color;
  final String season;
  final String material;
  final String variantNote;
  final String articul;
  final String description;
  final String imageUrl;
  final List<String> images;
  final double price;
  final double basePrice;
  final String batchId;
  final String warehouseId;

  /// {өлшем: қолжетімді дана}
  final Map<String, int> availableSizes;
  final Map<String, CatalogSizeBatch> sizeBatches;
  final double ratingAvg;
  final int ratingCount;

  /// Стилист слоты: top|outer|bottom|one_piece|shoes|accessory
  final String slot;

  /// Стилист түсіндірмесі («неге үйлеседі»).
  final String why;

  /// Көмекші түсіндірмесі («неге ұсынылды»).
  final String reason;

  const CatalogHit({
    required this.productId,
    required this.adminUid,
    required this.storeName,
    required this.city,
    required this.name,
    required this.brand,
    required this.type,
    required this.categoryKey,
    required this.audience,
    required this.color,
    required this.season,
    required this.material,
    required this.variantNote,
    required this.articul,
    required this.description,
    required this.imageUrl,
    required this.images,
    required this.price,
    required this.basePrice,
    required this.batchId,
    required this.warehouseId,
    required this.availableSizes,
    required this.sizeBatches,
    required this.ratingAvg,
    required this.ratingCount,
    this.slot = '',
    this.why = '',
    this.reason = '',
  });

  factory CatalogHit.fromMap(Map<String, dynamic> m) {
    final sizes = <String, int>{};
    final rawSizes = m['available_sizes'];
    if (rawSizes is Map) {
      rawSizes.forEach((k, v) {
        final q = v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0;
        if (q > 0) sizes[k.toString()] = q;
      });
    }
    final batches = <String, CatalogSizeBatch>{};
    final rawBatches = m['size_batches'];
    if (rawBatches is Map) {
      rawBatches.forEach((k, v) {
        if (v is Map) {
          batches[k.toString()] =
              CatalogSizeBatch.fromMap(Map<String, dynamic>.from(v));
        }
      });
    }
    final imgs = (m['images'] as List?)?.map((e) => e.toString()).toList() ??
        const <String>[];
    final image = m['image_url']?.toString() ?? '';
    return CatalogHit(
      productId: m['product_id']?.toString() ?? '',
      adminUid: m['admin_uid']?.toString() ?? '',
      storeName: m['store_name']?.toString() ?? '',
      city: m['city']?.toString() ?? '',
      name: m['name']?.toString() ?? '',
      brand: m['brand']?.toString() ?? '',
      type: m['type']?.toString() ?? '',
      categoryKey: m['category_key']?.toString() ?? '',
      audience: m['audience']?.toString() ?? '',
      color: m['color']?.toString() ?? '',
      season: m['season']?.toString() ?? '',
      material: m['material']?.toString() ?? '',
      variantNote: m['variant_note']?.toString() ?? '',
      articul: m['articul']?.toString() ?? '',
      description: m['description']?.toString() ?? '',
      imageUrl: image.isNotEmpty ? image : (imgs.isNotEmpty ? imgs.first : ''),
      images: imgs,
      price: _num(m['price']),
      basePrice: _num(m['base_price']),
      batchId: m['batch_id']?.toString() ?? '',
      warehouseId: m['warehouse_id']?.toString() ?? '',
      availableSizes: sizes,
      sizeBatches: batches,
      ratingAvg: _num(m['rating_avg']),
      ratingCount: (m['rating_count'] as num?)?.toInt() ?? 0,
      slot: m['slot']?.toString() ?? '',
      why: m['why']?.toString() ?? '',
      reason: m['reason']?.toString() ?? '',
    );
  }

  /// Өлшемдер: сандық болса санына қарай, әйтпесе S<M<L<XL тәртібімен.
  List<String> get sizeList {
    const letters = ['XXS', 'XS', 'S', 'M', 'L', 'XL', 'XXL', 'XXXL'];
    final keys = availableSizes.keys.toList();
    keys.sort((a, b) {
      final na = double.tryParse(a.replaceAll(',', '.'));
      final nb = double.tryParse(b.replaceAll(',', '.'));
      if (na != null && nb != null) return na.compareTo(nb);
      if (na != null) return -1;
      if (nb != null) return 1;
      final ia = letters.indexOf(a.toUpperCase());
      final ib = letters.indexOf(b.toUpperCase());
      if (ia >= 0 && ib >= 0) return ia.compareTo(ib);
      return a.compareTo(b);
    });
    return keys;
  }

  bool get hasDiscount => basePrice > price && basePrice > 0;

  /// Берілген өлшемнің бағасы (өлшемнің өз партиясы бойынша).
  double priceFor(String? size) {
    if (size == null) return price;
    return sizeBatches[size]?.price ?? price;
  }

  /// Себет жолы. Өлшемнің өз партиясы (қоймасы, бағасы) қолданылады;
  /// партия жоқ болса — негізгі (ең арзан) партия. warehouseAddress бос:
  /// себет/чекаут оны қоймадан өзі толтырады.
  CartItemModel toCartItem(String size) {
    final sb = sizeBatches[size];
    final p = sb?.price ?? price;
    final base = sb?.basePrice ?? basePrice;
    return CartItemModel(
      productId: productId,
      productName: name,
      batchId: sb?.batchId ?? batchId,
      size: size,
      qty: 1,
      price: p,
      originalPrice: base > p ? base : 0,
      adminUid: adminUid,
      storeName: storeName,
      imageUrl: imageUrl,
      brand: brand,
      type: type,
      color: color,
      variantNote: variantNote,
      articul: articul,
      warehouseId: sb?.warehouseId ?? warehouseId,
      warehouseAddress: '',
    );
  }
}
