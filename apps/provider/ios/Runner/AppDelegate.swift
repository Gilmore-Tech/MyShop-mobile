import Flutter
import UIKit
import UserNotifications
import GoogleMaps
import PushKit
import CallKit
import AVFAudio
import WebRTC
import CoreLocation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var rootVoipBridgeRegistered = false
  private var rootRequestActionBridgeRegistered = false
  private var rootLiveActivityBridgeRegistered = false
  private var rootDisplayChannelRegistered = false
  private var rootLocationAuthorizationBridgeRegistered = false

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
    IncomingRequestActionBridge.shared.start()
    RequestLiveActivityBridge.shared.start()
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
    IncomingRequestActionBridge.shared.register(
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    RequestLiveActivityBridge.shared.register(
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    AlwaysLocationAuthorizationBridge.shared.register(
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    registerDisplayWakeLockChannel(binaryMessenger: engineBridge.applicationRegistrar.messenger())
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if IncomingRequestActionBridge.shared.handle(url: url) {
      return true
    }
    return super.application(app, open: url, options: options)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if IncomingRequestActionBridge.shared.handle(response: response, center: center) {
      completionHandler()
      return
    }

    // Preserve FlutterFire / flutter_local_notifications handling for the
    // default notification tap and for every unrelated notification category.
    super.userNotificationCenter(
      center,
      didReceive: response,
      withCompletionHandler: completionHandler
    )
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

    if !rootRequestActionBridgeRegistered {
      IncomingRequestActionBridge.shared.register(binaryMessenger: messenger)
      rootRequestActionBridgeRegistered = true
      NSLog("[RequestAction] bridge registered on root FlutterViewController")
    }

    if !rootLiveActivityBridgeRegistered {
      RequestLiveActivityBridge.shared.register(binaryMessenger: messenger)
      rootLiveActivityBridgeRegistered = true
      NSLog("[LiveActivity] bridge registered on root FlutterViewController")
    }

    if !rootDisplayChannelRegistered {
      registerDisplayWakeLockChannel(binaryMessenger: messenger)
      rootDisplayChannelRegistered = true
    }

    if !rootLocationAuthorizationBridgeRegistered {
      AlwaysLocationAuthorizationBridge.shared.register(binaryMessenger: messenger)
      rootLocationAuthorizationBridgeRegistered = true
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

/// Owns the iOS-only second-stage location authorization request.
///
/// Registration is harmless and never asks for permission. The Core Location
/// request is made only when Dart invokes the method after the provider taps
/// Go Online and accepts the in-app background-location disclosure.
final class AlwaysLocationAuthorizationBridge: NSObject, CLLocationManagerDelegate {
  static let shared = AlwaysLocationAuthorizationBridge()

  private enum AuthorizationRequestKind {
    case whenInUse
    case always
  }

  private let channelName = "com.gilmoretech.myshopprovider/location_authorization"
  private let requestAttemptedKey = "myshop.didRequestAlwaysLocationAuthorization"
  private let decisionTimeout: TimeInterval = 30
  private let foregroundActivationTimeout: TimeInterval = 5

  private var methodChannel: FlutterMethodChannel?
  private var locationManager: CLLocationManager?
  private var pendingResult: FlutterResult?
  private var pendingRequestKind: AuthorizationRequestKind?
  private var pollTimer: Timer?
  private var timeoutWorkItem: DispatchWorkItem?
  private var requestIssuedAt: Date?

  func register(binaryMessenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: binaryMessenger
    )
    methodChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(
          code: "BRIDGE_UNAVAILABLE",
          message: "The location authorization bridge is unavailable.",
          details: nil
        ))
        return
      }
      switch call.method {
      case "getAuthorizationStatus":
        let manager = CLLocationManager()
        let status = self.statusName(manager.authorizationStatus)
        NSLog("[LocationAuthorization] status query: \(status)")
        result(status)
      case "requestWhenInUseAuthorization":
        DispatchQueue.main.async {
          self.requestWhenInUseAuthorization(result: result)
        }
      case "requestAlwaysAuthorization":
        DispatchQueue.main.async {
          self.requestAlwaysAuthorization(result: result)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func requestWhenInUseAuthorization(result: @escaping FlutterResult) {
    guard UIApplication.shared.applicationState == .active else {
      result(FlutterError(
        code: "NOT_FOREGROUND",
        message: "Location authorization must be requested in the foreground.",
        details: nil
      ))
      return
    }

    guard pendingResult == nil else {
      result(FlutterError(
        code: "REQUEST_IN_PROGRESS",
        message: "A location authorization request is already in progress.",
        details: nil
      ))
      return
    }

    let manager = CLLocationManager()
    let currentStatus = manager.authorizationStatus
    NSLog(
      "[LocationAuthorization] When In Use request from \(statusName(currentStatus))"
    )
    guard currentStatus == .notDetermined else {
      result(statusName(currentStatus))
      return
    }

    guard hasWhenInUseUsageDescription else {
      result(FlutterError(
        code: "MISSING_USAGE_DESCRIPTION",
        message: "The iOS foreground-location usage description is missing.",
        details: nil
      ))
      return
    }

    manager.delegate = self
    locationManager = manager
    pendingResult = result
    pendingRequestKind = .whenInUse

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak manager] in
      guard let self, let manager, self.pendingResult != nil else { return }
      self.requestIssuedAt = Date()
      manager.requestWhenInUseAuthorization()
      self.startPolling()
      self.startTimeout()
    }
  }

  private func requestAlwaysAuthorization(
    result: @escaping FlutterResult,
    foregroundWaitStartedAt: Date? = nil
  ) {
    guard UIApplication.shared.applicationState == .active else {
      // Dismissing the first-stage When In Use system sheet can deliver the
      // Core Location callback while UIApplication is still briefly inactive.
      // A second-stage request made in that window is ignored by iOS. Wait for
      // the app to become active instead of making the provider tap again.
      let waitStartedAt = foregroundWaitStartedAt ?? Date()
      if Date().timeIntervalSince(waitStartedAt) < foregroundActivationTimeout {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
          self?.requestAlwaysAuthorization(
            result: result,
            foregroundWaitStartedAt: waitStartedAt
          )
        }
        return
      }
      result(FlutterError(
        code: "NOT_FOREGROUND",
        message: "Always location authorization must be requested in the foreground.",
        details: nil
      ))
      return
    }

    guard pendingResult == nil else {
      result(FlutterError(
        code: "REQUEST_IN_PROGRESS",
        message: "An Always location authorization request is already in progress.",
        details: nil
      ))
      return
    }

    let manager = CLLocationManager()
    let currentStatus = manager.authorizationStatus
    NSLog(
      "[LocationAuthorization] Always request from \(statusName(currentStatus))"
    )
    guard currentStatus == .authorizedWhenInUse else {
      result(statusName(currentStatus))
      return
    }

    guard hasRequiredUsageDescriptions else {
      result(FlutterError(
        code: "MISSING_USAGE_DESCRIPTION",
        message: "The iOS background-location usage descriptions are missing.",
        details: nil
      ))
      return
    }

    // Apple permits a separate Always request after When In Use, but limits
    // that request. Once this installation has attempted it, Settings is the
    // deterministic recovery path instead of issuing a no-op request and
    // leaving the Go Online spinner waiting for a callback that will not come.
    if UserDefaults.standard.bool(forKey: requestAttemptedKey) {
      result(statusName(currentStatus))
      return
    }

    manager.delegate = self
    locationManager = manager
    pendingResult = result
    pendingRequestKind = .always

    // Let Core Location deliver any initial delegate state generated by
    // constructing the manager before treating a While In Use callback as the
    // user's response to the second-stage prompt.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak manager] in
      guard let self, let manager, self.pendingResult != nil else { return }
      self.requestIssuedAt = Date()
      UserDefaults.standard.set(true, forKey: self.requestAttemptedKey)
      manager.requestAlwaysAuthorization()
      self.startPolling()
      self.startTimeout()
    }
  }

  private var hasRequiredUsageDescriptions: Bool {
    let bundle = Bundle.main
    let whenInUse = bundle.object(
      forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription"
    ) as? String
    let always = bundle.object(
      forInfoDictionaryKey: "NSLocationAlwaysAndWhenInUseUsageDescription"
    ) as? String
    return !(whenInUse?.isEmpty ?? true) && !(always?.isEmpty ?? true)
  }

  private var hasWhenInUseUsageDescription: Bool {
    let value = Bundle.main.object(
      forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription"
    ) as? String
    return !(value?.isEmpty ?? true)
  }

  private func startPolling() {
    pollTimer?.invalidate()
    let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
      guard let self, let manager = self.locationManager else { return }
      let status = manager.authorizationStatus
      if self.isTerminal(status, for: self.pendingRequestKind) {
        self.finish(status: status)
      }
    }
    pollTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func startTimeout() {
    timeoutWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      guard let self, let manager = self.locationManager else { return }
      self.finish(status: manager.authorizationStatus)
    }
    timeoutWorkItem = workItem
    DispatchQueue.main.asyncAfter(
      deadline: .now() + decisionTimeout,
      execute: workItem
    )
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard
      pendingResult != nil,
      let requestKind = pendingRequestKind,
      let issuedAt = requestIssuedAt
    else {
      return
    }
    let status = manager.authorizationStatus

    if requestKind == .whenInUse {
      if status != .notDetermined {
        finish(status: status)
      }
      return
    }

    if status == .authorizedAlways || status == .denied || status == .restricted {
      finish(status: status)
      return
    }

    // When the provider chooses "Keep Only While Using", Apple reports a
    // fresh While In Use delegate callback. Ignore only the immediate initial
    // manager callback that can precede the actual system prompt.
    if status == .authorizedWhenInUse,
       Date().timeIntervalSince(issuedAt) >= 0.5 {
      finish(status: status)
    }
  }

  private func isTerminal(
    _ status: CLAuthorizationStatus,
    for requestKind: AuthorizationRequestKind?
  ) -> Bool {
    switch requestKind {
    case .whenInUse:
      return status != .notDetermined
    case .always:
      return status == .authorizedAlways || status == .denied || status == .restricted
    case nil:
      return false
    }
  }

  private func finish(status: CLAuthorizationStatus) {
    guard let result = pendingResult else { return }
    NSLog("[LocationAuthorization] request finished: \(statusName(status))")
    pendingResult = nil
    pollTimer?.invalidate()
    pollTimer = nil
    timeoutWorkItem?.cancel()
    timeoutWorkItem = nil
    requestIssuedAt = nil
    pendingRequestKind = nil
    locationManager?.delegate = nil
    locationManager = nil
    result(statusName(status))
  }

  private func statusName(_ status: CLAuthorizationStatus) -> String {
    switch status {
    case .authorizedAlways:
      return "always"
    case .authorizedWhenInUse:
      return "whileInUse"
    case .denied:
      return "denied"
    case .restricted:
      return "restricted"
    case .notDetermined:
      return "notDetermined"
    @unknown default:
      return "unavailable"
    }
  }
}

