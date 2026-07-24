import 'package:api_client/mobile_diagnostics.dart' show debugLog;
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A location the user has recently picked from any location-search
/// surface (ride destination search, job location search, map pickers).
/// Persisted locally per-install and cleared on logout — see
/// logout_cleanup_bridge. Distinct from the backend "saved locations"
/// (Home/Work): this is a rolling history of recent picks, capped at
/// [_maxEntries].
class RecentLocation {
  final String name;
  final String address;
  final double lat;
  final double lng;
  final int lastUsedAt;

  const RecentLocation({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.lastUsedAt,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        'lat': lat,
        'lng': lng,
        'lastUsedAt': lastUsedAt,
      };

  static RecentLocation? fromJson(Map<String, dynamic> j) {
    final lat = (j['lat'] as num?)?.toDouble();
    final lng = (j['lng'] as num?)?.toDouble();
    final name = j['name'] as String?;
    final address = j['address'] as String?;
    if (lat == null || lng == null || name == null || address == null) {
      return null;
    }
    return RecentLocation(
      name: name,
      address: address,
      lat: lat,
      lng: lng,
      lastUsedAt: (j['lastUsedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

class RecentLocationsNotifier extends StateNotifier<List<RecentLocation>> {
  RecentLocationsNotifier() : super(const []) {
    _hydrate();
  }

  static const _storageKey = 'ride_recent_locations_v1';
  static const _maxEntries = 5;

  /// Completes once the initial disk read finishes (success or failure).
  /// `add()` awaits this so a fast tap immediately after construction
  /// doesn't get overwritten by the still-pending hydrate.
  final Completer<void> _hydrated = Completer<void>();

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final items = decoded
          .whereType<Map<String, dynamic>>()
          .map(RecentLocation.fromJson)
          .whereType<RecentLocation>()
          .toList(growable: false);
      if (!mounted) return;
      state = items;
    } catch (e) {
      debugLog(() => '[RecentLocations] hydrate failed: $e');
      // Drop a corrupt blob so the next save starts clean.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_storageKey);
      } catch (_) {}
    } finally {
      if (!_hydrated.isCompleted) _hydrated.complete();
    }
  }

  Future<void> add({
    required String name,
    required String address,
    required double lat,
    required double lng,
  }) async {
    if (!_hydrated.isCompleted) await _hydrated.future;
    if (!mounted) return;

    // Dedupe by coordinate (~11m tolerance). Picking the same spot twice
    // shouldn't fill the list with near-identical entries.
    bool sameSpot(RecentLocation r) =>
        (r.lat - lat).abs() < 1e-4 && (r.lng - lng).abs() < 1e-4;

    final entry = RecentLocation(
      name: name,
      address: address,
      lat: lat,
      lng: lng,
      lastUsedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final next = <RecentLocation>[
      entry,
      for (final r in state)
        if (!sameSpot(r)) r,
    ];
    if (next.length > _maxEntries) {
      next.removeRange(_maxEntries, next.length);
    }
    state = next;
    await _persist(next);
  }

  Future<void> clear() async {
    if (mounted) state = const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (e) {
      debugLog(() => '[RecentLocations] clear failed: $e');
    }
  }

  Future<void> _persist(List<RecentLocation> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (items.isEmpty) {
        await prefs.remove(_storageKey);
        return;
      }
      await prefs.setString(
        _storageKey,
        jsonEncode(items.map((i) => i.toJson()).toList()),
      );
    } catch (e) {
      debugLog(() => '[RecentLocations] persist failed: $e');
    }
  }
}

final recentLocationsProvider =
    StateNotifierProvider<RecentLocationsNotifier, List<RecentLocation>>(
  (_) => RecentLocationsNotifier(),
);
