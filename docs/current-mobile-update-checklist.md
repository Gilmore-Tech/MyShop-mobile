# Current Mobile Update Checklist

Status captured: **2026-08-01 GMT**

## 2026-07-31 18:56 UTC credit-preservation and exact resume checkpoint

- [x] Overall verified goal progress at this pause is **78% complete / 22%
      remaining**. This percentage counts released evidence and independently
      verified local slices; it does not count unfinished source, an unrun
      harness, a store upload, or an intended change as complete.
- [x] All implementation/review agents were stopped at the owner's request to
      conserve credits. No change from this resumed hardening pass was pushed,
      merged, deployed, migrated or applied to an environment.
- [x] Mobile Driver online/offline/location authority foundation is safely
      committed locally as `7105dd4b0e913e6ad902ee25373f336cc72aa467`.
      The follow-on request-ingress worktree is
      `/Users/ayiks/Desktop/ayiks/gilmore/worktrees/mobile/myshop-mobile-driver-ride-offer-authority-gate-20260731`
      on `fix/driver-ride-offer-authority-gate-20260731`. It contains the
      integrated authoritative-deadline commit `6668e07` and exactly two
      unfinished, uncommitted paths:
      `apps/provider/lib/src/core/services/ride_offer_receipt_service.dart`
      and the new
      `apps/provider/lib/src/core/providers/driver_ride_offer_authority_provider.dart`.
      The partial source passes `git diff --check`, but it is not wired through
      all ingress/action surfaces and has not been tested; do not build, push or
      merge it as-is.
- [x] Backend dispatch/availability/logout/token authority is safely committed
      locally at combined head `0eb18fdbb4f208168d76c9754623ad2810218f8c`
      in
      `/Users/ayiks/Desktop/ayiks/gilmore/worktrees/backend/myshop-backend-dispatch-contract-20260731`.
      Exact displaced-session cleanup is separately committed as
      `59615bf502652df91de6ad01403c856f6a4115fb`; independent review accepted it
      with no introduced critical/high blocker.
- [x] The critical login winner/CAS draft remains deliberately uncommitted in
      exactly
      `apps/api/src/modules/auth/auth.service.ts` and
      `apps/api/src/modules/auth/role-refresh-lineage.service.ts` inside
      `/Users/ayiks/Desktop/ayiks/gilmore/worktrees/backend/myshop-backend-session-establishment-race-20260731`.
      Do not commit or continue it without explicit owner approval after
      restating that a defective change could disrupt all logins. Do not clean
      or overwrite the draft either.
- [x] The successor-safe markerless Redis-presence follow-up has a clean,
      no-edit worktree at
      `/Users/ayiks/Desktop/ayiks/gilmore/worktrees/backend/myshop-backend-markerless-presence-cleanup-20260731`,
      branch `fix/markerless-provider-presence-cleanup-20260731`, based on
      `59615bf`. The finding is medium operational/durability severity: it
      cannot pass canonical PostGIS matching after the provider is durably
      Offline, but stale Redis GEO members can accumulate and must be fixed
      before claiming 100k-DAU readiness.
- [ ] Exact resume order: (1) finish the central typed Mobile offer-authority
      store/gate and tests; (2) wire socket, FCM, durable receipt, Flutter/native
      tap/action, Android overlay, iOS Live Activity, canonical recovery,
      accept/decline/expiry and exact cleanup; (3) run full Provider/API-client
      gates and independent review; (4) obtain explicit approval before the
      critical login CAS rewrite; (5) finish markerless cleanup and remaining
      legacy-session races; (6) run the real PostgreSQL/Redis concurrency,
      Redis failover, staging canary, fault and load gates.
- [ ] Any newly reported production bug must first be recorded under the store
      monitoring section with app/platform/build, time, user-visible symptom,
      reproduction, logs/request reference and severity. Isolate an emergency
      fix from these unfinished branches unless evidence proves the bug belongs
      to the same authority contract.

## 2026-07-31 store release and monitoring checkpoint

### Referral signup incident audit

- [x] Source trace confirms that an omitted/blank referral code does not block
      signup: both Mobile apps omit it from `RegisterRequest`, and Backend
      skips referral validation/linkage. If a code is supplied, Backend calls
      `validateRegistrationCode()` before creating OTP state or attempting
      delivery.
- [x] A supplied code currently fails registration with
      `ROLE_ACCOUNT_REFERRALS_SUSPENDED` whenever either
      `FF_ROLE_ACCOUNT_REFERRALS` or the database
      `role_account_referrals_enabled` switch is not exactly true. This occurs
      before OTP and explains why only some signup attempts can fail while
      otherwise identical attempts without a code succeed.
- [x] Mobile referral signup recovery is committed locally in isolated branch
      `fix/referral-signup-reliability-20260731` at `901fa2f` and `0fe9850`.
      Client and Provider now map role-referral and platform-code failures to
      safe copy, preserve the entered optional code, and offer an explicit
      remove-code-and-single-retry path; blank codes remain omitted. Fresh
      focused evidence: Client **3/3**, Provider **9/9**, API client **3/3**,
      targeted analyzers and diff check pass. Independent review found no
      high/medium blocker. Nothing is pushed or deployed.
