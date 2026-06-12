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
  // v7 — admin (owner) онбординг күйі
  String _shopStatus = 'approved'; // approved|none|pending|rejected
  bool _termsAccepted = false;

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
  String get shopStatus => _shopStatus;
  bool get termsAccepted => _termsAccepted;

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
    String shopStatus = 'approved',
    bool termsAccepted = false,
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
    _shopStatus = shopStatus;
    _termsAccepted = termsAccepted;
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
    _shopStatus = 'approved';
    _termsAccepted = false;
    notifyListeners();
  }
}
