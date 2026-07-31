# Current Mobile Update Checklist

Status captured: **2026-07-31 GMT**

## Authoritative 2026-07-31 main release cut

This block supersedes older status lines for the immediate store update. The
older sections remain the implementation and test ledger; they must not be
used to add unreviewed work to this cut.

### Frozen candidate

- [x] Released baseline is `1.4.1+25` on Client Android, Client iOS, Provider
      Android and Provider iOS.
- [x] Mobile runtime candidate is exact tested staging commit
      `4fae1fe30a054e168134d9ccc83d3c9960d6169a`.
- [x] Backend dependency candidate is exact tested staging commit
      `6aa1cc2553b0c3a0b2bde56fa27824e90dec2ec4`.
- [x] Admin `main` and `staging` have identical content; no Admin release is
      included.
- [x] The owner reports the frozen Mobile and Backend candidate behavior was
      tested on staging and authorizes preparation of the store update.
- [x] Exact Mobile staging commit `4fae1fe…`, tree `4c8d008c…`, passed all
      three release-contract suites, **800/800** tests across six packages,
      all seven package analyzers with zero issues, `git diff --check`, and
      finished with a clean detached worktree.
- [x] The dirty primary workspaces and every uncommitted/deferred branch are
      excluded. Only committed staging ancestry may enter `main`.

### Included in this update

- Graceful offline/service handling without false Terms/Privacy failure,
  avoidable logout, or loss of recoverable ride/request state.
- Exact-role session ownership, crash-consistent token refresh recovery and
  removal of the Provider-only local seven-day session expiry.
- Provider trusted-location recovery ordering without weakening document,
  verification, vehicle or online-eligibility rules.
- Single-owner Provider request-notification navigation, terminal request
  cleanup and safe cancellation/reconnect recovery.
- Provider signup/OTP reliability, Ghana-only Provider registration numbers,
  optional referral handling and user-safe actionable errors.
- Client booking-action/iOS review-flow corrections and the retained,
  documented in-app VoIP functionality.

### Production and signed-build gates

- [ ] Create and review Backend `staging` to `main` PR.
- [ ] Apply
      `20260727000000_durable_role_refresh_lineage` to the production database.
- [ ] Replace the Backend fleet with **zero mixed-version serving**, following
      `docs/refresh-lineage-controlled-cutover.md`; verify the two refresh
      authority flags, exact deployed commit, health and recovery telemetry.
- [ ] Create and review Mobile release PR to `main`; its runtime tree must equal
      frozen staging commit `4fae1fe…` apart from this release-control record.
- [ ] Read the highest private build number for all four app/store targets.
- [ ] Use marketing version `1.4.1` and one common build number greater than
      `25` and greater than every private-console maximum.
- [ ] Build Client AAB, Client IPA, Provider AAB and Provider IPA from one
      clean exact `origin/main` SHA using `tool/build.sh`.
- [ ] Verify bundle IDs, version/build, signing identities, production API,
      embedded source SHA and absence of staging endpoints in all artifacts;
      retain SHA-256 hashes.
- [ ] Install the exact release artifacts and smoke test login/session restore,
      offline recovery, Client booking, Provider online/location, foreground
      and background request delivery, notification tap, cancellation,
      Provider signup/OTP and in-app calling.
- [ ] In App Store Connect, retain the VoIP/background-audio review video and
      notes for both apps and keep China unavailable while CallKit is active.
- [ ] Upload only the verified artifacts to internal tracks, complete the
      matching privacy/Data Safety answers, then promote with rollback and
      monitoring owners recorded.

### Explicitly deferred

- Offer API/Admin offer publishing, automated batch payouts, promo-point
  redemption, SmileKYC, aggregate capacity claims and all other wider
  100k-DAU audit work remain outside this store update.

## Authoritative 2026-07-31 Provider signup/OTP reliability control block

This block is the authority for the reported Provider phone-stage signup and
OTP-delivery incident only. It does not replace the separate session-recovery
block below and does not reopen already-merged notification work.

- **Release status: merged into the frozen staging candidate and accepted by
  the owner for release preparation; production signed-artifact smoke proof
  remains open in the main release-cut block above.**
- Notification/request-routing fixes are already merged to Mobile staging by
  PR `#112`, merge `d0d39ab`; they require no duplicate PR.
- Mobile runtime/test commit `46b1320` and its checklist commit `96d1049`
  merged through PR `#113` into staging `4fae1fe…`.
- Backend runtime/test commit `d28df1a` merged through PR `#135` into staging
  `6aa1cc2…`.
- Approved rules: Provider registration accepts Ghana numbers only; referral
  is optional and must never block when absent/blank, but a supplied code must
  be valid. Client registration and Provider sign-in country behavior remain
  unchanged.
- This slice adds no database migration and makes no production configuration
  or deployment change.

### Completed engineering gates

- [x] Provider signup restricts the country picker and final submission to
      canonical Ghana E.164 (`+233` plus nine digits), with the same backend
      contract and a stable `INVALID_PHONE_FORMAT` response.
- [x] Blank/absent referral bypasses referral validation. Malformed supplied
      codes return stable corrective copy; existing backend authority still
      decides whether a well-formed code exists, is allowed and is not self
      referral.
- [x] Restored/stale registration drafts are revalidated before paid OTP work.
      Driver/Artisan errors return to the exact profile, vehicle, service,
      ride-category, region or legal step; stale category/region selections
      are cleared and refetched.
- [x] Known backend registration failures have app-owned actionable copy.
      Unknown failures may include only a validated UUID support reference;
      raw server errors are not shown.
- [x] Provider registration admission uses an opaque per-phone bucket plus an
      independent high-ceiling IP abuse fence, so legitimate Ghanaian users
      behind one carrier NAT do not exhaust one another's ordinary auth bucket.
      Client registration remains on its existing IP bucket.
- [x] OTP delivery, verification, successful session establishment and the
      public OTP-flow response cannot be converted into a false failure by an
      audit-database outage. Arkesel/WhatsApp/voice policy, circuit and provider
      outcomes remain authoritative.
- [x] Provider signup failures write privacy-minimal diagnostics with provider
      type, stable error code, app/platform/build and support reference only;
      no phone, email, referral, vehicle, device, IP, token or user-agent value
      is retained by this diagnostic.
- [x] Mobile focused evidence passes **52/52 tests**, targeted analysis and
      `git diff --check`. Backend focused evidence passes **240/240 tests**,
      API typecheck, production build and `git diff --check`. Independent
      Mobile and Backend reviews found no release blocker.

### Open staging/release gates

- [x] Commit only the recorded Mobile and Backend diffs and push separate
      branches: Mobile `46b1320` / PR `#113`; Backend `d28df1a` / PR `#135`.
- [x] Review both PRs and merge them to `staging`.
- [x] Deploy the Backend staging candidate and test the matching Mobile staging
      candidate, as confirmed by the owner. No migration command was required
      for this signup slice.
- [ ] Physically test Driver and Artisan signup with local and `+233` forms;
      reject non-Ghana/malformed values before API/OTP work.
- [ ] Prove referral absent, blank, malformed, nonexistent, self-owned and
      valid cases; only absent/blank may bypass referral authority.
- [ ] Prove duplicate email/role/vehicle, stale service/ride category, region,
      legal-version and provider-delivery failures show actionable safe copy
      and return to the correct step without losing the draft.