- [x] Automatic exact-role code creation is database-owned: each new
      client/driver/artisan profile trigger creates one `role_reward_accounts`
      row; `generate_role_referral_code()` serializes allocation with a
      transaction advisory lock, checks both new and legacy namespaces, and a
      unique index is the final collision fence. Focused Backend migration,
      referral and registration DTO suites pass **25/25**; Provider referral
      validation passes **2/2**; Client deep-link/signup routing passes **4/4**.
      No real-database collision/load run was performed in this checkpoint.
- [x] Current Admin supports list, metrics, exact-role funnel, manual reward
      award/void and reward configuration. It has no API, permission or UI for
      creating, assigning, replacing or aliasing referral codes. Existing
      `manage_referrals` is not Super-Admin-only.
- [x] The owner approved a distinct **platform referral code** model on
      2026-07-31. It is not an alias for any client/driver/artisan role and
      creates **no digital or individual referral reward**; any campaign reward
      is physical and outside MyShop's payment/loyalty ledgers. It only tallies
      signup attribution on Admin. Approved V1 uses exact format
      `MYSHOP-XXXXXX`, a required campaign name, one attribution per exact role
      registration, aggregate total/client/driver/artisan/daily reporting
      without personal drilldown, immutable deactivate-only codes, no expiry
      or usage cap, and an independent default-off rollout switch. The same
      private phone identity may be attributed separately when it genuinely
      creates Client, Driver and Artisan roles. Deactivation blocks new
      registration requests while preserving a code already accepted into
      that five-minute OTP. Only literal global `super_admin` may create or
      deactivate; `view_referrals` may view aggregate results. Existing
      generated exact-role codes and reward behavior remain unchanged.
- [x] Admin platform-code V1 is committed locally at `8d9a2e9` on
      `feat/platform-attribution-codes-admin-20260731`. It adds a separately
      loaded platform-promo tab, exact-Super-Admin create/deactivate actions,
      permanent immutable lifecycle and aggregate total/by-role/daily counts
      without PII, drilldown or digital-reward actions. Contract tests pass
      **5/5**, safe-error tests **12/12**, typecheck/lint/production build/diff
      checks pass, and independent review found no high/medium blocker. It is
      not pushed or deployed.
- [x] Backend platform-code V1 is committed locally as stack `6612ce1`,
      `a852798`, `b0a8606`, with final branch
      `fix/platform-code-legacy-collision-20260801`. It adds separate immutable
      attribution tables; independent default-off environment/database gates;
      OTP-bound snapshots; exact-role, reviewer and mutual-exclusion fences;
      globally serialized platform, role and legacy code namespaces; audited
      exact-Super-Admin create/deactivate endpoints; and aggregate-only Admin
      reads. Reciprocal database triggers close both platform/role attribution
      races and platform/legacy-code races without allowing a later trigger to
      mutate reviewer reward state. Final focused Backend suites pass
      **262/262**, the changed migration/service suites pass **18/18**, the
      disposable harness parses cleanly and diff checks pass. It is not pushed,
      deployed or applied to a database. Final independent review found no
      high/medium blocker and marked the stack ready for staged testing.
- [ ] Before enabling platform attribution, run migration
      `20260731180000_platform_signup_attribution` on a disposable PostgreSQL
      database and execute
      `pnpm --filter @myshop/database test:platform-attribution:integration`.
      The harness covers both winners of role/platform and legacy/platform
      races plus NULL, normalization, collision and reviewer-fence sequences,
      but is unrun because local Docker/PostgreSQL is off. Then apply only to
      staging, set `FF_PLATFORM_SIGNUP_ATTRIBUTION=true` and audited DB key
      `platform_signup_attribution_enabled=true`, and verify: no-code signup;
      existing individual role-code signup/reward; platform-code signup for
      Client, Driver and Artisan exact roles; aggregate-only Admin counts; zero
      loyalty/payment ledger writes; inactive-code recovery; an OTP accepted
      immediately before deactivation; exact-Super-Admin mutation denial; and
      permanent deactivation. Keep both production switches false until this
      evidence is recorded.
- [ ] Production referral-switch state was not proved in this audit: the public
      `/v1/config` request is correctly authentication-protected. Verify both
      the Render environment flag and audited database boolean without exposing
      credentials before reproducing the incident.

- [x] The owner reports that Client Android, Client iOS, Provider Android and
      Provider iOS `1.4.1+26` were released to their stores. Store feedback and
      newly reported production defects must be added to this checklist as
      they arrive; they must not be mixed into an unrelated deferred branch.
- [x] A public Ghana storefront check observed marketing version `1.4.1` on
      both Google Play package IDs on 2026-07-31. Public Play pages do not
      expose `versionCode`, staged-rollout percentage or private-console build
      evidence, so this observation alone does not prove build `26` or a 100%
      rollout.
- [ ] Apple's public Ghana lookup still exposed Client `1.3.9` and Provider
      `1.4.0` on a fresh bundle-ID lookup at `2026-07-31 18:22 UTC`, despite
      the owner-confirmed store release. Confirm App Store Connect availability
      and wait until both public
      listings expose `1.4.1`; do not treat upload, processing, approval and
      public propagation as the same state.
