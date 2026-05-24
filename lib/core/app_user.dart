class AppUser {
  static String uid                  = '';
  static String ownerUid             = ''; // admin → өз uid; seller → admin uid
  static String name                 = '';
  static String email                = '';
  static String role                 = ''; // 'admin' | 'seller'
  static bool   active               = true;
  // v2.2
  static String businessCode         = ''; // admin: 6 цифрлы код
  static String assignedWarehouseId  = ''; // seller-дің қоймасы
  static String joinStatus           = 'none'; // 'none' | 'pending' | 'active'

  static bool get isAdmin  => role == 'admin';
  static bool get isSeller => role == 'seller';
  static bool get isLoaded => uid.isNotEmpty;

  static void set({
    required String uid,
    required String ownerUid,
    required String name,
    required String email,
    required String role,
    bool   active               = true,
    String businessCode         = '',
    String assignedWarehouseId  = '',
    String joinStatus           = 'none',
  }) {
    AppUser.uid                 = uid;
    AppUser.ownerUid            = ownerUid;
    AppUser.name                = name;
    AppUser.email               = email;
    AppUser.role                = role;
    AppUser.active              = active;
    AppUser.businessCode        = businessCode;
    AppUser.assignedWarehouseId = assignedWarehouseId;
    AppUser.joinStatus          = joinStatus;
  }

  static void clear() {
    uid                 = '';
    ownerUid            = '';
    name                = '';
    email               = '';
    role                = '';
    active              = true;
    businessCode        = '';
    assignedWarehouseId = '';
    joinStatus          = 'none';
  }
}