- [ ] Prove Arkesel SMS signup, delayed SMS plus resend, wrong/expired OTP,
      background/foreground and a controlled audit-store failure without
      duplicate delivery, consumed-code lockout or false session failure.
- [ ] Correlate a failed test with the support reference in the immutable audit
      view and verify the diagnostic contains no disallowed personal data.
- [ ] Recheck Render's actual
      `OTP_DELIVERY_GLOBAL_LIMIT_PER_MINUTE`. Code/default remains **20/minute**;
      no paid-send ceiling increase is authorized until the owner chooses the
      cost/capacity limit.

### Explicit nonblocking follow-ups

- Guard-level `429` responses occur before the audit interceptor; existing
  Redis throttle metrics count them, but they do not yet receive the full
  signup support-reference diagnostic.
- The ephemeral per-phone throttle key uses one-way SHA-256 like the existing
  OTP limiter; keyed-HMAC hardening is deferred.

## Authoritative 2026-07-30 session-recovery control block

This block supersedes the 2026-07-29 candidate status immediately below. The
older block and the historical ledger remain evidence; they must not be used
to claim that this new repair has already been committed, deployed or tested
on physical devices.

- **Release status: NO-GO pending source integration, staging deployment and
  physical upgrade/reconnect testing.**
- Released baseline on Client Android, Client iOS, Provider Android and
  Provider iOS remains **`1.4.1+25`**, source
  `66c4f9c7f5ab958271bfef0ddb6e9ad086c982e4`.
- Mobile implementation is isolated at
  `/private/tmp/myshop-mobile-client-session-recovery`, branch
  `fix/client-network-session-recovery-20260730`, based on Mobile staging
  `160e99f`. It is uncommitted and unpushed.
- Backend implementation is isolated at
  `/private/tmp/myshop-attempt-bound-refresh-recovery`, branch
  `fix/attempt-bound-refresh-recovery-20260730`, based on Backend staging
  `432decf`. It is uncommitted and unpushed.
- The dirty primary Mobile workspace, its location/dispatch work, release
  scripts, checklists and Provider Pod lock were not overwritten or staged.
  Backend/Admin primary workspaces were not changed.
- Included scope is only the reported false-session-loss repair and the exact
  ownership required to make it safe: crash-consistent token-pair storage,
  durable refresh-attempt recovery, saved-session restore, Provider
  seven-day-local-expiry removal, explicit logout fencing, exact
  `sub + role + roleAccountId + sid` ownership for REST/realtime/chat/device
  registrations, and backend immediate-predecessor recovery.
- Provider location/dispatch changes, OTP redesign, payment work, telemetry
  expansion, Admin changes and the wider 100k-DAU roadmap remain excluded.
- This repair adds no migration. It uses the already-reviewed
  `20260727000000_durable_role_refresh_lineage` schema and its two rollout
  flags. Staging/production migration state and both JSON boolean flags must
  still be verified against the exact target database before deployment.

### Completed engineering gates

- [x] Network, timeout, `5xx`, unknown transport failures and code-less `401`
      responses preserve local credentials and never route an existing user
      to OTP.
- [x] Only explicit terminal backend codes may clear an exact current session;
      a late terminal response or retry from session A cannot clear, replay or
      publish through session B.
- [x] Mobile persists one 256-bit `refreshAttemptId` before the refresh request
      and reuses it after an ambiguous lost response. Backend reconstructs the
      same immediate successor only from exact predecessor, attempt, SID,
      role-account and durable-lineage evidence.
- [x] Released `+25` two-key credentials upgrade non-destructively. Torn
      pre-SID and missing-role-account states use explicit bootstrap-only
      recovery rather than ordinary refresh or destructive guessing.
- [x] A user-initiated logout is fenced before repair/network I/O. A valid
      access token is revoked directly; missing, unreadable, expired or
      near-expiry access is refreshed behind the fence. Delayed logout A cannot
      hide or clear a separately accepted login B.
- [x] Client and Provider cold-start restore use cached exact-role profiles
      where available. Temporary profile/service failure stays in saved-session
      recovery with exactly `Connect to the internet and try again.` and never
      falls through to legal-consent or phone/OTP screens.
- [x] Provider authentication no longer expires locally after seven days.
      Going Online eligibility, verification, vehicle, notification and
      location controls remain independent and fail closed.
- [x] Main, chat and call sockets; Client/Provider chat outboxes; FCM, VoIP and
      ActivityKit registrations; cached profiles; legal status and Provider
      Online intent are bound to the exact role account and SID.
- [x] iOS install-boundary handling preserves the first `+25` upgrade and
      clears Keychain credentials/device identity after a later detectable
      uninstall/reinstall boundary.
- [x] Independent Backend and Mobile audits found no remaining release blocker
      in this isolated scope.
- [x] Final automated evidence is green:
  - Backend **222 suites / 4,402 tests**, auth-focused **261/261**, refresh
    cutover verifier **5/5**, build and typecheck pass; lint has zero errors
    (repository-existing warnings remain).
  - shared API-client **294/294**, Client **160/160**, Provider **246/246**;
    all three analyzers and both diff checks pass.
  - Client and Provider Android debug APKs and unsigned iOS device apps compile
    successfully. These are compile checks wired to staging, not signed release
    artifacts and not store-submission evidence.

### Open release gates

- [x] Reconcile the Backend worktree onto current `origin/staging`; its two
      newer location commits were non-overlapping and the auth patch reapplied
      cleanly.
- [ ] Review the exact final Mobile and Backend diffs once more.
- [ ] Commit intentionally, push, open separate Mobile/Backend PRs to staging,
      and merge only the reviewed files. Do not include dirty primary-worktree
      or generated Pod-lock changes.
- [ ] Verify `20260727000000_durable_role_refresh_lineage` and both rollout
      flags on the exact staging database. Preserve Redis; do not flush it.
- [ ] Deploy Backend first using the documented zero-mixed-version controlled
      replacement. Old and new API replicas must never rotate refresh tokens
      concurrently.
- [ ] Install the staging Mobile candidate as an in-place update over a real
      `1.4.1+25` Client and Provider, as well as on fresh Android/iPhone/iPad
      installs.
- [ ] Physically prove: genuine offline/online recovery on home and active
      ride/job routes; expired-access refresh; a deliberately lost refresh
      response; concurrent REST/socket/call refresh; app kill/relaunch;
      explicit logout; same-account new login; account/role A-to-B switch; and
      no OTP navigation unless the backend returns an approved terminal code.
- [ ] Correlate physical evidence with Backend refresh/lineage logs and confirm
      no `REFRESH_TOKEN_REUSED` cleanup follows a recovered predecessor.
- [ ] After staging acceptance, perform the same controlled Backend rollout to
      production, then select one private-console build number greater than
      `25` and every existing maximum, build four signed artifacts from one
      exact reviewed `origin/main` SHA, inspect them and submit.

## Authoritative post-`1.4.1+25` release control block

This block supersedes older baseline versions and progress percentages retained
later in this file as historical evidence.

- **Release status: NO-GO pending staging deployment and physical retest.**
  The combined Mobile and Backend candidates are committed, pushed and
  repository-gate clean; neither has been merged, deployed or migrated.
- Released baseline on all four store targets: **`1.4.1+25`**.
- Exact released source:
  `66c4f9c7f5ab958271bfef0ddb6e9ad086c982e4`.
