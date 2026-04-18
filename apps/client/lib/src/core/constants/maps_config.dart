/// Static configuration for Google Maps services used by the client app
/// (Maps SDK, Places API, Geocoding API).
///
/// The key is read from `--dart-define=GOOGLE_MAPS_API_KEY=...` at build time.
/// Falls back to the dev key that matches AndroidManifest / Info.plist.
class MapsConfig {
  const MapsConfig._();

  static const String apiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: 'AIzaSyAdeUq7xKMQsvxWYwv8rTeE3YK_egOLx34',
  );
}