- [ ] The currently public iOS descriptions still contain unproved/deferred
      claims, including instant/same-day payout, a 24-hour verification SLA,
      verified clients, trip recording, full Twi and loyalty promises. Confirm
      the pending `1.4.1` metadata against
      `docs/store-listing-v1.4.1-corrections.md` before it becomes public, and
      verify the Android listings use semantically equivalent safe copy.
- [ ] Install the store-served Client and Provider builds on physical Android
      and iPhone devices and record their displayed build/version before
      running the smoke matrix below.
- [ ] Record a 24-hour, 48-hour and 72-hour post-release observation for
      crashes, unexpected logout/session recovery, OTP delivery, Client
      booking, Provider online/location, request delivery, calls, payments and
      refunds, including rollback thresholds and the operator responsible.
- [x] Completed a source-backed post-release observability inventory. The
      System Audit summary, durable ride/offer/payment/refund records, Admin
      reports and protected Prometheus metrics can cover aggregate operational
      checks without exposing customer records.
- [ ] Client and Provider currently initialize no Crashlytics/Sentry-equivalent
      crash service. Mobile lifecycle telemetry is not crash-free-user, ANR,
      native-crash, startup-crash or symbolication evidence; select and prove a
      privacy-reviewed crash-monitoring path before claiming crash coverage.
- [ ] For the already-released build, record the 24/48/72-hour crash and ANR
      baseline from Google Play Android Vitals and App Store Connect crash
      diagnostics for each app while the in-app crash-monitoring decision is
      still open.
- [ ] `/v1/metrics` is bearer-protected and defaults disabled; verify its actual
      production configuration and external scraper/dashboards without printing
      credentials. Health plus the Admin audit vault remain the minimum manual
      observation path until this is proved.
- [ ] Approve numeric release abort/page thresholds and a named on-call owner
      for readiness/API 5xx/latency, refresh and OTP failure ratios, booking and
      offer-receipt outcomes, stale provider location, request delivery, call
      connection/drop/TURN errors, and payment/refund failure or backlog age.
- [x] Production `/v1/health/live` and `/v1/health/ready` returned HTTP `200`
      at `2026-07-31 14:51 UTC`; database and Redis reported `ok`, and both
      responses identified deployed commit `6d6bcb466926c828191660601d24aa426edf7df9`.
- [x] A second production `/v1/health` observation at
      `2026-07-31 17:31 UTC` remained HTTP `200` with database and Redis `ok`
      and the same deployed commit.
- [x] A third production Render health observation at
      `2026-07-31 18:18 UTC` remained HTTP `200` with database and Redis `ok`,
      uptime above 7.8 hours and the same deployed commit; release version
      metadata still reported `unknown`.
- [x] A fourth production health observation at `2026-07-31 18:30 UTC`
      remained HTTP `200`; database and Redis were `ok`, uptime exceeded eight
      hours and commit `6d6bcb466926c828191660601d24aa426edf7df9` was
      unchanged. Release version metadata still reported `unknown`.
- [x] A fifth production health observation at `2026-07-31 18:52 UTC`
      remained HTTP `200`; database and Redis were `ok`, uptime exceeded 8.4
      hours and commit `6d6bcb466926c828191660601d24aa426edf7df9` was
      unchanged. Release version metadata still reported `unknown`.
- [ ] Production health still reports release version `unknown`. Set and
      verify non-secret Backend `APP_VERSION` release metadata separately;
      this does not invalidate the exact deployed-commit evidence above.
- [ ] Keep the controlled refresh-lineage authority cutover and all preserved
      deferred branches outside emergency store-fix work until their own
      production gates pass.

## 2026-07-31 resumed goal: bounded hardening queue

- [x] Reconciled the preserved Mobile, Backend and Admin work. Large OTP,
      release-integration and Mobile worktrees remain preservation sources,
      not merge candidates; each change must be extracted onto current
      `staging` as a small independently tested PR.
- [x] Preserved the primary Mobile workspace without deleting or rebasing it:
      local-only branch `wip/goal-mobile-preservation-20260731`, commit
      `37d8ef905266dd16e56448c73956152a8f788da4`, contains all 87 changed paths.
      Of those, 77 contain work absent from both current remote branches and 48
      overlap paths changed upstream. Do not push or merge this raw snapshot;
      its old base predates the credential-removal merge. Extract reviewed
      slices onto current `staging` instead.
- [ ] Backend support-attachment URL redaction is isolated from current
      Backend `staging` in exactly two tracked files. It preserves the stable
      `UNCONFIRMED_ATTACHMENT` code/message and replaces returned URLs with a
      non-sensitive invalid-entry count. Evidence currently passes the focused
      **4/4** suite, API typecheck, five-package API build, Prettier,
      `git diff --check`, and the full **222/222 suites / 4,429/4,429 tests**.
      The focused test, typecheck, full suite and forced uncached **5/5** build
      were rerun successfully with the repository-pinned Node **22.23.0**.
      Local commit: `1d695b6963aef47eb3703e6983a55c9b8a86a130`;
      it has not been pushed or merged.