- Current Mobile staging base:
  `b863d2b455cf1486aa29f7e71fa12257ace0e700`.
- Current Backend staging base:
  `18b3cd37c8337b7317297851f7c731e3688ba559`.
- Combined Mobile candidate:
  `agent/reconnect-session-recovery-staging-20260729`, component commits
  `a473b6a`, `31cbb43` and `ff39c90`.
- Combined Backend candidate:
  `agent/reconnect-session-recovery-backend-staging-20260729`, component
  commits `c1b51ae` and `dd0135d`.
- Current repair scope: automatic readiness recovery without route
  replacement; exact active ride/request reconciliation; and durable,
  attempt-bound recovery of the immediate refresh-token predecessor after a
  lost response.
- Still deferred and excluded: login-OTP delivery redesign, Provider
  location/dispatch fence, Backend/Admin audit candidates, telemetry
  expansion and unrelated primary-worktree changes.
- Primary Mobile workspace and its Provider `ios/Podfile.lock` modification are
  preserved and must not be staged into this candidate.
- The connectivity and ride-cancellation slices require no migration. The
  session slice adds only
  `20260727000000_durable_role_refresh_lineage`; it must first deploy with both
  `refresh_lineage_authority_enabled` and
  `refresh_lineage_cutover_quiesced` exactly `false`.
- Approved execution path for this update is a **manual build from the exact
  reviewed `origin/main` commit**. GitHub Actions release automation remains
  deferred; the current tag workflows do not supply the source/build-number
  inputs required by `tool/build.sh` and must not be used for this submission.

### Candidate implementation gates

- [x] Freeze and record the exact combined Mobile and Backend path inventory,
      branch, commit and migration after the three isolated repair slices are
      integrated. No primary-worktree, Podfile, OTP, location/dispatch,
      telemetry-expansion or Admin change may enter by accident.
- [x] Offline, timeout, malformed legal status and temporary service failure
      preserve the exact current route/form and never imply missing legal
      consent. The notice body must be exactly
      `Connect to the internet and try again.`
- [x] The notice disappears automatically only after `/health/ready` confirms
      healthy database and Redis dependencies; Retry must perform the same
      single-flight check without navigating.
- [x] Client matching, driver-found and tracking routes plus active ride/job
      routes retain usable lifecycle controls beneath a non-blocking top
      notice, including before an active ride ID has hydrated.
- [x] Confirmed user-facing error sinks render only fixed app-owned copy.
- [x] Client fare flow exposes a truthful state-aware action at every reviewed
      loading/error/location/availability state on iPhone and iPad layouts.
- [x] Complete combined test, analyzer, changed-source formatting, diff and
      release-contract gates on the final integrated candidate: Backend
      **222 suites / 4,345 tests**, build, typecheck and cutover verifier
      **4/4**; Mobile API-client **199**, Client **139**, Provider **215**,
      Shared UI **41**, all seven analyzers and diff checks pass.
- [x] Existing production configuration validates without exposing secrets for
      Client Android, Client iOS, Provider Android and Provider iOS through
      `tool/build.sh ... --validate-only`.
- [ ] Fresh-install and in-place upgrade from `1.4.1+25` pass on physical
      Android, iPhone and supported iPad devices.

### Apple submission gates

- [x] Retain the real booking-scoped `voip`, PushKit, CallKit and WebRTC
      functionality in both apps, including both apps' background `audio`
      during an accepted audible call. Candidate native/Pod diffs from `+25`
      are empty.
- [ ] Record the required two-device physical call/background-audio evidence
      and complete `docs/app-review-ios-voip-evidence.md`.
- [ ] Remove Mainland China from both apps' App Store availability while
      CallKit remains enabled.
- [ ] Read all four private-console maxima and select one unused build number
      greater than `25` and every maximum.
- [ ] Build, sign, inspect and install all four artifacts from one reviewed
      `main` commit, then submit with the exact review notes and video links.

### 2026-07-28 physical-failure repair and retest gates

- [x] Isolated connectivity/router candidate uses a foreground-aware,
      single-flight, bounded-backoff readiness probe. Its focused tests pass
      **26/26**, including automatic dismissal, stable Client GoRouter
      identity, usable matching/driver-found/tracking controls with no
      hydrated ride ID, and the exact approved connection copy with no
      retained “current screen/session” sentence.
- [x] Isolated cancellation/reconciliation candidates pass Backend
      **218 suites / 4,279 tests**, API-client **198**, Provider **208** and
      Client **132** tests, Backend typecheck/build and targeted Mobile
      analyzers. Exact cancellation reasons cannot be overwritten by a generic
      empty-pending result. A queued/coalesced Provider recovery follow-up also
      passes **25/25** targeted tests, including reconnects at one through four
      seconds and retained offer identities after a transient fetch failure.
- [x] Finish and independently review the durable refresh-lineage Backend plus
      the crash-consistent 256-bit Mobile `refreshAttemptId`: Backend
      **250/250**, cutover verifier **4/4**, Mobile API-client **199/199**,
      Backend build, Mobile analyze and both diff checks pass.
- [x] Integrate the three isolated repair slices on their exact staging bases,
      preserving both API-client barrel exports, then run the combined gates.
- [ ] Apply `20260727000000_durable_role_refresh_lineage` on staging; verify
      `role_refresh_sessions` and `role_refresh_lineage_cutover_status`; verify
      both rollout flags are JSON boolean `false`; keep Redis intact throughout
      the shadow deployment.
- [ ] Deploy and verify the migration plus Backend before installing the new
      Mobile candidate. Do not reverse this order: Mobile may send
      `refreshAttemptId` only after every serving Backend replica accepts and
      records it.
- [ ] Do not use a mixed-version rolling interval for this auth change. Drain
      or stop every old Backend replica before a new replica is allowed to
      rotate refresh credentials, then pass readiness before reopening
      traffic. An old replica can interpret a new replica's immediate
      predecessor as terminal reuse and destroy the recovered session.
- [ ] Prove an expired access token plus concurrent REST/socket/call refresh
      callers and a lost refresh HTTP response do not clear tokens, log out, or
      request OTP. The same stored attempt ID must recover the same successor;
      a missing or mismatched ID must not recover an attempt-bound rotation.
- [ ] Disconnect/reconnect on Client matching, driver-found and active tracking.
      Restore the same route and authoritative ride state. If the ride ended
      while offline, show the correct rider/driver/admin/system notice.
- [ ] Cancel from the Client while the Provider is foregrounded, backgrounded
      and offline. The Provider request, ringtone, overlay and durable offer
      must disappear immediately or on reconnect and must not replay.
- [ ] Repeat all physical checks on fresh installs and upgrades from
      `1.4.1+25` on Android, iPhone and a supported iPad.

### Committed repair evidence

- Mobile connectivity/router:
  `/private/tmp/myshop-mobile-offline-active-recovery-20260728`,
  `fix/offline-active-state-recovery-20260728`, commit `5e29c1a`.
- Mobile cancellation recovery:
  `/private/tmp/myshop-cancellation-recovery-mobile`,
  `codex/cancellation-recovery-mobile-20260728`, commit `f4a804f`.
- Backend cancellation recovery:
  `/private/tmp/myshop-cancellation-recovery-backend`,
  `codex/cancellation-recovery-backend-20260728`, commit `86b44a9`.
