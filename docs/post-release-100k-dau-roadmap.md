# MyShop post-release and 100k-DAU roadmap

Status captured: **2026-07-22 GMT**

This document restarts the scale programme from the observed released state. It
does not treat a daily-active-user target as a concurrency claim, and it does
not activate deferred product features. Every workload value and business rule
remains subject to owner approval before it becomes a test or production limit.

## 1. Observed release baseline

| Surface | Authoritative observation | Consequence |
| --- | --- | --- |
| Production API | `/v1/health` and `/v1/health/ready` return HTTP 200 with PostgreSQL and Redis `ok`; deployed commit is backend `d918243cd7c6bda778fa54dec6ac0fdbe8140595`. | Production does **not** yet contain the follow-up maintenance/audit hardening merged to backend staging. |
| Live service flags | Public server-owned reads return `maintenance_mode=false`, `rides_enabled=true`, and `artisan_jobs_enabled=true`. | Rides and ordinary artisan jobs are open; changes to these flags remain controlled operational actions. |
| OTP policy | The production API advertises SMS primary with WhatsApp fallback. | Delivery, callback, cost, provider-circuit and handset evidence still require monitoring; the channel advertisement alone is not delivery proof. |
| Admin | `https://admin.myshop.gilmoretechnologiesgh.com/login` is live on Vercel deployment `dpl_6rNMmNbA97TPyvU4uURTg5tPLXMz`. Admin main is `30f2ed04cc03a3fa5cf20e4075368b9d67c4a7f3`. | The audit-vault UI is deployed, but authenticated Super Admin acceptance and Product Owner 403 evidence are still required. |
| Staging API | `/v1/health/ready` is healthy at `myshop-api-test.onrender.com`, but it serves backend `fed0d149…`, ten commits behind repository staging `4e100a9…`. | It is not an exact-current load target and must not produce release/capacity evidence yet. |
| Android client | The official Play listing for `com.gilmoretech.myshopclient` serves marketing version `1.4.1`, updated 21 July 2026. | The public build code is not exposed by the listing and must be read from Play Console before choosing the next code. |
| Android provider | The official Play listing for `com.gilmoretech.myshopprovider` serves marketing version `1.4.1`, updated 21 July 2026. | The public build code is not exposed by the listing and must be read from Play Console before choosing the next code. |
| iOS client | Apple's official lookup still serves `1.3.9`, released 13 July 2026, for bundle `com.gilmoretech.myshopclient`. | The audited update is not publicly available to iOS client users. |
| iOS provider | Apple's official lookup still serves `1.4.0`, released 13 July 2026, for bundle `com.gilmoretech.myshopprovider`. | The audited update is not publicly available to iOS providers. |

Public listing URLs:

- Android client: <https://play.google.com/store/apps/details?id=com.gilmoretech.myshopclient>
- Android provider: <https://play.google.com/store/apps/details?id=com.gilmoretech.myshopprovider>
- iOS client: <https://apps.apple.com/gh/app/myshop-akwaaba/id6773658114>
- iOS provider: <https://apps.apple.com/gh/app/myshop-provider/id6773660049>

## 2. Source reconciliation after outside changes

All three local worktrees were clean before this roadmap branch was created.
No uncommitted outside work was overwritten.

| Repository | Main | Staging | Reconciled state |
| --- | --- | --- | --- |
| Backend | `d918243…` | `4e100a9…` | PR #116 is merged only to staging. It adds exact Admin/deployment access during maintenance, strict legal-hold input, authenticated-role telemetry identity and CSV formula containment. |
| Mobile | `61241f8…` | `bd63907…` | PR #92 is merged only to staging. It restores privacy-safe audit telemetry and binds future artifacts to an exact clean main SHA with build `24` or higher than both store-console maxima. |
| Admin | `30f2ed0…` | `b4bebb5…` | Audit Vault is already merged to main and publicly deployed. The main and staging trees contain the same feature content through different merge commits. |

Current local hardening checkpoint (not pushed or deployed):

| Repository | Clean local branch | Verified milestone | Relationship to reconciled staging |
| --- | --- | --- | --- |
| Backend | `codex/scale-worker-bounds` | Scale implementation and full regression gate through `6fa8f66` | Based directly on `4e100a987602415516fb619b32af5af8cd27e2f0` |
| Mobile | `codex/mobile-poll-backpressure` | Mobile backpressure plus evidence through `ac4a94f6dd0e653293c217b83af763ac522412a9` | Based directly on `bd6390727ec2a6c5e8bf4dc4d5512433b992e18e`; later commits may update this roadmap only |
| Admin | `feat/system-audit` | `e6b6ab5d326aa90c8d6821dc5106940691787c48` | Clean; no post-release scale change is pending in this increment |

