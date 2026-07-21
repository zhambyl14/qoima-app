import '../../core/banks.dart';

/// Дүкен ашу заявкасы (Supabase `shop_requests`).
class ShopRequestModel {
  final String id;
  final String ownerUid;
  final String ownerName;
  final String ownerPhone;
  final String ownerIin; // ЖСН / БСН
  final String shopName;
  final String city;
  final String category;
  final String description;
  final String cardNumber;
  final String cardHolder;
  final String cardBank;
  final String kaspiLink; // ЕСКІ өріс (bank_qrs.kaspi-ге көшеді)
  final Map<String, String> bankQrs; // {bank_id: qr_link}
  final bool contractAccepted;
  final String status; // 'pending' | 'approved' | 'rejected'
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String reviewedBy;
  final String reviewNote;

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
    this.kaspiLink = '',
    this.bankQrs = const {},
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

  /// Supabase `shop_requests` жолынан (snake_case бағандар).
  factory ShopRequestModel.fromMap(Map<String, dynamic> m) {
    DateTime? dtn(dynamic v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
    return ShopRequestModel(
      id: m['id'] as String? ?? '',
      ownerUid: m['owner_uid'] as String? ?? '',
      ownerName: m['owner_name'] as String? ?? '',
      ownerPhone: m['owner_phone'] as String? ?? '',
      ownerIin: m['owner_iin'] as String? ?? '',
      shopName: m['shop_name'] as String? ?? '',
      city: m['city'] as String? ?? '',
      category: m['category'] as String? ?? '',
      description: m['description'] as String? ?? '',
      cardNumber: m['card_number'] as String? ?? '',
      cardHolder: m['card_holder'] as String? ?? '',
      cardBank: m['card_bank'] as String? ?? '',
      kaspiLink: m['kaspi_link'] as String? ?? '',
      bankQrs: parseBankQrs(m['bank_qrs'], m['kaspi_link'] as String? ?? ''),
      contractAccepted: m['contract_accepted'] as bool? ?? false,
      status: m['status'] as String? ?? 'pending',
      createdAt: dtn(m['created_at']) ?? DateTime.now(),
      reviewedAt: dtn(m['reviewed_at']),
      reviewedBy: m['reviewed_by'] as String? ?? '',
      reviewNote: m['review_note'] as String? ?? '',
    );
  }

  /// Supabase жазу үшін (insert; id/даталарды DB басқарады).
  Map<String, dynamic> toMap() => {
        'owner_uid': ownerUid,
        'owner_name': ownerName,
        'owner_phone': ownerPhone,
        'owner_iin': ownerIin,
        'shop_name': shopName,
        'city': city,
        'category': category,
        'description': description,
        'card_number': cardNumber,
        'card_holder': cardHolder,
        'card_bank': cardBank,
        'kaspi_link': kaspiLink,
        'bank_qrs': bankQrs,
        'contract_accepted': contractAccepted,
        'status': status,
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
        kaspiLink: kaspiLink,
        bankQrs: bankQrs,
        contractAccepted: contractAccepted,
        status: status ?? this.status,
        createdAt: createdAt,
        reviewedAt: reviewedAt ?? this.reviewedAt,
        reviewedBy: reviewedBy ?? this.reviewedBy,
        reviewNote: reviewNote ?? this.reviewNote,
      );
}
