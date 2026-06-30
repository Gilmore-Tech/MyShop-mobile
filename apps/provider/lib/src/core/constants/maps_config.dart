import 'dart:io' show Platform;

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
/// must be set in `android/gradle.properties` (`MAPS_API_KEY=AIza…`) so
/// the native Maps SDK on Android picks it up via the manifest
/// `${MAPS_API_KEY}` placeholder. `tool/run.sh` / `tool/build.sh` wire all
/// of this from `.env.dev` / `.env.prod`.
class MapsConfig {
  const MapsConfig._();

  static const String apiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );

  /// This app's Android `applicationId` — sent as the `X-Android-Package`
  /// header so an Android-application-restricted key accepts a direct REST
  /// call to the Maps web services (see [restApiHeaders]).
  static const String androidPackage = 'com.gilmoretech.myshopprovider';

  /// This app's iOS bundle identifier — sent as `X-Ios-Bundle-Identifier`.
  static const String iosBundleId = 'com.gilmoretech.myshopprovider';

  /// SHA-1 fingerprint (colon-separated, uppercase — keytool format) of the
  /// signing certificate that is whitelisted on the Android key for THIS
  /// build. Supplied per build via `--dart-define=MAPS_ANDROID_CERT_SHA1=…`
  /// because debug and release builds present different certificates and the
  /// `X-Android-Cert` header value must match one allowed on the key:
  ///   - `tool/run.sh`   → the debug-keystore SHA-1
  ///   - `tool/build.sh` → the upload / Play App Signing SHA-1
  static const String androidCertSha1 = String.fromEnvironment(
    'MAPS_ANDROID_CERT_SHA1',
    defaultValue: '',
  );

  /// Headers that identify this app to the Google Maps **web-service** APIs
  /// (Directions, Roads, Static Maps) so a platform-restricted key accepts a
  /// direct REST request.
  ///
  /// The native Maps SDK adds these automatically when it renders the map;
  /// raw Dio/`Image.network` calls do not, so an app-restricted key rejects
  /// them with `REQUEST_DENIED` unless we attach these headers ourselves.
  ///
  /// Returns an empty map on platforms/values we can't identify (desktop,
  /// tests, or a missing cert) — the caller still sends the key, so an
  /// *unrestricted* key keeps working unchanged.
  static Map<String, String> get restApiHeaders {
    if (Platform.isAndroid) {
      if (androidCertSha1.isEmpty) return const {};
      return {
        'X-Android-Package': androidPackage,
        'X-Android-Cert': androidCertSha1,
      };
    }
    if (Platform.isIOS) {
      return {'X-Ios-Bundle-Identifier': iosBundleId};
    }
    return const {};
  }
}
