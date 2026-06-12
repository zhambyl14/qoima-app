import 'package:cloud_firestore/cloud_firestore.dart';

/// Дүкен ашу заявкасы. Жаңа admin (owner) тіркелген соң толтырып жібереді,
/// superadmin (маркетплейс модераторы) бекітеді немесе бас тартады.
/// Top-level collection: `shopRequests/{requestId}`.
class ShopRequestModel {
  final String id;

  // Иесі туралы
  final String ownerUid;
  final String ownerName;
  final String ownerPhone;
  final String ownerIin; // ЖСН / БСН

  // Дүкен туралы
  final String shopName;
  final String city;
  final String category;
  final String description;

  // Қаржы — төлемдер келетін карта (v10). Карта номері бос орынсыз (16 сан) сақталады.
  final String cardNumber;
  final String cardHolder; // картадағы аты-жөні (лат.) — опционалды
  final String cardBank;   // 'Kaspi Gold' т.б. — опционалды

  // Партнёр шартымен (оферта) танысып, келісті ме (v10).
  final bool contractAccepted;

  // Статус: 'pending' | 'approved' | 'rejected'
  final String status;

  // Мета
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String reviewedBy; // superadmin uid (болса)
  final String reviewNote; // бас тарту себебі (болса)

  const ShopRequestModel({
    required this.id,
    required this.ownerUid,
    required this.ownerName,
    required this.ownerPhone,
    this.ownerIin = '',
    required this.shopName,
    required this.city,
    required this.category,
    this.description = '',
    this.cardNumber = '',
    this.cardHolder = '',
    this.cardBank = '',
    this.contractAccepted = false,
    this.status = 'pending',
    required this.createdAt,
    this.reviewedAt,
    this.reviewedBy = '',
    this.reviewNote = '',
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  factory ShopRequestModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ShopRequestModel(
      id: doc.id,
      ownerUid: d['ownerUid'] as String? ?? '',
      ownerName: d['ownerName'] as String? ?? '',
      ownerPhone: d['ownerPhone'] as String? ?? '',
      ownerIin: d['ownerIin'] as String? ?? '',
      shopName: d['shopName'] as String? ?? '',
      city: d['city'] as String? ?? '',
      category: d['category'] as String? ?? '',
      description: d['description'] as String? ?? '',
      cardNumber: d['cardNumber'] as String? ?? '',
      cardHolder: d['cardHolder'] as String? ?? '',
      cardBank: d['cardBank'] as String? ?? '',
      contractAccepted: d['contractAccepted'] as bool? ?? false,
      status: d['status'] as String? ?? 'pending',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reviewedAt: (d['reviewedAt'] as Timestamp?)?.toDate(),
      reviewedBy: d['reviewedBy'] as String? ?? '',
      reviewNote: d['reviewNote'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'ownerUid': ownerUid,
        'ownerName': ownerName,
        'ownerPhone': ownerPhone,
        'ownerIin': ownerIin,
        'shopName': shopName,
        'city': city,
        'category': category,
        'description': description,
        'cardNumber': cardNumber,
        'cardHolder': cardHolder,
        'cardBank': cardBank,
        'contractAccepted': contractAccepted,
        'status': status,
        'createdAt': Timestamp.fromDate(createdAt),
        'reviewedAt': reviewedAt != null ? Timestamp.fromDate(reviewedAt!) : null,
        'reviewedBy': reviewedBy,
        'reviewNote': reviewNote,
      };

  ShopRequestModel copyWith({
    String? status,
    DateTime? reviewedAt,
    String? reviewedBy,
    String? reviewNote,
  }) =>
      ShopRequestModel(
        id: id,
        ownerUid: ownerUid,
        ownerName: ownerName,
        ownerPhone: ownerPhone,
        ownerIin: ownerIin,
        shopName: shopName,
        city: city,
        category: category,
        description: description,
        cardNumber: cardNumber,
        cardHolder: cardHolder,
        cardBank: cardBank,
        contractAccepted: contractAccepted,
        status: status ?? this.status,
        createdAt: createdAt,
        reviewedAt: reviewedAt ?? this.reviewedAt,
        reviewedBy: reviewedBy ?? this.reviewedBy,
        reviewNote: reviewNote ?? this.reviewNote,
      );
}
