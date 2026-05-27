import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Best-effort cached position used to display distance on the Live Job
/// Feed snapshot cards. Returns whatever the OS has cached from other
/// features (availability online-toggle, active-job tracking) — no new
/// permission prompt and no GPS hit. Returns null if no fix is cached or
/// any platform exception occurs; the carousel then hides the distance
/// line entirely.
final lastKnownPositionProvider = FutureProvider<Position?>((ref) async {
  try {
    return await Geolocator.getLastKnownPosition();
  } catch (_) {
    return null;
  }
});