## 3. Next production update — do before scale claims

- [ ] Review backend staging `4e100a9…`, promote it to main, migrate only if
      the exact main tree reports a reviewed pending migration, manually deploy
      the recorded SHA, and prove health plus signed deployment evidence.
- [ ] Complete authenticated Super Admin Audit Vault acceptance: timeline,
      filters/pagination, mobile activity, CSV/JSON, legal hold, integrity and
      Product Owner 403.
- [ ] Obtain the real Data Protection Commission registration number. Publish a
      new immutable Privacy version; never mutate accepted `1.4.1` content.
- [ ] Read the highest private build codes from both Play Console and App Store
      Connect. Promote reviewed mobile staging to main and build all four
      artifacts from one clean explicit main SHA using codes above every maximum.
- [ ] Release and install the iOS client/provider updates. Do not raise any
      mandatory minimum build until both stores serve the reviewed build and a
      rollback build/link is verified.
- [ ] Re-run installed-device foreground/background/terminated/locked tests for
      OTP, Go Online, location, ride/job receipt, calls, payments and recovery.

## 4. Features deliberately outside the capacity programme

The following remain contained until their own approved product, money,
privacy and acceptance gates pass. A load test must not silently activate them:

- automated batch or provider-aggregate payouts;
- promo-code and loyalty-point redemption;
- scheduled artisan jobs;
- cancellation consequences;
- lost-device and deleted-role self-service recovery;
- support/dispute attachments and privileged provider-document upload;
- emergency recording, general email/SMS/WhatsApp notifications, USSD,
  SmileKYC and automated police checks.

## 5. 100k-DAU programme

### Phase A — approve the traffic model

The owner must approve measured or planned peaks for each row in
`myshop/docs/load-test-report.md`: concurrent signed-in clients, online drivers,
online artisans, Socket.IO connections, GPS event rates, estimates, bookings,
jobs/bids, OTP bursts, webhook traffic, regional mix, data volume and duration.
Until then, repository pilot/stress presets are diagnostic only.

Required inputs before the model is frozen:

- current peak hourly/15-minute API requests and unique sessions;
- current and expected client-to-provider population;
- expected peak Online driver and artisan counts in the pilot region;
- expected rides and artisan jobs per peak hour;
- expected OTP login/registration burst and acceptable delivery cap;
- expected simultaneous in-app calls;
- launch/campaign multiplier and growth horizon.

### Phase B — production-shaped topology

- [ ] Confirm the actual Render production plan, CPU/RAM, instance count and
      whether autoscaling or a manual warm-capacity procedure is available. The
      repository Blueprint still says `plan: free` and declares no replica or
      autoscaling policy; dashboard overrides are not externally observable.
- [ ] Run at least two same-region API instances before claiming replica fault
      tolerance. Preserve Socket.IO Redis-adapter authority and graceful drain.
- [ ] Confirm the current Redis region, tier, memory limit, HA/failover, backups,
      TLS, exact prefixes and `noeviction`. The last owner-reported Redis region
      was Cape Town while API/PostgreSQL are Frankfurt; reverify rather than
      assuming it is unchanged. Cross-region Redis is not an approved 100k-DAU
      topology.
- [ ] Budget PostgreSQL connections across every API/worker replica. Code
      defaults to pool min `2`, max `10` **per process**; the deployed overrides
      and Neon compute/connection limits must be recorded before scaling replicas.
- [ ] Prove database recovery on an isolated production-shaped restore and
      establish a reviewed bootstrap/baseline procedure for a truly empty
      database. A fresh chronological replay exposed two historical
      preconditions: the production-applied
      `20260615000000_ride_max_broadcast_drivers_config` migration precedes the
      later `updated_at` default that made it succeed in production, and the
      System Audit migration intentionally requires the exact active bootstrap
      Super Administrator. Do not edit either applied migration or manually
      alter production history to make a synthetic empty replay pass.
- [ ] Separate or explicitly capacity-budget scheduled/outbox workers. The API
      currently hosts scheduled work and does not use an external broker.
- [ ] Configure external metrics, alerts, log retention/redaction, paging and
      named owners before fault tests.

