import ActivityKit
import Flutter
import Foundation

/// Durable Flutter bridge for ActivityKit push-to-start and per-activity update
/// tokens. The backend needs both tokens: one starts an offer while Runner is
/// terminated, and the other updates or ends that exact activity afterwards.
final class RequestLiveActivityBridge: NSObject, FlutterStreamHandler, @unchecked Sendable {
  static let shared = RequestLiveActivityBridge()

  private let methodChannelName = "com.gilmoretech.myshop/live_activity"
  private let eventChannelName = "com.gilmoretech.myshop/live_activity/events"
  private let pushToStartTokenKey = "myshop.liveActivity.pushToStartToken"
  private let activityTokensKey = "myshop.liveActivity.updateTokens"
  private let pendingEventsKey = "myshop.liveActivity.pendingEvents"
  private let maximumPendingEvents = 100

  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?
  private var observersStarted = false
  private var activityEnablementTask: Task<Void, Never>?
  private var pushToStartTask: Task<Void, Never>?
  private var activityUpdatesTask: Task<Void, Never>?
  private var tokenTasks: [String: Task<Void, Never>] = [:]
  private var stateTasks: [String: Task<Void, Never>] = [:]
  private var contentTasks: [String: Task<Void, Never>] = [:]
  private var expiryTasks: [String: Task<Void, Never>] = [:]
  private var endedActivityIds = Set<String>()
  private var activityTokens: [String: String] = [:]
  private var pendingEvents: [[String: Any]] = []

  override private init() {
    super.init()
    activityTokens = UserDefaults.standard.dictionary(forKey: activityTokensKey)
      as? [String: String] ?? [:]
    pendingEvents = UserDefaults.standard.array(forKey: pendingEventsKey)
      as? [[String: Any]] ?? []
  }

  func start() {
    guard !observersStarted else { return }
    observersStarted = true
    guard #available(iOS 16.1, *) else { return }
    if !ActivityAuthorizationInfo().areActivitiesEnabled {
      UserDefaults.standard.removeObject(forKey: pushToStartTokenKey)
    }

    activityEnablementTask = Task { [weak self] in
      guard let self else { return }
      for await enabled in ActivityAuthorizationInfo().activityEnablementUpdates {
        guard !Task.isCancelled else { return }
        await MainActor.run { self.recordActivityEnablement(enabled) }
      }
    }

    observeCurrentActivities()
    activityUpdatesTask = Task { [weak self] in
      guard let self else { return }
      for await activity in Activity<RequestOfferAttributes>.activityUpdates {
        guard !Task.isCancelled else { return }
        await MainActor.run { self.observe(activity) }
      }
    }

    guard #available(iOS 17.2, *) else { return }
    if let token = Activity<RequestOfferAttributes>.pushToStartToken {
      recordPushToStartToken(token)
    }
    pushToStartTask = Task { [weak self] in
      guard let self else { return }
      for await token in Activity<RequestOfferAttributes>.pushToStartTokenUpdates {
        guard !Task.isCancelled else { return }
        await MainActor.run { self.recordPushToStartToken(token) }
      }
    }
  }

