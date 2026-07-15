# Provider request overlay rollout

Status as of 2026-07-15. Development branches:

- Mobile: `feature/provider-request-overlay-redesign`
- Backend: `feature/provider-request-overlay-redesign`

## Product contract

- Android uses a native custom overlay after the provider explicitly grants
  **Display over other apps**. When permission is unavailable, the app falls
  back to an actionable high-priority notification.
- Android full-screen intent remains reserved for real calls/alarms. A request
  overlay foreground service may require a minimal ongoing system notification;
  the offer card itself is the primary UI.
- iOS does not permit an arbitrary overlay over another app. It uses a Time
  Sensitive actionable system notification, with the same backend expiry and
  action lifecycle.
- The backend absolute `expiresAt` is authoritative. Devices must never restart
  a fresh countdown after delayed delivery or a cold start.
- Locked presentation never contains customer/passenger names, exact addresses,
  raw job descriptions, avatars, or photos. Those fields appear only after an
  authenticated unlock.
- Ride actions: **Accept**, **Skip**, **View details**.
- Artisan actions: **Submit bid**, **Skip**, **View job**. Submit bid opens the
  existing bid form because amount, ETA, duration, and notes are required.

## Implementation checklist

### Audit and branches

- [x] Confirm the call feature is merged into mobile `staging`.
- [x] Create clean mobile/backend `feature/provider-request-overlay` branches.
- [x] Audit foreground, background, terminated, locked, expiry, and action paths.
- [x] Audit targeting: rides are sequential (one driver by default); artisan job
  invitations currently target the nearest three eligible artisans concurrently.

### Backend offer contract

- [x] Add a compact versioned ride/job offer payload with `offerId`, `sentAt`,
  and absolute `expiresAt`.
- [x] Make APNs/FCM visible title/body privacy-safe.
- [x] Add exact remaining Android TTL, APNs expiration, and stable collapse IDs.
- [x] Add a data-only `offer_revoked` control message contract.
- [x] Include ride fare/distance/duration and job category/distance/minimum-bid
  summary fields without exceeding the FCM payload limit.
- [x] Exempt live offer/control pushes from generic inbox rate limiting.
- [x] Enforce the driver role on ride REST accept/decline actions.
- [x] Add focused notification, ride, and marketplace tests.

### Shared mobile action path

- [x] Add REST client methods for ride accept/skip and job skip.
- [x] Add local fallback action buttons and deterministic notification IDs.
- [x] Drive fallback request timeout from backend `expiresAt`.
- [x] Add `ride:dismissed`/job terminal cleanup for foreground request surfaces.
- [x] Add the native action queue controller with cold-start replay and ack.
- [x] Cancel overlay, notification, ringtone, and in-app request state together.
- [x] Route ride accept to the authoritative active ride.
- [x] Route job Submit bid through hydrated job details into the bid sheet.

### Android

- [x] Add the reusable `incoming_request_overlay` Flutter plugin.
- [x] Add overlay permission onboarding and real status in Notification Settings.
- [x] Render a custom ride/job card with countdown and repeating sound/vibration.
- [x] Redact the card while keyguard is locked and require unlock for private
  details or state-changing actions.
- [x] Persist native button actions before launching Flutter.
- [x] Retain the actionable notification fallback when overlay permission is off.
- [x] Declare and build-verify the `specialUse` foreground-service type and
  permissions.
- [ ] Complete the corresponding special-use declaration in Play Console before
  production rollout.

### iOS

- [x] Register `RIDE_REQUEST` and `JOB_REQUEST` categories/actions at launch.
- [x] Persist and replay selected native actions across terminated-app starts.
- [x] Use Time Sensitive delivery, privacy-safe copy, APNs expiry, and collapse ID.
- [x] Remove delivered offers on action/revocation when iOS permits it.
- [x] Expose real notification/Time Sensitive status and a Settings link.

### Modern request redesign and map preview