- Mobile refresh-attempt binding:
  `/private/tmp/myshop-mobile-refresh-attempt-staging-rc`,
  `fix/staging-refresh-attempt-binding-rc`, commit `6adf508`.
- Backend durable refresh lineage:
  `/private/tmp/myshop-refresh-lineage-staging-rc`,
  `fix/staging-durable-refresh-lineage-rc`, commit `1ddd3de`.
- The two combined branches are pushed. They have not been merged, deployed or
  migrated; all staging and physical acceptance gates above remain open.

This is the single authoritative checklist for the next Client and Provider
store update. The larger production audit and 100k-DAU roadmap remain evidence
and future-work registers; they do not expand this release unless an item is
explicitly copied into this file with owner approval.

## Historical pre-`+25` ledger — superseded

The remainder below is retained only to preserve decisions and evidence from
earlier releases. Its `+24` baseline, percentages and included-scope wording
must not be used to build or submit the current candidate.

At that historical checkpoint, counted progress was **92/137 checklist items
(67%)**. The stricter
final release-gate subset is **4/19 (21%)** because signed builds,
physical-device
acceptance, store declarations and canary evidence can only close after scope
reconciliation, the private-console build-number check and physical testing.
These are evidence counts, not estimates of effort.

## 1. Fixed release baseline

- [x] Previous release identity confirmed by the owner: **Client Android,
      Client iOS, Provider Android and Provider iOS are `1.4.1+24`**.
- [x] All four previous artifacts were built from `main`.
- [ ] Record the exact `main` source SHA used for `1.4.1+24`. It is currently
      unknown.
- [x] Repository pubspec values such as `1.4.1+20` are source defaults and must
      not be reported as the previous store build.

## 2. Approved scope for this update

### Included

- [x] Privacy-minimal mobile Audit telemetry already present on
      `origin/staging`.
- [x] Telemetry privacy hardening: route templates, query/fragment removal,
      concrete route-ID redaction, bounded correlation IDs and primitive-only
      metadata.
- [x] Telemetry delivery hardening: bounded queue/batches, non-blocking
      failures, low-activity delayed flush and bounded jittered retry.
- [x] Mobile payment-settlement reliability:
  - one in-flight status read per current ride or artisan-job payment;
  - generation/payment-ID fencing so a late response from an older attempt
    cannot settle or fail a replacement payment;
  - one shared provider active-job refresh during payment/recovery overlap;
  - privacy-safe payment lifecycle telemetry containing phase/outcome only.
- [x] Provider cash-commission (`Owings`) remittance reconciliation was
      explicitly added to this release scope on 2026-07-23 GMT.
- [x] Backend reconciliation is idempotent and provider-scoped: a successful
      Paystack verification applies a partial payment once, while failed,
      abandoned or reversed attempts leave the owing balance unchanged.
- [x] Provider payment UX polls an owned remittance status and reports success
      only after the backend completes settlement; delayed verification does
      not invite a duplicate payment.
- [x] Client session resilience was explicitly added to this release on
      2026-07-24 GMT: a temporary ride/API failure, Redis eviction/restart or
      refresh-lock contention must not convert the active Client role into an
      OTP login.
- [x] PostgreSQL remains authoritative for an already-bound Client session.
      Missing/malformed Redis cache state is recoverable only when the exact
      durable SID matches; explicit replacement SID, logout/recovery fence and
      generation-zero legacy state still fail closed.
- [x] The Client app caches the last successfully authenticated role-scoped
      profile and restores it before a quiet refresh; a temporary profile
      request failure does not erase tokens or redirect a returning user to
      OTP.
- [x] `REFRESH_IN_FLIGHT` is retried with bounded backoff and never clears
      tokens. True terminal refresh errors retain their existing logout
      behaviour.
- [x] Abandoning a ride estimate via system back, app back or Cancel clears
      pickup, destination, stops, vehicle choice and therefore the old fare.
- [x] A confirmed no-driver/matching cancellation also clears the same
      uncommitted draft before returning home; active/recoverable ride state is
      not touched.
- [x] Exact-role referrals were explicitly added to this release by the owner
      on 2026-07-24 GMT. Client, Driver and Artisan codes, referral history,
      reward accounts and balances remain strictly role-owned.
- [x] Referral migration `20260724000000_role_owned_referrals` is applied on
      staging. All nine post-migration invariants are zero; 53 role accounts
      migrated and 20 ambiguous legacy role accounts remain quarantined rather
      than being guessed.
- [x] Referral rollout remains fail-closed behind both environment flags and
      the audited database flag `role_account_referrals_enabled`. The database
      flag is still `false`; Admin showing
      `ROLE_ACCOUNT_REFERRALS_SUSPENDED` is therefore expected.
- [x] Rider matching status and pre-accept cancellation were explicitly added
      to this release by the owner on 2026-07-25 GMT.
- [x] Sequential ride decisions are reduced from 45 to **30 seconds per
      provider**, beginning only after that provider's authenticated receipt.
      The separate ten-second delivery allowance and five-minute search cutoff
      remain unchanged.
- [x] The Client receives only server-authoritative receipt/deadline data and
      displays a real 30-second countdown corrected against server time; it
      never starts or extends the provider decision clock from handset time.
- [x] The matching screen distinguishes initial search, driver receipt,
      declined/expired driver, next-driver search and radius expansion. It
      shows only a generic driver icon before acceptance.
- [x] A rider may cancel at any point before acceptance after a confirmation
      prompt. This cancellation is free and has no rider or provider strike.
      A create/cancel race remains fail-closed until the authoritative ride ID
      is known and cancelled.
- [x] Rider cancellation immediately closes the provider ringtone, overlay and
      request UI. The provider receives both an in-app notice and a normal
      system notification, including while the app is backgrounded.
- [x] Edit pickup is deliberately excluded from this release.
- [x] Client homepage usability was explicitly added to this release by the
      owner on 2026-07-26 GMT.
- [x] Restore the homepage current-location label to the user's
      human-readable resolved location. Reverse-geocoding must use bounded
      retry and must not present the synthetic `Using GPS location` label as
      though it were an address.
- [x] Add a Recent Activity section containing the latest three combined
      rides/jobs, newest first across all statuses. Tapping an item opens its
      existing detail view and `View all` opens the existing Activity screen.
      It is one-shot and session-cached, fetches at most three records from
      each source without 15-second polling, and is invalidated after
      create/status/cancel changes, reconnect and logout.
- [x] Hide the entire Special Offers section, including its heading and
      reserved space, whenever there are no offers.
- [x] Show a polished activity empty state when the Client has no recent rides
      or jobs.
- [x] Fix compact-width service-card overflow with a responsive call-to-action
      that remains usable without overflowing constrained cards.
- [ ] Apply migration
      `20260725000000_ride_acceptance_window_30s` to staging before testing
      this candidate.
- [ ] Physically prove the countdown begins only after receipt, survives
      reconnect without resetting, and gives each sequential provider a fresh
      30 seconds.
- [ ] Physically prove cancellation during initial search, provider ringing,
      another-driver search and radius expansion closes the ride with no fee
      or strike and immediately dismisses the provider UI.
- [ ] Physically prove the provider sees the cancellation in-app in foreground
      and as a normal system notification in background/locked states.
- [ ] Enable both referral environment flags on staging, use Super Admin to
      enable the database gate, and canary exact-role display, copy/share,
      registration attribution, rewards and disable rollback before production.
