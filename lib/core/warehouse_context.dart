import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/warehouse_model.dart';
import '../data/services/firestore_service.dart';
import 'app_user.dart';

class WarehouseContext extends ChangeNotifier {
  static const _prefKey = 'selected_warehouse_id';

  WarehouseModel? _current;
  List<WarehouseModel> _all = [];

  WarehouseModel? get current => _current;
  List<WarehouseModel> get all => _all;
  bool get isLoaded => _current != null;
  bool get isEmpty => _all.isEmpty;
  bool get hasMultiple => _all.length > 1;

  /// Admin тіркелген/кірген соң қоймаларды жүктейді
  Future<void> load() async {
    if (!AppUser.isAdmin) return;
    try {
      final service = FirestoreService();
      _all = await service.getWarehouses();
      if (_all.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString(_prefKey);

      _current = _all.firstWhere(
        (w) => w.id == savedId,
        orElse: () => _all.firstWhere((w) => w.isMain, orElse: () => _all.first),
      );
      notifyListeners();
    } catch (_) {}
  }

  void switchTo(WarehouseModel wh) async {
    _current = wh;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, wh.id);
  }

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
    _current = null;
    _all = [];
    notifyListeners();
  }
}