- [ ] Backend Prisma error-metadata redaction is isolated from current
      Backend `staging` in exactly two tracked files. `P2002` retains HTTP
      `409`, `UNIQUE_CONSTRAINT` and its stable message; `P2003` retains HTTP
      `400`, `FOREIGN_KEY_VIOLATION` and its stable message, while Prisma
      constraint/model/field metadata is omitted. Evidence passes the focused
      **5/5** suite, API typecheck, five-package API build, Prettier,
      `git diff --check`, and the full **222/222 suites / 4,431/4,431 tests**.
      The focused test, typecheck, full suite and forced uncached **5/5** build
      were rerun successfully with Node **22.23.0**. It remains a separate
      unpushed slice at local commit
      `7f07061e2d1728f28b8044fd5b62d3178d520bac`.
- [ ] Admin support-contact/log-privacy hardening is isolated from current
      Admin `staging` in exactly seven scoped files; `.claude` is unchanged.
      It preserves direct-recipient/audience SMS behavior and current safe API
      mappings, installs the approved support email/phone defaults, and fixes
      generic diagnostics to a constant error class. Evidence passes log
      privacy **3/3**, support contacts **1/1**, API error containment
      **11/11**, clawback groups **2/2**, lint with zero errors, the production
      build and `git diff --check`. Stored `platform_config` values may
      override the defaults and still require separate environment checks.
      Local commit: `c1ed7deb39b91aa7f1e25dd04a61a2ede23b1dd9`;
      it has not been pushed or merged.
- [ ] Follow with the Admin audit-vault/webhook failure-containment slice,
      corrected against the current exact-role SMS contract.
- [x] Current Backend already contains Redis-global HTTP admission,
      Redis-backed WebSocket leases, OTP Redis-TIME budgets/cooldowns/circuit
      containment, and a production `noeviction` startup/readiness gate. Do
      not duplicate these capabilities; their configured capacity and real
      infrastructure evidence remain separate open gates.
- [x] Audited the preserved scale branch against current `staging`: it is 22
      commits ahead but 35 behind, spans 264 files and 63 migrations, and has
      stale 45-second ride-offer assumptions. It is forbidden as a wholesale
      merge or cherry-pick source.
- [ ] Scale slice 1 is isolated from current Backend `staging`: the unused
      module-level Prisma singleton is removed, leaving one Nest-owned pool per
      API replica, with fixed-label active/idle/total/waiting/capacity gauges
      and bounded pool configuration. Repository-wide consumer proof found no
      caller of the removed singleton. Exact Node **22.23.0** evidence passes
      focused **17/17**, full **223/223 suites / 4,435/4,435 tests**, API
      typecheck, forced uncached **5/5** build, formatting and diff checks. No
      migration is added. Before staging, verify actual pool min/max/timeouts,
      replica count and Neon connection capacity; metrics also remain invisible
      until the protected metrics pipeline is enabled and scraped. Local
      commit: `9f80465fb3317438bf6e99890a5b22add8662054`;
      it has not been pushed or merged.
- [ ] Scale slice 2 audit is complete on Backend staging `a8a1e268…`.
      Production `noeviction`, global admission and WebSocket leases already
      exist, but the shared command client still permits offline queue/replay
      with no command/socket deadline, Socket.IO pub/sub uses unlimited retries
      and is invisible to readiness, and several Provider HTTP/socket auth paths
      can misclassify Redis infrastructure failure as 401/takeover. Implement
      bounded no-replay command/pub-sub clients, runtime readiness and truthful
      retryable authority-unavailable errors without clearing login tokens.
      No migration, Redis flush or prefix change is required. Owner approval is
      pending for the recommended 10-second startup, 2-second command,
      3-second socket-stall and 2-second shutdown limits, and for disconnecting
      existing sockets to force safe reconnect rather than allowing local-only
      split-brain operation during pub/sub loss.
- [ ] Scale slice 3: extract the first multi-replica scheduler-fencing cohort
      for ride-stage, disconnect-grace and location-degradation work, with
      durable row claims and reviewed concurrent indexes. Depends on slice 2.
- [ ] Scale slice 4: add owner-gated alert rules for replica/build health,
      5xx/p99, database/Redis pressure, stalled workers, audit loss, TURN and
      event-loop lag. Numeric thresholds require explicit owner approval.
- [ ] Scale slice 5: port only isolated topology/backlog/load evidence tooling
      to the current 30-second request contract. Existing presets top out at
      500 client VUs and a 2x pilot and must not be represented as 100k-DAU
      proof; live-provider bulk OTP remains excluded.

## 2026-07-31 dispatch-authority hardening checkpoint

- [x] Provider Mobile no longer manufactures a ride-offer deadline from
      `createdAt`, `acceptanceWindowSeconds`, `expiresInSeconds` or a local
      30-second fallback. It requires the Backend's absolute offer deadline,
      performs bounded pending-offer reconciliation when that deadline is
      missing, and otherwise clears the request without sending a punitive
      decline. The isolated local commit
      `a5d806689059c377fc1988db5263973754ce2be0` passes the complete Provider
      **292/292** test suite, targeted analysis and `git diff --check`; it has
      not been pushed or merged.