/// Bridges actionable iOS ride/job notifications into Dart without depending on
/// a Flutter engine already being alive. iOS may deliver an action while the app
/// is terminated, so every action is persisted before the notification-center
/// completion handler is called and replayed when Flutter attaches.
final class IncomingRequestActionBridge: NSObject, FlutterStreamHandler {
  static let shared = IncomingRequestActionBridge()

  static let rideCategoryIdentifier = "RIDE_REQUEST"
  static let jobCategoryIdentifier = "JOB_REQUEST"

  static let rideAcceptAction = "RIDE_ACCEPT"
  static let rideSkipAction = "RIDE_SKIP"
  static let rideViewAction = "RIDE_VIEW"
  static let jobSubmitBidAction = "JOB_SUBMIT_BID"
  static let jobSkipAction = "JOB_SKIP"
  static let jobViewAction = "JOB_VIEW"

  private static let recognizedActionIdentifiers: Set<String> = [
    rideAcceptAction,
    rideSkipAction,
    rideViewAction,
    jobSubmitBidAction,
    jobSkipAction,
    jobViewAction,
  ]

  private let pendingActionsKey = "myshop.pendingIncomingRequestActions"
  private let maximumPendingActions = 20
  private var pendingActions: [[String: Any]] = []
  private var loadedPendingActions = false
  private var started = false
  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?

