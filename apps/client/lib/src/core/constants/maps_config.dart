import 'dart:io' show Platform;

/// Static configuration for Google Maps services used by the client app
/// (Maps SDK, Places API, Geocoding API).
///
/// The key MUST be supplied at build time via `--dart-define`:
///
///   flutter build apk --dart-define=GOOGLE_MAPS_API_KEY=AIza...
///
/// Empty default so a build that forgot the define fails visibly
/// instead of silently shipping with a placeholder key. The same value
/// must live in `android/gradle.properties` (`MAPS_API_KEY=AIza…`) for
/// the native Android Maps SDK to pick it up via the manifest
/// `${MAPS_API_KEY}` placeholder. `tool/run.sh` / `tool/build.sh` wire
/// all of this from `.env.dev` / `.env.prod`.
class MapsConfig {
  const MapsConfig._();

  static const String apiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );

  /// This app's Android `applicationId` — sent as the `X-Android-Package`
  /// header so an Android-application-restricted key accepts a direct REST
  /// call to the Maps web services (see [restApiHeaders]).
  static const String androidPackage = 'com.gilmoretech.myshopclient';

  /// This app's iOS bundle identifier — sent as `X-Ios-Bundle-Identifier`.
  static const String iosBundleId = 'com.gilmoretech.myshopclient';

  /// SHA-1 fingerprint of the signing certificate whitelisted on the Android
  /// key for THIS build. The env file may use keytool/Cloud Console's
  /// colon-delimited form; [restApiHeaders] normalizes it to the delimiter-
  /// free Base16 format required by the `X-Android-Cert` HTTP header.
  ///   - `tool/run.sh`   → the debug-keystore SHA-1
  ///   - `tool/build.sh` → the upload / Play App Signing SHA-1
  static const String androidCertSha1 = String.fromEnvironment(
    'MAPS_ANDROID_CERT_SHA1',
    defaultValue: '',
  );

  static String normalizeAndroidCertSha1(String value) =>
      value.replaceAll(':', '').trim().toUpperCase();

  /// Headers that identify this app to the Google Maps **web-service** APIs
  /// (Places, Geocoding, Directions, Roads, Static Maps) so a
  /// platform-restricted key accepts a direct REST request.
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
      final cert = normalizeAndroidCertSha1(androidCertSha1);
      if (cert.isEmpty) return const {};
      return {
        'X-Android-Package': androidPackage,
        'X-Android-Cert': cert,
      };
    }
    if (Platform.isIOS) {
      return {'X-Ios-Bundle-Identifier': iosBundleId};
    }
    return const {};
  }
}