- [ ] Physically prove one phone with multiple roles never exposes or accepts a
      sibling role's code, history, points or reward balance.
- [ ] Physically prove an upgraded Client remains authenticated through an
      expired-access-token refresh and a controlled missing Client Redis cache
      row.
- [ ] Physically prove a no-driver `503` leaves the Client authenticated and
      that the next request starts with an empty trip/fare draft.
- [ ] Physically prove Android back, iOS back gesture, app back and Cancel each
      start the next ride request from an empty draft.
- [ ] Deploy the two reconciliation migrations and exact Backend candidate to
      staging before installing the corresponding Provider candidate.
- [ ] Physically prove on staging that a completed partial payment reduces
      `Owings` by the exact amount and a cancelled attempt becomes terminal
      without changing `Owings`.
- [ ] Merge and deploy Backend PR `#122`, then prove the two existing staging
      reconciliation candidates leave `processing`: the completed partial
      payment must settle once and the cancelled attempt must close without
      changing debt.
- [x] Release provenance tooling: require a clean exact `origin/main` SHA,
      embed it in Android, iOS and telemetry, and automatically inspect every
      built APK/AAB/IPA for identity, version, build, source, signature,
      production endpoint and staging-URL absence.
- [ ] Produce and verify the four signed artifacts from the eventual reviewed
      `main` SHA.
- [x] Candidate iOS privacy manifests declare linked, non-tracking Product
      Interaction for Analytics and add Analytics to the existing linked,
      non-tracking Device ID purpose.
- [ ] Apply the matching App Store Connect privacy and Google Play Data Safety
      answers to both apps; this is a private-console action and has not been
      completed.

### Explicitly excluded

- [x] No new payment provider or payment method.
- [x] No change to fares, commission, tips, refund rules, dispute timing,
      clawbacks, provider earnings or payout rules.
- [x] Automated batch/aggregate payouts remain disabled.
- [x] Promo/loyalty redemption remains disabled.
- [x] No call-duration, one-active-call or signalling-limit behavior change.
- [x] No provider-session relaxation: Driver and Artisan authentication
      remains Redis-and-PostgreSQL fail-closed.
- [x] No wholesale merge of the 136-path Mobile stability candidate.
- [x] No wholesale Backend/Admin scale candidate, realtime chat/GPS tranche,
      role recovery/purge, scheduled jobs, SmileKYC/police automation,
      emergency recording, support/dispute attachments, cancellation
      consequences or active-trip fallback.
- [x] No pickup editing from the matching screen in this release.
- [x] No offers API or Admin-to-Mobile offer-population build in this release;
      that integration is explicitly deferred to the next update.

Any request to add one of these items must first identify its exact paths,
business rules, migrations, tests and rollback, then receive an explicit owner
approval recorded here.

## 3. Current isolated candidates

### Current combined release heads

- Backend reviewed base: `origin/main`
  `11021d36a98c80d22c94c88a2e7592ae20c44b24`; production is still serving
  older commit `d918243cd7c6bda778fa54dec6ac0fdbe8140595`.
- Backend staging: `b904e516244e761d25013978bb33a1c8f596deb3`;
  staging health reports this exact commit with PostgreSQL and Redis healthy.
- Backend payment-lock fix: PR `#122`, commit
  `c5d8badf57424745d26eb8f32ebc94857715e3ee`
  (`fix(payments): return typed advisory lock result`), awaiting
  staging merge/deploy/canary.
- Mobile staging: `4daa9fdff57229920639a4cba677cb415063fa9a`.
- Admin staging: `71fb1597707826fdfc15b35148952838ff89853d`.
- [x] All three local workspaces were clean before release validation began.
- [ ] Merge validated Mobile staging to Mobile main.
- [ ] Merge validated Admin staging to Admin main.
- [ ] Merge the payment fix through Backend staging and Backend main after its
      staging canary.

### Historical isolated telemetry/payment candidate

- Main-based audit branch: `codex/audit-telemetry-mobile-rc`
- Production base: `origin/main` `61241f89dd48adef0c23d4bf9dbd2373b505947d`
- Main-based commit:
  `9979cc4` (`feat(release): add audited telemetry and payment reliability`)
- Staging review branch: `codex/audit-telemetry-payment-staging`
- Staging base before merge:
  `bd6390727ec2a6c5e8bf4dc4d5512433b992e18e`
- Staging candidate commit:
  `469c880` (`feat(release): add audited telemetry and payment reliability`)
- Isolated worktrees:
  `/private/tmp/myshop-mobile-audit-telemetry-rc` and
  `/private/tmp/myshop-mobile-audit-telemetry-staging-rc`
- Current scope: **32 paths** — the 12-path telemetry unit, five payment-only
  paths extracted from mixed commit `0e9c160…`, and 13 narrowly scoped
  provenance/version/native-metadata paths, plus the two iOS privacy manifests.
- [x] The five original payment files matched their reviewed source blobs
      exactly before payment lifecycle telemetry was added.
- [x] The four call-related paths from `0e9c160…` were not included.
- [x] Committed pre-marketing-version 32-path implementation fingerprint
      relative to the recorded `main` base:
      `9e1b64c5270f3136d514ff695815ab3fc40e98a22688ad28b9a2539316f1fe7b`.
- [x] Staging runtime delta is 26 paths, excluding this documentation-only
      checklist, because six approved paths already existed on
      `origin/staging`; its committed implementation fingerprint is
      `c96af523ee33618719511b58f170cdc4590da64fe5521b0a4063877fac8f00ab`.
- [x] Every one of the 32 approved implementation paths in staging commit
      `469c880` is byte-identical to the corresponding path in main-based
      commit `9979cc4`.
- [ ] Recompute and record the final candidate fingerprint after the approved
      marketing-version change.
- [x] Commit the exact approved implementation candidate locally.
- [x] Push `codex/audit-telemetry-payment-staging` to
      `origin` without merging it.
- [x] Merge the normal feature → staging review pull request; PR `#93` is
      present in `origin/staging` at merge commit `2a860ad`.
- [x] Cash-remittance reconciliation was committed and reviewed as Backend PR
      `#117` and Mobile PR `#94`.
- [x] Both reconciliation PRs are merged into `origin/staging`: Backend merge
      `0f4ca89` and Mobile merge `a86ff4a`. This is not evidence of deployment
      or physical payment acceptance.
- Client session/ride reset branches:
  `codex/client-session-ride-reset` in cleanly isolated Backend and Mobile
  worktrees. They branch from the already-reviewed reconciliation commits,
  which are ancestors of the current `origin/staging`; their PR diffs therefore
  contain only the new bug-fix delta.

## 4. Current verification evidence

- [x] Focused privacy/telemetry suite: **13/13 passed**.
- [x] Focused Client payment authority/telemetry suite: **8/8 passed**.
- [x] Focused Provider active-job authority suite: **7/7 passed**.
- [x] Complete API-client suite: **173/173 passed**.
- [x] Complete Provider suite: **172/172 passed**.
- [x] Complete Client suite: **88/88 passed**.
- [x] The pre-login timer defect is corrected: unauthenticated events remain
      queued without a timer or request; a later authenticated event schedules
      the batch. The focused regression proves both events are retained.
