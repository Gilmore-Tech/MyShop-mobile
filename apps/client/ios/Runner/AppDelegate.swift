import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Google Maps API key. Read from Info.plist (`GMSApiKey` entry,
    // which is populated from the `GOOGLE_MAPS_API_KEY` build setting
    // — defined per-config in Xcode or via `xcodebuild ... GOOGLE_MAPS_API_KEY=...`).
    // The hardcoded fallback was removed for v1.0 — a missing key now
    // renders blank maps instead of silently shipping a checked-in key.
    if let key = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !key.isEmpty {
      GMSServices.provideAPIKey(key)
    }

    // Obtain an APNs token without presenting a permission prompt over the
    // launch screen. FcmService owns the single user-facing request after
    // Flutter has painted its first frame.
    DispatchQueue.main.async {
      application.registerForRemoteNotifications()
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Logging-only overrides — the Firebase Messaging proxy still receives
  // the token via swizzling because `FirebaseAppDelegateProxyEnabled = true`
  // in Info.plist. Without these hooks the underlying APNs success/failure
  // is invisible, so we log to console for diagnosing future regressions.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    NSLog("[APNs] registered")
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("[APNs] registration FAILED: \(error.localizedDescription) (full: \(error))")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
