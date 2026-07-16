import UniformTypeIdentifiers
import UserNotifications

/// Enriches actionable request notifications without exposing customer
/// identity or exact locations on the lock screen.
final class NotificationService: UNNotificationServiceExtension {
  private static let maximumAttachmentBytes = 2 * 1024 * 1024
  private static let requestTypes: Set<String> = ["ride_request", "job_request"]

  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var bestAttemptContent: UNMutableNotificationContent?
  private var downloadTask: URLSessionDataTask?
  private var delivered = false

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    self.contentHandler = contentHandler
    guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
      contentHandler(request.content)
      return
    }
    bestAttemptContent = content

    let payload = Self.normalisedPayload(content.userInfo)
    let requestType = Self.requestType(from: payload)
    guard Self.requestTypes.contains(requestType) else {
      finish(with: content)
      return
    }

    content.sound = UNNotificationSound(named: UNNotificationSoundName("incoming_request.caf"))
    if content.categoryIdentifier.isEmpty {
      content.categoryIdentifier = requestType == "ride_request" ? "RIDE_REQUEST" : "JOB_REQUEST"
    }
    if #available(iOSApplicationExtension 15.0, *) {
      content.interruptionLevel = .timeSensitive
      content.relevanceScore = 1
    }

    // The current backend map contains exact offer coordinates. It is never
    // attached to a lock-screen notification unless a future backend renderer
    // explicitly marks a redacted image as privacy safe. The opaque, expiring
    // URL alone is not sufficient because the rendered pixels can still reveal
    // a home or job location.
    guard Self.boolValue(payload["mapPreviewPrivacySafe"]),
          let rawURL = Self.stringValue(payload["mapPreviewUrl"]),
          let url = URL(string: rawURL),
          url.scheme?.lowercased() == "https",
          url.user == nil,
          url.password == nil
    else {
      finish(with: content)
      return
    }

    var urlRequest = URLRequest(url: url)
    urlRequest.timeoutInterval = 5
    urlRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    downloadTask = URLSession.shared.dataTask(with: urlRequest) { [weak self] data, response, _ in
      guard let self else { return }
      defer { self.downloadTask = nil }
      guard let data,
            !data.isEmpty,
            data.count <= Self.maximumAttachmentBytes,
            let http = response as? HTTPURLResponse,
            (200 ... 299).contains(http.statusCode),
            let type = Self.allowedImageType(http.value(forHTTPHeaderField: "Content-Type")),
            let attachment = Self.makeAttachment(data: data, type: type)
      else {
        self.finish(with: content)
        return
      }
      DispatchQueue.main.async {
        content.attachments = [attachment]
        self.finish(with: content)
      }
    }
    downloadTask?.resume()
  }

  override func serviceExtensionTimeWillExpire() {
    downloadTask?.cancel()
    downloadTask = nil
    if let bestAttemptContent {
      finish(with: bestAttemptContent)
    }
  }

  private func finish(with content: UNNotificationContent) {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in self?.finish(with: content) }
      return
    }
    guard !delivered, let handler = contentHandler else { return }
    delivered = true
    contentHandler = nil
    handler(content)
  }

  private static func requestType(from payload: [String: Any]) -> String {
    let raw = stringValue(payload["requestType"])
      ?? stringValue(payload["type"])
      ?? ""
    return raw.lowercased().replacingOccurrences(of: ".", with: "_")
  }

  private static func allowedImageType(_ raw: String?) -> UTType? {
    let contentType = raw?
      .split(separator: ";", maxSplits: 1)
      .first?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    switch contentType {
    case "image/png": return .png
    case "image/jpeg", "image/jpg": return .jpeg
    default: return nil
    }
  }

  private static func makeAttachment(data: Data, type: UTType) -> UNNotificationAttachment? {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    do {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
      let fileURL = directory.appendingPathComponent("request-map.\(type.preferredFilenameExtension ?? "img")")
      try data.write(to: fileURL, options: [.atomic])
      return try UNNotificationAttachment(
        identifier: "request-map",
        url: fileURL,
        options: [UNNotificationAttachmentOptionsTypeHintKey: type.identifier]
      )
    } catch {
      return nil
    }
  }

  private static func normalisedPayload(_ raw: [AnyHashable: Any]) -> [String: Any] {
    var payload: [String: Any] = [:]
    for (key, value) in raw {
      guard let key = key as? String else { continue }
      payload[key] = value
    }
    if let nested = payload["data"] as? [String: Any] {
      payload.merge(nested) { current, _ in current }
    }
    for key in ["offerPayload", "ridePayload", "jobPayload"] {
      guard let encoded = stringValue(payload[key]),
            let data = encoded.data(using: .utf8),
            let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { continue }
      payload.merge(decoded) { current, _ in current }
    }
    return payload
  }

  private static func stringValue(_ value: Any?) -> String? {
    if let value = value as? String, !value.isEmpty { return value }
    if let value = value as? NSNumber { return value.stringValue }
    return nil
  }

  private static func boolValue(_ value: Any?) -> Bool {
    if let value = value as? Bool { return value }
    if let value = value as? NSNumber { return value.boolValue }
    guard let value = value as? String else { return false }
    return ["1", "true", "yes"].contains(value.lowercased())
  }
}
