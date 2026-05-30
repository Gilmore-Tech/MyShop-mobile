import Flutter
import UIKit
import GoogleMaps
import UserNotifications

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

    // APNs registration backstop. The firebase_messaging plugin normally
    // requests permission and calls `application.registerForRemoteNotifications()`
    // via swizzling once its requestPermission() runs. On some device/build
    // combos that swizzled call never fires, APNs registration silently
    // never happens, and FCM then surfaces `apns-token-not-set` on
    // getToken() — which is exactly the symptom we hit on this build.
    //
    // Forcing the auth request + registration in native code is idempotent
    // (iOS returns the cached token when registration already succeeded)
    // and removes the dependency on plugin swizzling timing.
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .badge, .sound]
    ) { granted, error in
      if let error = error {
        NSLog("[APNs] requestAuthorization error: \(error.localizedDescription)")
      }
      if granted {
        DispatchQueue.main.async {
          application.registerForRemoteNotifications()
        }
      } else {
        NSLog("[APNs] requestAuthorization not granted")
      }
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
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    NSLog("[APNs] registered, token=\(hex.prefix(12))…\(hex.suffix(8))")
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