#### Initial scheduled-work capacity audit

The post-release source audit found that the most latency-sensitive paths are
already designed for more than one API replica: ride dispatch and offer expiry,
active-trip ETA refresh, stale-provider recovery, Paystack webhook processing,
pending transfers, tips and refunds use PostgreSQL `SKIP LOCKED`, compare-and-set
updates, token-owned leases or equivalent durable claims. This is correctness
evidence only; their throughput and pool cost still require measurement.

The following remaining workers are capacity risks before a 100k-DAU claim:

- bid-window expiry scans every open expired job without a batch limit and then
  performs per-job offer revocation plus bid counts;
- directed-quote, scheduled-job, job-staleness and welfare-check workers use
  unbounded candidate reads followed by per-row notification/database work;
- rating reveal updates and returns every expired row in one statement;
- provider-document lifecycle staging runs broad SQL every minute, while audit
  telemetry retention can keep deleting 5,000-row batches until the entire
  expired backlog is drained by an API-hosted cron;
- surge evaluation performs global demand/supply counts every minute; index and
  production-cardinality evidence is still required;
- several effects are durably deduplicated or compare-and-set protected, but
  that prevents duplicate outcomes rather than duplicate scan/query load across
  replicas.

- [x] Add a deployment-wide, token-owned Redis lease around the first
      scan-heavy worker set: bid expiry, directed quotes, scheduled-job
      reminders, job staleness, welfare checks, rating reveal, surge evaluation,
      provider-document lifecycle and audit retention. Redis failure skips the
      tick; it never falls back to every replica scanning. This is currently a
      local backend branch from exact repository staging and is not deployed.
      Prometheus counters and duration histograms expose bounded worker names
      and lease/execution outcomes without user identifiers. Backend commit
      `a78cd1b` renews an acquired lease by its random owner token while work is
      still running and records renewal failure or ownership loss. Commit
      `606a068` applies the same authority to ride-stage monitoring,
      disconnection-grace enumeration, and active-location degradation
      detection/escalation.
- [x] Add fifteen online partial indexes for the exact bid, directed-assignment,
      job-staleness, scheduled-job, welfare-alert, rating-reveal, requested-ride
      and Online-driver predicates plus ride-stage and provider-location
      degradation scans, with fail-closed validity/table postflights.
      All migrations executed successfully on disposable PostgreSQL. With
      20,000–100,000 synthetic rows per table, PostgreSQL selected every new
      index (index-only scans for the six due-work queries and bitmap index scans
      for the two surge counts) from the first set. The seven ride/location
      indexes in backend commit `645da93` are valid/ready on the disposable
      database; representative-volume planner proof is still required. No
      staging or production database was touched.
- [x] Register all fifteen scale indexes in the central reviewed-online-index
      manifest, the aggregate preflight and the invalid-only recovery script.
      The full API regression run initially rejected the unregistered
      migrations, proving the deployment guard was effective. After the
      registration fix, the migration contract passes **450/450** checks and
      the complete API suite passes **213/213 suites and 4,221/4,221 tests**.
      API typecheck and production build pass; lint has zero errors and 52
      pre-existing warnings. The registration migration applied successfully
      only to the disposable database. These latest checks ran on local Node
      24.14.1 and therefore do not replace the pinned-Node-22 evidence above.
- [x] Run the complete focused gate under pinned Node 22.23.0. The exact
      production Dockerfile built successfully from the pinned base-image
      digest, and its read-only test-source runs pass **12/12 suites and
      272/272 tests**, including global-module injection. API typecheck, API
      production build, changed-file lint,
      Prisma validation and diff checks also pass. Local production image:
      **181,359,385 bytes**, `sha256:cbf0da9c36ad89f6fda5186c069325c59810a023a929dde898f25c9d297df45f`.
- [ ] Inventory the production cardinality and query plan for every scheduled
      candidate scan without exposing user data. Backend commit `963d550`
      provides an aggregate-only, read-only diagnostic with 30-second statement
      and two-second lock timeouts. Commit `645da93` expands it to 27
      candidate/backlog measurements, fifteen index-state checks and eleven
      planner-only `EXPLAIN`s. It executes successfully on the fully migrated
      disposable database; all fifteen indexes are valid/ready. Production has
      not been queried and remains the missing sizing evidence. The Redis-backed
      disconnection set now has a fail-closed, aggregate-only diagnostic in
      backend commit `c187a5e`. It accepts only an explicitly acknowledged TLS
      staging/production target and emits whitelisted `INFO` fields, fingerprints
      plus aggregate `ZCARD`/`SCARD` backlog counts only—never URLs,
      credentials, prefixes, keys, members or ride IDs. Its contract passes
      **3/3**; the complete API gate passes **214/214 suites and 4,224/4,224
      tests**, typecheck, zero-error lint and script syntax. Neither production
      diagnostic has been run yet.
