import UIKit
import UserNotifications
import UserNotificationsUI

/// Expanded, branded request card. It intentionally renders only coarse offer
/// facts; names, addresses, descriptions, photos, and raw coordinates remain
/// inside the authenticated Flutter flow.
@objc(NotificationViewController)
final class NotificationViewController: UIViewController, UNNotificationContentExtension {
  private let accent = UIColor(red: 0.09, green: 0.57, blue: 0.36, alpha: 1)
  private let gold = UIColor(red: 0.92, green: 0.65, blue: 0.12, alpha: 1)
  private let headerLabel = UILabel()
  private let amountLabel = UILabel()
  private let amountCaptionLabel = UILabel()
  private let pricingLabel = UILabel()
  private let factsStack = UIStackView()
  private let countdownLabel = UILabel()
  private let privacyLabel = UILabel()
  private let mapImageView = UIImageView()
  private var countdownTimer: Timer?
  private var expirationDate: Date?

  override func viewDidLoad() {
    super.viewDidLoad()
    configureView()
  }

  deinit {
    countdownTimer?.invalidate()
  }

  func didReceive(_ notification: UNNotification) {
    let payload = RequestPayload(notification.request.content.userInfo)
    let isRide = payload.requestType == "ride_request"

    headerLabel.text = isRide ? "New ride request" : "New artisan job"
    amountLabel.text = payload.amountText
    amountCaptionLabel.text = payload.amountCaption
    amountCaptionLabel.isHidden = payload.amountCaption == nil
    pricingLabel.text = payload.pricingText
    pricingLabel.isHidden = payload.pricingText == nil
    factsStack.arrangedSubviews.forEach {
      factsStack.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
    for fact in payload.safeFacts {
      factsStack.addArrangedSubview(makeFactChip(fact))
    }
    privacyLabel.text = isRide
      ? "Unlock MyShop to view the route, addresses, and passenger."
      : "Unlock MyShop to view the location, description, photos, and client."

    expirationDate = payload.expiresAt
    updateCountdown()
    countdownTimer?.invalidate()
    if payload.expiresAt != nil {
      countdownTimer = Timer.scheduledTimer(
        timeInterval: 1,
        target: self,
        selector: #selector(updateCountdown),
        userInfo: nil,
        repeats: true
      )
    }

    showSafeAttachment(notification.request.content.attachments.first)
  }

  private func configureView() {
    view.backgroundColor = UIColor.secondarySystemBackground
    view.layer.cornerRadius = 22
    view.clipsToBounds = true

    let iconView = UIImageView(image: UIImage(systemName: "bolt.fill"))
    iconView.tintColor = .white
    iconView.contentMode = .center
    iconView.backgroundColor = accent
    iconView.layer.cornerRadius = 24
    iconView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      iconView.widthAnchor.constraint(equalToConstant: 48),
      iconView.heightAnchor.constraint(equalToConstant: 48),
    ])

    headerLabel.font = .systemFont(ofSize: 18, weight: .bold)
    headerLabel.textColor = .label
    headerLabel.numberOfLines = 1

    countdownLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
    countdownLabel.textColor = accent
    countdownLabel.textAlignment = .right

    let headingText = UIStackView(arrangedSubviews: [headerLabel, countdownLabel])
    headingText.axis = .vertical
    headingText.spacing = 4

    let heading = UIStackView(arrangedSubviews: [iconView, headingText])
    heading.axis = .horizontal
    heading.alignment = .center
    heading.spacing = 12

    amountLabel.font = .systemFont(ofSize: 31, weight: .heavy)
    amountLabel.textColor = .label
    amountLabel.adjustsFontSizeToFitWidth = true
    amountLabel.minimumScaleFactor = 0.7

    amountCaptionLabel.font = .systemFont(ofSize: 11, weight: .bold)
    amountCaptionLabel.textColor = .secondaryLabel
    amountCaptionLabel.numberOfLines = 1

    pricingLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    pricingLabel.textColor = .secondaryLabel
    pricingLabel.numberOfLines = 2
    pricingLabel.adjustsFontSizeToFitWidth = true
    pricingLabel.minimumScaleFactor = 0.8

    factsStack.axis = .horizontal
    factsStack.alignment = .fill
    factsStack.distribution = .fillEqually
    factsStack.spacing = 8

    mapImageView.contentMode = .scaleAspectFill
    mapImageView.backgroundColor = UIColor.tertiarySystemFill
    mapImageView.layer.cornerRadius = 14
    mapImageView.clipsToBounds = true
    mapImageView.isHidden = true
    mapImageView.translatesAutoresizingMaskIntoConstraints = false
    mapImageView.heightAnchor.constraint(equalToConstant: 118).isActive = true

