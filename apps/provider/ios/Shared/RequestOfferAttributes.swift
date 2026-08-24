import ActivityKit
import Foundation

/// Privacy-safe wire contract shared by Runner, the Live Activity extension,
/// and the backend's ActivityKit APNs payloads.
///
/// Remote `start` and `update` pushes must use the Codable field names exactly
/// as declared here. In particular, dates are Unix seconds instead of `Date`
/// so the APNs JSON representation is unambiguous across server runtimes.
@available(iOS 16.1, *)
struct RequestOfferAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    let status: String
    /// Legacy rider quote. Never display this as provider earnings.
    let farePesewas: Int?
    let prePromoFarePesewas: Int?
    let clientPayableEstimatePesewas: Int?
    let promoDiscountPesewas: Int?
    let loyaltyDiscountPesewas: Int?
    let platformDiscountPesewas: Int?
    let tollLabel: String?
    let tollFeePesewas: Int?
    let promoApplied: Bool?
    let paymentMethod: String?
    let minimumBidPesewas: Int?
    let distanceKm: Double?
    let durationMinutes: Int?
    let category: String?
    let expiresAtEpochSeconds: Int
    let endReason: String?
  }

  let requestId: String
  let offerId: String
  let requestType: String
  let attempt: Int?
  let notificationReceiptVersion: Int?
  let notificationReceiptUrl: String?
  let notificationReceiptToken: String?
}
