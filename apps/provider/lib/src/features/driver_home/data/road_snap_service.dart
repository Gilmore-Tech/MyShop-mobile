import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Deprecated compatibility wrapper kept only so older imports fail softly
/// during development. Provider no longer calls Google's Roads API from the
/// mobile app because that requires exposing a paid web-service key in the
/// APK/IPA. Use [GpsPositionSmoother] for local marker smoothing instead.
@Deprecated('Use GpsPositionSmoother; mobile Roads API calls are disabled.')
class RoadSnapService {
  RoadSnapService();

  Future<LatLng?> snap(LatLng point) async {
    return point;
  }
}

final roadSnapServiceProvider = Provider<RoadSnapService>((ref) {
  return RoadSnapService();
});