- [ ] Backend immutable Driver offer authority is isolated on current
      `staging` and adds the public role-account/online-session/selected-vehicle
      tuple without exposing the private auth SID. Independent review found and
      the amended candidate corrected two blockers: pre-deploy offers use only
      a total-absence legacy path with no tuple synthesis/rebinding, and receipt
      activation serializes `user -> driver -> offer` before revalidation and
      publishes only after commit. Local commit
      `cce4bda17a63b51494137b43fb874f9e450dbe04` passes focused **119/119**,
      full API **222/222 suites / 4,444/4,444 tests**, typecheck, build, lint
      with zero new errors and `git diff --check`. A second independent review
      found no remaining high/medium source blocker and confirmed the legacy,
      A-to-B vehicle, lock-order, post-commit publication and privacy fences.
      The race has deterministic SQL/lock assertions but no real PostgreSQL
      concurrency test, so staging must exercise two-replica receipt versus
      Offline/re-online/vehicle invalidation and duplicate-receipt races before
      production.
- [ ] Backend ordinary availability teardown is now fenced by the authenticated
      SID and, for updated clients, the exact `expectedOnlineSessionId` captured
      when the provider went Online. Driver and Artisan Offline plus
      `/location/unavailable` lock the user and exact role row, preserve active
      work, fail stale epochs with `AVAILABILITY_SESSION_CHANGED`, clear the
      complete epoch only after a successful CAS, and re-lock before Redis
      presence cleanup so a reopened epoch is not erased. Forced
      admin/auth/security/liveness teardown remains intentionally separate.
      Independent review found and the amended candidate corrected one
      reliability gap in the legacy GPS Offline endpoints: a post-commit Redis
      cleanup exception is now best effort and cannot make authoritative
      Offline appear failed, while a reopened epoch still returns `409`.
      Amended local commit
      `4e353a93add21d9661940582a7f57cc27201ffbd` passes full API
      **224/224 suites / 4,478/4,478 tests**, focused **192/192**, typecheck,
      build, lint with zero errors and `git diff --check`; it is not pushed or
      deployed. A real multi-connection PostgreSQL interleaving test remains
      required. Correctness-preserving cleanup currently awaits Redis while
      holding provider locks, so bounded Redis command deadlines are also a
      production prerequisite.
- [x] The immutable offer-authority, availability/location CAS and ordinary
      exact-SID logout slices are now preserved together on current Backend
      `staging` as local commits `cce4bda`, `4e353a9` and `19fa0e3`. The exact
      combined stack additionally contains the PostgreSQL concurrency harness
      and notification-token unregister fence at local head `0eb18fd`. Its
      complete API gate passes **226/226 suites / 4,495/4,495 tests**, API and
      E2E typechecks, build, lint with zero errors and `git diff --check`.
      Nothing is pushed, merged or deployed.
- [ ] A real multi-connection PostgreSQL dispatch race harness is implemented,
      independently reviewed and preserved at source commit `d61051c` (combined
      as `ac49d16`). It covers receipt versus Offline/re-online, stale offer
      versus a replacement session, vehicle A-to-B, two independent duplicate
      receipts, stale cleanup versus a reopened epoch, and stale
      location-unavailable refusal using lock barriers rather than sleeps.
      Static evidence passes **173/173** focused tests, API/E2E typechecks,
      build, lint, formatting and runner safety guards. Runtime remains open
      because Docker Engine is not running; execute only against the runner's
      disposable loopback `myshop_test` database under pinned Node 22.
- [x] Mobile's exact Driver authority foundation is implemented and preserved
      locally at commit
      `7105dd4b0e913e6ad902ee25373f336cc72aa467` in the
      isolated `fix/driver-dispatch-authority-foundation-20260731` worktree.
      The correction pass now uses an exact auth subject/role/account/SID
      identity, SHA-256 durable authority and SID-scoped Online intent; verifies
      direct Online with an authoritative read-back before installation;
      compensates a failed installation with the captured session; gates idle
      reconciliation on exact durable intent; preserves the existing location
      epoch for a valid active ride; rejects stale role/account/SID work; and
      sends `expectedOnlineSessionId` for ordinary Offline. The final correction
      also serializes explicit Driver Online/Offline intent, makes reconciliation
      reruns lossless, fences overlapping location-loss reports and oversized
      sequences, force-clears busy logout state, and validates exact Offline
      acknowledgements for Driver and Artisan compensation. Final evidence
      passes Provider **367/367**, API-client **297/297**, critical authority
      **102/102**, both analyzers, formatting and `git diff --check`. A fresh
      independent final review found no remaining blocker. This commit is not
      pushed or deployed and cannot ship without the matching Backend CAS plus
      complete request-ingress/action gates below.