    privacyLabel.font = .systemFont(ofSize: 13, weight: .medium)
    privacyLabel.textColor = .secondaryLabel
    privacyLabel.numberOfLines = 2
    privacyLabel.setContentCompressionResistancePriority(.required, for: .vertical)

    let privacyIcon = UIImageView(image: UIImage(systemName: "lock.fill"))
    privacyIcon.tintColor = gold
    privacyIcon.contentMode = .top
    privacyIcon.translatesAutoresizingMaskIntoConstraints = false
    privacyIcon.widthAnchor.constraint(equalToConstant: 17).isActive = true

    let privacyRow = UIStackView(arrangedSubviews: [privacyIcon, privacyLabel])
    privacyRow.axis = .horizontal
    privacyRow.alignment = .top
    privacyRow.spacing = 8

    let stack = UIStackView(arrangedSubviews: [
      heading,
      amountLabel,
      amountCaptionLabel,
      pricingLabel,
      factsStack,
      mapImageView,
      privacyRow,
    ])
    stack.axis = .vertical
    stack.spacing = 14
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
      stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -16),
    ])
    preferredContentSize = CGSize(width: 0, height: 305)
  }

  private func makeFactChip(_ text: String) -> UIView {
    let label = UILabel()
    label.text = text
    label.font = .systemFont(ofSize: 13, weight: .semibold)
    label.textColor = .label
    label.textAlignment = .center
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.75
    label.backgroundColor = accent.withAlphaComponent(0.12)
    label.layer.cornerRadius = 11
    label.clipsToBounds = true
    label.heightAnchor.constraint(equalToConstant: 38).isActive = true
    return label
  }

  @objc private func updateCountdown() {
    guard let expirationDate else {
      countdownLabel.text = "Limited-time offer"
      return
    }
    let remaining = max(0, Int(expirationDate.timeIntervalSinceNow.rounded(.up)))
    if remaining == 0 {
      countdownTimer?.invalidate()
      countdownLabel.text = "Offer expired"
      countdownLabel.textColor = .systemRed
      return
    }
    countdownLabel.textColor = accent
    countdownLabel.text = String(format: "Respond in %d:%02d", remaining / 60, remaining % 60)
  }

  private func showSafeAttachment(_ attachment: UNNotificationAttachment?) {
    guard let attachment else {
      mapImageView.isHidden = true
      preferredContentSize = CGSize(width: 0, height: 305)
      return
    }
    let didAccess = attachment.url.startAccessingSecurityScopedResource()
    defer {
      if didAccess { attachment.url.stopAccessingSecurityScopedResource() }
    }
    guard let image = UIImage(contentsOfFile: attachment.url.path) else {
      mapImageView.isHidden = true
      preferredContentSize = CGSize(width: 0, height: 305)
      return
    }
    mapImageView.image = image
    mapImageView.isHidden = false
    preferredContentSize = CGSize(width: 0, height: 437)
  }
}

private struct RequestPayload {
  let requestType: String
  let amountText: String
  let amountCaption: String?
  let pricingText: String?
  let safeFacts: [String]
  let expiresAt: Date?

