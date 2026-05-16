/// Static configuration for Google Maps-related services used by the
/// provider app (Maps SDK, Roads API, Directions API, …).
///
/// The key MUST be supplied at build time via `--dart-define`:
///
///   flutter build apk --dart-define=GOOGLE_MAPS_API_KEY=AIza...
///
/// `defaultValue` is intentionally empty so a build without the define
/// fails fast (map widget renders blank + Directions calls reject)
/// rather than silently shipping with a placeholder key. The same value
/// must be set in `android/local.properties` (`MAPS_API_KEY=AIza…`) so
/// the native Maps SDK on Android picks it up via the manifest
/// `${MAPS_API_KEY}` placeholder.
class MapsConfig {
  const MapsConfig._();

  static const String apiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );
}