- [x] Redesign ride and artisan request screens with a clearer amount,
  countdown, distance/duration, request details, and fixed action hierarchy.
- [x] Add a non-interactive in-app map for ride pickup/destination and artisan
  job location, with a neutral fallback when coordinates are unavailable.
- [x] Add an Android native map/photo hero and keep primary actions pinned below
  the scrollable request details.
- [x] Issue an opaque backend `mapPreviewUrl` that expires with the exact offer;
  exact coordinates and Mapbox credentials remain server-side.
- [x] Stream the static image with no-store headers, bounded image validation,
  capability-token log redaction, and HTTPS-only Android loading.
- [x] Never fetch or display the map/photo while Android is locked. iOS keeps its
  privacy-safe system notification and shows the map after the app is unlocked.
- [ ] Confirm the production API `APP_URL` is public HTTPS and that
  `MAPBOX_ACCESS_TOKEN` can read the configured `MAPBOX_STYLE_URL`.
- [ ] Complete the redesigned-card physical-device checks below.

## Automated verification

- [x] Provider `flutter analyze` and full provider Flutter test suite.
- [x] Android release AAB build and native overlay Kotlin unit tests.
- [x] Unsigned iOS device build and Swift parser check.
- [x] API client ride/job action tests and overlay package tests.
- [x] Backend Nest build, TypeScript type-check, and focused regression tests.

### Deferred product/data decisions

- [ ] Decide whether artisan matching remains three concurrent bidders or changes
  to provider-by-provider rounds. It is targeted, not platform-wide broadcast.
- [ ] Add a real customer-entered `budgetPesewas` field end to end if product
  requires “Budget.” Until then, UI must label category pricing as **Minimum bid**
  and must not present the existing zero placeholder as a customer budget.
- [x] Round coordinates in the platform-wide artisan social-proof feed to a
  roughly one-kilometre grid; it remains non-actionable and anonymised.

## Rollout status

- [x] Commit and push both `feature/provider-request-overlay` branches.
- [x] Open backend PR [#93](https://github.com/Gilmore-Tech/myshop/pull/93)
  into `staging`.
- [x] Open draft mobile PR
  [#82](https://github.com/Gilmore-Tech/MyShop-mobile/pull/82) into `staging`.
- [ ] Restore GitHub Actions runner availability and rerun both PR checks. The
  2026-07-15 runs did not start any steps because organization billing failed
  or the Actions spending limit was reached; this was not a test failure.
- [x] Merge backend PR #93 and mobile PR #82 into `staging`.
- [ ] Commit, push, and open PRs for the redesign branches after local and
  physical-device acceptance.

## Physical-device acceptance matrix

- [ ] Android foreground, background, terminated, other app, screen off, locked.
- [ ] Android overlay permission granted, denied, revoked, and OEM battery saver.
- [ ] iOS foreground, background, terminated, screen off, and locked.
- [ ] iOS Time Sensitive on/off and previews Always/When Unlocked/Never.
- [ ] Ride Accept/Skip/View; another driver wins; rider cancels; exact expiry.
- [ ] Job Submit bid/Skip/View; client cancels; bid submitted; exact expiry.
- [ ] Repeating Android sound/vibration stops on every terminal/action path.
- [ ] No stale offer appears after an offline device reconnects.
- [ ] No names, exact addresses, descriptions, or photos appear while locked.
- [ ] An unrelated provider account receives no actionable offer.
- [ ] Android unlocked ride card shows the map preview, both route markers, and
  pinned Accept/View/Skip actions without clipping on a small screen.
- [ ] Android unlocked job card shows the job-location preview/photo and pinned
  Submit bid/View/Skip actions without clipping.
- [ ] Map failure, slow network, expired preview URL, and missing coordinates all
  degrade to readable request details without delaying offer actions.
- [ ] Flutter ride/job detail screens show their interactive data only after
  unlock and preserve Accept/Decline/Submit bid/Skip behavior.
