# MyShop 1.4.1 store-listing corrections

Status: **draft for Product/Legal approval; not yet applied in either store**

This sheet is intentionally conservative. It uses only business rules already
recorded in the production release checklist and avoids promising deferred
features, unverified service levels, or payment timing. Store operators must
compare the final rendered listing with this sheet before submitting version
`1.4.1`.

## Last captured listing identities and public versions

| App | Platform | Exact public identity | Public version last checked 2026-07-23 GMT |
| --- | --- | --- | --- |
| Client | Android | `com.gilmoretech.myshopclient` | `1.4.1` |
| Client | iOS | bundle `com.gilmoretech.myshopclient`, Apple ID `6773658114` | `1.3.9` |
| Provider | Android | `com.gilmoretech.myshopprovider` | `1.4.1` |
| Provider | iOS | bundle `com.gilmoretech.myshopprovider`, Apple ID `6773660049` | `1.4.0` |

This is the last recorded read-only public snapshot, not a live store-console
or private-build check. The current release line in that snapshot is `1.4.1`:
it is public on Android, while the iOS update remains pending. Recheck all four
public listings and read the highest private build number for each app/store
immediately before choosing a new build code.

## Claims that must be removed or corrected

| Current claim pattern | Release-safe correction |
| --- | --- |
| “No surge surprises” | State that the user reviews the fare shown before requesting. Do not imply surge or other configured pricing adjustments can never apply. |
| “Instant” or “same-day” payout after every ride/job | Do not promise payout timing. Automated scheduled/batch and aggregate payouts are disabled for this release, and dispute/payment state can hold settlement. |
| Provider verification “within 24 hours” | Remove the SLA. Review is manual and requires the approved reviewer chain; no completion time is approved. |
| Artisan requires both Business Registration and Trade Certificate | State Ghana Card plus **either** Business Registration **or** Trade Certificate. Each document is independently approved. |
| Driver verification described as Ghana Card/selfie only | State Ghana Card, driver’s licence, profile picture, and separate roadworthiness and insurance evidence for the selected vehicle. Each item is independently approved. |
| “One-tap” or “two-tap” emergency activation | State a deliberate three-second hold. The hold itself confirms activation; there is no second confirmation. |
| Trip or emergency recording is available | Remove. Emergency audio/video recording is explicitly deferred and disabled. |
| Phone numbers are always masked | Remove unless every exposed phone-call route is proved to use a masking proxy. In-app communication can be described without claiming that an external phone call hides the number. |
| Full Twi/bilingual availability | Remove unless the exact signed app is independently localization-tested and Product approves the claim. |
| Loyalty earning/redemption or promotion benefits | Remove for this release. Reward mutation and redemption stay disabled. |
| USSD or automated SmileKYC | Remove. Both are deferred. Verification is manual in v1. |
| Guaranteed verified clients, background checks, or police checks | Remove unless the exact enabled workflow and evidence are proved. |
| Fixed support email or response-within-24-hours promise | Direct users to the in-app tracked ticket flow until the mailbox and named monitoring owner are verified. |
| Operating nationwide | Production service remains the approved Ashanti Region pilot. Ghana-wide geofencing is staging-only. |

## Conservative client description draft

MyShop helps clients request rides and find artisans in supported areas of
Ghana.

### Rides

- Enter pickup and destination details and review the fare shown before
  requesting.
- Follow the assigned driver during an active ride.
- Use the payment options made available for the booking in the app.

### Artisan services

- Post a service request and review available bids.
- Choose an artisan and follow the job through its recorded stages.
- Confirm completion and use the in-app dispute flow when something is wrong.

### Safety and privacy

- Provider accounts are reviewed manually under MyShop's verification rules.
- During an eligible active booking, hold the SOS control for three seconds to
  raise the platform alert and open the Ghana Police dialler.
- Use the communication tools made available for an eligible booking.

MyShop is operating an open-beta pilot in the Ashanti Region. Availability and
payment methods depend on the booking and current service coverage.

For help, open a tracked support ticket inside the app.

## Conservative provider description draft

MyShop Provider is the work app for approved MyShop drivers and artisans in the
supported pilot area.

### Manual approval

- Drivers provide a Ghana Card, driver's licence, profile picture, and separate
  roadworthiness and insurance evidence for each vehicle.
- Artisans provide a Ghana Card plus either a Business Registration or a Trade
  Certificate.
- Each required document is reviewed independently. Provider approval follows
  the Coordinator and Regional Manager process before Go Online is available.
- Drivers with multiple vehicles choose one approved vehicle when going
  Online; only that vehicle is active for the session.

### Work and safety

- Eligible drivers receive ride requests and eligible artisans receive service
  requests while Online.
- Booking status, earnings, and payment state are shown in the app. No payout
  timing is guaranteed by this listing.
- Location is used while Online, including background operation where the
  device permits it, so nearby requests and active work can be supported.
- During eligible active work, hold the SOS control for three seconds to raise
  the platform alert and open the Ghana Police dialler.

MyShop Provider is operating an open-beta pilot in the Ashanti Region.

For verification or booking help, open a tracked support ticket inside the app.

## Submission gate

- [ ] Product approves the final client wording.
- [ ] Product approves the final provider wording.
- [ ] Legal/privacy confirms the location, verification, payment, and safety
      descriptions.
- [ ] Support confirms a named owner for any published mailbox; otherwise the
      listing keeps in-app ticket wording only.
- [ ] Deferred features remain absent from description, screenshots, release
      notes, reviewer notes, and promotional text.
- [ ] Android and iOS text for the same app are semantically identical.
- [ ] Screenshots match the signed `1.4.1` artifacts and show no deferred or
      false-success state.
- [ ] Release notes describe only behavior present in the exact signed build.
- [ ] The selected build code is higher than every private build in both store
      consoles for that exact app.
- [ ] All four artifacts come from one reviewed, clean `origin/main` SHA and
      pass `tool/verify-release-artifact.sh`; the historical `+23` set and lone
      Provider `+24` APK are not submission candidates.
- [ ] Fresh iOS archives pass app-owned dSYM verification. Matching vendor
      dSYMs are obtained, or the exact Mapbox/WebRTC/`objective_c`
      crash-symbolication limitation is explicitly accepted; empty UUID-only
      dSYMs must never be manufactured to hide the warning.
