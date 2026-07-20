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
    let farePesewas: Int?
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
}
