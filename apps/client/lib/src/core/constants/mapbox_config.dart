/// Mapbox configuration for the client app — used by the artisan
/// pin-drop / job-location flow. Tokens MUST be supplied at build time:
///
///   flutter build apk \
///     --dart-define=MAPBOX_ACCESS_TOKEN=pk.eyJ... \
///     --dart-define=MAPBOX_STYLE_URL=mapbox://styles/gilmore/cmnl0...
///
/// Empty `defaultValue` so a missing define fails visibly (map renders
/// the Mapbox watermark + "access token required" error) instead of
/// silently shipping with a checked-in token.
class MapboxConfig {
  const MapboxConfig._();

  static const String accessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: '',
  );

  static const String styleUrl = String.fromEnvironment(
    'MAPBOX_STYLE_URL',
    defaultValue: '',
  );

  /// Default map center — Kumasi, Ashanti Region.
  static const double defaultLat = 6.6885;
  static const double defaultLng = -1.6244;
}
