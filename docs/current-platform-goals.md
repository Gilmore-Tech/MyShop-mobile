# Current MyShop Platform Goals

Status captured: **2026-08-12 GMT**  
Authority: **this file is the current cross-repository goal board**

Unless a row explicitly says **merged**, **applied** or **deployed**, checked
implementation work below is frozen in an isolated local worktree and has
**not** been committed, published or deployed. Record the PR and deployment SHA
here when that changes.

The older mobile-update and production-audit checklists are retained as
historical evidence. Their unchecked boxes do not automatically become current
work. A new finding is recorded as evidence, a dependency, or a risk; it changes
this goal list only when the owner explicitly changes priority, a production
incident requires containment, or evidence proves a current goal cannot safely
continue.

## Owner decisions already fixed

- [x] Production acceptance testing for the current release is complete.
- [x] The Provider location `403 PROVIDER_NOT_ELIGIBLE` retry loop is being
      observed. No recovery change is authorized yet.
- [x] Correcting the Provider store descriptions remains planned work.
- [x] Redis command-cost containment, telemetry truth, platform attribution and
      100k-DAU qualification are the active platform program.
- [x] The 100k-DAU target covers both vertical and horizontal scaling.

## Current goals and dependencies

These are not one serial queue. Redis observation, fare promotion, store-copy
work and 100k preparation can proceed concurrently. Truthful telemetry is a
prerequisite for the production attribution canary. Full 100k qualification is
blocked on observability, workload calibration and the scaling architecture.

### G1 — Verify the Redis command-cost reduction

Outcome: prove that the deployed refresh-lineage bridge optimization reduced
commands without increasing login, refresh or session errors.

- [x] Command-amplification cause identified and code optimization deployed in
      production SHA `f88e245d95cee03e32bfbe93b659ff8356e86a1a`.
- [ ] Capture Upstash Throughput and Top Commands over a clean observation
      window.
- [ ] Confirm bridge logs over multiple 30-second cycles show
      `batchReadFallback=false`, `databaseComparisonFallback=false`,
      `fastMatched` approximately equal to `scanned`, and deep/deferred work
      converging to zero.
- [ ] Compare auth/login/refresh error rates before and after deployment.
- [ ] Record actual commands/day and projected monthly cost.

### G2 — Make System Audit and telemetry truthful

Outcome: Admin identifies the origin of each audit row, and a successfully
acknowledged mobile batch no longer remains queued, deterministically repeats
or starves newer events.

- [x] Root causes reproduced in source and covered by focused tests.
- [x] Backend compatibility response, server-side telemetry validation and
      actor/origin/diagnostic presentation implemented and independently
      reviewed.
- [x] Mobile canonical response parsing and reported app/platform/build/version
      context implemented and independently reviewed.
- [x] Admin provenance, source/environment filters and truthful at-least-once
      labels implemented and independently reviewed.
- [x] Privacy-safe operational HTTP summaries implemented and independently
      reviewed. Fast high-volume traffic is aggregated, while pre-interceptor
      guard failures, 5xx, slow and aborted requests retain truthful status,
      severity, metrics and support references.
- [ ] Promote in the mandatory order: Backend, API smoke, Admin, then future
      mobile store build.
- [ ] Promote the operational HTTP summaries separately, then prove exact 429,
      5xx, slow-request and abort outcomes on one replica and across the fleet.
- [ ] Start a clean post-deploy measurement window. Historical duplicate rows
      remain historical evidence and are not silently rewritten.

Accepted residual risk: an ambiguous transport loss after server commit can
still duplicate an at-least-once event row. Durable `clientEventId` plus a
unique index is preserved in the future backlog as a separate migration.

### G3 — Correct Admin ride fare authority

Outcome: completed rides show the authoritative client amount and never turn an
unknown value into a fabricated zero.

- [x] Backend page-bounded bulk pricing resolver implemented and independently
      reviewed; no N+1 query and no migration.
- [x] Admin old/new payload normalizer implemented and independently reviewed;
      explicit `null` and zero remain distinct.
- [ ] Promote Backend first, then Admin.
- [ ] Verify one quoted, completed unpaid, completed paid, promo and zero-fare
      case on staging before production.

### G4 — Controlled platform-attribution rollout

Outcome: activate attribution-only campaign codes through a controlled canary,
with no points, payment or individual referral reward.

- [x] Existing Backend, Admin and Mobile feature implementation confirmed
      merged; production database migration is already applied.
- [x] Exact-super-admin protection for the attribution DB switch implemented.
- [x] Combined environment-and-database gate semantics documented and tested.
- [x] Reciprocal attribution race proof passed against a fully migrated
      disposable PostgreSQL database and is wired into CI.
