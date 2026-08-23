import ActivityKit
import Flutter
import Foundation

/// Receipt capabilities must never be forwarded through an HTTP redirect. The
/// URL itself is signed by the backend, but URLSession follows redirects by
/// default and would otherwise copy the short-lived bearer capability to the
/// redirect target.
private final class NoRedirectReceiptSessionDelegate:
  NSObject,
  URLSessionTaskDelegate,
  @unchecked Sendable
{
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

/// Durable Flutter bridge for ActivityKit push-to-start and per-activity update
/// tokens. The backend needs both tokens: one starts an offer while Runner is
/// terminated, and the other updates or ends that exact activity afterwards.
final class RequestLiveActivityBridge: NSObject, FlutterStreamHandler, @unchecked Sendable {
  static let shared = RequestLiveActivityBridge()

  private enum RideReceiptOutcome {
    case acknowledged(Int)
    case terminal
    case retryable
  }

  private let methodChannelName = "com.gilmoretech.myshop/live_activity"
  private let eventChannelName = "com.gilmoretech.myshop/live_activity/events"
  private let pushToStartTokenKey = "myshop.liveActivity.pushToStartToken"
  private let activityTokensKey = "myshop.liveActivity.updateTokens"
  private let pendingEventsKey = "myshop.liveActivity.pendingEvents"
  private let maximumPendingEvents = 100
  private static let receiptSessionDelegate = NoRedirectReceiptSessionDelegate()
  private static let receiptSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 2
    configuration.timeoutIntervalForResource = 3
    return URLSession(
      configuration: configuration,
      delegate: receiptSessionDelegate,
      delegateQueue: nil
    )
  }()

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
  private var receiptTasks: [String: Task<Void, Never>] = [:]
  private var receiptBindingTasks: [String: Task<Void, Never>] = [:]
  private var acknowledgedReceiptActivityIds = Set<String>()
  private var boundReceiptTokens: [String: String] = [:]
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
    acknowledgeRideReceiptIfNeeded(activity)
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

  /// A remotely started Live Activity does not pass through the notification
  /// service extension. ActivityKit wakes Runner after a successful start, so
  /// acknowledge the same short-lived, offer-scoped HMAC here. This keeps the
  /// Live Activity as the single visible iOS request surface while preserving
  /// the server-authoritative 10-second delivery and 30-second decision clocks.
  @available(iOS 16.1, *)
  private func acknowledgeRideReceiptIfNeeded(
    _ activity: Activity<RequestOfferAttributes>
  ) {
    let attributes = activity.attributes
    guard Self.normalisedRequestType(attributes.requestType) == "ride",
          attributes.notificationReceiptVersion == 1,
          let receiptURL = Self.validReceiptURL(attributes.notificationReceiptUrl),
          let receiptToken = attributes.notificationReceiptToken,
          receiptToken.range(
            of: #"^[A-Za-z0-9_-]{43}$"#,
            options: .regularExpression
          ) != nil,
          !acknowledgedReceiptActivityIds.contains(activity.id),
          receiptTasks[activity.id] == nil
    else { return }

    receiptTasks[activity.id] = Task { [weak self] in
      guard let self else { return }
      let updateToken = await MainActor.run {
        activity.pushToken.map(Self.hex) ?? self.activityTokens[activity.id]
      }
      var receiptOutcome = RideReceiptOutcome.retryable
      for attempt in 1 ... 3 {
        guard !Task.isCancelled else { break }
        receiptOutcome = await Self.postRideReceipt(
          url: receiptURL,
          rideId: attributes.requestId,
          offerId: attributes.offerId,
          attempt: attributes.attempt,
          receiptToken: receiptToken,
          activityId: updateToken == nil ? nil : activity.id,
          updateToken: updateToken
        )
        if case .retryable = receiptOutcome {
          // Retry only transport/server failures while the 10-second delivery
          // capability can still be valid.
        } else {
          break
        }
        if Task.isCancelled { break }
        if attempt < 3 {
          try? await Task.sleep(
            nanoseconds: UInt64(attempt) * 400_000_000
          )
        }
      }
      guard !Task.isCancelled, Self.canUpdate(activity) else {
        await MainActor.run { self.receiptTasks.removeValue(forKey: activity.id) }
        return
      }
      switch receiptOutcome {
      case let .acknowledged(decisionExpiry):
        await self.applyDecisionExpiry(decisionExpiry, to: activity)
        guard !Task.isCancelled, Self.canUpdate(activity) else {
          await MainActor.run { self.receiptTasks.removeValue(forKey: activity.id) }
          return
        }
        await MainActor.run {
          self.acknowledgedReceiptActivityIds.insert(activity.id)
          if let updateToken {
            self.boundReceiptTokens[activity.id] = updateToken
          }
          self.scheduleExpiry(for: activity)
          self.bindRideActivityIfNeeded(activity)
        }
      case .terminal:
        _ = await self.endActivities(
          requestId: attributes.requestId,
          offerId: attributes.offerId,
          requestType: attributes.requestType,
          reason: "expired"
        )
      case .retryable:
        break
      }
      await MainActor.run {
        self.receiptTasks.removeValue(forKey: activity.id)
      }
    }
  }

  private static func validReceiptURL(_ raw: String?) -> URL? {
    guard let raw,
          let url = URL(string: raw),
          url.scheme?.lowercased() == "https",
          url.user == nil,
          url.password == nil,
          url.host != nil,
          url.query == nil,
          url.fragment == nil,
          url.path.hasSuffix("/v1/rides/offers/notification-receipt")
    else { return nil }
    return url
  }

  private static func postRideReceipt(
    url: URL,
    rideId: String,
    offerId: String,
    attempt: Int?,
    receiptToken: String,
    activityId: String?,
    updateToken: String?
  ) async -> RideReceiptOutcome {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 2
    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    var body: [String: Any] = [
      "rideId": rideId,
      "offerId": offerId,
      "receiptToken": receiptToken,
    ]
    if let activityId, let updateToken {
      body["activityId"] = activityId
      body["updateToken"] = updateToken
    }
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    do {
      let (data, response) = try await Self.receiptSession.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        return .retryable
      }
      guard (200 ... 299).contains(http.statusCode) else {
        NSLog("[LiveActivity] ride receipt rejected for offerId=%@", offerId)
        if [408, 425, 429].contains(http.statusCode) {
          return .retryable
        }
        return (400 ... 499).contains(http.statusCode) ? .terminal : .retryable
      }
      guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return .retryable
      }
      let payload = root["data"] as? [String: Any] ?? root
      guard payload["rideId"] as? String == rideId,
            payload["offerId"] as? String == offerId,
            attempt == nil || (payload["attempt"] as? NSNumber)?.intValue == attempt
      else {
        NSLog("[LiveActivity] ride receipt identity mismatch for offerId=%@", offerId)
        return .terminal
      }
      guard let rawDeadline = payload["decisionExpiresAt"] as? String
              ?? payload["acceptanceExpiresAt"] as? String
              ?? payload["expiresAt"] as? String,
            let rawServerNow = payload["serverNow"] as? String,
            let deadline = Self.parseISO8601(rawDeadline),
            let serverNow = Self.parseISO8601(rawServerNow)
      else {
        NSLog("[LiveActivity] ride receipt omitted decision deadline for offerId=%@", offerId)
        return .retryable
      }
      let remainingSeconds = deadline.timeIntervalSince(serverNow)
      guard remainingSeconds > 0, remainingSeconds <= 31 else {
        NSLog("[LiveActivity] ride receipt deadline invalid for offerId=%@", offerId)
        return .terminal
      }
      NSLog("[LiveActivity] ride receipt acknowledged for offerId=%@", offerId)
      return .acknowledged(
        // Use the backend's absolute deadline rather than adding the original
        // remaining interval after this HTTP response arrives. That keeps the
        // Live Activity aligned with the in-app timer and avoids extending the
        // actionable-looking surface by network or token-binding latency.
        Int(ceil(deadline.timeIntervalSince1970))
      )
    } catch {
      NSLog(
        "[LiveActivity] ride receipt failed for offerId=%@ error=%@",
        offerId,
        String(describing: error)
      )
      return .retryable
    }
  }

  private static func parseISO8601(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let parsed = fractional.date(from: value) {
      return parsed
    }
    return ISO8601DateFormatter().date(from: value)
  }

  @available(iOS 16.1, *)
  private func applyDecisionExpiry(
    _ expiresAtEpochSeconds: Int,
    to activity: Activity<RequestOfferAttributes>
  ) async {
    let current: RequestOfferAttributes.ContentState
    if #available(iOS 16.2, *) {
      current = activity.content.state
    } else {
      current = activity.contentState
    }
    let updated = RequestOfferAttributes.ContentState(
      status: current.status,
      farePesewas: current.farePesewas,
      prePromoFarePesewas: current.prePromoFarePesewas,
      clientPayableEstimatePesewas: current.clientPayableEstimatePesewas,
      promoDiscountPesewas: current.promoDiscountPesewas,
      loyaltyDiscountPesewas: current.loyaltyDiscountPesewas,
      platformDiscountPesewas: current.platformDiscountPesewas,
      tollLabel: current.tollLabel,
      tollFeePesewas: current.tollFeePesewas,
      promoApplied: current.promoApplied,
      paymentMethod: current.paymentMethod,
      minimumBidPesewas: current.minimumBidPesewas,
      distanceKm: current.distanceKm,
      durationMinutes: current.durationMinutes,
      category: current.category,
      expiresAtEpochSeconds: expiresAtEpochSeconds,
      endReason: current.endReason
    )
    if #available(iOS 16.2, *) {
      await activity.update(
        ActivityContent(
          state: updated,
          staleDate: Date(timeIntervalSince1970: TimeInterval(expiresAtEpochSeconds))
        )
      )
    } else {
      await activity.update(using: updated)
    }
  }

  @available(iOS 16.1, *)
  private func recordActivityToken(
    _ data: Data,
    activity: Activity<RequestOfferAttributes>
  ) {
    let token = Self.hex(data)
    if activityTokens[activity.id] != token {
      activityTokens[activity.id] = token
      persistActivityTokens()
      var event = activityPayload(activity)
      event["type"] = "activityUpdateToken"
      event["token"] = token
      emitOrQueue(event)
    }
    bindRideActivityIfNeeded(activity)
  }

  /// Bind the per-activity update token through the same signed, offer-scoped
  /// receipt endpoint. This path is native because Flutter may not initialise
  /// after ActivityKit wakes a terminated app. Without this binding, the
  /// backend could start an activity but could not reliably end it.
  @available(iOS 16.1, *)
  private func bindRideActivityIfNeeded(
    _ activity: Activity<RequestOfferAttributes>
  ) {
    let attributes = activity.attributes
    guard Self.normalisedRequestType(attributes.requestType) == "ride",
          attributes.notificationReceiptVersion == 1,
          acknowledgedReceiptActivityIds.contains(activity.id),
          receiptBindingTasks[activity.id] == nil,
          Self.canUpdate(activity),
          let receiptURL = Self.validReceiptURL(attributes.notificationReceiptUrl),
          let receiptToken = attributes.notificationReceiptToken,
          receiptToken.range(
            of: #"^[A-Za-z0-9_-]{43}$"#,
            options: .regularExpression
          ) != nil,
          let updateToken = activity.pushToken.map(Self.hex) ?? activityTokens[activity.id],
          boundReceiptTokens[activity.id] != updateToken
    else { return }

    receiptBindingTasks[activity.id] = Task { [weak self] in
      guard let self else { return }
      var outcome = RideReceiptOutcome.retryable
      for attempt in 1 ... 3 {
        guard !Task.isCancelled else { break }
        outcome = await Self.postRideReceipt(
          url: receiptURL,
          rideId: attributes.requestId,
          offerId: attributes.offerId,
          attempt: attributes.attempt,
          receiptToken: receiptToken,
          activityId: activity.id,
          updateToken: updateToken
        )
        if case .retryable = outcome {
          if attempt < 3 {
            try? await Task.sleep(nanoseconds: UInt64(attempt) * 400_000_000)
          }
        } else {
          break
        }
      }

      guard !Task.isCancelled, Self.canUpdate(activity) else {
        await MainActor.run {
          self.receiptBindingTasks.removeValue(forKey: activity.id)
        }
        return
      }
      var shouldCheckForRotatedToken = false
      switch outcome {
      case let .acknowledged(decisionExpiry):
        await self.applyDecisionExpiry(decisionExpiry, to: activity)
        guard !Task.isCancelled, Self.canUpdate(activity) else {
          await MainActor.run {
            self.receiptBindingTasks.removeValue(forKey: activity.id)
          }
          return
        }
        await MainActor.run {
          self.boundReceiptTokens[activity.id] = updateToken
          self.scheduleExpiry(for: activity)
        }
        shouldCheckForRotatedToken = true
      case .terminal:
        _ = await self.endActivities(
          requestId: attributes.requestId,
          offerId: attributes.offerId,
          requestType: attributes.requestType,
          reason: "expired"
        )
      case .retryable:
        break
      }
      await MainActor.run {
        self.receiptBindingTasks.removeValue(forKey: activity.id)
        if shouldCheckForRotatedToken {
          self.bindRideActivityIfNeeded(activity)
        }
      }
    }
  }

  @available(iOS 16.1, *)
  private func recordEnded(_ activity: Activity<RequestOfferAttributes>) {
    guard endedActivityIds.insert(activity.id).inserted else { return }
    tokenTasks.removeValue(forKey: activity.id)?.cancel()
    stateTasks.removeValue(forKey: activity.id)?.cancel()
    contentTasks.removeValue(forKey: activity.id)?.cancel()
    expiryTasks.removeValue(forKey: activity.id)?.cancel()
    receiptTasks.removeValue(forKey: activity.id)?.cancel()
    receiptBindingTasks.removeValue(forKey: activity.id)?.cancel()
    acknowledgedReceiptActivityIds.remove(activity.id)
    boundReceiptTokens.removeValue(forKey: activity.id)
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
        prePromoFarePesewas: current.prePromoFarePesewas,
        clientPayableEstimatePesewas: current.clientPayableEstimatePesewas,
        promoDiscountPesewas: current.promoDiscountPesewas,
        loyaltyDiscountPesewas: current.loyaltyDiscountPesewas,
        platformDiscountPesewas: current.platformDiscountPesewas,
        tollLabel: current.tollLabel,
        tollFeePesewas: current.tollFeePesewas,
        promoApplied: current.promoApplied,
        paymentMethod: current.paymentMethod,
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
    receiptTasks.values.forEach { $0.cancel() }
    receiptBindingTasks.values.forEach { $0.cancel() }
    tokenTasks.removeAll()
    stateTasks.removeAll()
    contentTasks.removeAll()
    expiryTasks.removeAll()
    receiptTasks.removeAll()
    receiptBindingTasks.removeAll()
    acknowledgedReceiptActivityIds.removeAll()
    boundReceiptTokens.removeAll()
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

  @available(iOS 16.1, *)
  private static func canUpdate(
    _ activity: Activity<RequestOfferAttributes>
  ) -> Bool {
    activity.activityState != .ended && activity.activityState != .dismissed
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