- [x] Fatal-info analyzers for Client, Provider and API client: **no issues**.
- [x] `git diff --check`, privacy source scan and exact 30-path implementation
      inventory passed.
- [x] Current Mobile automated total: **433/433 passed**.
- [x] Release version, source and artifact contract suites: **3/3 passed**.
- [x] Source verifier explicitly rejects malformed/mismatched SHAs, commits not
      at `origin/main`, dirty tracked files and untracked files.
- [x] Client and Provider Android candidate manifests compile with the
      production build's AndroidX property; both iOS plists and
      `ExportOptions.plist` parse successfully.
- [x] Local release-key inspection confirms the expected Client and Provider
      upload-certificate SHA-1 values. Play Console comparison remains a
      separate private-console gate.
- [x] Both iOS privacy manifests parse successfully and contain
      `NSPrivacyCollectedDataTypeProductInteraction` for Analytics plus
      Analytics as an additional Device ID purpose.
- [x] The IPA verifier now parses the packaged privacy manifest and requires it
      to be byte-identical to the reviewed app manifest; the artifact contract
      test passes and prevents packaging from silently dropping or replacing
      the declarations.
- [x] Backend-contract audit proved that ingestion may return HTTP 200 with
      `accepted: 0` when telemetry storage fails. Mobile now removes a batch
      only when the server confirms the full count; zero or partial acceptance
      is retained and retried. Both regressions and all three complete mobile
      suites pass.
- [x] The exact staging commit `469c880` independently passes Client **88/88**,
      Provider **169/169**, API client **172/172**, all three fatal-info
      analyzers, all three release contracts and `git diff --check`; its
      worktree is clean.
- [x] Repository Privacy Policy `1.4.1` sections 3.7 and 4 already disclose
      device/technical/security/audit/performance events and their use for
      diagnosis, capacity and user-experience improvement.
- [x] Cash-remittance Backend verification passed: Payment/Webhook focused
      suites **159/159**, migration-deploy contract **418/418**, Prisma schema
      validation and API build.
- [x] Cash-remittance Mobile verification passed: Provider reconciliation
      poller **3/3**, API-client status contract **4/4**, all three complete
      suites **433/433**, and the complete Provider analyzer with no issues.
- [x] Session/auth focused Backend verification passed: JWT guard,
      durable-role fence and AuthService suites **188/188**; complete API suite
      **4,140/4,140** and API build passed.
- [x] Client session/ride focused verification passed: cached restoration,
      refresh contention, draft reset and booking coordinator tests all pass.
- [x] Complete Client, Provider and API-client suites pass after the bug fix;
      Provider is **172/172** and API client is **175/175**.
- [x] Client, Provider and API-client analyzers report no issues after the bug
      fix.
- [x] Regression proves a generation-zero Client row cannot be bound when the
      Redis session proof is absent, while an already durable exact Client SID
      survives cache loss.
- [x] Exact current Mobile staging `4daa9fdf` passes the complete monorepo test
      command: Client **93/93**, Provider **174/174**, API client **175/175**,
      plus shared-package tests; all seven fatal-info analyzers are clean.
- [x] Exact current Mobile staging passes release-version, release-source and
      release-artifact contracts plus `git diff --check`.
- [x] Exact current Backend plus payment-lock fix passes **211/211 suites,
      4,112/4,112 tests**, API typecheck, production build, formatting and an
      executable PostgreSQL lock-shape check returning `lockAcquired = 1`.
- [x] Exact current Admin staging builds all 48 routes, has zero lint errors
      (existing warnings remain), and passes **39/39** contract tests.
- [x] Client homepage focused verification passes **9/9**: Recent Activity
      provider **3/3**, current-location provider **4/4**, and homepage widget
      behavior **2/2**. The final complete Client suite passes **111/111**,
      `flutter analyze --fatal-infos --fatal-warnings` reports zero issues,
      and `git diff --check` passes.
- [ ] The same policy does not expressly say that named screen, lifecycle and
      meaningful-action events are collected. Product/qualified Legal must
      decide whether the existing disclosure is sufficient or publish a new
      immutable policy version; this is not silently assumed by engineering.

## 5. Decisions still required

- [ ] Read the highest private build number for all four app/store targets.
- [x] Marketing version remains the previously approved `1.4.1` for both apps.
- [ ] Select one build number higher than every private-console maximum.
      `+25` is valid only if no target already contains a build above `24`.
- [ ] Confirm whether the existing Privacy Policy/store declarations already
      cover named screen/lifecycle/payment-phase telemetry. The source audit
      found broad technical/audit disclosure but no explicit named-action
      wording. If Product/qualified Legal requires a change, publish a new
      immutable version and obtain the required acceptance.
- [x] The owner decided on 2026-07-25 GMT that changing the operational
      decision window from 45 to 30 seconds does not require provider
      re-consent. Existing accepted Driver Terms `1.4.1` remain immutable and
      are not edited in place by this candidate.
- [ ] Add the real DPC registration number when available; never fabricate it.

## 6. Exact store privacy answers for this update

These rows describe only the telemetry delta. They do not replace the complete
existing privacy declarations for location, payment, identity, content,
communications or third-party SDKs.

### Apple — Client and Provider

- [ ] Product Interaction: **Collected = Yes; Linked to identity = Yes;
      Tracking = No; Purpose = Analytics**.
- [ ] Device ID: retain **Collected = Yes; Linked to identity = Yes;
      Tracking = No; Purpose = App Functionality**, and add **Analytics**.
- [ ] Confirm the final App Store Connect answers match the signed artifact and
      the embedded privacy manifest for each app.

### Google Play — Client and Provider

- [ ] App activity → App interactions: **Collected = Yes; Shared = No;
      Ephemeral = No; Required = Yes; Purpose = Analytics**.
- [ ] Device or other IDs: retain **Collected = Yes; Shared = No; Ephemeral =
      No; Required = Yes**, and include **Analytics** in addition to every
      already truthful purpose such as App functionality.
- [ ] Do not change global encryption, deletion-request, sharing or SDK answers
      from this delta alone; compare the complete current form with the exact
      signed artifact before submission.

## 7. Exact candidate inventories

The original approved telemetry/payment/provenance/privacy baseline remains the
following 32 paths.

### Telemetry and payment reliability

- `apps/client/lib/src/app/client_app.dart`
- `apps/client/lib/src/app/router.dart`
- `apps/client/lib/src/core/di/providers.dart`
- `apps/client/lib/src/features/auth/providers/auth_controller.dart`
- `apps/client/lib/src/features/ride/providers/ride_payment_provider.dart`
- `apps/client/lib/src/features/services/providers/payment_provider.dart`
- `apps/client/test/features/services/providers/payment_authority_test.dart`
- `apps/provider/lib/src/app/provider_app.dart`
- `apps/provider/lib/src/app/router.dart`
- `apps/provider/lib/src/core/di/providers.dart`
- `apps/provider/lib/src/core/providers/availability_controller.dart`
- `apps/provider/lib/src/features/artisan_home/providers/active_job_provider.dart`
- `apps/provider/lib/src/features/driver_home/providers/ride_request_provider.dart`
- `apps/provider/test/features/artisan_home/providers/active_job_lifecycle_authority_test.dart`
- `packages/api_client/lib/api_client.dart`
- `packages/api_client/lib/src/services/system_telemetry_service.dart`
- `packages/api_client/test/services/system_telemetry_service_test.dart`

