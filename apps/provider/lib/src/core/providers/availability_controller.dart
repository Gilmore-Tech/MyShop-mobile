import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../features/profile/providers/provider_type_provider.dart';
import '../di/providers.dart';
import 'provider_status_provider.dart';

/// Last known GPS fix — populated by the location bridge whenever a fix
/// arrives. Used so the offline-toggle POST can include coordinates even
/// after the location stream has been torn down.
///
/// TODO(backend-B1): once POST /providers/availability ships, coords are
/// no longer required and this cache can be retired.
final lastKnownPositionProvider = StateProvider<Position?>((_) => null);

/// Orchestrates the online/offline transition for the provider:
///
///   - goOnline(): verify location → fetch a fix → POST
///     `/location/{driver,artisan}/update` with status:'online' → flip
///     local state. Posting before the flip closes a race where the
///     socket bridge's first heartbeat lagged the local toggle by a few
///     seconds, leaving the artisan locally-online but invisible to the
///     matcher. Jobs created in that window were silently missed.
///   - goOffline(): POST `status:'offline'` with last-known coords, then
///     flip local state so the UI reflects the intent immediately. Even if
///     the POST fails, local state still flips — otherwise the user is
///     stuck online on flaky networks.
///
/// Rationale: previously the app only signalled "offline" via the socket
/// disconnect, leaving the backend to infer offline via a location TTL.
/// That meant a freshly-toggled-off driver/artisan could still receive
/// dispatches for minutes. Explicit offline POST closes that window.
class AvailabilityController {
  AvailabilityController(this._ref);

  final Ref _ref;

  /// Flip to online. Verifies location services + permission first because
  /// an online provider without a GPS fix is invisible to the matcher
  /// (the backend requires `current_location IS NOT NULL`). POSTs the
  /// online status to the backend before flipping local state so the
  /// matcher includes this provider on the very next request.
  ///
  /// Returns `null` on success, or a user-facing error message on failure.
  Future<String?> goOnline() async {
    final gate = await _checkLocationReady();
    if (gate != null) return gate;

    // Need a fix to send with the online POST — backend requires
    // current_location to be non-null before it'll mark us online.
    Position position;
    final cached = _ref.read(lastKnownPositionProvider);
    if (cached != null) {
      position = cached;
    } else {
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
        _ref.read(lastKnownPositionProvider.notifier).state = position;
      } catch (e) {
        debugPrint('[Availability] online: position fetch failed — $e');
        return "Couldn't get your location. Check signal and try again.";
      }
    }

    final isArtisan = _ref.read(providerTypeProvider).isArtisan;
    final locationService = _ref.read(locationServiceProvider);
    try {
      if (isArtisan) {
        await locationService.updateArtisanLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          status: 'online',
        );
      } else {
        await locationService.updateDriverLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          status: 'online',
        );
      }
      debugPrint('[Availability] online POST sent');
    } on ApiException catch (e) {
      debugPrint('[Availability] online POST failed: $e');
      return e.message.isNotEmpty
          ? e.message
          : "Couldn't reach the server. Check your connection and try again.";
    } catch (e) {
      debugPrint('[Availability] online POST error: $e');
      return "Couldn't reach the server. Check your connection and try again.";
    }

    _ref.read(providerStatusProvider.notifier).goOnline();
    return null;
  }

  /// Verify location services are on and permission is granted. Requests
  /// permission if it hasn't been asked yet. Returns a user-facing error
  /// message if location can't be used, `null` if all good.
  Future<String?> _checkLocationReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return 'Turn on Location Services to go online.';
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return 'Location permission is required to go online. '
          'Grant it in Settings and try again.';
    }
    return null;
  }

  /// Force the provider offline without a user gesture — used by the
  /// location-permission watcher when the OS revokes permission or
  /// services are disabled mid-session.
  Future<void> forceOfflineDueToLocationLost() async {
    if (_ref.read(providerStatusProvider).isOffline) return;
    debugPrint('[Availability] forcing offline: location unavailable');
    await goOffline();
  }

  /// Flip to offline and inform the backend so the matcher stops
  /// dispatching. Local state flips immediately; the backend call is
  /// best-effort.
  Future<void> goOffline() async {
    _ref.read(providerStatusProvider.notifier).goOffline();
    await _postOffline();
  }

  Future<void> _postOffline() async {
    final pos = _ref.read(lastKnownPositionProvider);
    if (pos == null) {
      // No cached fix — can't satisfy the current endpoint's required
      // lat/lng. Safe to skip: the device never successfully went online
      // from the backend's perspective either.
      debugPrint('[Availability] no cached position — skipping offline POST');
      return;
    }

    final isArtisan = _ref.read(providerTypeProvider).isArtisan;
    final locationService = _ref.read(locationServiceProvider);
    try {
      if (isArtisan) {
        await locationService.updateArtisanLocation(
          latitude: pos.latitude,
          longitude: pos.longitude,
          status: 'offline',
        );
      } else {
        await locationService.updateDriverLocation(
          latitude: pos.latitude,
          longitude: pos.longitude,
          status: 'offline',
        );
      }
      debugPrint('[Availability] offline POST sent');
    } on ApiException catch (e) {
      debugPrint('[Availability] offline POST failed: $e');
    } catch (e) {
      debugPrint('[Availability] offline POST error: $e');
    }
  }
}

final availabilityControllerProvider = Provider<AvailabilityController>((ref) {
  return AvailabilityController(ref);
});