  func register(binaryMessenger: FlutterBinaryMessenger) {
    start()
    methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: binaryMessenger
    )
    methodChannel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }

    eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: binaryMessenger
    )
    eventChannel?.setStreamHandler(self)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getState":
      result(currentState())

    case "endRequest":
      guard #available(iOS 16.1, *) else {
        result(0)
        return
      }
      guard let arguments = call.arguments as? [String: Any],
            let requestId = arguments["requestId"] as? String,
            !requestId.isEmpty
      else {
        result(FlutterError(
          code: "INVALID_ARGUMENT",
          message: "endRequest requires requestId",
          details: nil
        ))
        return
      }
      let offerId = arguments["offerId"] as? String
      let requestType = arguments["requestType"] as? String
      let reason = (arguments["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      Task { [weak self] in
        guard let self else {
          await MainActor.run { result(0) }
          return
        }
        let count = await self.endActivities(
          requestId: requestId,
          offerId: offerId,
          requestType: requestType,
          reason: reason
        )
        await MainActor.run { result(count) }
      }

    case "endAll":
      guard #available(iOS 16.1, *) else {
        result(0)
        return
      }
      let arguments = call.arguments as? [String: Any]
      let reason = (arguments?["reason"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      Task { [weak self] in
        guard let self else {
          await MainActor.run { result(0) }
          return
        }
        let count = await self.endActivities(
          requestId: nil,
          offerId: nil,
          requestType: nil,
          reason: reason
        )
        await MainActor.run {
          self.purgePerActivityState()
          result(count)
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func currentState() -> [String: Any] {
    guard #available(iOS 16.1, *) else {
      return ["activities": []]
    }

    var state: [String: Any] = [
      "activities": Activity<RequestOfferAttributes>.activities.map(activityPayload),
    ]
    let activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
    state["activitiesEnabled"] = activitiesEnabled
    if !activitiesEnabled {
      UserDefaults.standard.removeObject(forKey: pushToStartTokenKey)
      return state
    }
    if #available(iOS 17.2, *) {
      let liveToken = Activity<RequestOfferAttributes>.pushToStartToken.map(Self.hex)
      if let token = liveToken ?? UserDefaults.standard.string(forKey: pushToStartTokenKey) {
        state["pushToStartToken"] = token
      }
    }
    return state
  }

  /// Rejects forged/stale custom-scheme actions before they enter Dart's
  /// durable notification-action queue. A valid link must identify a currently
  /// active, unexpired ActivityKit offer.
  func isActiveRequestAction(
    requestId: String,
    offerId: String?,
    requestType: String
  ) -> Bool {
    guard #available(iOS 16.1, *) else { return false }
    let now = Int(Date().timeIntervalSince1970)
    return Activity<RequestOfferAttributes>.activities.contains { activity in
      guard activity.attributes.requestId == requestId,
            offerId == nil || offerId?.isEmpty == true || activity.attributes.offerId == offerId,
            Self.normalisedRequestType(activity.attributes.requestType)
              == Self.normalisedRequestType(requestType)
      else { return false }
      let state: RequestOfferAttributes.ContentState
      if #available(iOS 16.2, *) {
        state = activity.content.state
      } else {
        state = activity.contentState
      }
      let status = state.status.lowercased()
      return status != "ended"
        && status != "expired"
        && status != "cancelled"
        && state.expiresAtEpochSeconds > now
    }
  }

  @available(iOS 16.1, *)
  private func observeCurrentActivities() {
    for activity in Activity<RequestOfferAttributes>.activities {
      observe(activity)
    }
  }

  @available(iOS 16.1, *)
  private func observe(_ activity: Activity<RequestOfferAttributes>) {
    if let token = activity.pushToken {
      recordActivityToken(token, activity: activity)
    }
    if tokenTasks[activity.id] == nil {
      tokenTasks[activity.id] = Task { [weak self] in
        guard let self else { return }
        for await token in activity.pushTokenUpdates {
          guard !Task.isCancelled else { return }
          await MainActor.run { self.recordActivityToken(token, activity: activity) }
        }
      }
    }
    if stateTasks[activity.id] == nil {
      stateTasks[activity.id] = Task { [weak self] in
        guard let self else { return }
        for await state in activity.activityStateUpdates {
          guard !Task.isCancelled else { return }
          guard state == .ended || state == .dismissed else { continue }
          await MainActor.run { self.recordEnded(activity) }
          return
        }
      }
    }
    if #available(iOS 16.2, *), contentTasks[activity.id] == nil {
      contentTasks[activity.id] = Task { [weak self] in
        guard let self else { return }
        for await _ in activity.contentUpdates {
          guard !Task.isCancelled else { return }
          await MainActor.run { self.scheduleExpiry(for: activity) }
        }
      }
    }
    scheduleExpiry(for: activity)
  }

  @available(iOS 16.1, *)
  private func recordActivityToken(
    _ data: Data,
    activity: Activity<RequestOfferAttributes>
  ) {
    let token = Self.hex(data)
    guard activityTokens[activity.id] != token else { return }
    activityTokens[activity.id] = token
    persistActivityTokens()
    var event = activityPayload(activity)
    event["type"] = "activityUpdateToken"
    event["token"] = token
    emitOrQueue(event)
  }

  @available(iOS 16.1, *)
  private func recordEnded(_ activity: Activity<RequestOfferAttributes>) {
    guard endedActivityIds.insert(activity.id).inserted else { return }
    tokenTasks.removeValue(forKey: activity.id)?.cancel()
    stateTasks.removeValue(forKey: activity.id)?.cancel()
    contentTasks.removeValue(forKey: activity.id)?.cancel()
    expiryTasks.removeValue(forKey: activity.id)?.cancel()
    activityTokens.removeValue(forKey: activity.id)
    persistActivityTokens()
    var event = activityPayload(activity)
    event["type"] = "activityEnded"
    emitOrQueue(event)
  }

  @available(iOS 17.2, *)
  private func recordPushToStartToken(_ data: Data) {
    let token = Self.hex(data)
    let previous = UserDefaults.standard.string(forKey: pushToStartTokenKey)
    guard previous != token else { return }
    UserDefaults.standard.set(token, forKey: pushToStartTokenKey)
    emitOrQueue(["type": "pushToStartToken", "token": token])
  }

  @available(iOS 16.1, *)
  private func recordActivityEnablement(_ enabled: Bool) {
    if !enabled {
      UserDefaults.standard.removeObject(forKey: pushToStartTokenKey)
    }
    emitOrQueue([
      "type": "activitiesEnabled",
      "activitiesEnabled": enabled,
    ])

    // Re-publish the current start token after the user turns Live Activities
    // back on. Disabling them clears our persisted copy so this is not
    // suppressed as a duplicate.
    if enabled, #available(iOS 17.2, *),
       let token = Activity<RequestOfferAttributes>.pushToStartToken {
      recordPushToStartToken(token)
    }
  }

  @available(iOS 16.1, *)
  private func activityPayload(
    _ activity: Activity<RequestOfferAttributes>
  ) -> [String: Any] {
    let state: RequestOfferAttributes.ContentState
    if #available(iOS 16.2, *) {
      state = activity.content.state
    } else {
      state = activity.contentState
    }
    var payload: [String: Any] = [
      "activityId": activity.id,
      "requestId": activity.attributes.requestId,
      "offerId": activity.attributes.offerId,
      "requestType": activity.attributes.requestType,
      "expiresAt": state.expiresAtEpochSeconds,
    ]
    if let token = activity.pushToken.map(Self.hex) ?? activityTokens[activity.id] {
      payload["updateToken"] = token
    }
    return payload
  }

  @available(iOS 16.1, *)
  private func endActivities(
    requestId: String?,
    offerId: String?,
    requestType: String?,
    reason: String?
  ) async -> Int {
    let activities = Activity<RequestOfferAttributes>.activities.filter { activity in
      if let requestId, activity.attributes.requestId != requestId { return false }
      if let offerId, !offerId.isEmpty, activity.attributes.offerId != offerId { return false }
      if let requestType, !requestType.isEmpty,
         Self.normalisedRequestType(activity.attributes.requestType)
           != Self.normalisedRequestType(requestType) {
        return false
      }
      return true
    }
    let safeReason = Self.userFacingEndReason(reason)

    for activity in activities {
      let current: RequestOfferAttributes.ContentState
      if #available(iOS 16.2, *) {
        current = activity.content.state
      } else {
        current = activity.contentState
      }
      let ended = RequestOfferAttributes.ContentState(
        status: "ended",
        farePesewas: current.farePesewas,
        minimumBidPesewas: current.minimumBidPesewas,
        distanceKm: current.distanceKm,
        durationMinutes: current.durationMinutes,
        category: current.category,
        expiresAtEpochSeconds: current.expiresAtEpochSeconds,
        endReason: safeReason
      )
      if #available(iOS 16.2, *) {
        await activity.end(
          ActivityContent(state: ended, staleDate: Date()),
          dismissalPolicy: .immediate
        )
      } else {
        await activity.end(using: ended, dismissalPolicy: .immediate)
      }
      await MainActor.run { self.recordEnded(activity) }
    }
    return activities.count
  }

  @available(iOS 16.1, *)
  private func scheduleExpiry(for activity: Activity<RequestOfferAttributes>) {
    expiryTasks.removeValue(forKey: activity.id)?.cancel()
    let state: RequestOfferAttributes.ContentState
    if #available(iOS 16.2, *) {
      state = activity.content.state
    } else {
      state = activity.contentState
    }
    let delay = max(
      0,
      TimeInterval(state.expiresAtEpochSeconds) - Date().timeIntervalSince1970
    )
    expiryTasks[activity.id] = Task { [weak self] in
      let nanoseconds = UInt64(min(delay, 86_400) * 1_000_000_000)
      if nanoseconds > 0 {
        try? await Task.sleep(nanoseconds: nanoseconds)
      }
      guard !Task.isCancelled, let self else { return }

      // Re-read content in case a remote update extended the deadline after
      // this timer was scheduled.
      let latest: RequestOfferAttributes.ContentState
      if #available(iOS 16.2, *) {
        latest = activity.content.state
      } else {
        latest = activity.contentState
      }
      if latest.expiresAtEpochSeconds > Int(Date().timeIntervalSince1970) {
        await MainActor.run { self.scheduleExpiry(for: activity) }
        return
      }
      _ = await self.endActivities(
        requestId: activity.attributes.requestId,
        offerId: activity.attributes.offerId,
        requestType: activity.attributes.requestType,
        reason: "expired"
      )
    }
  }

  private func emitOrQueue(_ event: [String: Any]) {
    if let eventSink {
      DispatchQueue.main.async { eventSink(event) }
      return
    }
    pendingEvents.append(event)
    if pendingEvents.count > maximumPendingEvents {
      pendingEvents.removeFirst(pendingEvents.count - maximumPendingEvents)
    }
    UserDefaults.standard.set(pendingEvents, forKey: pendingEventsKey)
  }

  private func persistActivityTokens() {
    UserDefaults.standard.set(activityTokens, forKey: activityTokensKey)
  }

  private func purgePerActivityState() {
    tokenTasks.values.forEach { $0.cancel() }
    stateTasks.values.forEach { $0.cancel() }
    contentTasks.values.forEach { $0.cancel() }
    expiryTasks.values.forEach { $0.cancel() }
    tokenTasks.removeAll()
    stateTasks.removeAll()
    contentTasks.removeAll()
    expiryTasks.removeAll()
    activityTokens.removeAll()
    persistActivityTokens()
    pendingEvents.removeAll { event in
      let type = event["type"] as? String
      return type == "activityUpdateToken" || type == "activityEnded"
    }
    if pendingEvents.isEmpty {
      UserDefaults.standard.removeObject(forKey: pendingEventsKey)
    } else {
      UserDefaults.standard.set(pendingEvents, forKey: pendingEventsKey)
    }
  }

  private static func hex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
  }

  private static func normalisedRequestType(_ value: String) -> String {
    let lowercased = value.lowercased()
    if lowercased.contains("ride") { return "ride" }
    if lowercased.contains("job") { return "job" }
    return lowercased
  }

  private static func userFacingEndReason(_ value: String?) -> String {
    switch value?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
    case "expired", "timeout", "timed_out":
      return "Offer expired"
    case "accepted", "ride_accepted", "job_accepted", "resolved", "completed":
      return "Offer resolved"
    case "cancelled", "canceled", "revoked", "offer_revoked", "withdrawn":
      return "Offer withdrawn"
    case "skipped", "declined", "ignored":
      return "Offer skipped"
    case "signed_out", "logout", "account_changed":
      return "Signed out"
    default:
      return "Offer ended"
    }
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    let replay = pendingEvents
    pendingEvents.removeAll()
    UserDefaults.standard.removeObject(forKey: pendingEventsKey)
    for event in replay {
      DispatchQueue.main.async { events(event) }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}