- [ ] The corrected foundation and authoritative-deadline slice are combined
      at local commit `6668e07`. Central typed parsing and SID-scoped receipt
      persistence were started but paused uncommitted in the two exact files
      recorded in the credit-preservation checkpoint. Still gate every Driver
      request ingress and action: socket, foreground/background FCM, pending
      recovery, notification tap/action, Android overlay/native queue, iOS
      queued action/Live Activity, accept/decline/expiry and terminal cleanup.
      Partial, malformed and unsupported tuples fail closed; a wholly absent
      legacy tuple is default-off, must have a hard reviewed sunset, and must
      never be synthesized or rebound by Mobile. This slice is incomplete and
      untested at the pause.
- [x] Completed an exact read-only inventory of Driver request surfaces. The
      authority foundation itself is identity-scoped, but current socket,
      foreground/background FCM, durable receipt, Flutter/native notification,
      Android overlay/queued action, iOS action/Live Activity, pending recovery,
      canonical GET/router restoration, accept/decline and cleanup paths do not
      consume the full tuple. Several persist only ride/offer/deadline under
      global keys, use ride-ID aliases, or survive SID/vehicle/logout changes.
      Treat every listed ingress/action gap as critical. Integrate one typed
      `{authorityVersion, providerId, onlineSessionId, selectedVehicleId,
      rideId, offerId, absoluteDeadline}` contract, validate before persistence
      or receipt and after every await, use exact compare-and-remove cleanup,
      and clear every Dart/native surface on Offline/logout/SID/account/vehicle
      change. Plain `GET /rides/:id` is not offer-action authority.
- [x] Completed a read-only audit of current Artisan dispatch. Current source
      invites up to three artisans in parallel and uses a five-minute bid
      window anchored to job creation; it does not implement ride-style
      sequential 30/45-second delivery. Redis is still actionable invitation
      authority, bid submission is not bound to the receiving SID/session, and
      no durable `ArtisanOffer` ledger exists.
- [ ] Keep Artisan V2 dormant until the owner explicitly decides its parallel
      versus sequential behavior, receipt/no-receipt window and replacement,
      exact bid-capacity semantics, pending-offer capacity reservation,
      post-window selection deadline, directed-quote behavior, pre-bid data
      exposure and no-capability rollout fallback. Do not infer these rules from
      the approved Driver protocol.
- [x] Completed a provider-epoch mutation audit across availability, location,
      degradation/zombie workers, socket disconnect grace, notification/VoIP/
      Live Activity tokens, logout and session establishment. The new offer
      ledger and teardown CAS are sound within their exact tuples, but the audit
      found release blockers outside those slices: Online activation can publish
      presence and compensate Offline without an exact final epoch; accepted
      location writes can perform provider-only degradation/heartbeat/GEO side
      effects; worker cleanup can erase a reopened epoch; socket disconnect
      grace is not session-bound; and session-establishment cleanup
      can race a newer login. Close these paths with the same immutable tuple
      and add deterministic replacement-session tests before declaring the
      dispatch/session hardening complete.
- [x] Delayed FCM, VoIP, Live Activity device and per-activity unregisters are
      now fenced by the exact authenticated SID at their final transaction
      boundary. Current-session cleanup and token-hash mismatch behavior are
      preserved; session A cannot delete a binding registered by replacement
      session B, and sibling roles remain untouched. Source commit `2d1bedd`
      is combined as `0eb18fd`; the exact combined **226-suite / 4,495-test**
      gate above includes its current-session, A-to-B replacement and controller
      wiring tests. A separate final source review found no high/medium blocker,
      confirmed all four controller SID paths and transaction/row-lock fences,
      and confirmed forced all-session cleanup remains unchanged. The only low
      evidence gap is that the A-to-B token tests mock PostgreSQL lock ordering;
      the real multi-connection harness remains the integration gate. Its final
      independent rerun passes the two relevant suites, **65/65** tests, and
      `git diff --check`. No migration is required and nothing is deployed.
- [ ] Ordinary user logout is now fenced to the exact authenticated SID on an
      isolated backend stack. A delayed logout from session A is an idempotent
      no-op after B replaces it; an applied A logout removes only A's durable
      role authority, role tokens, exact-SID sockets and Redis refresh state.
      Post-commit Redis failure remains private best effort and cannot turn the
      durable logout into a misleading 5xx. Forced Admin/security revocation
      remains intentionally all-session. Original local commit
      `4d6d11dff8798400d620ab3f401d713d088d5ede` passed full API
      **225/225 suites / 4,481/4,481 tests**, typecheck, build, lint with zero
      errors and `git diff --check`; it has been amended for strict-PNPM runtime
      portability and combined locally as `19fa0e3` after the availability CAS.
      Nothing is pushed or
      deployed. A cross-device login can still be temporarily blocked if Redis
      failed after logout and retained A until its stale-session window; track
      this under Redis recovery rather than weakening the exact-SID CAS.
