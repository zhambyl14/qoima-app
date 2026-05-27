import 'package:flutter/material.dart';

class AppUser extends ChangeNotifier {
  static late AppUser _i;
  static AppUser get current => _i;

  AppUser() { _i = this; }

  String _uid                 = '';
  String _ownerUid            = '';
  String _name                = '';
  String _email               = '';
  String _phone               = '';
  String _role                = '';
  bool   _active              = true;
  String _businessCode        = '';
  String _assignedWarehouseId = '';
  String _joinStatus          = 'none';

  String get uid                 => _uid;
  String get ownerUid            => _ownerUid;
  String get name                => _name;
  String get email               => _email;
  String get phone               => _phone;
  String get role                => _role;
  bool   get active              => _active;
  String get businessCode        => _businessCode;
  String get assignedWarehouseId => _assignedWarehouseId;
  String get joinStatus          => _joinStatus;

  bool get isAdmin  => _role == 'admin';
  bool get isSeller => _role == 'seller';
  bool get isClient => _role == 'client';
  bool get isLoaded => _uid.isNotEmpty;

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

  void set({
    required String uid,
    required String ownerUid,
    required String name,
    required String email,
    required String role,
    bool   active               = true,
    String phone                = '',
    String businessCode         = '',
    String assignedWarehouseId  = '',
    String joinStatus           = 'none',
  }) {
    _uid                 = uid;
    _ownerUid            = ownerUid;
    _name                = name;
    _email               = email;
    _phone               = phone;
    _role                = role;
    _active              = active;
    _businessCode        = businessCode;
    _assignedWarehouseId = assignedWarehouseId;
    _joinStatus          = joinStatus;
    notifyListeners();
  }

  void clear() {
    _uid                 = '';
    _ownerUid            = '';
    _name                = '';
    _email               = '';
    _phone               = '';
    _role                = '';
    _active              = true;
    _businessCode        = '';
    _assignedWarehouseId = '';
    _joinStatus          = 'none';
    notifyListeners();
  }
}