- [ ] Promote the hardening change and require exact-head CI success.
- [ ] Verify the production environment flag and the authorized Admin combined
      gate status, existing production codes and attribution counts. The public
      database gate is currently true but is not activation proof.
- [ ] If production is not already active, use the hardened exact-Super-Admin
      path to set the database gate false before changing the environment flag;
      deploy `FF_PLATFORM_SIGNUP_ATTRIBUTION=true` and confirm the combined
      status remains false.
- [ ] Create a clearly named production canary code while distribution is
      contained, then enable the audited database gate and confirm the combined
      status is true.
- [ ] Canary one non-reviewer Client, Driver and Artisan; verify aggregate
      counts and zero loyalty/payment ledger writes.
- [ ] Verify deactivation and the five-minute accepted-OTP tail, then decide
      whether to distribute the campaign broadly.

### G5 — Qualify for 100k DAU

Outcome: produce retained evidence that the platform survives an
owner-approved 100k-DAU workload and a 2x peak, including component failure.

- [x] A vertical-plus-horizontal capacity-gap draft has been independently
      reviewed as a truthful statement of what is and is not ready.
- [ ] Approve the population/peak assumptions, route mix, coordinate/cache
      distribution, samples per batch, historical cardinality and numeric
      infrastructure thresholds before executing the 25% run.
- [ ] Establish trustworthy private metrics/log streams and numeric paging
      thresholds.
- [x] Global throttler command amplification corrected in a separate,
      independently reviewed local change without weakening auth, password or
      callback controls.
- [ ] Promote the throttler correction only after operational telemetry is
      trustworthy; prove ordinary traffic uses one admission script and record
      the resulting Upstash command reduction.
- [ ] Separate HTTP, scheduler and worker runtime roles before adding API
      replicas.
- [ ] Vertically size PostgreSQL and Redis from measured CPU, memory, IOPS,
      connections, commands and bandwidth, with recovery/HA evidence.
- [ ] Qualify two or more API replicas plus independently scalable workers.
- [ ] Run the 25%, 50%, 100%, 8–24-hour soak, 2x peak and fault-injection ladder
      on a disposable production-shaped environment.
- [ ] Pass business invariants: no lost/duplicate accepted work, no money
      reconciliation delta, no Redis eviction, no DB pool timeout and backlog
      recovery to zero.

### G6 — Correct Provider store descriptions

Outcome: store copy accurately describes the Provider experience and does not
present incoming trip price as provider earnings.

- [ ] Audit current Google Play and App Store text against shipped behavior.
- [ ] Prepare reviewed replacement copy and screenshots/metadata if required.
- [ ] Submit the metadata-only correction and retain store acceptance evidence.

## Explicitly deferred or closed

- Provider location 403 retry recovery: **observe only** until the owner makes a
  decision or evidence shows active-ride/systemwide impact.
- Admin reset-password authorization wording and enforcement do not currently
  express the same authority model. This is a recorded security-contract review
  for the future backlog and is not silently mixed into the Redis-cost change.
- Current-release production acceptance testing: **complete**.
- Old build numbers, old PR SHAs, old store uploads and old July/August release
  gates: **historical**, not current goals.
- Broad referral/reward expansion, automated batch payouts, BR-53/Artisan V2,
  remaining session/Redis hardening and other disabled slices are preserved as
  **future backlog goals outside the current execution window**. They are not
  erased, and the owner can promote one onto this board explicitly.

## Frozen local evidence awaiting publication

- System telemetry: Backend diff `7815e38c…`, Mobile diff `66f10257…`, clean
  Admin diff `07c90105…`; independent conditional GO.
- Admin ride fare: Backend diff `a74bbf91…`; Admin tracked diff `22dc041a…`, new
  contract `646e533b…`, and new contract test `1426b42f…`; independent GO.
- Platform attribution hardening: all-file manifest `3f82a3e4…`; independent
  GO after two consecutive full-database race proofs.
- Operational HTTP telemetry: full 11-file patch `15ea2f0a…` and ordered-file
  manifest `a48d3baa…`; independent GO after the full 4,494-test API suite and
  real Nest guard-lifecycle proof.
- Redis throttler topology: changed-file manifest `5bb8deca…` and tracked diff
  `6b80d34d…`; independent GO after 227 focused tests.
- 100k capacity: gap document `0b2c163f…` and load README `e1d81ee3…` are local
  documentation only; replace these fingerprints with the PR/deployment SHA
  when published.

## Required evidence for every goal change

Record the date, owner decision, exact repository/SHA or environment, what was
observed, and whether the item is a goal, dependency, risk or historical note.
Do not convert a diagnostic finding into a release blocker without stating the
user impact and the evidence that makes it blocking.