- [ ] A fresh session-establishment concurrency audit found two independent
      critical races after the exact logout/token fixes. Ordinary login cleanup
      was role-wide, so delayed login B could force replacement C Offline,
      disconnect C and delete C's newly registered role tokens. Local Commit A
      `59615bf502652df91de6ad01403c856f6a4115fb` now retires only the captured
      predecessor SID, provider epoch and role tokens transactionally, and its
      exact Redis presence marker cannot erase a replacement epoch. Focused
      evidence passes **419/419** plus API typecheck. Independent exact-tree
      review accepted Commit A with no introduced critical/high defect after
      rerunning five focused suites (**378/378**), API typecheck and diff
      checks. It also found a medium scale gap: a markerless pre-deploy Online
      provider becomes durably Offline and cannot pass canonical PostGIS
      matching, but its Redis GEO member does not expire because the zombie
      sweep scans DB-Online rows only. Add successor-safe absent-marker cleanup
      before claiming 100k-DAU readiness. Separately,
      session creation writes Redis before an unconditional durable activation;
      the interleaving `B Redis -> C Redis -> C DB -> B DB` can split database
      and Redis authority. Isolate exact predecessor cleanup and durable
      activation CAS as separate commits, retain broad Admin/security revocation,
      and prove B/C interleavings plus same-platform token replacement before
      accepting the session-establishment path. The full Commit B CAS/winner
      reconciliation rewrite is paused with an uncommitted two-file draft
      because the safety reviewer requires direct owner approval for this
      critical sign-in-path change. No migration is expected; a mixed-version
      rollout remains forbidden.
- [ ] Follow the two critical login fixes with the audited legacy-session
      cohort: remove pre-authorization role-wide cleanup in enforced and shadow
      refresh, exact-SID fence post-refresh socket sweeps, stop lazy session
      ownership mutation inside `JwtAuthGuard`, validate durable SID/generation
      for WebSockets, and bind any OTP takeover approval to the exact displaced
      SID/generation. These are high-severity session-integrity gates and are not
      satisfied by the ordinary logout or token-unregister commits.
## Authoritative 2026-08-01 platform-attribution update

This block supersedes older release-status wording for the current update. The
older sections remain implementation evidence and historical context.

- [x] The owner reports that Client Android, Client iOS, Provider Android and
      Provider iOS `1.4.1+26` were released. Build `26` is permanently occupied.
- [x] Platform promotional codes are attribution-only, use the approved
      `MYSHOP-XXXXXX` format, create no individual digital reward, and tally
      aggregate Client, Driver and Artisan signups in Admin.
- [x] Backend staging migration `20260731180000_platform_signup_attribution`
      was applied, both staging gates were enabled, and an end-to-end signup
      with a platform code succeeded.
- [x] Mobile Client/Provider signup preserves optional-code failures, maps the
      platform-code errors to safe copy, and permits an explicit code removal
      and one retry without attribution.
- [x] The Mobile production branch is cut from exact `origin/main`; its only
      runtime delta is the two tested referral-signup commits. Release metadata,
      mechanical formatting and this checklist are included, while the
      unrelated deferred staging checklist snapshot is excluded.
- [ ] Backend release-gate repair must pass exact-SHA CI before promotion. The
      already-applied attribution SQL remains immutable and checksum-frozen;
      the fresh-database legacy config precondition is a separate guarded
      migration.
- [ ] Admin and Backend must merge through reviewed production PRs. Production
      launches dark: migration first, environment and DB attribution gates
      false, then Admin deploy and a controlled canary before activation.
- [ ] The next store candidate is marketing version `1.4.2`. The release-tool
      build floor is `26`, so `27` is the minimum; before building, confirm the
      current private App Store Connect and Play Console maxima for all four
      targets and use one common number greater than every maximum.
- [ ] Build Client/Provider AAB and IPA only from the final clean Mobile `main`
      merge SHA. Retain artifacts only under the repository `build/releases/`
      folder, verify signing/version/source/production API and SHA-256 hashes,
      then install and smoke-test before store submission.
- [ ] Production codes are created separately in production while attribution
      remains paused. Staging code rows, IDs and tallies are never copied.
- [ ] Offer API/Admin publishing, digital promo rewards, automated batch
      payouts, SmileKYC and wider deferred/100k-DAU work remain excluded.

## 2026-07-31 repository credential containment

- [x] A tracked repository-tool configuration in Mobile and Admin was found to
      contain a GitHub personal access token. The secret value is deliberately
      omitted from this record and must be treated as compromised.
- [x] Focused one-file removal branches contain no Mobile/Admin runtime,
      database, API or signed-artifact change: Mobile PR `#118` targets
      `staging`; Admin PR `#30` targets `staging`.
- [x] The owner confirmed the exposed credential was revoked and replaced the
      developer automation credential through the host/keychain only. Removing
      it from Git does not revoke it or erase repository history.
- [x] Focused removal PRs `#118`/`#30` merged through Mobile/Admin `staging`;
      focused PRs `#119`/`#31` then promoted only the same one-file fixes to
      `main`. Path-only current-tree scans on all four protected refs returned
      no token-pattern match at Mobile main `1f30c9f…`, Mobile staging
      `9931c5f…`, Admin main `ad28ab9…` and Admin staging `798c94e…`.
      These repository-tool-only merges do not alter or require rebuilding the
      four signed `1.4.1+26` artifacts.
