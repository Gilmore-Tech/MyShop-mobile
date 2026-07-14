import Flutter
import UIKit
import GoogleMaps
import PushKit
import CallKit
import AVFAudio
import WebRTC

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var rootVoipBridgeRegistered = false
  private var rootDisplayChannelRegistered = false

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
    VoipCallBridge.shared.start()
    registerRootFlutterChannels()
    DispatchQueue.main.async { [weak self] in
      self?.registerRootFlutterChannels()
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
    VoipCallBridge.shared.register(binaryMessenger: engineBridge.applicationRegistrar.messenger())
    registerDisplayWakeLockChannel(binaryMessenger: engineBridge.applicationRegistrar.messenger())
  }

  private func registerRootFlutterChannels() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      NSLog("[VoIP] root FlutterViewController unavailable during launch")
      return
    }
    let messenger = controller.binaryMessenger

    if !rootVoipBridgeRegistered {
      VoipCallBridge.shared.register(binaryMessenger: messenger)
      rootVoipBridgeRegistered = true
      NSLog("[VoIP] bridge registered on root FlutterViewController")
    }

    if !rootDisplayChannelRegistered {
      registerDisplayWakeLockChannel(binaryMessenger: messenger)
      rootDisplayChannelRegistered = true
    }
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

private final class VoipCallBridge: NSObject, PKPushRegistryDelegate, CXProviderDelegate, FlutterStreamHandler {
  static let shared = VoipCallBridge()

  private var pushRegistry: PKPushRegistry?
  private var callProvider: CXProvider?
  private let callController = CXCallController()
  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?
  private var voipToken: String?
  private var activeCallIds: [UUID: String] = [:]
  private var activePayloads: [UUID: [String: Any]] = [:]
  private var answeredCalls = Set<UUID>()
  private var expiryWorkItems: [UUID: DispatchWorkItem] = [:]
  private var pendingCallActions: [[String: Any]] = []
  private var loadedPendingCallActions = false
  private let pendingCallActionsKey = "myshop.pendingCallKitActions"

  func start() {
    if !loadedPendingCallActions {
      pendingCallActions = UserDefaults.standard.array(forKey: pendingCallActionsKey)
        as? [[String: Any]] ?? []
      loadedPendingCallActions = true
    }
    if callProvider == nil {
      let config = CXProviderConfiguration(localizedName: "MyShop Provider")
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
    case "answerCall":
      guard
        let args = call.arguments as? [String: Any],
        let callId = args["callId"] as? String
      else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing callId", details: nil))
        return
      }
      guard let uuid = activeCallIds.first(where: { $0.value == callId })?.key else {
        result(false)
        return
      }
      if answeredCalls.contains(uuid) {
        result(true)
        return
      }
      let transaction = CXTransaction(action: CXAnswerCallAction(call: uuid))
      callController.request(transaction) { error in
        DispatchQueue.main.async {
          if let error = error {
            result(FlutterError(
              code: "CALLKIT_ANSWER_ERROR",
              message: error.localizedDescription,
              details: nil
            ))
          } else {
            result(true)
          }
        }
      }
    case "acknowledgeCallAction":
      guard
        let args = call.arguments as? [String: Any],
        let actionId = args["actionId"] as? String
      else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing actionId", details: nil))
        return
      }
      pendingCallActions.removeAll { $0["actionId"] as? String == actionId }
      persistPendingCallActions()
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
    NSLog("[VoIP] incoming PushKit payload callId=\(callPayload["callId"] ?? "missing")")
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
    if let existing = activeCallIds.first(where: { $0.value == callId })?.key {
      activePayloads[existing] = payload
      scheduleExpiry(for: existing, payload: payload)
      NSLog("[VoIP] duplicate incoming call ignored callId=\(callId)")
      completion(nil)
      return
    }
    let uuid = UUID(uuidString: callId) ?? UUID()
    activeCallIds[uuid] = callId
    activePayloads[uuid] = payload
    scheduleExpiry(for: uuid, payload: payload)

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
        self?.cleanup(uuid)
      } else {
        NSLog("[VoIP] CallKit incoming call reported callId=\(callId)")
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
    expiryWorkItems.removeValue(forKey: action.callUUID)?.cancel()
    enqueueCallAction("callAccepted", payload: payload(for: action.callUUID))
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    let type = answeredCalls.contains(action.callUUID) ? "callEnded" : "callDeclined"
    enqueueCallAction(type, payload: payload(for: action.callUUID))
    cleanup(action.callUUID)
    action.fulfill()
  }

  func providerDidReset(_ provider: CXProvider) {
    expiryWorkItems.values.forEach { $0.cancel() }
    expiryWorkItems.removeAll()
    activeCallIds.removeAll()
    activePayloads.removeAll()
    answeredCalls.removeAll()
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    do {
      try audioSession.setCategory(
        .playAndRecord,
        mode: .voiceChat,
        options: [.allowBluetooth, .allowBluetoothA2DP]
      )
    } catch {
      NSLog("[VoIP] audio session activation failed: \(error.localizedDescription)")
    }
    // CallKit owns activation. WebRTC must still be informed even when an
    // optional category override fails, otherwise both tracks can stay silent.
    RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
  }

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    if let token = voipToken {
      emit("voipToken", payload: ["token": token])
    }
    for action in pendingCallActions {
      emitEvent(action)
    }
    // PushKit can report CallKit before Flutter attaches its event listener.
    // Replay active incoming calls so Dart can join the call socket and receive
    // a caller-side cancellation without waiting for the user to answer.
    for payload in activePayloads.values {
      emit("incomingCall", payload: payload)
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
    emitEvent(event)
  }

  private func enqueueCallAction(_ type: String, payload: [String: Any]) {
    var event = payload
    event["type"] = type
    event["actionId"] = UUID().uuidString
    pendingCallActions.append(event)
    persistPendingCallActions()
    emitEvent(event)
  }

  private func persistPendingCallActions() {
    UserDefaults.standard.set(pendingCallActions, forKey: pendingCallActionsKey)
  }

  private func emitEvent(_ event: [String: Any]) {
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
    expiryWorkItems.removeValue(forKey: uuid)?.cancel()
    activeCallIds.removeValue(forKey: uuid)
    activePayloads.removeValue(forKey: uuid)
    answeredCalls.remove(uuid)
  }

  private func scheduleExpiry(for uuid: UUID, payload: [String: Any]) {
    expiryWorkItems.removeValue(forKey: uuid)?.cancel()
    guard let raw = payload["expiresAt"] as? String else { return }
    let fractionalFormatter = ISO8601DateFormatter()
    fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let expiresAt = fractionalFormatter.date(from: raw)
      ?? ISO8601DateFormatter().date(from: raw)
    else { return }

    let workItem = DispatchWorkItem { [weak self] in
      guard let self = self, self.activeCallIds[uuid] != nil else { return }
      let callId = self.activeCallIds[uuid] ?? uuid.uuidString
      self.callProvider?.reportCall(with: uuid, endedAt: Date(), reason: .unanswered)
      self.cleanup(uuid)
      NSLog("[VoIP] unanswered call expired callId=\(callId)")
    }
    expiryWorkItems[uuid] = workItem
    DispatchQueue.main.asyncAfter(
      deadline: .now() + max(0, expiresAt.timeIntervalSinceNow),
      execute: workItem
    )
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
