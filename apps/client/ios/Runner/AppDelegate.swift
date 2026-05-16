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
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