  func start() {
    guard !started else { return }
    started = true
    loadPendingActionsIfNeeded()
    registerNotificationCategories()
  }

  func register(binaryMessenger: FlutterBinaryMessenger) {
    start()

    methodChannel = FlutterMethodChannel(
      name: "com.gilmoretech.myshop/request_action",
      binaryMessenger: binaryMessenger
    )
    methodChannel?.setMethodCallHandler { [weak self] call, result in
      self?.handleMethodCall(call, result: result)
    }

    eventChannel = FlutterEventChannel(
      name: "com.gilmoretech.myshop/request_action/events",
      binaryMessenger: binaryMessenger
    )
    eventChannel?.setStreamHandler(self)
  }

  /// Returns true only for one of MyShop's explicit request action buttons.
  /// Default notification taps deliberately return false so FlutterFire keeps
  /// owning the existing deep-link path.
  func handle(
    response: UNNotificationResponse,
    center: UNUserNotificationCenter
  ) -> Bool {
    let actionIdentifier = response.actionIdentifier
    guard Self.recognizedActionIdentifiers.contains(actionIdentifier) else {
      return false
    }

    loadPendingActionsIfNeeded()
    let payload = normalisePayload(response.notification.request.content.userInfo)
    let stableIdentifier = stableNotificationIdentifier(from: payload)
    let deliveredIdentifier = response.notification.request.identifier

    var event = payload
    if let requestType = payload["type"] as? String {
      event["requestType"] = requestType
    }
    event["type"] = "requestAction"
    event["action"] = actionIdentifier
    event["actionIdentifier"] = actionIdentifier
    event["actionId"] = UUID().uuidString
    event["notificationIdentifier"] = deliveredIdentifier
    if let stableIdentifier {
      event["stableNotificationIdentifier"] = stableIdentifier
    }
    event["createdAt"] = ISO8601DateFormatter().string(from: Date())

    // Persist synchronously before AppDelegate completes the OS callback. If
    // Flutter is not ready yet, onListen replays this exact event later.
    queue(event)

    var identifiers = [deliveredIdentifier]
    if let stableIdentifier, stableIdentifier != deliveredIdentifier {
      identifiers.append(stableIdentifier)
    }
    removeNotifications(identifiers, center: center)
    NSLog(
      "[RequestAction] queued action=\(actionIdentifier) "
        + "notification=\(deliveredIdentifier)"
    )
    return true
  }