- [x] Add bounded keyset/claim batches and explicit per-tick work budgets where
      the current worker can consume an unbounded backlog. The wider cron audit
      also found unbounded candidate enumeration in disconnection `SMEMBERS`,
      stale payment verification, escrow payout retry, clawback write-off,
      insufficient-balance expiry and session-recovery cleanup. Backend commit
      `02174c4` closes the ride-stage portion: each stage uses the indexed
      timestamp/UUID keyset plus a Redis cursor, a configurable 1–500 per-stage
      budget (safe default 100), tail wrap and cursor-corruption recovery. It
      does not change stage thresholds, cooldowns, notifications or ride state.
      Disposable PostgreSQL accepted empty and non-empty cursors and selected
      `rides_stage_accepted_due_idx`; the complete API gate passes **214/214
      suites and 4,228/4,228 tests**, API/config builds, typechecks and
      zero-error lint. Backend commit `a0ede16` also replaces the unbounded
      disconnection `SMEMBERS` scan with a Redis-server-clock deadline queue, a
      configurable 1–500 total per-tick budget (safe default 100), and a bounded
      rolling sampler that drains entries written by older deployments. Queue
      registration happens before the per-ride grace records so a partial write
      cannot strand undiscoverable work; reconnect, heartbeat renewal, replica
      claim loss and escalation retry paths retain their existing safety
      semantics. The complete API gate now passes **214/214 suites and
      4,232/4,232 tests**, API/config typechecks and builds, script syntax,
      zero-error lint and diff checks. These latest checks ran on local Node
      24.14.1, so a pinned Node 22.23.0 gate remains required before a PR. Final
      deployed budget sizing still depends on the production aggregate
      diagnostic. Replica-level leases reduce duplicate scans but do not replace
      bounded durable work for the remaining paths.
      Backend commit `6fa8f66` additionally gives stale-charge verification and
      escrow payout retry their own deployment-wide leases, configurable 1–500
      total per-tick budgets (safe default 100), oldest-first keyset traversal
      and Redis-backed wraparound cursors. Persistently blocked gateway or
      manual-review rows therefore cannot monopolise a batch. Escrow release and
      missing-hold recovery now also have single-owner leases while retaining
      their existing PostgreSQL compare-and-set authority. Two online partial
      payment indexes and a fail-closed postflight applied successfully on the
      disposable database; the expanded diagnostic reports **29** aggregate
      workloads, **17** index states and **13** planner-only plans. The full API
      gate passes **214/214 suites and 4,247/4,247 tests**, builds, typechecks,
      Prisma validation, zero-error lint, the aggregate diagnostic and the
      online-index preflight. No staging or production system was touched.
      Backend commit `1390423` closes the three remaining enumerated paths.
      Insufficient-balance expiry now uses one five-minute deployment lease,
      separately bounded deadline and failed-alert queues, atomic queue moves,
      deduplicated notification retries and alternating queue priority; the
      original 24-hour client retry deadline is never extended. Clawback
      write-off now uses a leased, oldest-first `(created_at, id)` keyset with a
      durable wraparound cursor and per-provider failure isolation. Session
      recovery cleanup now runs through one lease and two bounded candidate
      phases while rechecking the exact 24-hour cutoff and continuing to protect
      `resolving` rows. All three budgets validate to 1–500 with a safe source
      default of 100; production values remain subject to the measured backlog
      and owner-approved workload model. A reviewed concurrent partial index
      supports pending clawback traversal, and the preflight no longer
      incorrectly requires a provider-document index that a later reviewed
      migration intentionally drops while the invalid-remnant repair still
      recognises it. The disposable database has **229** applied migrations,
      passes the **83-index** deployment preflight and reports **32** aggregate
      workloads, **19** worker index states and **16** planner-only checks. The
      online-index write-continuity proof passes. On pinned Node **22.23.0**, the
      exact committed source passes **214/214 suites and 4,269/4,269 tests**, API
      typecheck, production build and lint with zero errors and 52 pre-existing
      warnings. No staging or production system was touched.
