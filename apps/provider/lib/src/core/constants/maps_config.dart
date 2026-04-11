/// Static configuration for Google Maps-related services used by the provider
/// app (Maps SDK, Roads API, Directions API, …).
///
/// For now we fall back to a hardcoded dev key that matches the one in
/// `android/app/src/main/AndroidManifest.xml`. Override it per-environment at
/// build time with `--dart-define=GOOGLE_MAPS_API_KEY=...`.
///
/// TODO(ops): move the dev key out of source control and load from
/// `local.properties` / Info.plist / secret manager before shipping.
class MapsConfig {
  const MapsConfig._();

  static const String apiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: 'AIzaSyAdeUq7xKMQsvxWYwv8rTeE3YK_egOLx34',
  );
}
