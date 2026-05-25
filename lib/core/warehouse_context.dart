import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/warehouse_model.dart';
import '../data/services/firestore_service.dart';
import 'app_user.dart';

class WarehouseContext extends ChangeNotifier {
  static const _prefKey = 'selected_warehouse_id';

  WarehouseModel? _current;
  List<WarehouseModel> _all = [];

  StreamSubscription<List<WarehouseModel>>? _warehouseSub;
  StreamSubscription<String>? _sellerSub;

  WarehouseModel? get current => _current;
  List<WarehouseModel> get all => _all;
  bool get isLoaded => _current != null;
  bool get isEmpty => _all.isEmpty;
  bool get hasMultiple => _all.length > 1;

  Future<void> load() async {
    if (AppUser.isAdmin) {
      await _loadForAdmin();
    } else if (AppUser.isSeller) {
      await _loadForSeller();
    }
  }

  // Admin: subscribes to real-time warehouse stream so any warehouse add/remove
  // is immediately reflected everywhere via notifyListeners().
  Future<void> _loadForAdmin() async {
    await _warehouseSub?.cancel();
    try {
      final service = FirestoreService();
      final prefs   = await SharedPreferences.getInstance();
      final savedId = prefs.getString(_prefKey);

      _warehouseSub = service.watchWarehouses().listen(
        (warehouses) {
          _all = warehouses;
          if (_all.isEmpty) {
            _current = null;
          } else if (_current != null) {
            _current = _all.firstWhere(
              (w) => w.id == _current!.id,
              orElse: () => _all.first,
            );
          } else {
            _current = _all.firstWhere(
              (w) => w.id == savedId,
              orElse: () => _all.firstWhere((w) => w.isMain, orElse: () => _all.first),
            );
          }
          notifyListeners();
        },
        onError: (_) {}, // Stream errors don't crash the app.
      );
    } catch (_) {}
  }

  // Seller: watches own Firestore document so any admin reassignment is
  // immediately reflected in the UI without needing to restart the app.
  Future<void> _loadForSeller() async {
    await _sellerSub?.cancel();
    if (AppUser.ownerUid.isEmpty) return; // Not yet linked to an admin.
    try {
      final service      = FirestoreService();
      final warehouses   = await service.getWarehouses();
      _all               = warehouses;
      final warehouseId  = AppUser.assignedWarehouseId;
      if (warehouseId.isNotEmpty) {
        _current = _all.firstWhere(
          (w) => w.id == warehouseId,
          orElse: () => _all.isNotEmpty ? _all.first : _current!,
        );
      }
      notifyListeners();

      // Subscribe to Firestore so reassignment by admin triggers instant UI update.
      _sellerSub = service.watchSellerAssignedWarehouseId().listen(
        (newId) async {
          if (newId.isEmpty || newId == (_current?.id ?? '')) return;
          try {
            AppUser.assignedWarehouseId = newId;
            final whs = await service.getWarehouses();
            _all     = whs;
            _current = _all.firstWhere(
              (w) => w.id == newId,
              orElse: () => _all.isNotEmpty ? _all.first : _current!,
            );
            notifyListeners();
          } catch (_) {}
        },
        onError: (_) {},
      );
    } catch (_) {}
  }

  // Save pref BEFORE notifying so data is never lost on app restart.
  Future<void> switchTo(WarehouseModel wh) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, wh.id);
    _current = wh;
    notifyListeners();
  }

  // Kept for external callers that still pass data in (e.g., migration code).
  void refresh(List<WarehouseModel> warehouses) {
    _all = warehouses;
    if (_current != null) {
      _current = _all.firstWhere(
        (w) => w.id == _current!.id,
        orElse: () => _all.isNotEmpty ? _all.first : _current!,
      );
    } else if (_all.isNotEmpty) {
      _current = _all.firstWhere((w) => w.isMain, orElse: () => _all.first);
    }
    notifyListeners();
  }

  Future<void> reload() => load();

  void clear() {
    _warehouseSub?.cancel();
    _sellerSub?.cancel();
    _warehouseSub = null;
    _sellerSub    = null;
    _current      = null;
    _all          = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _warehouseSub?.cancel();
    _sellerSub?.cancel();
    super.dispose();
  }
}
