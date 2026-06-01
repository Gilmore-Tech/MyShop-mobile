/// Static configuration for Google Maps services used by the client app
/// (Maps SDK, Places API, Geocoding API).
///
/// The key MUST be supplied at build time via `--dart-define`:
///
///   flutter build apk --dart-define=GOOGLE_MAPS_API_KEY=AIza...
///
/// Empty default so a build that forgot the define fails visibly
/// instead of silently shipping with a placeholder key. The same value
/// must live in `android/local.properties` (`MAPS_API_KEY=AIza…`) for
/// the native Android Maps SDK to pick it up via the manifest
/// `${MAPS_API_KEY}` placeholder.
class MapsConfig {
  const MapsConfig._();

  static const String apiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );
}
