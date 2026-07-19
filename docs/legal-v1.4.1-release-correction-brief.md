# MyShop v1.4.1 legal-content correction brief

Status: **release-blocking factual correction input; not legal advice and not an
approved replacement document**

This brief gives Product and qualified Ghanaian counsel a bounded correction
set based only on owner-approved business rules and verified runtime state. It
must not be copied into production as final legal wording without review.

## 1. Verified public state on 2026-07-19

The production API currently serves:

| Document/audience | Version | Effective date | Verified problem |
| --- | --- | --- | --- |
| Terms / client | `1.0.0` | absent | Marked `DRAFT`; stale USSD, Flutterwave, fixed-percentage/cancellation, two-hour dispute, deletion-recovery and emergency-automation claims |
| Terms / driver | `1.0.0` | absent | Marked `DRAFT`; stale fixed 20%, Flutterwave, instant/batch payout and emergency-automation claims |
| Terms / artisan | `1.0.0` | absent | Marked `DRAFT`; stale fixed 20%, Flutterwave, two-hour dispute, instant/batch payout, cancellation and emergency-automation claims |
| Privacy / both | `1.0.0` | 2026-04-14 | Published; still requires counsel to reconcile data processing, retention and enabled features with the candidate |
| Acceptable Use / both | `1.0.0` | absent | Marked `DRAFT` and claims the deferred USSD channel |
| Community Guidelines / both | `1.0.0` | absent | No effective date; contains unproved automated emergency/recording and universal masking claims |

The exact public document bodies were not copied into audit output. The backend
candidate now includes an aggregate-only preflight that reports counts for
these conditions without emitting text, URLs, users or record identifiers.

## 2. Publication controls required

- Never edit or overwrite the accepted/current `1.0.0` tuple in place. Publish
  corrected text under a new semantic version and retain the old version for
  audit.
- The repository seed treats every source document as inactive unless its
  frontmatter explicitly sets `publish: true`. Publication requires a
  non-future effective timestamp and refuses draft/launch placeholders.
- Product/qualified Ghana counsel must approve the final text, exact effective
  date and notice. The owner has approved the consent transition: timestamp-only
  legacy roles must re-consent; active work may finish, new work remains
  blocked, and SOS/support/logout remain available.
- The strict aggregate preflight must report zero for the four consent-gated
  rows: Terms/client, Terms/driver, Terms/artisan and Privacy/both, all corrected
  version `1.4.1`. Acceptable Use is incorporated into each Terms document; it
  and Community Guidelines are not separate v1 consent controls.

### Verified consent-path impact (2026-07-19)

| Surface | Exact local authority | Remaining release evidence |
| --- | --- | --- |
| Client registration | Two independent unchecked controls display the exact current client Terms and shared Privacy; one acceptance is insufficient and both exact selections are submitted. | Prove the corrected `1.4.1` content and version-change refresh on installed old/new builds. |
| Provider registration | Driver and artisan flows independently display their role Terms and shared Privacy. The phone step waits for exact documents and fails closed if unavailable. | Prove both provider roles on installed builds, including delayed OTP and a mid-flow version change. |
| Shared mobile API | Registration sends exactly two document ID/slug/version/audience selections; the former boolean-only contract is rejected. | Pin the generated/client contract to the reviewed backend SHA. |
| Registration API | Initiation validates current/effective highest-precedence documents, Redis binds the snapshots to OTP, and completion revalidates and writes the immutable ledger in the role-creation transaction. | Prove the hard old-client cutover and live OTP callback path on pinned staging. |
| Existing sessions | Consent status and authenticated re-consent detect exact missing versions. New booking/job/matching paths are fenced while active work, SOS, support and logout continue. | Execute installed-app legacy re-consent and active-work continuity journeys. |
| Database/publication | Migration `20260719060000_immutable_role_legal_acceptance` enforces role ownership, exact current/effective audience precedence and immutable evidence. Published tuples are immutable; corrections are new rows. Final private-root purge may null only the deleted identity pointer. | Publish the reviewed rows, run strict preflight to zero and retain database/public-hash evidence. |
| Separate production Admin | No v1 legal editor is required; corrected rows use the reviewed seed/API publication procedure. | Preserve separation of duties and audit the actual operator publication. A richer Next Admin editor remains future scope. |

No acceptance is fabricated from legacy timestamps. The hard cutover rejects
old boolean-only registrations, and any legal version change between OTP
initiation and completion requires the user to refresh and accept again. These
mechanics are owner-approved and locally implemented; only legal content and
deployed proof remain open.

## 3. Approved factual replacement rules

The replacement documents may describe the following facts. Wording, statutory
bases, remedies, liability, retention exceptions and notices remain for counsel.

### Product and account scope