### Release provenance and native metadata

- `apps/client/android/app/build.gradle.kts`
- `apps/client/android/app/src/main/AndroidManifest.xml`
- `apps/client/ios/Runner/Info.plist`
- `apps/provider/android/app/build.gradle.kts`
- `apps/provider/android/app/src/main/AndroidManifest.xml`
- `apps/provider/ios/Runner/Info.plist`
- `tool/build.sh`
- `tool/resolve-release-version.sh`
- `tool/test-release-version-contract.sh`
- `tool/verify-release-source.sh`
- `tool/test-release-source-contract.sh`
- `tool/verify-release-artifact.sh`
- `tool/test-release-artifact-contract.sh`

### Privacy-manifest delta

- `apps/client/ios/Runner/PrivacyInfo.xcprivacy`
- `apps/provider/ios/Runner/PrivacyInfo.xcprivacy`

### Client session and ride-reset bug-fix delta

- `apps/client/lib/src/features/auth/data/auth_repository.dart`
- `apps/client/lib/src/features/auth/providers/auth_controller.dart`
- `apps/client/lib/src/features/ride/providers/edit_trip_provider.dart`
- `apps/client/lib/src/features/ride/screens/driver_matching_screen.dart`
- `apps/client/lib/src/features/ride/screens/fare_estimate_screen.dart`
- `apps/client/test/app/client_bootstrap_router_test.dart`
- `apps/client/test/features/auth/client_auth_repository_session_test.dart`
- `apps/client/test/features/ride/providers/ride_request_draft_reset_test.dart`
- `packages/api_client/lib/src/http/token_refresher.dart`
- `packages/api_client/test/http/token_refresher_test.dart`

### Exact-role referral delta

- `apps/client/lib/src/core/deep_links/referral_deep_link.dart`
- `apps/client/lib/src/features/auth/screens/sign_up_screen.dart`
- `apps/client/lib/src/features/profile/providers/referral_provider.dart`
- `apps/client/lib/src/features/profile/screens/referral_screen.dart`
- `apps/client/test/core/deep_links/referral_deep_link_test.dart`
- `apps/client/test/features/auth/signup_redirect_test.dart`
- `apps/client/test/features/profile/referral_buttons_test.dart`
- `apps/client/test/features/profile/role_owned_data_error_test.dart`
- `apps/provider/lib/src/app/router.dart`
- `apps/provider/lib/src/features/auth/screens/phone_input_screen.dart`
- `apps/provider/lib/src/features/profile/providers/referral_provider.dart`
- `apps/provider/lib/src/features/profile/screens/account_settings_screen.dart`
- `apps/provider/lib/src/features/profile/screens/referral_screen.dart`
- `apps/provider/lib/src/features/registration/providers/registration_controller.dart`
- `apps/provider/lib/src/features/registration/screens/artisan_registration_screen.dart`
- `apps/provider/lib/src/features/registration/screens/driver_registration_screen.dart`
- `apps/provider/lib/src/features/registration/widgets/artisan_profile_step.dart`
- `apps/provider/lib/src/features/registration/widgets/driver_profile_step.dart`
- `apps/provider/pubspec.lock`
- `apps/provider/pubspec.yaml`
- `apps/provider/test/features/registration/referral_registration_test.dart`
- `docs/production-release-audit-checklist.md`
- `docs/staging-release-candidate-runbook.md`

### Ride matching status, cancellation and 30-second decision delta

- `apps/client/lib/src/core/providers/socket_provider.dart`
- `apps/client/lib/src/features/ride/providers/ride_provider.dart`
- `apps/client/lib/src/features/ride/screens/driver_matching_screen.dart`
- `apps/client/test/features/ride/providers/cancel_in_flight_ride_request_test.dart`
- `apps/client/test/features/ride/screens/driver_matching_status_test.dart`
- `apps/provider/lib/src/core/providers/socket_provider.dart`
- `apps/provider/lib/src/core/services/fcm_service.dart`
- `apps/provider/lib/src/core/services/local_notification_service.dart`
- `apps/provider/lib/src/core/services/ride_cancellation_notice.dart`
- `apps/provider/lib/src/core/services/ride_offer_receipt_service.dart`
- `apps/provider/lib/src/features/driver_home/providers/ride_request_provider.dart`
- `apps/provider/lib/src/features/driver_home/screens/ride_request_screen.dart`
- `apps/provider/test/core/services/ride_cancellation_notice_test.dart`

The paired Backend delta is restricted to receipt-authoritative countdown
events, the approved 30-second configuration and their tests/migration:

- `apps/api/src/modules/location/location.gateway.spec.ts`
- `apps/api/src/modules/location/location.gateway.ts`
- `apps/api/src/modules/notification/dto/register-device.dto.ts`
- `apps/api/src/modules/notification/push.service.ts`
- `apps/api/src/modules/providers/provider-eligibility.service.ts`
- `apps/api/src/modules/ride/ride-cancellation.service.ts`
- `apps/api/src/modules/ride/ride-migration-contract.spec.ts`
- `apps/api/src/modules/ride/ride-offer.constants.ts`
- `apps/api/src/modules/ride/ride-offer.service.spec.ts`
- `apps/api/src/modules/ride/ride-offer.service.ts`
- `apps/api/src/modules/ride/ride.controller.ts`
- `apps/api/src/modules/ride/ride.redispatch.spec.ts`
- `apps/api/src/modules/ride/ride.service.spec.ts`
- `apps/api/src/modules/ride/ride.service.ts`
- `docs/active-trip-fallback-release-gaps.md`
- `packages/database/prisma/migrations/20260725000000_ride_acceptance_window_30s/migration.sql`
- `packages/database/prisma/seed.ts`

The paired Backend delta is restricted to exact session authority and tests:

- `apps/api/src/common/guards/jwt-auth.guard.ts`
- `apps/api/src/common/guards/jwt-auth.guard.spec.ts`
- `apps/api/src/modules/account-exit/account-exit.service.ts`
- `apps/api/src/modules/account-exit/account-exit.service.spec.ts`
- `apps/api/src/modules/auth/auth.service.ts`
- `apps/api/src/modules/auth/auth.service.spec.ts`

No file outside the recorded inventories is authorised for this update without
first updating this checklist and obtaining owner approval.

## 8. Release gates

- [x] Fix the pending telemetry-timer lifecycle/test defect.
- [x] Complete all automated tests and analyzers with zero failures.
- [x] Owner approved the exact 32-path implementation inventory on
      2026-07-23 GMT.
- [x] Complete the source-provenance unit and prove it refuses dirty,
      non-`main` or source-mismatched builds.
- [ ] Apply the approved marketing version and one build number above every
      private-console maximum, then verify the actual signed artifacts.
- [ ] Merge through staging, deploy no unrelated Mobile/Backend/Admin changes,
      and test the exact reviewed SHA.
- [ ] Verify controlled events in Super Admin Mobile Activity: correct role,
      app, version/source, screen template, payment phase and 90-day expiry;
      prove no phone, OTP, location, message, amount, payment reference or raw
      provider response is retained.
- [ ] Physical-device payment tests for ride and artisan flows: MTN MoMo,
      Telecel Cash and card where currently supported; pending, delayed
      callback, retry, duplicate tap, app background/return, old-response race,
      success, decline and timeout.
- [ ] Physical-device telemetry tests: foreground, background, offline,
      reconnect, low-activity session and authenticated retry.