  init(_ raw: [AnyHashable: Any]) {
    var values: [String: Any] = [:]
    for (key, value) in raw {
      if let key = key as? String { values[key] = value }
    }
    if let nested = values["data"] as? [String: Any] {
      values.merge(nested) { current, _ in current }
    }
    for key in ["offerPayload", "ridePayload", "jobPayload"] {
      guard let encoded = Self.string(values[key]),
            let data = encoded.data(using: .utf8),
            let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { continue }
      values.merge(decoded) { current, _ in current }
    }

    let rawType = Self.string(values["requestType"])
      ?? Self.string(values["type"])
      ?? (values["rideId"] == nil ? "job_request" : "ride_request")
    requestType = rawType.lowercased().replacingOccurrences(of: ".", with: "_")

    if requestType == "ride_request" {
      let earnings = Self.int(values["estimatedProviderEarningsPesewas"])
      let tripFare = Self.int(values["prePromoFarePesewas"])
      let riderPays = Self.int(values["clientPayableEstimatePesewas"])
        ?? Self.int(values["collectFromClientPesewas"])
      let legacyFare = Self.int(values["estimatedFarePesewas"])
      let paymentMethod = Self.string(values["paymentMethod"])
      if let earnings {
        amountText = Self.cedis(earnings)
        amountCaption = "ESTIMATED EARNINGS"
      } else if let tripFare {
        amountText = Self.cedis(tripFare)
        amountCaption = "EST. FULL FARE"
      } else if let riderPays {
        amountText = Self.cedis(riderPays)
        amountCaption = Self.riderQuoteLabel(paymentMethod).uppercased()
      } else {
        amountText = legacyFare.map(Self.cedis) ?? "Fare shown in MyShop"
        amountCaption = "ESTIMATED FARE"
      }

      let platformDiscount = Self.int(values["platformDiscountPesewas"])
      let promoDiscount = Self.int(values["promoDiscountPesewas"])
      let loyaltyDiscount = Self.int(values["loyaltyDiscountPesewas"])
      let covered: Int?
      if let platformDiscount {
        covered = platformDiscount
      } else if promoDiscount != nil || loyaltyDiscount != nil {
        covered = (promoDiscount ?? 0) + (loyaltyDiscount ?? 0)
      } else {
        covered = nil
      }
      let discounted = Self.bool(values["promoApplied"]) == true || (covered ?? 0) > 0
      var pricing: [String] = []
      if !discounted,
         let tripFare,
         let riderPays,
         tripFare == riderPays,
         earnings != nil {
        pricing.append("Est. full fare · \(Self.riderQuoteLabel(paymentMethod)) \(Self.cedis(tripFare))")
      } else {
        if earnings != nil, let tripFare {
          pricing.append("Est. full fare \(Self.cedis(tripFare))")
        }
        if earnings != nil, let riderPays {
          pricing.append("\(Self.riderQuoteLabel(paymentMethod)) \(Self.cedis(riderPays))")
        }
      }
      if let covered, covered > 0 {
        pricing.append("MyShop covers \(Self.cedis(covered))")
      }
      pricingText = pricing.isEmpty ? nil : pricing.joined(separator: " · ")
      var facts: [String] = []
      if let km = Self.double(values["distanceKm"]) {
        facts.append(String(format: "%.1f km trip", km))
      }
      if let minutes = Self.int(values["durationMins"]) {
        facts.append("~\(minutes) min")
      }
      safeFacts = facts.isEmpty ? ["Private route", "Verified request"] : Array(facts.prefix(2))
    } else {
      let minimumBid = Self.int(values["minBidPesewas"])
      amountText = minimumBid.map { "Bid from \(Self.cedis($0))" } ?? "Submit your quote"
      amountCaption = minimumBid == nil ? "YOUR QUOTE" : "MINIMUM BID"
      pricingText = nil
      var facts: [String] = []
      if let category = Self.string(values["categoryName"]), !category.isEmpty {
        facts.append(String(category.prefix(38)))
      }
      if let metres = Self.double(values["distanceMeters"]) {
        facts.append(String(format: "%.1f km away", metres / 1_000))
      }
      safeFacts = facts.isEmpty ? ["New job", "Location protected"] : Array(facts.prefix(2))
    }

    let expiresRaw = Self.string(values["expiresAt"])
      ?? Self.string(values["acceptanceExpiresAt"])
    expiresAt = expiresRaw.flatMap(Self.parseDate)
  }

  private static func cedis(_ pesewas: Int) -> String {
    String(format: "GHS %.2f", Double(pesewas) / 100)
  }

  private static func parseDate(_ raw: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
  }

  private static func string(_ value: Any?) -> String? {
    if let value = value as? String { return value }
    if let value = value as? NSNumber { return value.stringValue }
    return nil
  }

  private static func int(_ value: Any?) -> Int? {
    if let value = value as? NSNumber { return value.intValue }
    if let value = value as? String { return Int(value) }
    return nil
  }

  private static func double(_ value: Any?) -> Double? {
    if let value = value as? NSNumber { return value.doubleValue }
    if let value = value as? String { return Double(value) }
    return nil
  }

  private static func bool(_ value: Any?) -> Bool? {
    if let value = value as? Bool { return value }
    if let value = value as? NSNumber { return value.boolValue }
    if let value = value as? String {
      if value.lowercased() == "true" { return true }
      if value.lowercased() == "false" { return false }
    }
    return nil
  }

  private static func riderQuoteLabel(_ paymentMethod: String?) -> String {
    guard let method = paymentMethod?.trimmingCharacters(in: .whitespacesAndNewlines),
          !method.isEmpty else { return "Rider quote" }
    return method.lowercased() == "cash" ? "Rider quote · cash" : "Rider quote · in app"
  }
}