- [ ] Move or elect one scheduler/worker authority before scaling API replicas;
      retain row-level claims so worker failover remains safe.
- [ ] Prove scheduler lag, database pool occupancy and notification/outbox
      backlog at normal peak, 2x peak, soak and one-replica-loss conditions.

#### Initial mobile request-amplification audit

- [x] Coalesce the client Activity foreground refresh so its 15-second timer,
      pull-to-refresh and event-driven reload cannot overlap the same
      `GET /jobs` request. Timer refreshes retain the last visible snapshot
      instead of flashing a loading state.
- [x] Coalesce the Online-artisan 10-second REST fallback so a degraded API
      cannot create more than one `GET /jobs` request per device at a time.
      The production cadence and foreground-only/FCM behavior are unchanged.
- [x] Add deterministic slow-response tests for both paths. Client and provider
      focused tests pass, both focused analyzers report no issues, formatting
      and `git diff --check` pass. Local mobile commit: `e551a41`; it is not
      pushed or deployed.
- [x] Coalesce the three-second REST call-state safety net in both apps, and
      cache the call socket while mounted so closing a call screen never reads
      Riverpod after widget disposal. A slow initial join plus timer tick now
      remains one request per call screen.
- [x] Coalesce ride and artisan-job payment settlement reads. Each polling run
      carries a generation plus exact payment ID, so a late success/failure
      from an abandoned attempt cannot mutate or settle its replacement.
- [x] Coalesce provider active-job acknowledgement/status refreshes shared by
      its immediate read, timer, socket recovery and payment-retry paths.
      Slow-response, retry-generation and call-disposal regressions pass in
      **16/16** focused tests; focused client/provider analyzers and diff checks
      pass. Local mobile commit: `162ef33`; it is not pushed or deployed.
- [x] Coalesce provider location-permission checks per Online generation. Slow
      platform checks cannot overlap, and a result from a superseded/Offline
      generation cannot report a false location loss.
- [x] Coalesce the client job and bid REST safety nets across the job screen,
      bid screen and bid sheet. The coordinator joins initial loads, limits
      each job/resource to one request and releases its fence after failure so
      later recovery remains possible. The current source passes **91/91**
      client tests and **173/173** provider tests; both full-app analyzers and
      `git diff --check` pass. Local mobile commit: `711dd40`; it is not pushed
      or deployed.
- [ ] Approve any cadence jitter or adaptive backoff separately. No polling
      interval or user-visible freshness contract has been changed by this
      increment.

### Phase C — measured scale ladder

Use only the repository's fail-closed wrapper against an isolated
production-shaped target. Never load-test production.

1. Provision fresh server-issued, exact-role fixtures for the target.
2. Run smoke and the bounded pilot preset.
3. Run the approved normal peak model.
4. Run 2x peak headroom.
5. Hold a soak long enough to expose pool, memory, worker and backlog growth.
6. Inject replica, Redis, database, network and SIGTERM faults.
7. Reconcile rides, offers, provider sessions, jobs, webhooks and money ledgers.
8. Rehearse rollback and record recovery time.
9. Set the temporary operating cap to the highest fully passing level, not the
   requested DAU number.

The fail-closed load-harness contract currently passes **10/10** local tests,
including production-host refusal, target/commit binding, exact-role fixtures,
provider epoch/sequence checks, call participant uniqueness and Cloudflare TURN
preflight. The `k6` executable is not installed on the current machine. Passing
the harness contract proves safety wiring only; it is not a load result.

### Phase D — rollout

Canary the exact reviewed backend/mobile artifacts, observe the approved window,
then expand gradually. Stop on lost/duplicate accepted work, money mismatch,
provider Online/session divergence, sustained latency/error/backlog thresholds,
or missing alerts. The 100k-DAU claim remains unproven until the completed load
evidence record is signed by the release, backend/SRE and payments owners.

## 6. Decisions still required

| Decision | Status |
| --- | --- |
| Approved peak traffic model and 2x headroom | **Required** |
| Actual Render plan/replica/autoscaling budget | **Required** |
| Current Redis region/tier/HA/capacity | **Required** |
| Current Neon compute tier and connection ceiling | **Required** |
| Highest private Android/iOS build codes | **Required** |
| Real DPC registration number | **Required** |
| Named load, incident-abort and release owners | **Required** |