- Production service is Ashanti Region only. Ghana-wide geofencing is staging
  test configuration, not a production availability promise.
- V1 is app-based. USSD and Smile Identity automation are deferred and must not
  be presented as available channels.
- One private phone-auth identity may anchor one client, one driver and one
  artisan role. Each role has a separate non-public role-account ID, data,
  sessions, loyalty/referrals and emergency contacts. Deleting one role leaves
  siblings untouched.

### Provider verification

- V1 verification is manual. Every document is decided independently; a
  category/region coordinator approves and forwards, and Regional Manager final
  approval is mandatory before first Go Online.
- Artisan eligibility is Ghana Card plus exactly one of Business Registration
  or Trade Certificate.
- Driver evidence is Ghana Card, driver's licence, profile photo, roadworthiness
  certificate and insurance certificate. Roadworthiness and insurance are
  separate records attached to each vehicle.
- A printed expiry date is valid through that whole GMT date and becomes invalid
  at 00:00 GMT the next day. Advance expiry notice is seven days. Replacement
  review grace ends at the earlier of seven days from confirmed upload or the
  old document's invalidity boundary.
- Drivers may create multiple vehicles but select exactly one eligible vehicle
  per Online session. Approved vehicles are immutable to the driver; admin
  edits create a newly reviewed version. Vehicle and vehicle-category approval
  use Coordinator then Regional Manager review.

### Money, disputes and cancellation containment

- Commission is an admin-owned database value snapshotted at booking and
  applied to final pre-promotion fare. Do not promise a fixed 20% or remaining
  80% in copy.
- Tips are paid fully to the provider with zero commission.
- Client dispute admission lasts 24 hours: rides from `ride.completedAt`, and
  artisan jobs from `clientConfirmedCompleteAt`. The provider payout hold is a
  separate two-hour control; auditable recovery/clawback covers hours 2–24.
- Cash-origin refunds use an OTP-verified client MoMo destination. A provider
  clawback is created only after authoritative refund success.
- Automated batch/aggregate payouts are suspended for this release. Do not
  promise an 18:00 GMT batch, retry schedule or guaranteed 30–60 second payout.
  Describe only the payout behavior actually enabled and operationally proved
  at publication time.
- Promotion/loyalty/referral redemption and mutation are suspended. Existing
  balances and history remain visible/preserved.
- Cancellation remains available, but automatic fees, debt carry-forward,
  ratings/counters and cancellation-triggered transfers are suspended for this
  emergency release. Remove the current 20% artisan cancellation promise and
  any GH₵5 consequence until the release switch is separately enabled and
  proved.
- The payment gateway should not be named unless Finance/Product confirms the
  user-facing methods in the exact release. The candidate integrates Paystack;
  current Flutterwave claims are stale.

### Dispatch, safety and account lifecycle

- Ride offers are sequential. The server attempts authenticated delivery for
  ten seconds; a receipt starts a fresh 45-second driver decision window.
- SOS activation is a three-second hold with countdown, haptics and cancellation
  during the hold, followed by immediate activation. Do not promise automated
  police calls, audio/video recording, uploads, universal phone masking or
  emergency-contact delivery until each exact behavior is enabled and proved.
- A deleted role is retained for exactly 2,160 hours. Recovery is a gated OTP
  request plus the approved review chain, not a 24-hour undo. Automatic purge
  remains disabled until its storage, hold, backup and legal evidence passes.

## 4. Inputs still required from the owner/counsel

- Exact registered operator name, company number and registered address.
- Effective date and advance-notice period. Existing timestamp-only roles must
  explicitly re-consent under the approved active-work continuity rule.
- Approved, monitored legal, privacy, safety/appeals and support contacts; remove
  every placeholder or unowned mailbox.
- Exact enabled payment and payout methods at publication time, without an
  unproved delivery-time SLA.
- Final statutory retention schedule and legal bases by record class, including
  precise non-tax post-closure periods and hold-release notices.
- Review of independent-contractor, insurance, transport, consumer-protection,
  refund, suspension/appeal, liability, dispute-resolution and data-processing
  clauses under current Ghanaian law.

## 5. Release evidence

The legal gate closes only when:

1. Product/qualified Ghana counsel signs Terms/client, Terms/driver,
   Terms/artisan and Privacy/both version `1.4.1`, including their effective
   dates and approved hashes. Acceptable Use is incorporated in Terms.
2. The four rows are published through the audited seed/API path without
   changing an existing version tuple.
3. `ASSERT_RELEASE_READY=true` reports zero aggregate violations.
4. Public staging and production responses match the approved versions/hashes
   for every required audience.
5. Installed old/new client and provider apps prove exact registration,
   mid-OTP version refresh, legacy re-consent, active-work continuity and
   server-side new-work blocking.
