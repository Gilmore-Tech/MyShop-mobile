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
    // populated from the `GOOGLE_MAPS_API_KEY` build setting). The
    // hardcoded fallback was removed for v1.0 — a missing key renders
    // blank maps rather than silently shipping a checked-in key.
    if let key = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !key.isEmpty {
      GMSServices.provideAPIKey(key)
    }

    // Obtain the APNs token without prompting on the launch screen.
    // FcmService requests visible notification permission after first paint.
    DispatchQueue.main.async {
      application.registerForRemoteNotifications()
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

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
    registerDisplayWakeLockChannel(binaryMessenger: engineBridge.applicationRegistrar.messenger())
  }

  private func registerDisplayWakeLockChannel(binaryMessenger: FlutterBinaryMessenger) {
    let displayChannel = FlutterMethodChannel(
      name: "com.gilmoretech.myshopprovider/display",
      binaryMessenger: binaryMessenger
    )
    displayChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "setKeepScreenOn":
        guard
          let args = call.arguments as? [String: Any],
          let enabled = args["enabled"] as? Bool
        else {
          result(FlutterError(
            code: "INVALID_ARGUMENT",
            message: "Missing enabled boolean",
            details: nil
          ))
          return
        }
        UIApplication.shared.isIdleTimerDisabled = enabled
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