- [ ] Coordinate a decision with both developers on whether revoked historical
      secret material warrants repository-history rewriting; do not rewrite
      shared history during the active release.
- [ ] GitHub Actions did not execute Mobile PR `#117`, `#118` or `#119`:
      GitHub marked their `analyze-and-test` jobs failed before assigning a
      runner because of
      an account payment/spending-limit condition. This is infrastructure
      evidence, not a passing or failing source test. Keep the recorded local
      exact-commit gates authoritative until Actions is restored or the owner
      explicitly retains the documented manual release workflow.

## Authoritative 2026-07-31 main release cut

This block supersedes older status lines for the immediate store update. The
older sections remain the implementation and test ledger; they must not be
used to add unreviewed work to this cut.

### Frozen candidate

- [x] The baseline immediately before this cut was `1.4.1+25` on Client
      Android, Client iOS, Provider Android and Provider iOS; the released
      candidate tracked at the top of this file is `1.4.1+26`.
- [x] Mobile runtime candidate is exact tested staging commit
      `4fae1fe30a054e168134d9ccc83d3c9960d6169a`.
- [x] Backend dependency candidate is exact tested staging commit
      `a8a1e268e1923dcac0c02ad749bd43c5d0847f4d`; its only change above
      runtime candidate `6aa1cc2…` is the corrected referral DTO test.
- [x] Admin `main` and `staging` have identical content; no Admin release is
      included.
- [x] The owner reports the frozen Mobile and Backend candidate behavior was
      tested on staging and authorizes preparation of the store update.
- [x] Exact Mobile staging commit `4fae1fe…`, tree `4c8d008c…`, passed all
      three release-contract suites, **800/800** tests across six packages,
      all seven package analyzers with zero issues, `git diff --check`, and
      finished with a clean detached worktree.
- [x] Exact Backend staging tree `d1202dce…` passed **222/222 suites and
      4,429/4,429 tests**, API typecheck, the five-task production API build,
      refresh-lineage verifier **5/5**, focused lineage **69/69**, and
      `git diff --check`.
- [x] The dirty primary workspaces and every uncommitted/deferred branch are
      excluded. Only committed staging ancestry may enter `main`.

### Post-freeze signed candidate checkpoint

- [x] Provider iOS native dependency lock correction passed through staging
      PR `#115` and main PR `#116`. Final release source is exact clean
      `origin/main` commit
      `cd24d241c43764f3d3b7f764ba6f68cc09d79985`, tree
      `6f5992019c4072f40ce2e530f3189b057a4e9f59`.
- [x] The owner confirmed the highest private build number was `25` for Client
      Android, Client iOS, Provider Android and Provider iOS. The common
      signed candidate is marketing version `1.4.1`, build `26`.
- [x] Client AAB, Client IPA, Provider AAB and Provider IPA were built with
      `tool/build.sh` from the one exact clean source commit above. All four
      independently passed `tool/verify-release-artifact.sh`, including
      production API/no-staging checks, embedded source provenance, bundle
      identity, version/build and the reviewed Android/Apple signing identity.
- [x] The four final artifacts and user-facing notes are retained only under
      `build/releases/1.4.1+26/`; `SHA256SUMS` verifies all four:
      Client AAB `2c035171…`, Provider AAB `c36af4ce…`, Client IPA
      `d320b839…`, Provider IPA `d2489dba…`.
- [ ] The owner subsequently released the four store candidates. Retain this
      as an open evidence gap until the store-served artifacts are installed
      and physically smoked and the submission/canary outcomes are recorded;
      artifact verification alone was not physical-device proof.

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

- [x] Create and review Backend `staging` to `main` PR `#136`.
- [x] Apply
      `20260727000000_durable_role_refresh_lineage` to the production database.
- [x] Post-migration production verification reported **213 migrations** and
      `Database schema is up to date`; the approved geofence fingerprint
      remained `9faa785a0e5146c6e50d4e7b64b98a5e`.
- [ ] Replace the Backend fleet with **zero mixed-version serving**, following
      `docs/refresh-lineage-controlled-cutover.md`; verify the two refresh
      authority flags, exact deployed commit, health and recovery telemetry.
      The latest recorded production state has both
      `refresh_lineage_authority_enabled=false` and
      `refresh_lineage_cutover_quiesced=false`, so schema deployment alone does
      not close this gate.
- [x] Create and review Mobile release PR `#114` to `main`; its runtime tree
      equals frozen staging commit `4fae1fe…` apart from this release-control
      record. Provider lock correction PRs `#115`/`#116` produced the final
      signed source `cd24d241…` recorded above.
- [x] Read the highest private build number for all four app/store targets:
      the owner confirmed `25` for each target before building.
- [x] Use marketing version `1.4.1` and common build `26`, greater than the
      released/local floor and every owner-confirmed private-console maximum.
- [x] Build Client AAB, Client IPA, Provider AAB and Provider IPA from one
      clean exact `origin/main` SHA using `tool/build.sh`.
- [x] Verify bundle IDs, version/build, signing identities, production API,
      embedded source SHA and absence of staging endpoints in all artifacts;
      retain SHA-256 hashes in the project release folder.
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