- [ ] Physical-device Client session tests: background/foreground, access-token
      refresh, controlled Client Redis cache loss, no-driver response and app
      restart must retain the authenticated role without another OTP.
- [ ] Physical-device ride-draft tests: Android/iOS back, Cancel and no-driver
      dismissal must clear pickup, destination, stops, vehicle and fare.
- [ ] Physical-device sequential matching tests: each provider receives a
      fresh server-authoritative 30 seconds only after receipt; delayed
      delivery, decline, expiry, reconnect and radius expansion show the
      correct Client state without losing or duplicating the request.
- [ ] Physical-device pre-accept cancellation tests: Android back, iOS back
      gesture and Cancel require confirmation, remain free/penalty-free, close
      every active offer immediately, and produce foreground plus
      background/locked provider notices.
- [ ] Staging cash-remittance canary after PR `#122`: completed partial payment
      settles once, cancelled payment becomes terminal, balances refresh, and
      no row remains indefinitely in `processing`.
- [ ] Staging exact-role referral canary with gates on, followed by a tested
      gates-off rollback; ambiguous quarantined legacy ownership remains hidden.
- [ ] Build, sign, inspect and install all four artifacts from the same reviewed
      `main` SHA.
- [ ] Complete App Store privacy and Play Data Safety declarations before
      submission.
- [ ] Canary with the two developers, monitor API/database errors and dropped
      telemetry, retain the previous store build, and exercise rollback.
- [ ] Record store submission IDs, review results and served versions.

## 9. Change log

| Date GMT | Scope change | Evidence/state |
| --- | --- | --- |
| 2026-07-23 | Corrected previous release identity | Owner confirmed `1.4.1+24` on all four targets, built from `main`; exact SHA still missing. |
| 2026-07-23 | Isolated telemetry | 12-path telemetry unit based on current `origin/main`; staging branch was not merged wholesale. |
| 2026-07-23 | Hardened telemetry privacy | Route-ID/query redaction, bounded identifiers and primitive-only metadata; focused tests pass. |
| 2026-07-23 | Added payment reliability to release scope | Five payment-only paths extracted; call paths excluded; focused Client 8/8 and Provider 7/7 pass. |
| 2026-07-23 | Added delivery reliability and payment lifecycle telemetry | Low-activity flush, transient retry and phase-only payment events; API client and Provider full suites pass. Client full suite remains blocked by two pending-timer test failures. |
| 2026-07-23 | Closed the pre-login telemetry timer defect | Delivery now waits for an authenticated token without dropping queued events; Client 88/88, Provider 169/169 and API client 170/170 pass; all analyzers are clean. |
| 2026-07-23 | Added fail-closed release provenance | Candidate is now exactly 30 paths. Source/identity metadata and post-build inspection cover Android, iOS and telemetry; three contract suites, two Android manifest compiles and all plist parses pass. Marketing version, private-console maxima and actual artifacts remain open. |
| 2026-07-23 | Reconciled telemetry privacy declarations | Candidate is now exactly 32 paths. Both iOS manifests declare linked/non-tracking Product Interaction analytics and the Device ID analytics purpose; exact Apple/Google console answers are recorded. Repository policy has broad audit/diagnostic disclosure but its explicit named-event wording remains a Product/Legal decision. |
| 2026-07-23 | Bound privacy declarations to signed IPA verification | The artifact gate now rejects a packaged app privacy manifest that is missing, invalid or different from the reviewed source; the updated contract passes. |
| 2026-07-23 | Closed server-acknowledged telemetry loss | HTTP success no longer deletes a batch when ingestion reports zero/partial acceptance. Focused telemetry is 13/13; Client 88/88, Provider 169/169 and API client 172/172 pass, for 429/429 total. |
| 2026-07-23 | Exact implementation scope approved | Owner approved the recorded 32-path telemetry, payment-reliability, provenance and privacy-manifest candidate; excluded features remain excluded. |
| 2026-07-23 | Prepared exact staging review candidate | Main-based commit `9979cc4` and staging commit `469c880` have byte-identical approved implementation paths. The clean staging commit passes 429/429 tests, all analyzers, all release contracts and whitespace validation; it has not been pushed. |
| 2026-07-23 | Published the review branch | `codex/audit-telemetry-payment-staging` was pushed to `origin` with the runtime and checklist commits. It has not been merged or deployed; draft PR creation remains pending. |
| 2026-07-23 | Merged the approved telemetry/payment candidate to staging | PR `#93` is present in `origin/staging` merge commit `2a860ad`; this does not constitute a store release. |
| 2026-07-23 | Added provider `Owings` reconciliation candidate | Backend verifies missed/misdirected Paystack callbacks, settles partial commission debt idempotently, closes cancelled attempts without touching debt, and exposes an owned status endpoint. Provider now waits for that authoritative state. Focused Backend **159/159**, migration contract **418/418**, Provider **3/3** and API-client **4/4** pass; staging deploy and physical payment proof remain open. |
| 2026-07-24 | Merged provider `Owings` reconciliation to staging | Backend PR `#117` and Mobile PR `#94` are present in `origin/staging`; deployment and physical staging proof remain open. |
| 2026-07-24 | Added Client session and ride-draft incident fixes | Durable exact Client sessions survive Redis cache loss; refresh contention no longer clears tokens; the last authenticated Client profile is cached; and back/Cancel/no-driver exits clear only the next-ride draft. Backend focused **188/188**, all mobile suites and all analyzers pass. Physical staging proof remains open. |
| 2026-07-24 | Added exact-role referrals to this update | Backend, Mobile and Admin referral changes are merged to staging; the staging migration is applied with all invariants zero. Runtime remains disabled until exact-role canary and rollback proof. |
| 2026-07-24 | Reconciled exact combined release heads | Backend main is `11021d3`, Mobile staging is `4daa9fdf`, Admin staging is `71fb1597`; production Backend still serves older `d918243`. Current automated gates pass. |
| 2026-07-24 | Isolated the staging cash-remittance blocker | Direct selection of PostgreSQL's `void` advisory-lock result caused Prisma settlement failure. Backend PR `#122` returns a typed integer lock result; full API tests/build and live local SQL-shape proof pass. Staging deployment and payment canary remain open. |
| 2026-07-25 | Added rider-visible matching progress and safe pre-accept cancellation | Client now shows server-driven search/receipt/next-driver/radius states and a receipt-authoritative countdown; cancellation is confirmation-gated and race-safe; Provider request UI closes immediately and receives in-app plus system notices. Backend **211/211 suites and 4,117/4,117 tests**, Client **99/99**, Provider **176/176**, both fatal analyzers and the API build pass. Owner decided no provider re-consent is required; accepted Terms `1.4.1` remain unmodified. Staging migration/device proof remains open. |
| 2026-07-26 | Added Client homepage usability to this update | Implemented a human-readable current-location label with bounded reverse-geocoding retry, a one-shot session-cached Recent Activity view without 15-second polling, the latest three combined rides/jobs with existing detail/Activity navigation, hidden empty offers, an activity empty state and responsive compact service cards. The cache is invalidated after create/status/cancel changes, reconnect and logout. Focused verification is **9/9**, the full Client suite is **111/111**, the fatal analyzer is clean and `git diff --check` passes. Offers API and Admin-to-Mobile offer population are deferred to the next update. |
