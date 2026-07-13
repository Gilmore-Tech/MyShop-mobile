import Flutter
import UIKit
import GoogleMaps
import PushKit
import CallKit

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
    VoipCallBridge.shared.start()

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
    VoipCallBridge.shared.register(binaryMessenger: engineBridge.applicationRegistrar.messenger())
  }
}

private final class VoipCallBridge: NSObject, PKPushRegistryDelegate, CXProviderDelegate, FlutterStreamHandler {
  static let shared = VoipCallBridge()

  private var pushRegistry: PKPushRegistry?
  private var callProvider: CXProvider?
  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?
  private var voipToken: String?
  private var activeCallIds: [UUID: String] = [:]
  private var activePayloads: [UUID: [String: Any]] = [:]
  private var answeredCalls = Set<UUID>()

  func start() {
    if callProvider == nil {
      let config = CXProviderConfiguration(localizedName: "MyShop")
      config.supportsVideo = false
      config.maximumCallsPerCallGroup = 1
      config.maximumCallGroups = 1
      config.supportedHandleTypes = [.generic]
      let provider = CXProvider(configuration: config)
      provider.setDelegate(self, queue: nil)
      callProvider = provider
    }

    if pushRegistry == nil {
      let registry = PKPushRegistry(queue: DispatchQueue.main)
      registry.delegate = self
      registry.desiredPushTypes = [.voIP]
      pushRegistry = registry
    }
  }

  func register(binaryMessenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(
      name: "com.gilmoretech.myshop/voip_call",
      binaryMessenger: binaryMessenger
    )
    methodChannel?.setMethodCallHandler { [weak self] call, result in
      self?.handleMethodCall(call, result: result)
    }

    eventChannel = FlutterEventChannel(
      name: "com.gilmoretech.myshop/voip_call/events",
      binaryMessenger: binaryMessenger
    )
    eventChannel?.setStreamHandler(self)

    if let token = voipToken {
      emit("voipToken", payload: ["token": token])
    }
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getVoipToken":
      result(voipToken)
    case "showIncomingCall":
      guard let payload = call.arguments as? [String: Any] else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing call payload", details: nil))
        return
      }
      reportIncomingCall(payload: payload) { error in
        if let error = error {
          result(FlutterError(code: "CALLKIT_ERROR", message: error.localizedDescription, details: nil))
        } else {
          result(nil)
        }
      }
    case "endCall":
      guard
        let args = call.arguments as? [String: Any],
        let callId = args["callId"] as? String
      else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing callId", details: nil))
        return
      }
      endCall(callId: callId)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate pushCredentials: PKPushCredentials,
    for type: PKPushType
  ) {
    guard type == .voIP else { return }
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    voipToken = token
    NSLog("[VoIP] PushKit token updated")
    emit("voipToken", payload: ["token": token])
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didInvalidatePushTokenFor type: PKPushType
  ) {
    guard type == .voIP else { return }
    let token = voipToken
    voipToken = nil
    NSLog("[VoIP] PushKit token invalidated")
    emit("voipTokenInvalidated", payload: token == nil ? [:] : ["token": token!])
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }
    let callPayload = normalisePayload(payload.dictionaryPayload)
    reportIncomingCall(payload: callPayload) { _ in
      completion()
    }
  }

  private func reportIncomingCall(
    payload: [String: Any],
    completion: @escaping (Error?) -> Void
  ) {
    guard let provider = callProvider else {
      completion(nil)
      return
    }
    let callId = payload["callId"] as? String ?? UUID().uuidString
    let uuid = UUID(uuidString: callId) ?? UUID()
    activeCallIds[uuid] = callId
    activePayloads[uuid] = payload

    let callerName = (payload["callerName"] as? String)
      ?? (payload["title"] as? String)
      ?? "MyShop call"
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: callerName)
    update.localizedCallerName = callerName
    update.hasVideo = false

    provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
      if let error = error {
        NSLog("[VoIP] report incoming call failed: \(error.localizedDescription)")
      } else {
        self?.emit("incomingCall", payload: payload)
      }
      completion(error)
    }
  }

  private func endCall(callId: String) {
    let uuid = activeCallIds.first { $0.value == callId }?.key ?? UUID(uuidString: callId)
    guard let uuid = uuid else { return }
    callProvider?.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
    cleanup(uuid)
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    answeredCalls.insert(action.callUUID)
    emit("callAccepted", payload: payload(for: action.callUUID))
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    let type = answeredCalls.contains(action.callUUID) ? "callEnded" : "callDeclined"
    emit(type, payload: payload(for: action.callUUID))
    cleanup(action.callUUID)
    action.fulfill()
  }

  func providerDidReset(_ provider: CXProvider) {
    activeCallIds.removeAll()
    activePayloads.removeAll()
    answeredCalls.removeAll()
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    if let token = voipToken {
      emit("voipToken", payload: ["token": token])
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func emit(_ type: String, payload: [String: Any]) {
    var event = payload
    event["type"] = type
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(event)
    }
  }

  private func payload(for uuid: UUID) -> [String: Any] {
    var payload = activePayloads[uuid] ?? [:]
    if payload["callId"] == nil {
      payload["callId"] = activeCallIds[uuid] ?? uuid.uuidString
    }
    return payload
  }

  private func cleanup(_ uuid: UUID) {
    activeCallIds.removeValue(forKey: uuid)
    activePayloads.removeValue(forKey: uuid)
    answeredCalls.remove(uuid)
  }

  private func normalisePayload(_ raw: [AnyHashable: Any]) -> [String: Any] {
    var result: [String: Any] = [:]
    for (key, value) in raw {
      guard let stringKey = key as? String else { continue }
      if let nested = value as? [AnyHashable: Any] {
        result[stringKey] = normalisePayload(nested)
      } else {
        result[stringKey] = value
      }
    }
    return result
  }
}
