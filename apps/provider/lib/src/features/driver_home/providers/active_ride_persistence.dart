import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the id of the driver's currently-accepted ride so the app can
/// recover from a crash, force-quit, or the bounce-back bug that would
/// otherwise leave the backend flagging the driver as `busy` on a ride the
/// client UI has already forgotten about.
///
/// Stored in SharedPreferences (not secure storage) — the ride id is a
/// non-sensitive UUID and we want fast synchronous-ish reads on app start.
class ActiveRidePersistence {
  static const _key = 'driver.active_ride_id';

  Future<void> save(String rideId) async {
    if (rideId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, rideId);
    debugPrint('[ActiveRidePersistence] saved $rideId');
  }

  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_key);
    debugPrint('[ActiveRidePersistence] read $id');
    return id;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    debugPrint('[ActiveRidePersistence] cleared');
  }
}
