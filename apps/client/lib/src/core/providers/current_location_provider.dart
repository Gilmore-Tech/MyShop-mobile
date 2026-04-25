import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Cached last-known device GPS fix. Populated by [CurrentLocationService.ensure]
/// (which runs at app start and on demand). Stays null when location services
/// are off or permission is denied — callers must fall back themselves
/// (typically to the pilot-city centre).
final currentDevicePositionProvider = StateProvider<Position?>((_) => null);

/// Resolves and caches the device's current location. Use this instead of
/// calling Geolocator directly so every screen shares the same cached fix
/// and the user only sees the permission prompt once per session.
class CurrentLocationService {
  CurrentLocationService(this._ref);

  final Ref _ref;

  /// Returns the cached fix if we already have one, otherwise requests
  /// permission (if needed), reads the GPS, caches it, and returns the
  /// new fix. Returns `null` when the user denies permission or location
  /// services are off — the caller decides the fallback.
  Future<Position?> ensure({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = _ref.read(currentDevicePositionProvider);
      if (cached != null) return cached;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _ref.read(currentDevicePositionProvider.notifier).state = position;
      return position;
    } catch (_) {
      return null;
    }
  }
}

final currentLocationServiceProvider = Provider<CurrentLocationService>((ref) {
  return CurrentLocationService(ref);
});
