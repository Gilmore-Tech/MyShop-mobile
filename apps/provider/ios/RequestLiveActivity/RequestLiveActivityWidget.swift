import ActivityKit
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 16.1, *)
struct RequestLiveActivityWidget: Widget {
  private let accent = Color(red: 0.09, green: 0.57, blue: 0.36)
  private let gold = Color(red: 0.92, green: 0.65, blue: 0.12)

  var body: some WidgetConfiguration {
    ActivityConfiguration(for: RequestOfferAttributes.self) { context in
      lockScreenView(context)
        .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
        .activitySystemActionForegroundColor(accent)
        .widgetURL(
          isActionable(context) ? actionURL(context, action: viewAction(context)) : nil
        )
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label(kindTitle(context), systemImage: kindIcon(context))
            .font(.caption.bold())
            .foregroundStyle(accent)
        }
        DynamicIslandExpandedRegion(.trailing) {
          countdown(context)
            .font(.caption.bold().monospacedDigit())
            .foregroundStyle(accent)
        }
        DynamicIslandExpandedRegion(.center) {
          VStack(spacing: 2) {
            Text(amount(context))
              .font(.headline.bold())
              .lineLimit(1)
            if let summary = pricingSummary(context) {
              Text(summary)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(3)
            }
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack(spacing: 10) {
            ForEach(facts(context), id: \.self) { fact in
              Text(fact)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(accent.opacity(0.13), in: Capsule())
            }
            Spacer(minLength: 4)
            if isActionable(context) {
              Link(destination: actionURL(context, action: primaryAction(context))) {
                Text(primaryActionLabel(context))
                  .font(.caption.bold())
                  .padding(.horizontal, 11)
                  .padding(.vertical, 6)
                  .foregroundStyle(.white)
                  .background(accent, in: Capsule())
              }
            }
          }
        }
      } compactLeading: {
        Image(systemName: kindIcon(context))
          .foregroundStyle(accent)
      } compactTrailing: {
        countdown(context)
          .font(.caption2.bold().monospacedDigit())
          .foregroundStyle(accent)
          .frame(maxWidth: 42)
      } minimal: {
        Image(systemName: "bolt.fill")
          .foregroundStyle(gold)
      }
      .widgetURL(
        isActionable(context) ? actionURL(context, action: viewAction(context)) : nil
      )
      .keylineTint(accent)
    }
  }

  private func lockScreenView(_ context: ActivityViewContext<RequestOfferAttributes>) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        Image(systemName: kindIcon(context))
          .font(.headline)
          .foregroundStyle(.white)
          .frame(width: 38, height: 38)
          .background(accent, in: Circle())
        VStack(alignment: .leading, spacing: 2) {
          Text(kindTitle(context))
            .font(.headline)
          countdown(context)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(accent)
        }
        Spacer()
        Image(systemName: "lock.fill")
          .foregroundStyle(gold)
          .accessibilityLabel("Private details hidden")
      }

      Text(amount(context))
        .font(.system(size: 27, weight: .heavy, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.7)

      if let summary = pricingSummary(context) {
        Text(summary)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .lineLimit(3)
          .minimumScaleFactor(0.8)
      }

      HStack(spacing: 8) {
        ForEach(facts(context), id: \.self) { fact in
          Text(fact)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(accent.opacity(0.13), in: Capsule())
        }
        Spacer(minLength: 0)
      }

      if isActionable(context) {
        HStack(spacing: 10) {
          Link(destination: actionURL(context, action: viewAction(context))) {
            Text("View safely")
              .frame(maxWidth: .infinity)
              .padding(.vertical, 10)
              .background(Color.secondary.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
          }
          Link(destination: actionURL(context, action: primaryAction(context))) {
            Text(primaryActionLabel(context))
              .fontWeight(.bold)
              .foregroundStyle(.white)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 10)
              .background(accent, in: RoundedRectangle(cornerRadius: 12))
          }
        }
        .font(.subheadline.weight(.semibold))
      } else {
        Text("This offer is no longer available")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
      }
    }
    .padding(16)
  }

  @ViewBuilder
  private func countdown(_ context: ActivityViewContext<RequestOfferAttributes>) -> some View {
    let expiry = Date(timeIntervalSince1970: TimeInterval(context.state.expiresAtEpochSeconds))
    if context.state.status == "ended" || context.state.status == "expired" || expiry <= Date() {
      Text(userFacingEndReason(context.state.endReason))
        .lineLimit(1)
    } else {
      Text(timerInterval: Date() ... expiry, countsDown: true)
        .lineLimit(1)
    }
  }

  private func amount(_ context: ActivityViewContext<RequestOfferAttributes>) -> String {
    if let tripFare = context.state.prePromoFarePesewas, tripFare >= 0 {
      return "EST. FULL FARE  \(cedis(tripFare))"
    }
    if let clientPrice = resolvedClientPrice(context.state) {
      return "CLIENT PRICE  \(cedis(clientPrice))"
    }
    if let fare = context.state.farePesewas, fare >= 0 {
      return "ESTIMATED FARE  \(cedis(fare))"
    }
    if let minimumBid = context.state.minimumBidPesewas {
      return String(format: "Bid from GHS %.2f", Double(minimumBid) / 100)
    }
    return isRide(context) ? "Fare available in MyShop" : "Submit your quote"
  }

  private func pricingSummary(
    _ context: ActivityViewContext<RequestOfferAttributes>
  ) -> String? {
    guard isRide(context) else { return nil }
    let state = context.state
    var lines: [String] = []
    if let fee = state.tollFeePesewas, fee > 0 {
      let label = state.tollLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
      let resolvedLabel = label?.isEmpty == false ? label! : "Toll"
      lines.append("\(resolvedLabel.uppercased()) (100% TO YOU)  \(cedis(fee))")
    }
    if let tripFare = state.prePromoFarePesewas,
       let clientPrice = resolvedClientPrice(state),
       tripFare >= 0,
       clientPrice <= tripFare {
      let discount = tripFare - clientPrice
      lines.append("PROMO / DISCOUNT  - \(cedis(discount))")
      lines.append("CLIENT PRICE  \(cedis(clientPrice))")
    }
    return lines.isEmpty ? nil : lines.joined(separator: "\n")
  }

  private func resolvedClientPrice(_ state: RequestOfferAttributes.ContentState) -> Int? {
    if let clientPrice = state.clientPayableEstimatePesewas, clientPrice >= 0 {
      return clientPrice
    }
    let hasCurrentContext = state.prePromoFarePesewas != nil
      || state.platformDiscountPesewas != nil
      || state.promoDiscountPesewas != nil
      || state.loyaltyDiscountPesewas != nil
    guard hasCurrentContext, let legacyFare = state.farePesewas, legacyFare >= 0 else {
      return nil
    }
    return legacyFare
  }

  private func cedis(_ pesewas: Int) -> String {
    String(format: "GHS %.2f", Double(pesewas) / 100)
  }

  private func facts(_ context: ActivityViewContext<RequestOfferAttributes>) -> [String] {
    var values: [String] = []
    if !isRide(context), let category = context.state.category, !category.isEmpty {
      values.append(String(category.prefix(28)))
    }
    if let distance = context.state.distanceKm {
      values.append(String(format: "%.1f km", distance))
    }
    if let duration = context.state.durationMinutes {
      values.append("~\(duration) min")
    }
    if values.isEmpty {
      values = isRide(context) ? ["Private route"] : ["Location protected"]
    }
    return Array(values.prefix(2))
  }

  private func kindTitle(_ context: ActivityViewContext<RequestOfferAttributes>) -> String {
    isRide(context) ? "Ride request" : "Artisan job"
  }

  private func kindIcon(_ context: ActivityViewContext<RequestOfferAttributes>) -> String {
    isRide(context) ? "car.fill" : "wrench.and.screwdriver.fill"
  }

  private func isRide(_ context: ActivityViewContext<RequestOfferAttributes>) -> Bool {
    context.attributes.requestType.lowercased().contains("ride")
  }

  private func primaryActionLabel(
    _ context: ActivityViewContext<RequestOfferAttributes>
  ) -> String {
    isRide(context) ? "Accept" : "Submit bid"
  }

  private func primaryAction(
    _ context: ActivityViewContext<RequestOfferAttributes>
  ) -> String {
    isRide(context) ? "RIDE_ACCEPT" : "JOB_SUBMIT_BID"
  }

  private func viewAction(_ context: ActivityViewContext<RequestOfferAttributes>) -> String {
    isRide(context) ? "RIDE_VIEW" : "JOB_VIEW"
  }

  private func isActionable(_ context: ActivityViewContext<RequestOfferAttributes>) -> Bool {
    let status = context.state.status.lowercased()
    guard status != "ended", status != "expired", status != "cancelled" else { return false }
    return context.state.expiresAtEpochSeconds > Int(Date().timeIntervalSince1970)
  }

  private func userFacingEndReason(_ value: String?) -> String {
    switch value?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
    case "expired", "timeout", "timed_out", "offer expired":
      return "Offer expired"
    case "accepted", "ride_accepted", "job_accepted", "resolved", "completed", "offer resolved":
      return "Offer resolved"
    case "cancelled", "canceled", "revoked", "offer_revoked", "withdrawn", "offer withdrawn":
      return "Offer withdrawn"
    case "skipped", "declined", "ignored", "offer skipped":
      return "Offer skipped"
    case "signed_out", "logout", "account_changed", "signed out":
      return "Signed out"
    default:
      return "Offer ended"
    }
  }

  private func actionURL(
    _ context: ActivityViewContext<RequestOfferAttributes>,
    action: String
  ) -> URL {
    var components = URLComponents()
    components.scheme = "myshopprovider"
    components.host = "request-action"
    components.queryItems = [
      URLQueryItem(name: "requestId", value: context.attributes.requestId),
      URLQueryItem(name: "offerId", value: context.attributes.offerId),
      URLQueryItem(name: "requestType", value: context.attributes.requestType),
      URLQueryItem(
        name: "offerVersion",
        value: context.attributes.requestType.lowercased().contains("ride") ? "2" : nil
      ),
      URLQueryItem(name: "action", value: action),
      URLQueryItem(
        name: "expiresAt",
        value: ISO8601DateFormatter().string(
          from: Date(timeIntervalSince1970: TimeInterval(context.state.expiresAtEpochSeconds))
        )
      ),
    ]
    return components.url ?? URL(string: "myshopprovider://request-action")!
  }
}
