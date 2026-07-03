import 'package:flutter/material.dart';

class AppUser extends ChangeNotifier {
  static late AppUser _i;
  static AppUser get current => _i;

  AppUser() {
    _i = this;
  }

  String _uid = '';
  String _ownerUid = '';
  String _name = '';
  String _email = '';
  String _phone = '';
  String _role = '';
  bool _active = true;
  String _businessCode = '';
  String _assignedWarehouseId = '';
  String _joinStatus = 'none';
  String _city = '';
  // Клиент поштасын растады ма (false болса — қарай алады, бірақ сатып ала алмайды)
  bool _emailVerified = false;
  // v7 — admin (owner) онбординг күйі
  String _shopStatus = 'approved'; // approved|none|pending|rejected
  bool _termsAccepted = false;
  // Жалпы блок: superadmin блоктаған иесі/сатушысы ешқандай әрекет жасай алмайды.
  bool _blocked = false;
  String _blockReason = '';
  String _blockSource = ''; // 'self' | 'owner' (иесі блокталған — каскад)

  String get uid => _uid;
  String get ownerUid => _ownerUid;
  String get name => _name;
  String get email => _email;
  String get phone => _phone;
  String get role => _role;
  bool get active => _active;
  String get businessCode => _businessCode;
  String get assignedWarehouseId => _assignedWarehouseId;
  String get joinStatus => _joinStatus;
  String get city => _city;
  bool get emailVerified => _emailVerified;
  String get shopStatus => _shopStatus;
  bool get termsAccepted => _termsAccepted;
  bool get blocked => _blocked;
  String get blockReason => _blockReason;
  String get blockSource => _blockSource;

  bool get isAdmin => _role == 'admin';
  bool get isSeller => _role == 'seller';
  bool get isClient => _role == 'client';
  bool get isSuperadmin => _role == 'superadmin';
  bool get isLoaded => _uid.isNotEmpty;
  bool get isShopApproved => _shopStatus == 'approved';

  set assignedWarehouseId(String v) {
    if (_assignedWarehouseId == v) return;
    _assignedWarehouseId = v;
    notifyListeners();
  }

  set joinStatus(String v) {
    if (_joinStatus == v) return;
    _joinStatus = v;
    notifyListeners();
  }

  set shopStatus(String v) {
    if (_shopStatus == v) return;
    _shopStatus = v;
    notifyListeners();
  }

  set termsAccepted(bool v) {
    if (_termsAccepted == v) return;
    _termsAccepted = v;
    notifyListeners();
  }

  void setEmailVerified(bool v) {
    if (_emailVerified == v) return;
    _emailVerified = v;
    notifyListeners();
  }

  void set({
    required String uid,
    required String ownerUid,
    required String name,
    required String email,
    required String role,
    bool active = true,
    String phone = '',
    String businessCode = '',
    String assignedWarehouseId = '',
    String joinStatus = 'none',
    String city = '',
    bool emailVerified = false,
    String shopStatus = 'approved',
    bool termsAccepted = false,
    bool blocked = false,
    String blockReason = '',
    String blockSource = '',
  }) {
    _uid = uid;
    _ownerUid = ownerUid;
    _name = name;
    _email = email;
    _phone = phone;
    _role = role;
    _active = active;
    _businessCode = businessCode;
    _assignedWarehouseId = assignedWarehouseId;
    _joinStatus = joinStatus;
    _city = city;
    _emailVerified = emailVerified;
    _shopStatus = shopStatus;
    _termsAccepted = termsAccepted;
    _blocked = blocked;
    _blockReason = blockReason;
    _blockSource = blockSource;
    notifyListeners();
  }

  /// Seller блокталған иесінен босап шықты: блок алынып, join күйі тазарады —
  /// реактивті gate SellerJoinScreen-ге ауыстырады.
  void detachedFromOwner() {
    _blocked = false;
    _blockReason = '';
    _blockSource = '';
    _ownerUid = '';
    _joinStatus = 'none';
    _assignedWarehouseId = '';
    notifyListeners();
  }

  void updateCity(String city) {
    if (_city == city) return;
    _city = city;
    notifyListeners();
  }

  void updatePhone(String phone) {
    if (_phone == phone) return;
    _phone = phone;
    notifyListeners();
  }

  void clear() {
    _uid = '';
    _ownerUid = '';
    _name = '';
    _email = '';
    _phone = '';
    _role = '';
    _active = true;
    _businessCode = '';
    _assignedWarehouseId = '';
    _joinStatus = 'none';
    _city = '';
    _emailVerified = false;
    _shopStatus = 'approved';
    _termsAccepted = false;
    _blocked = false;
    _blockReason = '';
    _blockSource = '';
    notifyListeners();
  }
}