  /// Handles authenticated links from the Live Activity. The link only queues
  /// the same durable action contract as a notification button; Dart remains
  /// responsible for auth checks, server validation, and navigation.
  func handle(url: URL) -> Bool {
    guard url.scheme?.lowercased() == "myshopprovider",
          url.host?.lowercased() == "request-action",
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return false }

    var query: [String: String] = [:]
    for item in components.queryItems ?? [] {
      if let value = item.value, !value.isEmpty { query[item.name] = value }
    }
    guard let action = query["action"],
          Self.recognizedActionIdentifiers.contains(action),
          let requestId = query["requestId"],
          !requestId.isEmpty
    else { return false }

    let rawType = query["requestType"]?.lowercased() ?? ""
    let isRide = rawType.contains("ride") || action.hasPrefix("RIDE_")
    let requestType = isRide ? "ride_request" : "job_request"
    guard RequestLiveActivityBridge.shared.isActiveRequestAction(
      requestId: requestId,
      offerId: query["offerId"],
      requestType: requestType
    ) else {
      NSLog("[RequestAction] ignored stale or unauthorised Live Activity link")
      return true
    }
    var event: [String: Any] = [
      "type": "requestAction",
      "requestType": requestType,
      "action": action,
      "actionIdentifier": action,
      "actionId": UUID().uuidString,
      "createdAt": ISO8601DateFormatter().string(from: Date()),
    ]
    event[isRide ? "rideId" : "jobId"] = requestId
    if let offerId = query["offerId"] { event["offerId"] = offerId }
    if let expiresAt = query["expiresAt"] { event["expiresAt"] = expiresAt }
    queue(event)
    NSLog("[RequestAction] queued Live Activity action=\(action) request=\(requestId)")
    return true
  }

  private func queue(_ event: [String: Any]) {
    loadPendingActionsIfNeeded()
    pendingActions.append(event)
    if pendingActions.count > maximumPendingActions {
      pendingActions.removeFirst(pendingActions.count - maximumPendingActions)
    }
    persistPendingActions()
    emitEvent(event)
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPendingRequestActions":
      loadPendingActionsIfNeeded()
      result(pendingActions)

    case "acknowledgeRequestAction":
      guard
        let args = call.arguments as? [String: Any],
        let actionId = args["actionId"] as? String,
        !actionId.isEmpty
      else {
        result(FlutterError(
          code: "INVALID_ARGUMENT",
          message: "Missing actionId",
          details: nil
        ))
        return
      }
      loadPendingActionsIfNeeded()
      pendingActions.removeAll { $0["actionId"] as? String == actionId }
      persistPendingActions()
      result(nil)

    case "removeDeliveredRequestNotification":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(
          code: "INVALID_ARGUMENT",
          message: "Missing notification payload",
          details: nil
        ))
        return
      }
      var identifiers: [String] = []
      for key in ["notificationIdentifier", "stableNotificationIdentifier"] {
        if let identifier = args[key] as? String, !identifier.isEmpty {
          identifiers.append(identifier)
        }
      }
      if let stableIdentifier = stableNotificationIdentifier(from: args) {
        identifiers.append(stableIdentifier)
      }
      identifiers = Array(Set(identifiers))
      guard !identifiers.isEmpty || !requestIdentityValues(from: args).isEmpty else {
        result(FlutterError(
          code: "INVALID_ARGUMENT",
          message: "Missing rideId, jobId, offerId, or notification identifier",
          details: nil
        ))
        return
      }
      removeDeliveredRequestNotifications(
        identifiers: identifiers,
        matching: args,
        center: UNUserNotificationCenter.current()
      ) {
        // Method-channel results must be completed exactly once and only after
        // the asynchronous delivered-notification query has finished.
        result(nil)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func registerNotificationCategories() {
    let foregroundAuthenticated: UNNotificationActionOptions = [
      .foreground,
      .authenticationRequired,
    ]

    let rideActions = [
      UNNotificationAction(
        identifier: Self.rideAcceptAction,
        title: "Accept",
        options: foregroundAuthenticated
      ),
      UNNotificationAction(
        identifier: Self.rideSkipAction,
        title: "Skip",
        options: [.foreground, .authenticationRequired, .destructive]
      ),
      UNNotificationAction(
        identifier: Self.rideViewAction,
        title: "View details",
        options: foregroundAuthenticated
      ),
    ]
    let jobActions = [
      UNNotificationAction(
        identifier: Self.jobSubmitBidAction,
        title: "Submit bid",
        options: foregroundAuthenticated
      ),
      UNNotificationAction(
        identifier: Self.jobSkipAction,
        title: "Skip",
        options: [.foreground, .authenticationRequired, .destructive]
      ),
      UNNotificationAction(
        identifier: Self.jobViewAction,
        title: "View job",
        options: foregroundAuthenticated
      ),
    ]

    let rideCategory = UNNotificationCategory(
      identifier: Self.rideCategoryIdentifier,
      actions: rideActions,
      intentIdentifiers: [],
      hiddenPreviewsBodyPlaceholder: "Unlock to view ride request details",
      categorySummaryFormat: nil,
      options: []
    )
    let jobCategory = UNNotificationCategory(
      identifier: Self.jobCategoryIdentifier,
      actions: jobActions,
      intentIdentifiers: [],
      hiddenPreviewsBodyPlaceholder: "Unlock to view job request details",
      categorySummaryFormat: nil,
      options: []
    )

    let center = UNUserNotificationCenter.current()
    center.getNotificationCategories { existing in
      var categories = Set(existing.filter {
        $0.identifier != Self.rideCategoryIdentifier
          && $0.identifier != Self.jobCategoryIdentifier
      })
      categories.insert(rideCategory)
      categories.insert(jobCategory)
      center.setNotificationCategories(categories)
      NSLog("[RequestAction] ride/job notification categories registered")
    }
  }

  /// Contract shared with the backend's `apns-collapse-id`. UUID entity IDs
  /// keep both values safely below APNs' 64-byte collapse-id limit.
  private func stableNotificationIdentifier(from payload: [String: Any]) -> String? {
    if let identifier = payload["stableNotificationIdentifier"] as? String,
       !identifier.isEmpty {
      return identifier
    }

    let rawType = (payload["requestType"] as? String)
      ?? (payload["type"] as? String)
      ?? ""
    let type = rawType.replacingOccurrences(of: ".", with: "_")
    if (type == "ride_request" || type.isEmpty),
       let rideId = firstStringValue(in: payload, keys: ["rideId", "ride_id"]),
       !rideId.isEmpty {
      return "ride_request:\(rideId)"
    }
    if (type == "job_request" || type.isEmpty),
       let jobId = firstStringValue(in: payload, keys: ["jobId", "job_id"]),
       !jobId.isEmpty {
      return "job_request:\(jobId)"
    }
    return nil
  }

  /// APNs does not guarantee that `UNNotificationRequest.identifier` equals
  /// the provider's collapse ID on every OS/delivery path. Revocation therefore
  /// scans delivered notification content and removes the actual request IDs
  /// whose payload identifies the same ride, job, or matching offer.
  private func removeDeliveredRequestNotifications(
    identifiers: [String],
    matching payload: [String: Any],
    center: UNUserNotificationCenter,
    completion: @escaping () -> Void
  ) {
    let suppliedIdentifiers = Set(identifiers.filter { !$0.isEmpty })
    let targetIdentity = requestIdentityValues(from: payload)

    center.getDeliveredNotifications { [weak self] notifications in
      var identifiersToRemove = suppliedIdentifiers
      if let self {
        for notification in notifications {
          let deliveredPayload = self.normalisePayload(
            notification.request.content.userInfo
          )
          let deliveredIdentity = self.requestIdentityValues(from: deliveredPayload)
          if !targetIdentity.isEmpty
              && !deliveredIdentity.isDisjoint(with: targetIdentity) {
            identifiersToRemove.insert(notification.request.identifier)
          }
        }
      }

      let resolvedIdentifiers = Array(identifiersToRemove)
      if !resolvedIdentifiers.isEmpty {
        center.removeDeliveredNotifications(withIdentifiers: resolvedIdentifiers)
        center.removePendingNotificationRequests(withIdentifiers: resolvedIdentifiers)
      }
      DispatchQueue.main.async(execute: completion)
    }
  }

  private func requestIdentityValues(from payload: [String: Any]) -> Set<String> {
    var values = Set<String>()
    for keys in [
      ["rideId", "ride_id"],
      ["jobId", "job_id"],
      ["offerId", "offer_id"],
    ] {
      if let value = firstStringValue(in: payload, keys: keys), !value.isEmpty {
        values.insert(value)
      }
    }

    // Some FCM/APNs wrappers nest custom data beneath `data`. Normalise and
    // inspect that shape too without recursing indefinitely.
    if let nested = payload["data"] as? [String: Any] {
      for value in requestIdentityValuesFromFlatPayload(nested) {
        values.insert(value)
      }
    }
    return values
  }

  private func requestIdentityValuesFromFlatPayload(
    _ payload: [String: Any]
  ) -> Set<String> {
    var values = Set<String>()
    for keys in [
      ["rideId", "ride_id"],
      ["jobId", "job_id"],
      ["offerId", "offer_id"],
    ] {
      if let value = firstStringValue(in: payload, keys: keys), !value.isEmpty {
        values.insert(value)
      }
    }
    return values
  }

  private func firstStringValue(
    in payload: [String: Any],
    keys: [String]
  ) -> String? {
    for key in keys {
      if let value = stringValue(payload[key]), !value.isEmpty {
        return value
      }
    }
    return nil
  }

  private func removeNotifications(
    _ identifiers: [String],
    center: UNUserNotificationCenter
  ) {
    let uniqueIdentifiers = Array(Set(identifiers.filter { !$0.isEmpty }))
    guard !uniqueIdentifiers.isEmpty else { return }
    center.removeDeliveredNotifications(withIdentifiers: uniqueIdentifiers)
    center.removePendingNotificationRequests(withIdentifiers: uniqueIdentifiers)
  }

  private func loadPendingActionsIfNeeded() {
    guard !loadedPendingActions else { return }
    pendingActions = UserDefaults.standard.array(forKey: pendingActionsKey)
      as? [[String: Any]] ?? []
    loadedPendingActions = true
  }

  private func persistPendingActions() {
    UserDefaults.standard.set(pendingActions, forKey: pendingActionsKey)
  }

  private func emitEvent(_ event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(event)
    }
  }

  private func normalisePayload(_ raw: [AnyHashable: Any]) -> [String: Any] {
    var result: [String: Any] = [:]
    for (key, value) in raw {
      guard let stringKey = key as? String,
            let normalisedValue = normaliseValue(value)
      else { continue }
      result[stringKey] = normalisedValue
    }
    return result
  }

  private func normaliseValue(_ value: Any) -> Any? {
    switch value {
    case let value as String:
      return value
    case let value as NSNumber:
      return value
    case let value as [AnyHashable: Any]:
      return normalisePayload(value)
    case let value as [Any]:
      return value.compactMap(normaliseValue)
    default:
      return String(describing: value)
    }
  }

  private func stringValue(_ value: Any?) -> String? {
    switch value {
    case let string as String:
      return string
    case let number as NSNumber:
      return number.stringValue
    default:
      return nil
    }
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    loadPendingActionsIfNeeded()
    for action in pendingActions {
      emitEvent(action)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
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
