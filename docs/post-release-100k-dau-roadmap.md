# MyShop post-release and 100k-DAU roadmap

Status captured: **2026-07-23 GMT**

This document restarts the scale programme from the observed released state. It
does not treat a daily-active-user target as a concurrency claim, and it does
not activate deferred product features. Every workload value and business rule
remains subject to owner approval before it becomes a test or production limit.

This is the authoritative tracker for work after the `1.4.1` release. The larger
`production-release-audit-checklist.md` remains the historical release evidence
and approved-business-rule register; unchecked historical rows must not be read
as a request to repeat the release or reactivate deliberately deferred features.

The exact scope and live gates for the next mobile store update are maintained
in [`current-mobile-update-checklist.md`](current-mobile-update-checklist.md).
That short checklist is authoritative for the current release; this roadmap
cannot add an item to the release merely because it records it as future work.

## Current counted progress

Programme completion is **13/30 criteria (43%)**. This is an evidence count, not
an estimate of effort or a claim that production supports 100k DAU.

| Workstream                   | Complete |  Total | Current position                                                                                                                                                                                                          |
| ---------------------------- | -------: | -----: | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Next production update       |        0 |      7 | The authorised update is mobile Audit telemetry plus payment-settlement reliability, not a new payment method or business-rule change. Exact next console build numbers, signed artifacts, installed-device proof, Audit Vault acceptance, DPC publication and rollout/rollback proof remain open. |
| Production-shaped topology   |        0 |      7 | Actual Render, Redis-provider and Neon capacity facts, two-replica operation, recovery, worker capacity and operational monitoring remain unproved.                                                                        |
| Scheduled-work hardening     |        5 |      8 | Deployment leases, scale indexes, manifest enforcement, pinned-Node gate and exact scheduler ownership are complete; production cardinality/plans, final bounded-drain proof and load/fault backlog evidence remain open. |
| Mobile request-amplification |        8 |      8 | Source-level overlap, lifecycle and background-amplification controls are complete; their installed-device and load evidence is counted under the release/topology gates above.                                           |
| **Total**                    |   **13** | **30** | **43%**                                                                                                                                                                                                                   |

### Evidence boundary: released, local and remaining

| State                                                    | Current evidence                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Released/live**                                        | The owner confirms the last four mobile release builds—Client and Provider on Android and iOS—were built from `main` as `1.4.1+24`. Repository pubspec `1.4.1+20` is only a source floor and is not the released build identity. The exact `main` SHA used for `+24` is not yet recorded. Public Android listings serve marketing version `1.4.1`; Apple's official Ghana lookup still serves Client `1.3.9` and Provider `1.4.0`, so the owner-confirmed `+24` iOS build must not be described as publicly available until Apple serves it. Production API `d918243…` is healthy, Backend call foundation `09d1d15…` and Admin `30f2ed0…` with Audit Vault are live, and rides plus ordinary artisan jobs are enabled. |
| **Completed locally; not released**                      | The exact Backend candidate `8cfe1f7…`, based directly on live `d918243…`, is clean at 257 committed paths and passes pinned Node 22 evidence of 219/219 API suites and 4,453/4,453 tests, typecheck/build, the complete 56/56 topology/exporter/capture/evaluator/wrapper/load gate and zero lint errors. Its command Redis and Socket.IO Redis clients fail explicitly without offline queuing or ambiguous replay, every production command promise is source-audited, the reviewed production-log privacy tranche is integrated, and its capacity wrapper binds private aggregate PostgreSQL/Redis evidence to the exact release without carrying secrets into k6. Its cross-replica call successor proves exact peer/probe integrity and an actual Redis-adapter relay while keeping the probe production-forbidden and invisible to ordinary sockets; call and chat now distinguish temporary Redis session-authority failure from account takeover. Its unchanged pending migration chain applies on a disposable local live-base clone: Prisma reports all 265 migrations current, all 35 new online indexes ready/valid, and the additive marker/trigger/outbox/Audit objects present. Its Blueprint cannot request a production downgrade to Free, makes no unverified Redis-provider claim and grants a 60-second graceful drain. Exact Mobile candidate `4d0135b…`, directly above repository-main comparison head `61241f8…`, is clean at 136 committed main-delta paths and passes Client 96, Provider 174, API client 168, Shared Models 7 and Shared UI 30—475/475 tests—with all five analyzers clean. Its profile/release diagnostic boundary, FCM-background installation, native iOS debug-only output and socket/job-log redaction contracts are integrated. The exact eight-path Admin cleanup candidate `16305f6…`, directly above live `30f2ed0…`, passes focused 4/4, TypeScript and the 48-route production build; it does not rebuild Audit Vault. These are reviewed tranches only; broader mixed Mobile workspace work remains unreviewed/unpromoted. |
| **Still required for the current authorised update**    | Use only `current-mobile-update-checklist.md`. The isolated candidate contains the approved telemetry, payment-settlement reliability and release-provenance unit; source verification is green. Still required: exact owner review, marketing/build selection from all four private consoles, signed artifact verification, physical payment/telemetry tests, Audit Vault acceptance, store declarations, canary and rollback. Backend/Admin scale candidates, call-policy implementation and the wider 100k-DAU load/fault programme are outside this update. |
| **Already deferred; keep disabled**                      | Automated batch/aggregate payouts, promo/loyalty redemption, scheduled artisan jobs, SmileKYC/police automation, role recovery and permanent purge, emergency recording, support/dispute attachments, cancellation consequences and active-trip fallback until its separate proof passes.                                                                                                                                                                                                                                                                                                                        |

The rows above are the short status summary. A shipped implementation is not a
capacity pass; a green local gate is not a deployed release; and an already
deferred feature must not reappear in the current-phase remaining list.

### Authorised mobile Audit-telemetry and payment-reliability update

The current update is deliberately narrow:

- **Include:** the privacy-minimal mobile screen, lifecycle and named-action
  telemetry already committed on `origin/staging`; the approved ride/artisan
  settlement poll fencing and refresh coalescing; phase-only payment telemetry;
  and only the tests and release provenance/version plumbing required to build
  and verify them.
- **Reuse:** the already-live Backend ingestion/retention contract and the
  already-live Super Admin Audit Vault. They are acceptance dependencies, not
  implementation scope.
- **Exclude:** the 136-path Mobile pilot-stability candidate, Backend/Admin
  hardening candidates, new call-policy behavior, realtime chat/GPS work and
  every feature listed as deferred below.
- **Release identity:** the owner-confirmed previous four-platform build is
  `1.4.1+24`, built from `main`. The marketing version and next build number
  remain unselected until the four private console maxima are read; source
  `1.4.1+20` must never be substituted for the release record.

The exact candidate scope, fingerprint, verification evidence and remaining
gates now live only in
[`current-mobile-update-checklist.md`](current-mobile-update-checklist.md) to
prevent this roadmap from becoming a stale competing release record. The
candidate remains uncommitted, unpushed, unsigned, uninstalled and undeployed.
Local source proof adds no release or 100k-DAU capacity credit; programme
progress remains **13/30 (43%)**.

### Current workspace isolation checkpoint

The three remotes were fetched on 2026-07-23 GMT. No merge, rebase, stash,
commit, push, deployment or live-state change was performed. The current source
cannot yet be called a release candidate because each repository still contains
uncommitted work and the branch shapes differ:

| Repository | Production base | Current local/remote shape | Current source checkpoint |
| --- | --- | --- | --- |
| Mobile | `origin/main` comparison head `61241f8…` | Local `codex/mobile-poll-backpressure` `55d7823…` is 26 commits above `origin/staging` `bd63907…`; 128 tracked files are dirty and 12 files are untracked. | Against the repository-main comparison head, 142 tracked paths and 12 untracked files, excluding only this roadmap and the historical checklist, fingerprint to `567bd75531589f2e776046d8011d59d6f7e01c64e49d84ff443d7dc1fddc6f45`. The exact public Android source SHA is unknown. |
| Backend | `origin/main` `d918243…` | Local `codex/scale-worker-bounds` `a5079a1…` is 21 commits above `origin/staging` `4e100a9…`; production main and staging have diverged by 2/3 commits; 130 tracked files are dirty and 18 files are untracked. | Against the production base, 246 tracked paths and 18 untracked files fingerprint to `6bb8d06a535de3f79e97dce9a2436e7ba13f9c174f66633523f854a4bf75dea7`. |
| Admin | `origin/main` `30f2ed0…` | Local `feat/system-audit` `e6b6ab5…` is the already-merged feature head and sits behind main; 6 tracked files are dirty and 2 files are untracked. | Against the production base, 6 tracked paths and 2 untracked files fingerprint to `08705d11cfe3d9690d3091e34d6a422c036d3015908c8cceccf385800fe682e3`. |

The fingerprints bind final file content, not authorship. User and Codex edits
cannot be separated safely from Git metadata alone, so the current deltas must
remain intact until reviewed path by path. Create each eventual candidate from
the exact production base, apply only the reviewed delta, and rerun its gates;
do not push the Admin feature head directly or merge the divergent backend
histories blindly.

A later read-only refresh at 2026-07-23 08:58 GMT confirms the active
workspaces have not converged into candidates: Mobile has 128 dirty tracked plus
14 untracked files and 142 production-base tracked paths after excluding this
roadmap and the historical checklist; Backend has moved to 136 plus 20 and 248
production-base tracked paths; Admin remains 6 plus 2 and 6 production-base
tracked paths. The refresh uses a reproducible SHA-256 over the binary
`origin/main` diff followed
by the `MYSHOP_UNTRACKED_V1` marker and sorted JSON records containing each
untracked path, Git mode and blob hash, generated by the established
`myshop-candidate-v1` helper. The resulting source snapshots are Mobile
`6fc96d1ab663fe507136e4e294687820d3c76df7bd5629ca3a6b6fc142f9e9aa`,
Backend
`96c6e5656e134839176ef159a51f415dcc9261894df4602ddf22d674820f731b`
and Admin
`08705d11cfe3d9690d3091e34d6a422c036d3015908c8cceccf385800fe682e3`.
Clean detached reference worktrees now point to the exact production bases
Mobile `61241f8…`, Backend `d918243…` and Admin `30f2ed0…`; they contain no
candidate changes. The active indexes and files were not stashed, reset,
checked out, committed, merged or copied. These references are comparison
anchors only, not promotable artifacts.

A permanent path-level inventory gate now separates every production-base
delta into committed-only, working-only, committed-and-working or untracked
state, records current mode/blob hashes and fails to classify only by explicit
review. An untracked `.claude/` file is developer-local, but a tracked
`.claude/` change is repository-security-required because both Mobile and Admin
currently remove a historically committed GitHub credential. It does not infer
that any application path is safe to ship.
Its isolated Git-fixture contract passes. The current inventories are Mobile
156 paths (16 committed-only, 105 working-only, 21 overlapping, 14 untracked;
all 156 review-required) at
`89e02885036dd904a7f6152a062dc0615c434e9b2d94554950df65f2ce970391`,
Backend 268 (112, 86, 50, 20; all review-required) at
`dff47b2632fd44d82cc6f7472e4c42eb856f3c8b4f5d2c5a435c9446995706c4`,
and Admin 8 (0, 6, 0, 2; all 8 review-required) at
`383392bcc3874c1283dda73a8f44d91140f3f1528dc1341d9c1e5fd2e062840d`.
The gate detected Backend edits occurring during the first inventory and
rejected the earlier digests. A new runtime connection-ownership contract then
appeared after a repeated snapshot, so Backend is explicitly still moving; the
values above are only the latest observed checkpoint. They are drift detectors,
not owner review or release approval.

The eight-path Admin delta is now isolated as local candidate
`codex/pilot-stability-admin-rc` at `16305f6…`, whose sole parent is the live
Admin production base `30f2ed0…`. Its candidate fingerprint remains
`08705d11cfe3d9690d3091e34d6a422c036d3015908c8cceccf385800fe682e3`
and its inventory fingerprint remains
`383392bcc3874c1283dda73a8f44d91140f3f1528dc1341d9c1e5fd2e062840d`.
The candidate changes only the reviewed repository-credential removal,
owner-approved support destinations and bounded Admin diagnostics plus their
focused contracts; it does not rebuild or replace the already-live Audit
Vault. Its focused contracts pass **4/4**, TypeScript passes, diff checks are
clean and the exact candidate completes the **48-route** Next.js production
build with zero blocking errors and the existing 99 lint warnings. It has not
been pushed or deployed. Backend and Mobile remain mixed moving workspaces and
must reach the same production-base isolation standard independently.

The reviewed Backend tranche is now independently isolated on
`codex/pilot-stability-backend-rc` at `8cfe1f7…`, directly above the live
Backend production base `d918243…`. It contains the two missing
maintenance/Audit fixes, the 21 committed scale/worker/load/monitoring changes,
the strict-runtime Express import correction found by the pinned gate, and
four separately reviewed containment units: a connection-free database
package root, bounded Socket.IO Redis outage queues with rejection telemetry,
one validated release identity shared by health and metrics, and a command
Redis authority that fails explicitly instead of retaining or replaying
ambiguous OTP/session/admission/lease/payment commands. It also integrates the
reviewed production-log privacy tranche, which removes or bounds identifiers,
account destinations, payment references, call/session details,
document-verification results and message recipients in production
diagnostics. The follow-up Blueprint
safety commit removes the production `plan: free` request, removes the
unverified Redis-provider label and grants a 60-second graceful shutdown window
while preserving the existing dashboard-selected instance type and replica
count. It also contains the reviewed evidence-only topology/backlog/load
wrapper, which binds private aggregate PostgreSQL/Redis snapshots to the exact
release while keeping credentials out of k6. Its schema-v3 successor also
requires measured and owner-modeled API CPU/memory, Redis memory/command and
Neon compute/PITR budgets and provides the documented validator package
command. The default-off call-evidence successor also proves exact peer/probe
integrity and at least one actual Redis-adapter cross-replica relay while
remaining forbidden in production and absent from ordinary sockets. Call and
chat distinguish unavailable Redis session authority from account takeover.
The candidate is clean and contains exactly 257 committed
production-base paths with no working or untracked files; its inventory
fingerprints to
`0119f0f9ed7d4bf16bda626aa427669d1d5be563da5378b7fd42ae776203b4ac`.
Its production-delta fingerprint is
`7c6af9a09961d84f8eba1b0e246407be6c4e75e10d45b39493db8c7c51aaada6`.
The exact candidate passes **219/219 suites and 4,453/4,453 tests** in pinned
**Node 22.23.1**, API typecheck/build, **56/56** topology/exporter/capture/
evaluator/wrapper/load contracts, lint with zero errors and 52 existing
warnings, formatting and diff checks. A disposable
local PostgreSQL clone of the live-base migration state then replayed every
pending migration through `20260722248000_marketplace_notification_outbox`;
Prisma reports all **265** migrations current, all **35** new concurrent indexes
ready/valid, all seven nullable markers plus the reset trigger present, and the
outbox and Audit tables present. The aggregate scheduled-work diagnostic ran
read-only and ended with `ROLLBACK`; its disposable fixture contains zero
scheduled backlog, which does not infer production state. No staging or
production database, Redis, service, push or deployment was contacted. This is
still a local review checkpoint: production cardinality and overdue
scheduled-obligation state, real lock duration, real Redis-loss/recovery and
the three call-policy changes remain outside it until explicitly approved.

The production-topology source no longer requests a Free instance or assumes a
Redis vendor. Exact Backend candidate `8cfe1f7…` omits `plan` and
`numInstances`, so Render retains an existing service's dashboard-selected
instance type and manual instance count, and explicitly grants a 60-second
graceful drain. Render's current official documentation says Free web services
are not for production, cannot scale beyond one instance and can spin down;
new services default to Starter and one instance when these fields are omitted.
This closes the unsafe source downgrade, not the private topology gate. Before
promotion, capture the dashboard's actual paid plan, replica/autoscaling/disk
state and connection budgets, then bind those facts to the
100→250→500/fault/soak evidence. See the official
[Free-instance limits](https://render.com/docs/free),
[Blueprint fields](https://render.com/docs/blueprint-spec) and
[scaling behavior](https://render.com/docs/scaling).

The separately reviewed Backend repository-wide log/privacy extension was
committed as `faa11c1…`, rebased without conflicts onto the command-Redis
successor `8b31398…`, and fast-forwarded into privacy successor `4fdd52c…`.
Exact call-evidence successor `8cfe1f7…` retains that complete tranche. The
integrated 257-path candidate retains the Redis behavior and passes the combined
privacy/Redis/runtime focused gate **23/23**, the full pinned-Node result
**219/219 suites and 4,453/4,453 tests**, API typecheck/build, the complete
evidence/load boundary **56/56**, zero-error lint and diff checks. This
supersedes the earlier
uncommitted privacy checkpoint; neither checkpoint nor the integrated candidate
has been pushed or deployed, and source privacy containment adds no capacity
credit.

The reviewed Mobile stability predecessor was independently isolated on
`codex/pilot-stability-mobile-rc` at `4652371…`, six commits directly above the
repository-main comparison head `61241f8…` (whose pubspec floor is
`1.4.1+20` in both apps). That Git value is not a released build number; the
owner-confirmed previous four-platform release build is `1.4.1+24`, built from
`main`, with its exact source SHA still to be recorded. It
contains the reviewed polling/refresh coalescing controls, release-artifact
provenance gate, repository credential/crash-claim containment, and Client
lifecycle authority that pauses seven REST fallback pollers plus the general
ride/job socket while backgrounded without touching Provider tracking or the
separate in-call socket. The candidate is clean and contains exactly 45
committed production-base paths with no working or untracked files; its
inventory fingerprints to
`979dc00d1cbd2b3f3cb912b517f55f0f53938a036fc5f3a50f7c09eb82ec455c`.
On this exact source, Client passes **96/96**, Provider **173/173**, API client
**163/163** and Shared UI **30/30**—**462/462 tests**—and all four analyzers
report no issues. Bash syntax, XML/plist parsing, release-version, iOS-export
and artifact-verifier contracts, and diff checks pass. This is a local source
candidate only and is now superseded by the exact privacy successor below; do
not promote `4652371…` independently.

The Mobile diagnostic/log-privacy extension is committed as `4d0135b…`
directly above `4652371…` and fast-forwarded into the canonical local branch
`codex/pilot-stability-mobile-rc`. Its exact **102-path** unit is fully
committed with no working or untracked paths, inventory
`92cc49594e3107c04dea7d929076cfa1949864c83c3c13d1d3ce516224101aa0` and
unit fingerprint
`378d8c4b262fe9169d328c4391c2bf49a050ed06ec8513feaee9bb3a7dccf0e9`.
The extension makes profile/release Dart diagnostics fail closed before
interpolating payloads, installs the policy in both foreground and FCM
background isolates, confines app-owned iOS logging to `#if DEBUG`, removes
the raw job-parser dump, and prevents general/chat/call/Provider socket logs
from retaining payloads, connection/call/booking identifiers or server
disconnect text. Six interleaved telemetry and additional polling changes from
the mixed workspace were explicitly excluded; the only retained non-log rename
is required by Dart null-safety after introducing a lazy diagnostic closure.
The complete exact successor `4d0135b…` is clean at **136 committed
production-base paths**, inventory
`4c1bbceafee2e18a2a00b6c0c73231ce318d8870174ac5e97a648fb48a77942f`
and production-delta fingerprint
`856c0f598e7d1ed3682b8d153e1857f2f1eb37f535340d657510038cb3560411`.
Client passes **96/96**, Provider **174/174**, API client **168/168**, Shared
Models **7/7** and Shared UI **30/30**—**475/475 tests**—and all five analyzers
report no issues. Focused privacy contracts, all four iOS plist/privacy-manifest
parses and `git diff --check` pass. It remains unpushed, unsigned, uninstalled,
unuploaded and undeployed and adds no programme credit.

The exact Mobile candidate contains a release-artifact provenance gate. The
build wrapper refuses a dirty or non-`origin/main` source, injects the exact
reviewed commit into Android and iOS package metadata, and post-verifies the
package identity, marketing/build versions, source commit, signature,
production API endpoint and staging-URL absence. Bash syntax, the release
version contract, the iOS export contract, both plist parses and six malformed
or missing-artifact rejection cases pass locally. The historical `+23` set and
the lone Provider `+24` APK all fail this gate because they predate native
source provenance; the `+24` APK was also produced earlier than the complete
`+23` set and is quarantined despite its higher number. No exact signed APK,
AAB or IPA has passed the new success path yet, so this is not artifact or
store evidence.

The current call-capacity source audit also preserves three decision gaps
instead of assuming them away. Accepted call state has a fixed 30-minute Redis
TTL even though the default TURN credential lasts two hours; starting a call
does not reserve a booking-level non-terminal slot, so retries or two devices
can create parallel ringing sessions; and the WebSocket authority caps
connections but not signalling events per socket. The disposable-clone
provisioner creates and accepts sessions in batches of 25, while the
100/250/500 k6 ladder then holds exactly two unique sockets per accepted call
and sends one synthetic signal every five seconds. It proves control-plane
authentication, room admission, acknowledgements and at least one
cross-replica relay, but explicitly does not prove real WebRTC/TURN media,
incoming push latency or a simultaneous 500-call setup burst. Focused call,
TURN, Redis-adapter, connection and transport contracts pass **54/54** and the
load boundary passes **22/22** locally. Duration, one-live-call-per-booking and
signal-rate rules still need explicit owner approval before implementation.

The latest unauthenticated production recheck on 2026-07-23 GMT returned HTTP
200 from readiness with database/Redis `ok`, commit `d918243…`, maintenance
false, rides true and ordinary artisan jobs true. Metrics still return HTTP 404
and health reports `version=unknown`. Exact Backend candidate `8cfe1f7…` makes
repository `render.yaml` provider-neutral for Redis and removes the
`plan: free` request while leaving plan and replica count under the existing
dashboard configuration. Do not apply/sync the Blueprint until the owner
confirms the real production plan, replica policy and Redis provider.

The exact Backend candidate removes the next-release `version=unknown` ambiguity
without inventing a marketing version. Health and Prometheus now share one
privacy-safe release marker: a valid explicit `APP_VERSION` wins, otherwise the
validated immutable Render commit yields `git-<12 characters>` while retaining
the full validated commit in its separate field. Invalid values are never
reflected. Its focused health/metrics proof passes **25/25**, and the complete
candidate passes **4,437/4,437** tests under pinned Node **22.23.0**, API
typecheck/build, zero-error lint and clean diff checks. This is not deployed
evidence; exact deployed health/metrics proof remains open, and metrics stay
disabled until collector, bearer secret, alert owners and retention are
approved.

The exact Backend candidate also closes one local Socket.IO outage-amplification
path. The adapter previously configured both realtime clients with
`maxRetriesPerRequest: null` while retaining ioredis's default offline queue and
unfulfilled-command resend. A Redis outage could therefore retain an unbounded
number of ephemeral ride/job/call broadcasts in every API replica and replay
stale events after recovery; the upstream adapter also does not await ordinary
publish promises. The local correction disables the offline queue and
unfulfilled-command resend for both fixed-purpose realtime clients, caps
request retries at one, applies a five-second command timeout, observes
fire-and-forget publish rejection so it cannot become an unhandled process
rejection, and exports a label-free
`myshop_redis_realtime_publish_failures_total` counter. Focused evidence passes
**24/24** and the complete candidate passes **219/219 suites and
4,437/4,437 tests** under pinned Node **22.23.0**, plus API typecheck/build,
zero-error lint and clean diff checks. This is source containment only:
two-replica Redis-loss/recovery proof remains open, and it adds no capacity
credit. Programme progress remains **13/30 (43%)**.

The exact candidate's runtime-connection audit found that the shared database
package root
constructed and exported an implicit Prisma client every time any API module
imported a type or PostGIS helper. No current consumer used that singleton, and
its adapter did not open a pool until connected, but any access could have
created an unmanaged default PostgreSQL pool outside Nest shutdown, metrics and
the declared topology budget. The package root is now a connection-free barrel;
the only API database authority is the bounded Nest `PrismaService` pool. A
repository contract fixes the per-replica source model at one PostgreSQL pool
and three Redis connections: one command client plus the Socket.IO publisher
and subscriber. The topology validator now rejects a Redis per-instance count
other than three and a declared database pool above the runtime's hard
100-connection cap. Focused proof passes **5/5**; database/API typechecks and
builds pass; and the complete candidate passes **219/219 suites and
4,437/4,437 tests** under pinned Node **22.23.0**. Actual provider connection
counts, two-replica behavior and real dependency-fault proof remain open; no
capacity credit is added.

Exact Backend candidate `8cfe1f7…` contains the command-Redis successor
`8b31398…` under the same outage contract. It previously retained ioredis's offline queue,
unfulfilled-command
resend and unbounded command wait even though it is the authority for OTPs,
sessions, admission, leases and payment controls. The local correction disables
queueing and ambiguous resend, applies a five-second command timeout, caps
per-command retries at three and caps reconnect delay at two seconds. Bootstrap
allows transient connection errors to recover within a ten-second readiness
window, then fails closed with only a safe error class; shutdown falls back to
an immediate disconnect if graceful close cannot reach Redis. A permanent
source contract rejects direct blocking Redis consumers, which would be
incompatible with the command deadline. Focused connection contracts pass
as part of the combined **29/29** gate; the exact candidate passes **219/219
suites and 4,437/4,437 tests** in pinned Node **22.23.0**, API typecheck/build,
zero-error lint, diff checks and the Bash-capable Node 22 load boundary
**18/18**. This is not deployed or production-shaped fault evidence: real
Redis-loss/recovery, stale-write and client-recovery proof remain open, so
programme progress stays **13/30 (43%)**.

The follow-up rejection audit inventories all **268** Redis invocations made
through injected `RedisService` authorities, including the three
pipeline/stream constructors, and separately covers the command client's own
`ping`, `info` and `quit` promises. Every current promise is awaited, returned,
caught or handed immediately to a reviewed `Promise.allSettled` cache-cleanup
boundary; the stream and pipelines are consumed by `for await` or awaited
`exec`. One provider-location cleanup was simplified into a direct
`allSettled` expression so the rejection boundary is explicit. A permanent
type-aware source contract follows every variable/property typed
`RedisService`, so renaming the injected client cannot bypass the check.
The promise audit is part of the same committed exact candidate. The combined
focused proof passes **29/29** and the full pinned-Node result is **219/219
suites and 4,437/4,437 tests**.
This prevents a future fail-fast Redis rejection from being silently discarded
in source; it is not real process-outage evidence and adds no capacity credit.
The earlier uncommitted four-path extension on `237e879…` is superseded and
must not be promoted independently. Programme progress remains **13/30 (43%)**.

The separate “cadence jitter or adaptive backoff” row is an owner decision
hold, not a completion criterion: no jitter/backoff has been introduced and no
capacity credit depends on approving it.

**Current lane:** preserve the completed mobile source evidence, then close the
topology/observability inputs needed for a safe multi-replica load ladder. Do
not infer private provider settings. The next external facts required are the
current Render resource/replica settings, Redis provider/region/tier/limits/HA, Neon
compute/connection ceilings, and named alert/load/abort/release owners.

The current local backend checkpoint now has a strict secret-free topology
validator and intentionally incomplete capture template. It binds the exact
40-character release commit, target class and service name; rejects stale,
single-replica, cross-region, eviction, missing-HA/restore/metrics and
connection-budget evidence; and emits only bounded issue codes plus a
fingerprint. An official Neon documentation review corrected the initial
connection model before use: PgBouncer client capacity, the application
role/database server pool and PostgreSQL `max_connections` are now separate
schema-v2 budgets rather than incorrectly requiring the pooled-client ceiling
to fit below the PostgreSQL ceiling. A follow-up audit closed two fail-open
calculations: the validator now rejects an observed replica count below its
declared minimum, and Redis connection headroom uses the larger of modeled
per-replica demand and the observed provider connection count. Its
provider-neutral **10/10** focused tests pass on local Node 24. The capacity
wrapper must validate
that record before its first backlog snapshot or k6, and both manifests bind the
fingerprint. An execution-order regression exposed and fixed a non-executable
runner invocation; the complete load-harness boundary now passes **22/22** on
local Node 24; the topology, PostgreSQL/Redis exporter and owner-policy
contracts pass **30/30** together. The prior provider-neutral baseline passed
**28/28** in the Bash-capable pinned Node **22.23.1** image, but the two latest
regressions still require a repeat in that pinned runtime. This does not fill
in or approve any private topology fact and adds no completion credit.

The exact evidence-tooling provenance is now frozen instead of being left in the
mixed Backend workspace. Branch
`codex/pilot-stability-backend-capacity-evidence-only-rc` at `3edfec6…`
contains exactly **18 committed-only paths**, zero working or untracked paths,
directly above command-Redis base `8b31398…`; its inventory is
`9f7240c1e1b423b893eb05b9dc01952bccdbdd20c76a7a2182f7bd71c8ebec00`.
It passes **35/35** focused topology/exporter/capture/evaluator/wrapper tests,
forced dependency/API build, API typecheck, lint with zero errors and 52
existing warnings, formatting, shell syntax and diff checks on local Node 24.
The same 18-path unit was integrated above exact privacy candidate `4fdd52c…`
as `eb38971…`. It is retained by resource-budget successor `581265f…` and
current call-evidence successor `8cfe1f7…`, which has been fast-forwarded into
canonical local `codex/pilot-stability-backend-rc`. The complete successor is
clean at **257** production-base paths, inventory
`0119f0f9ed7d4bf16bda626aa427669d1d5be563da5378b7fd42ae776203b4ac`
and production-delta fingerprint
`7c6af9a09961d84f8eba1b0e246407be6c4e75e10d45b39493db8c7c51aaada6`.
Its exact pinned Node 22 evidence passes **219/219 suites and 4,453/4,453
tests**, API typecheck/build, **56/56** complete evidence/load contracts and
zero-error lint.
The candidate is not pushed, deployed or itself a capacity result.

A follow-up resource-budget audit found another fail-open condition: the
topology schema recorded API CPU/memory and Redis memory/command ceilings but
did not compare them with measured or modeled demand, and Neon PITR/compute
could pass without an approved minimum/headroom check. The five-path correction
is committed as `581265f…` directly above canonical predecessor `eb38971…` and
fast-forwarded into `codex/pilot-stability-backend-rc`. It upgrades the record
to schema v3 and requires observed API p95 CPU/memory, Redis memory and 24-hour
command peak, Neon 24-hour CU peak, separately owner-modeled target demand,
explicit headroom percentages and a minimum PITR duration. It always evaluates
the greater of observed and modeled demand, supplies no default threshold and
exposes the validator through one reviewed package command. The exact five-path
unit inventory is
`d3b78b6b5c005744cd8bbd682ff669ca8189d86b3c55f240c5c13bd7e1eda943`
and fingerprint
`76f8e0efa1d77b52e090526a8c7b96cca54f95a51bc963e01ca3ba2d79f8c7c2`.
The rebased exact successor passes **56/56** topology/exporter/capture/
evaluator/wrapper/load contracts on pinned Node **22.23.1**, formatting and
diff checks. It still requires owner review plus real private measurements and
approved thresholds and adds no completion credit.

The cross-replica call proof is committed as `8cfe1f7…` directly above
resource-budget predecessor `581265f…` and fast-forwarded into the canonical
Backend candidate. Its exact **11-path** unit has zero working/untracked paths,
inventory
`3851d7934a8ac1e4e596b7c2e623ec3b96ab858f42f2e25ebeb2d6dd5cb637c0`
and fingerprint
`0079fc4b5bb0e8fe4ea79aa2a7ea2de8fdf64207a36d1470276e7bc86c07b2f0`.
Its default-off, non-production-only replica probe is disclosed only to an
explicitly opted-in load socket; ordinary app sockets receive no probe. The k6
scenario proves exact peer role/account identity, acknowledgement binding to
one replica and at least one actual cross-replica signal. The gateway rejects
malformed call identifiers/types/data before authority lookup, permits
signalling only for ringing/accepted sessions, rejects terminal sessions and
fails closed when Redis session authority is unavailable. Call and chat now
surface that dependency failure without falsely claiming takeover. Exact
pinned-Node-22 evidence passes **8 focused suites / 90 tests**, the complete
evidence/load boundary **56/56**, and the full API **219/219 suites /
4,453/4,453 tests**, plus API build, typecheck, zero-error lint with 52 existing
warnings, formatting and diff checks.
This remains signalling-only source evidence: no real WebRTC/TURN media,
multi-device, carrier, multi-replica target or fault result was produced. It
does not implement the still-unapproved call-duration, one-non-terminal-call or
signalling-rate rules, is unpushed/undeployed and adds no capacity credit.

A realtime-ingress follow-up found two amplification bypasses without selecting
a new business threshold. WebSocket chat accepted almost the gateway's full
100 KB buffer even though the existing REST/Swagger contract limits a message
to 2,000 characters. Driver WebSocket GPS also bypassed the existing two-second
location-ingress ceiling and could execute the complete
PostgreSQL/Redis/eligibility pipeline for every packet. The Client's deliberate
ride-room recovery belt also re-emits a join every two seconds during matching,
and the server repeated participant database queries even when that exact
socket was already authorised in the room. Exactly **eight paths**—seven
working-only and one untracked integration test—above predecessor candidate
`581265f…` are isolated on
`codex/pilot-stability-backend-realtime-ingress-v2-rc`, inventory
`55127d938f80c3417a2d43b1656a0889b7d8b1aba9fa73068f956998801d39f1`.
Chat now shares the existing 2,000-character authority across REST and
WebSocket. Realtime GPS uses an atomic two-second Redis admission key separate
from the durable REST/batch path, so foreground traffic cannot suppress the
approved background writer. The same tranche replaces the active-trip
catch-up loop's maximum 120 sequential trail updates with one row-locked
endpoint read and one geometry update while preserving sample order, the
existing five-metre filter and accepted/ignored counts. For an active
`in_progress` ride, the current-location/session-sequence advance and
fare-bearing trail append now share one Prisma transaction: a trail failure
rolls back the consumed sequence and fails before Redis/cache/heartbeat
publication, allowing the retained mobile batch to retry. Both the locked
trail read and update recheck `in_progress`, preventing an old buffered fix
from being appended after completion or cancellation wins the row race. Idle,
accepted and en-route driver writes remain single-statement rather than
opening an interactive transaction for the idle population. Repeated ride/job room
joins now recheck the live role session but skip the duplicate participant
query; a reconnected socket has an empty room set and still takes the full
authorisation path. Fare-integrity review separately proved that only the
latest batch fix is constrained by the existing 50-metre online/matching
authority: an older buffered fix may report up to a 10-kilometre uncertainty
radius and still enter the fare/dispute-bearing `gps_trail`. The current
tranche deliberately preserves that released behavior until the owner approves
an accuracy and implausible-jump rule. Focused evidence passes **3 suites / 162
tests**; the exact API build, typecheck, **219/219 runnable suites /
4,448/4,448 runnable tests**,
zero-error lint with 52 existing warnings, formatting and diff checks pass on
local Node 24. The work is uncommitted/unpushed/undeployed and must be rebased
only onto current candidate `8cfe1f7…` before pinned Node 22 review; it adds no
capacity credit. A fail-closed disposable-local PostGIS integration suite now
four tests covering first-point geometry, ordered multi-point append, the
five-metre filter and terminal-ride refusal, but all four remain explicitly
skipped because no local PostGIS
service is available; they are not pass evidence. Cursor-
paginated chat history plus message/typing rates remain open because they
change client behavior or select new thresholds and require owner approval; a
green source gate is not real load evidence.

A follow-up backlog evaluator now makes the before/after snapshots
decision-bearing without inventing limits. Its private owner-approved policy is
bound to the exact run, release, topology, API, database and hashed Redis
namespace. Each of the 53 PostgreSQL workloads is pinned to the exact
measurement kind extracted from the reviewed aggregate query; all 57
PostgreSQL/Redis workload records require explicit count limits and only
durable-age workloads accept age limits. The wrapper validates the complete
policy before its first snapshot or k6, then verifies both snapshot digests,
capture timing and owner-approved drain limits afterward. Focused
exporter/evaluator tests pass **15/15** and the full load boundary remains
**22/22** on local Node 24 and Node 22.23.1. A follow-up caught and removed a differing
Redis-namespace hash formula between policy preflight and snapshot capture;
both now use one domain-separated helper, with exact regression coverage. The
final report also streams and fingerprints the exact scenario/run k6 result,
while a failed k6 execution retains after-state evidence but cannot produce a
ready evaluation. It must match the policy fingerprint emitted before the first
snapshot, preventing limits from being changed mid-run. No policy, threshold or
capacity result has been approved by this code, so progress remains **13/30
(43%)**.

## 1. Observed release baseline

| Surface            | Authoritative observation                                                                                                                                                                                                    | Consequence                                                                                                                                                                                         |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Production API     | Reverified 2026-07-23 GMT: both the canonical and direct Render domains return HTTP 200 from `/v1/health/ready`, with PostgreSQL and Redis `ok`; deployed commit remains backend `d918243cd7c6bda778fa54dec6ac0fdbe8140595`. | Production does **not** yet contain the follow-up maintenance/audit or scale hardening. `APP_VERSION` is also unset, so health reports `version=unknown`; commit remains the usable release marker. |
| Live service flags | Public server-owned reads return `maintenance_mode=false`, `rides_enabled=true`, and `artisan_jobs_enabled=true`.                                                                                                            | Rides and ordinary artisan jobs are open; changes to these flags remain controlled operational actions.                                                                                             |
| OTP policy         | The production API advertises SMS primary with WhatsApp fallback.                                                                                                                                                            | Delivery, callback, cost, provider-circuit and handset evidence still require monitoring; the channel advertisement alone is not delivery proof.                                                    |
| Admin              | `https://admin.myshop.gilmoretechnologiesgh.com/login` is live on Vercel deployment `dpl_6rNMmNbA97TPyvU4uURTg5tPLXMz`. Admin main is `30f2ed04cc03a3fa5cf20e4075368b9d67c4a7f3`.                                            | The audit-vault UI is deployed, but authenticated Super Admin acceptance and Product Owner 403 evidence are still required.                                                                         |
| Staging API        | Reverified 2026-07-23 GMT: `/v1/health/ready` is healthy at `myshop-api-test.onrender.com`, but it still serves backend `fed0d149…`, ten commits behind repository staging `4e100a9…`.                                       | It is not an exact-current load target and must not produce release/capacity evidence yet.                                                                                                          |
| Android client     | Owner-confirmed release build `1.4.1+24`, built from `main`; the official Play listing for `com.gilmoretech.myshopclient` serves marketing version `1.4.1`.                                                                  | The exact release SHA is not recorded and Play does not expose the build code publicly. Treat `+24` as owner-supplied release evidence; read Play Console before selecting the next code. |
| Android provider   | Owner-confirmed release build `1.4.1+24`, built from `main`; the official Play listing for `com.gilmoretech.myshopprovider` serves marketing version `1.4.1`.                                                                | The exact release SHA is not recorded. The listing mentions calling, but exact inclusion of mobile reliability commit `6fe3c70…` remains unproved until the release SHA or artifact provenance is recovered. |
| iOS client         | Owner-confirmed release build `1.4.1+24`, built from `main`; Apple's official Ghana lookup on 23 July still serves `1.3.9`, released 13 July, for bundle `com.gilmoretech.myshopclient`.                                      | The `+24` artifact/build exists according to the owner but is not yet the public App Store version. Do not force-update iOS users to it until Apple serves the reviewed build. |
| iOS provider       | Owner-confirmed release build `1.4.1+24`, built from `main`; Apple's official Ghana lookup on 23 July still serves `1.4.0`, released 13 July, for bundle `com.gilmoretech.myshopprovider`.                                    | The `+24` artifact/build exists according to the owner but is not yet the public App Store version. Do not force-update iOS providers to it until Apple serves the reviewed build. |

Public listing URLs:

- Android client: <https://play.google.com/store/apps/details?id=com.gilmoretech.myshopclient>
- Android provider: <https://play.google.com/store/apps/details?id=com.gilmoretech.myshopprovider>
- iOS client: <https://apps.apple.com/gh/app/myshop-akwaaba/id6773658114>
- iOS provider: <https://apps.apple.com/gh/app/myshop-provider/id6773660049>

Local artifact/reflog evidence must not fill the Play Console gap. The `+22`
Android bundles were created immediately after local branch `4e5cb28…`; the
`+23` bundles were created immediately after local `main` reached `f2556ea…`.
Neither generation embeds a source-commit marker. The `+22` manifests still
declare `USE_FULL_SCREEN_INTENT`; the `+23` manifests do not. These facts
distinguish the local files but do not prove which build Play currently serves.
Repository `main` `61241f8…` is dated 22 July, after the listing's 21 July
update, and is therefore only the current Git comparison head—not an exact
public-artifact source.

## 2. Source reconciliation after outside changes

All three local worktrees were clean before this roadmap branch was created.
No uncommitted outside work was overwritten.

| Repository | Main       | Staging    | Reconciled state                                                                                                                                                                           |
| ---------- | ---------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Backend    | `d918243…` | `4e100a9…` | PR #116 is merged only to staging. It adds exact Admin/deployment access during maintenance, strict legal-hold input, authenticated-role telemetry identity and CSV formula containment.   |
| Mobile     | `61241f8…` | `bd63907…` | PR #92 is merged only to staging. It restores privacy-safe audit telemetry and binds future artifacts to an exact clean main SHA with build `24` or higher than both store-console maxima. |
| Admin      | `30f2ed0…` | `b4bebb5…` | Audit Vault is already merged to main and publicly deployed. The main and staging trees contain the same feature content through different merge commits.                                  |

Current local hardening checkpoint (not pushed or deployed):

| Repository | Local branch/state                                                                                  | Verified milestone                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | Relationship to reconciled staging                                                                                                                                       |
| ---------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Backend    | `codex/scale-worker-bounds` through `a5079a1`, plus uncommitted evidence and clean-replay hardening | Bounded scheduled workers, the transactional marketplace-notification outbox and a hard-bounded daily settlement fetch pass the exact pinned-Node-22 build, full API test and lint gates. Every one of the 36 active cron entry points now has an exact observable deployment-wide owner in addition to its durable row/state authority; all 36 map to aggregate capacity evidence covering 53 durable-workload/index states and 48 planner checks. The latest pinned Node 22.23 gate passes 218/218 suites and 4,418/4,418 tests, builds and typechecks. The guarded exact-role fixture provisioner, explicit synthetic-route isolation and private runner boundary pass 18/18 contracts locally and under pinned Node 22. A local Node 24 follow-up raises the current boundary to 22/22 by binding owner-only PostgreSQL/Redis before/after snapshots to one run, release, API target, database/schema and hashed Redis namespace without exposing either connection to k6, and by proving cross-replica call evidence integrity; pinned Node 22 and real isolated-service proof remain open. The current full API gate passes 218/218 suites and 4,468/4,468 tests. A fresh disposable PostgreSQL/Redis clone completed live preflight and k6 1.3.0 smoke at 9/9 checks, 0/7 failed HTTP requests and p99 133.23 ms. The owner-gated monitoring increment adds explicit Blueprint metrics controls and 15 rehearsal alerts validated by official Prometheus 3.12.0. All 36 active cron cadences are now source-bound to exported expected-interval metrics; deterministic promtool cases prove stale/first-success and per-replica Redis behavior, while cadence/metrics contracts pass 20/20 under pinned Node 22. Neither increment is deployed or capacity evidence. A new lexically ordered, catalog-guarded precondition now fixes the first historical empty-database replay defect without changing the deployed legacy migration checksum; its migration compatibility contract passes 539/539 on Node 24. A real full replay and the later exact-Super-Administrator bootstrap procedure remain open. | Based directly on `4e100a987602415516fb619b32af5af8cd27e2f0`; the exporter/wrapper, clean-replay and realtime increments remain local and unreviewed                     |
| Mobile     | `codex/mobile-poll-backpressure` through `55d7823`                                                  | Mobile backpressure and the current scale/release evidence are based directly on repository staging. The release guard passes its version contract and correctly refuses this feature branch because only a clean exact `origin/main` SHA may produce store artifacts. Local production configuration validates for all four app/platform targets. The Apple Distribution identity and App Store profiles for both apps plus all three provider extensions are present and valid through July 2027, so the historical missing-signing-identity blocker is no longer current. The iOS export path now preserves the operator-selected build number, includes available symbols, prefers Apple's matching rsync implementation, and post-verifies archive UUID coverage. Existing `+23` archives prove app-owned coverage across 39 client and 40 provider binaries but expose four exact precompiled-vendor gaps per app: MapboxCommon, MapboxCoreMaps, WebRTC and objective_c. No new release artifact has been built.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | Based directly on `bd6390727ec2a6c5e8bf4dc4d5512433b992e18e`; the scale/release increment remains local and unreviewed                                                   |
| Admin      | `feat/system-audit`, plus uncommitted support and log-containment guards                            | The System Audit feature remains at `e6b6ab5d326aa90c8d6821dc5106940691787c48`. The current local increment replaces malformed support destinations with the owner-approved values, bounds the exact 12-call production console inventory and removes a tracked GitHub credential from repository tooling. The combined focused gate passes 42/42 tests; TypeScript, zero-error lint, the 48-route production build and diff check pass.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | The corrections are local and unreviewed; the exposed token still requires revocation and history review, and no dashboard, log sink or production configuration changed |

The backend table's earlier `539/539`/replay-open sentence is superseded by the
latest source evidence: bootstrap guards pass **5/5**, migration compatibility
passes **542/542**, and a disposable localhost PostgreSQL database applied all
**267 migrations** with Prisma up to date, the private staging schema removed,
one exact active Super Admin and five initial System Audit events. Full
pinned-Node-22 login/restore rehearsal is deferred to the next DR phase.

The same local support-contact correction now pins
`support@gilmoretechnologiesgh.com` in both mobile apps, the backend clean seed,
email templates/reply-to default and Admin settings, and pins
`+233(0)204962227` in the clean seed and Admin settings. A bounded read-only
preflight reports only a mismatch count and blocks release-ready mode when the
live `platform_config` values are absent or different. Backend gates pass
**218/218 suites and 4,432/4,432 tests**, Provider analysis plus **176/176**
tests pass, and the Admin focused contract, TypeScript, lint and production build
pass. This is source evidence only: the deployed database values, Render
`EMAIL_REPLY_TO`, attended mailbox and physical recovery/ticket journeys remain
unverified, so no completion criterion or capacity credit is added.

The Admin dashboard production-log inventory now covers all **12** console
calls across the exact **7** production files that contain them. The permanent
contract permits only warning/error output with reviewed static labels,
aggregate counts, bounded status/code values, opaque support references and a
fixed generic error kind; it rejects raw errors, mutable exception fields,
URLs, phone/token/payload fields and unreviewed interpolation. The three
remaining mutable `Error.name` paths in the API wrapper, PDF proxy and SMS
route now emit the fixed class `Error`. The complete focused Admin gate passes
**42/42 tests**; TypeScript passes, lint reports **0 errors / 99 existing
warnings**, the full **48-route** production build passes and `git diff --check`
is clean. This remains local source containment: no browser, log sink,
dashboard, account, provider or deployment was contacted, and deployed
access/retention/redaction plus operational ownership remain open. Programme
progress therefore remains **13/30 (43%)**.

The crash/credential follow-up found no Crashlytics, Firebase Analytics or
other reviewed crash/analytics SDK in either mobile dependency graph, and both
Firebase configurations explicitly disable Analytics. The app-owned iOS
privacy manifests nevertheless declared Crash Data and the client named
Crashlytics; both manifests now describe the actual no-crash-SDK artifact. A
permanent contract blocks unapproved crash/analytics dependencies, requires
Analytics to remain disabled and checks both privacy manifests. It also found a
literal GitHub personal access token tracked in the mobile and Admin MCP
configs, with history dating to April 2026. The current files now inherit
credentials only from the host environment, never the repository, and both
repositories reject a reintroduced token. Mobile privacy/log evidence passes
**9/9 focused tests** and the complete API-client suite passes **170/170**;
analysis and both plist validations pass. Admin’s combined focused gate passes
**42/42**. This is containment only: immediately revoke the exposed token,
review GitHub activity since first exposure, issue a least-privilege
replacement outside the repositories and enable secret scanning/push
protection. Privacy-safe crash incident reporting remains absent and requires a
separately approved provider, data fields, sampling, retention, access,
deletion and incident-owner design. Programme progress remains **13/30 (43%)**.

An Audit Vault acceptance source pass found two independent consistency defects
without changing its owner-approved access or retention rules. The dashboard
labels its window as GMT but previously let `datetime-local` parse in the
administrator device timezone, shifting the requested range outside GMT. A
three-path Admin extension above exact candidate `16305f6…` now parses and
renders the fields explicitly as UTC, rejects malformed/calendar-normalised
values and labels both controls GMT. Because the current backend verifier
recomputes only independent row hashes, the dashboard now says
“append-only evidence”, “row hashes” and “row hash status” instead of claiming
full immutability or tamper status. It is isolated on
`codex/pilot-stability-admin-audit-vault-rc`, inventory
`1ff3aa4b30eb57b50f85fc96a97ea08e2f9da1da6c7f23346d8773135622dbfc`.
Its exact GMT/evidence-copy tests pass **4/4**; all Admin source tests pass **46/46** and
TypeScript, changed-file lint and diff checks pass. The production build could
not complete because this environment was denied access to the two required
Google Font downloads; this is recorded as missing evidence, not a source
failure or a pass.

The backend separately committed legal-hold and alert-acknowledgement mutations
before inserting their immutable evidence, so an audit-database failure could
return 503 after governance state had already changed. A four-path extension
directly above exact backend candidate `8cfe1f7…` now creates each mutation and
its immutable ledger row in the same Prisma transaction, rolling both back when
evidence cannot be secured; secondary alert delivery remains best effort only
after commit. It is isolated on
`codex/pilot-stability-backend-audit-vault-rc`, inventory
`986d9c23be76063010427f7d8c5f196f350a65a61aad01b3c545cc500d48a40f`.
Focused exact-Super-Admin/governance evidence passes **3 suites / 18 tests**,
and the complete local-Node-24 API passes **219/219 suites and 4,457/4,457
tests**, typecheck, build, changed-file lint, formatting and diff checks. Both
extensions are working-only, uncommitted, unpushed and undeployed. Authenticated
timeline/filter/pagination/export/legal-hold/integrity acceptance and explicit
Product Owner 403 remain live gates. The current full-table, row-local SHA-256
verifier is also not a 100k-DAU tamper-evidence design: it is unbounded, has no
hash chain or externally retained anchor, and cannot prove deletion or
completeness. Replace it with an owner-reviewed bounded/asynchronous
verification and external anchoring design before claiming tamper evidence.
No completion or capacity credit is added and programme progress remains
**13/30 (43%)**.

## 3. Next production update — do before scale claims

- [ ] Revoke the GitHub personal access token exposed in mobile/Admin history,
      review organisation/repository/token activity since April 2026, remove
      unauthorised access, issue a least-privilege replacement outside Git and
      enable secret scanning/push protection. Current-file removal alone is not
      revocation.
- [ ] Approve and apply the conservative Client/Provider store descriptions in
      `store-listing-v1.4.1-corrections.md` to both stores. Apple currently
      advertises disabled or unapproved claims including trip recording,
      instant payout, a 24-hour verification SLA and guaranteed verification.
      Local Client/Provider copy no longer claims national-database checks or a
      24-hour manual-review/response SLA; focused tests and both fatal-info
      analyzers pass. Keep the approved 24-hour dispute filing window.
- [ ] Review exact backend candidate `8cfe1f7…`, based directly on live
      `d918243…`; do not merge the divergent or dirty staging workspace. Before
      promotion, run the aggregate scheduled-work diagnostic and obtain an owner
      decision for any already accepted `confirmed` job that is past its
      configured no-show deadline, then replay the candidate's pending migrations
      on a disposable production-shaped clone. Promote only the reviewed SHA,
      manually deploy that recorded SHA, and prove health plus signed deployment
      evidence. Before release-ready preflight, set the live `support_email` and
      `support_phone` to the owner-approved values and verify Render
      `EMAIL_REPLY_TO` uses the same mailbox; the preflight must report zero
      mismatches.
- [ ] Review the isolated 18-path capacity-evidence unit `3edfec6…` and its
      integration `eb38971…` above privacy successor `4fdd52c…`, retained by
      exact successor `8cfe1f7…`. Confirm
      the recorded inventories and lineage before using the tooling; then repeat
      the corrected boundary on pinned Node 22 and use it only with approved
      private topology, traffic/backlog limits and named owners. Do not treat a
      green harness as proof that the real system supports the target load.
- [ ] Review exact five-path schema-v3 resource-budget predecessor `581265f…`,
      retained by current candidate `8cfe1f7…`.
      Supply real API CPU/memory, Redis memory/command and Neon
      compute/PITR measurements plus independently approved modeled demand and
      headroom values; do not invent them from a plan name or the validator's
      passing fixtures.
- [ ] Review exact 11-path cross-replica call-evidence commit `8cfe1f7…`
      above `581265f…`; its complete pinned Node 22 gates pass. Keep the
      load-only replica probe unreachable to ordinary app sockets. Then prove
      100→250→500 real Android/iOS WebRTC calls, TURN analytics, replica faults,
      reconciliation and rollback on the isolated production-shaped target;
      never describe the signalling harness as media-capacity evidence.
- [ ] Review the exact eight-path realtime-ingress tranche above `581265f…`,
      rebase it only onto `8cfe1f7…`, and repeat it on pinned Node 22 plus a
      disposable PostgreSQL/PostGIS geometry gate. Approve buffered-fix
      accuracy/implausible-jump handling, the chat-history pagination contract
      and explicit message/typing limits before implementing them; then include
      chat and foreground/background GPS in the multi-replica load, backlog,
      Redis-fault and installed-device evidence.
- [ ] Complete authenticated Super Admin Audit Vault acceptance: timeline,
      filters/pagination, mobile activity, CSV/JSON, legal hold, integrity and
      Product Owner 403. First review the isolated three-path Admin GMT-window
      extension above `16305f6…` and the four-path backend atomic-governance
      extension above `8cfe1f7…`; rerun the Admin production build with its
      required font access and the backend gate on pinned Node 22 before
      promotion.
- [ ] Obtain the real Data Protection Commission registration number. Publish a
      new immutable Privacy version; never mutate accepted `1.4.1` content.
- [ ] Read the highest private build codes from both Play Console and App Store
      Connect. Promote reviewed mobile staging to main and build all four
      artifacts from one clean explicit main SHA using codes above every
      maximum. Require the package-provenance verifier to pass; never promote
      the historical `+23` set or lone Provider `+24` APK.
- [ ] Rebuild both iOS archives with the now-available Apple Distribution
      identity and valid App Store profiles. Prove the Apple-rsync export fix,
      archive/IPA identity, exact source marker, app-owned dSYM coverage and
      Transporter validation. Obtain matching vendor dSYMs from Mapbox,
      flutter-webrtc and Dart `objective_c`, or retain the exact
      crash-symbolication limitation as an explicitly accepted release risk;
      never fabricate empty dSYMs merely to silence App Store warnings.
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

The owner has already approved the pilot in-app call ladder of **100 → 250 →
500 simultaneous accepted calls**. The existing load contract maps that to
200/500/1,000 unique role sessions and a ten-minute signalling hold, with the
last completely passing and reconciled level becoming the temporary pilot cap.
This closes the call target decision only; it is not a substitute for the
remaining whole-platform traffic inputs above.

A follow-up fail-closed call-evidence increment now prevents two false-positive
paths in that ladder. It accepts only unique probes from the exact peer role
account and rejects malformed, duplicate or wrongly scoped relays. On an
isolated staging/disposable-clone target, an explicit production-forbidden flag
adds an ephemeral opaque process UUID to load-probe acknowledgements and
signals only for sockets that explicitly opt in through the load handshake;
ordinary app sockets receive no probe. k6 requires at least one delivery whose
sender and receiver UUIDs differ. A passing result therefore proves an actual
cross-replica Socket.IO Redis-adapter relay rather than inferring it from a
configured replica count. A later call-path audit also
made malformed call IDs/types/data fail before authentication or Redis access,
reserved synthetic renegotiation for opted-in load sockets, and forbids relays
after decline/end/expiry while preserving ringing and accepted calls. Call and
chat also report unavailable session authority without falsely claiming
takeover. The exact 11-path unit is committed as `8cfe1f7…`; pinned Node
**22.23.1** passes **8 focused suites / 90 tests**, **56/56** complete
evidence/load contracts and the full **219/219 suites / 4,453/4,453 tests**,
plus build/typecheck, zero-error lint, formatting and diff checks. The real
call ladder remains open.

A subsequent chat/location audit now rejects malformed booking, message, GPS
and room identifiers before session, Redis or database work; prevents
delimiter-based room injection; enforces the REST-equivalent 2,000-character
chat ceiling; rechecks exact-session authority after asynchronous work; and
contains unexpected persistence failures behind stable public WebSocket
errors. Redis session-authority outages remain fail-closed but now report
`SESSION_AUTHORITY_UNAVAILABLE` rather than falsely claiming a takeover or
invalid token. Realtime and location workers no longer log raw connection,
account, booking, call, message, ride/job or provider identifiers on the
audited paths. The complete communication/location/WebSocket/privacy gate
passes **23/23 suites and 364/364 tests**; the full API passes **218/218 suites
and 4,468/4,468 tests**, build, typecheck, lint with zero errors and 52 existing
warnings, formatting and diff checks on local Node 24. This is source
containment only; pinned Node 22, installed-device, multi-replica/fault and
rate/burst evidence remain open, so no capacity credit was added.

A bounded notification/OTP follow-up removes recipient/account, phone fragment,
delivery-correlation, provider-message, push/VoIP token and offer/request IDs
from audited carrier, callback, push, Live Activity, preview and revocation
logs. Operational logs retain only bounded channel, role, platform, event type,
status, latency, count, HTTP/provider code and error class. The regression
contract now covers those production files; focused evidence passes **17/17
suites and 252/252 tests**, and the full API remains **218/218 suites and
4,468/4,468 tests** with build, typecheck, zero-error lint and diff checks on
local Node 24. Admin, support, ride/matching, authentication/session and
recovery logging still require the same sweep, so the
privacy programme and overall 13/30 score remain open.

A third bounded financial-telemetry pass removes raw and masked user, provider,
payment, booking, dispute, refund, payout, clawback, tip, recipient, account,
gateway-reference, idempotency-key and source-IP identifiers from every
production log call in the payment module. Operational logs retain only bounded
booking/provider type, payment/gateway status, retry/record counts, HTTP/provider
codes and safe error class; the existing durable database audit, outbox,
reconciliation and financial state remain unchanged. The privacy contract now
scans the entire payment module. Focused payment/privacy evidence passes **28/28
suites and 685/685 tests**; the full API passes **218/218 suites and
4,468/4,468 tests**, build, typecheck, lint with zero errors and 52 existing
warnings, and diff checks on local Node 24. This is source containment only:
pinned Node 22, deployed-log retention/access/redaction, live gateway
reconciliation and the remaining repository log slices are open, so no
programme credit was added.

A fourth bounded identity-verification pass removes document, provider,
vehicle, client, Smile job and lifecycle-event identifiers plus raw rejected
promise reasons from the verification, Smile adapter, provider-session and
provider-document worker logs. It also stops logging provider-controlled KYC
failure text/codes while retaining bounded provider type, document/event type,
version, attempt count and safe error class. This does not enable SmileKYC for
v1 or change manual review, independent document approval, Coordinator/RM
authority, expiry, replacement or active-work rules. Focused
verification/provider/privacy evidence passes **13/13 suites and 190/190
tests**; the full API passes **218/218 suites and 4,468/4,468 tests**, build,
typecheck and lint with zero errors and 52 existing warnings on local Node 24.
Pinned Node 22, private-store/provider callback, deployed-log and remaining
repository telemetry evidence are still absent, so no programme credit was
added.

A fifth bounded authentication/session/recovery pass removes full and masked
phone values, private auth/account/admin IDs, carrier message IDs, recovery-row
IDs, device IDs, source IPs and refresh-token/session/JTI prefixes from the
audited authentication logs. Refresh diagnostics retain only the bounded
failure branch, role, elapsed time, safe error class and non-identifying
booleans; exact session and recovery authority remains in Redis/PostgreSQL and
the durable System Audit rather than the log sink. OTP delivery modes, carrier
selection, caps, sibling-role coexistence, exact-role revocation, the 90-day
role-recovery rules and reviewer containment are unchanged. The privacy
contract now scans every production authentication file and forbids masked or
truncated identifiers. Focused authentication/privacy evidence passes **16/16
suites and 263/263 tests**; the full API passes **218/218 suites and
4,468/4,468 tests**, build, typecheck, lint with zero errors and 52 existing
warnings, formatting and diff checks on local Node 24. Admin, support/ticket
and ride/matching telemetry, pinned Node 22, deployed-log access/retention and
real carrier/session-recovery evidence remain open, so no programme credit was
added.

A sixth bounded support-telemetry pass removes ticket, user and notification
target identifiers from support ticket creation, status-change and message
delivery logs. It also replaces raw exception classification with the shared
safe error-kind helper. Operational output retains only the bounded owner role,
ticket category and notification event outcome; ticket ownership, messages,
attachments, assignment and status history remain in their durable
PostgreSQL/notification records. Focused support/privacy evidence passes **4/4
suites and 19/19 tests**; the full API passes **218/218 suites and 4,468/4,468
tests**, build, typecheck, changed-file lint with zero errors, formatting and
diff checks on local Node 24. Admin and ride/matching telemetry, pinned Node 22,
deployed-log access/retention and real support-operator acceptance remain open,
so no programme credit was added.

A seventh bounded Admin-telemetry pass removes administrator, user, provider,
vehicle, document, bid, job, ride, payment, payout, emergency, welfare,
recovery-operation and clawback identifiers plus free-text reasons/titles and
financial values from Admin runtime logs. Operational output retains only
bounded action, provider/document type, review status/stage, role, mode,
notification outcome, aggregate counts and safe error/SQLSTATE class. The exact
actors, targets, reasons, changes, IPs and financial decisions remain in the
existing durable audit/System Audit and business records; Super Admin authority,
regional/category scope and Coordinator→RM verification behavior are unchanged.
The privacy contract now scans every production Admin file and explicitly
forbids free-text reason/title and amount fields. Focused Admin/privacy evidence
passes **20/20 suites and 492/492 tests**; the full API passes **218/218 suites
and 4,468/4,468 tests**, build, typecheck, lint with zero errors and 52 existing
warnings, formatting and diff checks on local Node 24. Ride/matching telemetry,
pinned Node 22, deployed-log access/retention and authenticated Admin acceptance
remain open, so no programme credit was added.

An eighth bounded ride and marketplace telemetry pass removes exact ride, job,
client, driver, artisan, bid, offer, category, document and welfare identifiers;
exact coordinates and address/category labels; free-text cancellation,
administrative and supplement reasons; financial values; and provider/runtime
error content from every production logger call in both modules. Operational
output retains only bounded lifecycle/status transitions, actor role, radius,
candidate/recipient/stage counts, booleans and the shared safe error class.
PostgreSQL offer, receipt, cancellation, dispute, payment, audit and lifecycle
authority; Redis delivery state; the per-driver 45-second sequential offer
rule; the ten-second receipt rule; artisan capacity; active-trip fallback;
cancellation consequences; and Coordinator/RM rules are unchanged. The privacy
contract now scans both complete production modules. Focused
ride/marketplace/privacy evidence passes **42/42 suites and 826/826 tests**; the
full API passes **218/218 suites and 4,468/4,468 tests**, build, typecheck, lint
with zero errors and 52 existing warnings, formatting and diff checks on local
Node 24. The named high-risk source slices are now covered. Pinned Node 22,
deployed-log access/retention/redaction, real device and multi-replica/fault
evidence remain open, so programme progress stays **13/30 (43%)**.

A ninth and final source-telemetry pass expands the privacy contract from named
high-risk slices to every production module and every logger-bearing shared
runtime/configuration file. It also verifies that production source contains no
direct console logger or static `Logger` escape path. Residual identifiers and
private values were removed from rewards, referrals, promotions, ratings,
emergency recording, object-storage, Redis, configuration and call-adapter
telemetry. The only retained opaque support references are in the deliberately
correlated HTTP error path, which has dedicated correlation/privacy tests.
Focused residual/privacy evidence passes **20/20 suites and 673/673 tests**; the
full API passes **218/218 suites and 4,468/4,468 tests**, build, typecheck, lint
with zero errors and 52 existing warnings, formatting and diff checks on local
Node 24. This completes the repository-wide production source inventory, not
the operational privacy criterion: pinned Node 22, deployed-log
access/retention/redaction, provider-key rotation/restriction, named ownership
and real device/multi-replica/fault evidence remain open. Programme progress
therefore stays **13/30 (43%)**.

A follow-up runtime gate rebuilt the exact current backend worktree with the
reviewed Docker base image and repository-pinned **Node 22.23.0** runtime.
Prisma client generation, every prerequisite package build and the API build
passed inside that image. A final read-only-source test run passed **218/218
suites and 4,468/4,468 tests**; API typecheck passed; lint passed with zero
errors and the same 52 existing warnings. Earlier diagnostic attempts that
omitted test files or repository-root fixtures were rejected and are not
counted as evidence. This closes the local pinned-runtime backend gate only. It
does not prove deployed privacy controls, production capacity or durability;
the exact isolated topology still needs the
100→250→500→soak→fault→reconciliation→alerts→rollback run. Programme progress
therefore remains **13/30 (43%)**.

A mobile device-log audit then found **715 eager Dart diagnostics across 96
production files**, including API/provider errors, URLs, payload keys, IDs and
call/ride/job state. Two direct `print` paths and one shared-UI audio-error path
were removed; the remaining **712 diagnostics across 94 files** now pass their
message as a lazy callback through one compile-time debug-only boundary.
Profile/release isolates neither emit nor construct those strings, and both app
entry points plus both FCM background entry points install the process-wide
Flutter diagnostic suppression before logging. All direct `dart:developer`,
`debugPrint` and `print` bypasses are contract-forbidden. The native sweep also
removed CallKit call IDs, Live Activity request/action IDs and localized
platform errors from both iOS AppDelegates; app-owned iOS diagnostics are
debug-only and static, and app-owned Android code has no direct logger. The
privacy/native contract passes **5/5**; the complete API-client, client and
provider suites pass **165 + 96 + 176 = 437 tests**; all three fatal-info
analyzers, both Swift parses, formatting and diff checks pass. A full Xcode
Simulator build could not start because the sandbox could not connect to
CoreSimulator, so archive compilation, installed release-device log inspection
and privacy-safe crash telemetry remain open. No device, service, account,
provider or deployment was contacted, and progress stays **13/30 (43%)**.

### Phase B — production-shaped topology

- [ ] Confirm the actual Render production plan, CPU/RAM, instance count and
      whether autoscaling or a manual warm-capacity procedure is available.
      Exact Backend candidate `8cfe1f7…` removes the repository's unsafe
      `plan: free` request and retains the existing dashboard-selected plan and
      replica count, but those private values are not externally observable.
      Also record whether a persistent disk is attached and confirm the
      candidate's effective 60-second shutdown delay. Render does not permit
      multi-instance scaling with an attached persistent disk.
- [ ] Run at least two same-region API instances before claiming replica fault
      tolerance. Preserve Socket.IO Redis-adapter authority and graceful drain.
      Local source enables Nest shutdown hooks, marks readiness draining, closes
      Socket.IO Redis, command Redis and PostgreSQL, and the runtime-image probe
      exits within 15 seconds when idle. The Blueprint now explicitly grants a
      60-second Render shutdown delay and contains no persistent disk. This is
      source eligibility only: prove active HTTP/Socket.IO/call/location traffic,
      scheduled-work lease recovery and zero lost committed work while one
      replica is terminated.
- [ ] Confirm the current Redis region, tier, memory limit, HA/failover, backups,
      TLS, exact prefixes and `noeviction`. The last owner-reported Redis region
      was Cape Town while API/PostgreSQL are Frankfurt; reverify rather than
      assuming it is unchanged. The 2026-07-22 production readiness result on
      deployed commit `d918243` proves that a non-empty deployed prefix, TLS and
      `noeviction` pass the runtime contract; it does **not** reveal region,
      tier, memory, HA, backups, connection headroom or the prefix value.
      Cross-region Redis is not an approved 100k-DAU topology.
- [ ] Budget PostgreSQL connections across every API/worker replica. Code
      defaults to pool min `2`, max `10` **per process**; the deployed overrides
      and Neon compute/connection limits must be recorded before scaling replicas.
      The current local telemetry checkpoint validates both bounds, owns the
      underlying `pg` pool explicitly and exports live total/idle/active/waiting
      plus min/max metrics from every process. This closes the source-level
      visibility gap, not the production-shaped sizing gate.
- [ ] Prove database recovery on an isolated production-shaped restore and
      establish a reviewed bootstrap/baseline procedure for a truly empty
      database. A fresh chronological replay exposed two historical
      preconditions: the production-applied
      `20260615000000_ride_max_broadcast_drivers_config` migration precedes the
      later `updated_at` default that made it succeed in production, and the
      System Audit migration intentionally requires the exact active bootstrap
      Super Administrator. The local
      `20260614990000_platform_config_updated_at_precondition` correction is
      deliberately ordered before the immutable legacy insert, adds the missing
      default only when absent, is a catalog-only no-op where the later default
      already exists, and fails on any unexpected default. The legacy migration
      remains byte-identical with its SHA-256 pinned; migration compatibility
      passes 539/539 and the complete API gate passes 218/218 suites and
      4,426/4,426 tests on local Node 24. This closes source ordering only.
      Current pinned-Node-22 proof, a complete disposable PostgreSQL replay,
      restore/recovery evidence and production disaster-recovery approval remain
      required. A local rehearsal-only preparer now refuses every non-empty,
      pooled, non-TLS remote, non-public or non-disposable target; reads the
      approved password twice from a hidden TTY; stages only a parameterized
      bcrypt-cost-12 hash; and logs no credential. Ordered migration
      `20260721990000_exact_super_admin_empty_bootstrap` consumes and drops it
      only while every admin/role-account table is empty, then lets the immutable
      System Audit migration record/protect the exact identity. Existing
      environments are no-ops. Guard tests pass 5/5 and migration compatibility
      passes 542/542 on local Node 24. A disposable localhost PostgreSQL replay
      then applied all 267 migrations; `prisma migrate status` reports up to
      date, the private bootstrap schema is absent, exactly one active approved
      Super Administrator exists and System Audit initialization contains five
      events. No staging or production database was contacted. The full
      pinned-Node-22 login/Audit-Vault/restore rehearsal remains next-phase
      disaster-recovery work. Do not edit either applied migration or manually
      alter production history to make a synthetic empty replay pass.
- [ ] Separate or explicitly capacity-budget scheduled/outbox workers. The API
      currently hosts scheduled work and does not use an external broker.
- [ ] Configure external metrics, alerts, log retention/redaction, paging and
      named owners before fault tests.
      The local telemetry checkpoint now exposes readiness and pending commands
      separately for the command, Socket.IO publisher and Socket.IO subscriber
      Redis clients, and every deployment-wide worker lease must use one of 22
      exact reviewed metric names. Provider-side Redis memory, connection,
      latency and eviction metrics and actual alert delivery remain unproven.
      Production returned HTTP 404 from the deployed `/v1/metrics` endpoint on
      2026-07-23, which proves metrics are currently disabled. Local backend
      `a5079a1` adds explicit opt-in Blueprint variables plus 15
      `owner_approval_required` Prometheus rehearsal alerts for replica/build,
      HTTP, dependency, pool, Redis, worker, audit, TURN and event-loop signals.
      All 36 active worker cadences are source-bound to exported expected
      intervals; the 15th rule alerts after three missed executions and covers
      absence of a first success. Official Prometheus 3.12.0 validates all 15
      rules and its deterministic stale/recent/per-replica cases pass; cadence
      and metrics contracts pass 20/20 under pinned Node 22. This does not
      configure a collector, recipient, provider dashboard, retention or
      production alert. Per-worker **backlog** rules still require the approved
      workload model and deployed runtime evidence. Local one-shot PostgreSQL
      and Redis exporters now cover the exact 53-workload aggregate diagnostic
      plus the four Redis-only disconnection/insufficient-balance queues. They
      validate fixed cardinality, enforce TLS and explicit target authority,
      and atomically publish count/real-age-authority gauges for one monitoring
      textfile collector without reading Redis members. Focused safety tests
      pass 12/12 on local Node 24; the complete local API gate passes 218/218
      suites and 4,426/4,426 tests, with API/database build and typecheck clean.
      A paired wrapper now runs both collectors before and after one load run,
      binds each owner-only manifest to the run ID, release/API/database/hashed
      Redis namespace, validated topology fingerprint and snapshot digests, and
      preserves the k6 credential boundary. The topology gate requires an
      owner-only, secret-free record for the exact target class, service and
      40-character release before the first snapshot or load action. Its
      focused validator passes 8/8 and the current load-harness contract passes
      22/22 locally on Node 24 and in the Bash-capable Node 22.23.1 image. The
      prior combined topology/exporter/evaluator gate passes 27/27 under Node
      22; the provider-neutral topology/exporter/evaluator increment passes
      28/28 in the Bash-capable pinned Node 22.23.1 image. They are not
      deployed, isolated-service evidence is still required, and no cadence or
      backlog threshold has been approved.

#### Dashboard capture and proposed rehearsal baseline

Private dashboard access was unavailable to this audit session on 2026-07-23.
The following facts therefore remain **unknown**, even where a repository or
historical value exists. Record values without secrets or endpoints:

| Provider       | Required current fact                                                                                                                                                                                                                 | Current evidence                                                                                                                                                                                                                                                   |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Render         | workspace plan; `myshop-api` instance type, CPU/RAM, Frankfurt region, instance count; attached persistent disk; manual/autoscaling configuration; effective shutdown delay and deploy/drain settings                                 | Public health proves one healthy release marker only. Repository Blueprint says `free`, no disk and a 60-second shutdown delay, but dashboard overrides cannot be ruled out.                                                                                       |
| Redis provider | provider and database/instance type; plan; primary/read regions; command/s, memory/data/connection/bandwidth limits; budget/rate-limit behavior; Redis `maxmemory-policy`; TLS; replication/multi-zone HA; backups and metrics access | Runtime readiness on the observed deployment proves that Redis reported `maxmemory-policy=noeviction` at startup. The last owner report placed the earlier store in Cape Town; the current provider, dashboard region, plan, durability and limits are unverified. |
| Neon           | production plan, Frankfurt branch/compute, minimum/maximum CU, scale-to-zero, pooled/direct connection limits, current connection use, working-set/cache hit, storage/WAL/PITR/restore limits                                         | The API reports PostgreSQL healthy and source uses a pooled application URL. No capacity or recovery limit is publicly observable.                                                                                                                                 |

Recommended **starting point for measurement**, not an approved purchase or a
final 100k-DAU size:

- two Render `Standard` web instances in Frankfurt (each 1 CPU/2 GB) with the
  existing readiness path and manual scaling; choose autoscaling only after the
  owner confirms a Pro workspace and approves its min/max and spend;
- one managed Redis database/instance whose write primary is Frankfurt, with no
  cross-region read replica for authority paths, TLS, `noeviction`, replication,
  multi-zone HA, backup/restore and provider metrics. The exact provider, tier,
  SLA and spend remain explicit owner decisions;
- production Neon in Frankfurt through the pooled application endpoint, scale
  to zero disabled, with actual min/max CU and `SHOW max_connections` recorded.
  At two API replicas, the current default pool ceiling reserves up to 20
  application connections; retain explicit headroom for migrations, operators,
  monitoring, failover and any separately deployed worker before raising it.

These are test-entry recommendations only. The highest passing, reconciled and
fault-tested size becomes the temporary operating cap. Official references:
[Render instance types](https://render.com/docs/compute-plans),
[Render scaling](https://render.com/docs/scaling),
[Render deploy and shutdown lifecycle](https://render.com/docs/deploys),
[Upstash regions/consistency](https://upstash.com/docs/redis/features/globaldatabase),
[Upstash replication](https://upstash.com/docs/redis/features/replication), and
[Upstash durable storage](https://upstash.com/docs/redis/features/durability),
[Neon compute/connection sizing](https://neon.com/docs/manage/endpoints/).

#### Initial scheduled-work capacity audit

The post-release source audit found that the most latency-sensitive paths are
already designed for more than one API replica: ride dispatch and offer expiry,
active-trip ETA refresh, stale-provider recovery, Paystack webhook processing,
pending transfers, tips and refunds use PostgreSQL `SKIP LOCKED`, compare-and-set
updates, token-owned leases or equivalent durable claims. This is correctness
evidence only; their throughput and pool cost still require measurement.

The source-level candidate-scan audit is substantially closed in the local
backend worktree, but the following risks remain before a 100k-DAU claim:

- backend commit `db5a37a` closes the identified marketplace state/notice crash
  gap for directed-quote revert, scheduled no-show cancellation, 48-hour job
  freeze and zero-bid escalation. Each state transition now records immutable
  recipient/payload snapshots in the same PostgreSQL transaction, and a bounded
  oldest-first worker claims, retries and deduplicates delivery. This remains a
  local checkpoint: deployed throughput, backlog-age alerts and replica-loss
  recovery are not yet proven;
- backend commit `875f1e3` closes the unbounded daily-settlement fetch: each
  Paystack request has a configurable 1–30 second timeout (safe default ten
  seconds), responses are limited to the requested 50 records, and the complete
  run is limited to a configurable 1–100 pages (safe default and hard maximum
  100). Invalid, inconsistent or over-budget pagination aborts without writing
  a partial financial report. The final production page budget still depends on
  the owner-approved workload model;
- surge evaluation now fetches only the single winning rule, but its global
  demand/supply counts still need representative-cardinality query plans and
  pool-cost evidence;
- batch payout enumeration and the weekly email digest remain unbounded in
  source, but both are explicitly disabled/deferred for this release and are
  production-forbidden by configuration. They become blocking before either
  feature is enabled;
- bounded queries, row claims and deployment leases prove source-side
  containment, not production throughput. Exact backlog cardinalities, pool
  occupancy, scheduler lag and multi-replica failure behavior remain unmeasured.

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
- [ ] Add bounded keyset/claim batches and explicit per-tick work budgets where
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
      Backend commit `1390423` closes three additional enumerated paths.
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
      warnings. No staging or production system was touched. Keep this item
      open until the remaining crash-safe notification/reconciliation gaps
      below are closed. Backend commit `20890aa` gives bid expiry,
      directed-quote acceptance,
      scheduled reminders, job staleness, welfare checks, rating reveal and
      audit retention deterministic configurable 1–500 work budgets (safe
      defaults 100), durable stage markers where repeated candidate selection
      would otherwise starve later work, and exact partial candidate indexes.
      Provider-document lifecycle uses bounded oldest-first event claims plus a
      single locked replacement-authority cohort so a crash cannot create a
      partly swapped current-document set; all provider reset/offline/expiry
      stages and expired processing-lease reclamation are also bounded without
      changing the approved active-work-finish rule. Stale payout reconciliation
      is oldest-first and bounded behind a deployment lease, daily payment
      reconciliation has a deployment lease, and surge selects only one
      deterministic winning rule instead of materialising all matching rules.
      All **264** migrations apply on disposable PostgreSQL; the aggregate-only
      diagnostic reports **34** workload counts and **36** required index rows,
      with every new index valid/ready. Event and payout plans select the new
      partial indexes; the nine-row provider-document fixture correctly chooses
      sequential scans and is not representative scale evidence. Focused tests
      pass **103/103** for the worker/config/index group and **82/82** for the
      payment/reconciliation/surge group. The exact committed tree passes the
      pinned Node **22.23.0** production build, **214/214 suites and
      4,375/4,375 tests**, lint with zero errors and 52 existing warnings,
      Prisma validation and diff checks. Exact stripped image
      `sha256:0319b306585a3b6af360bfeb6c2a6189cdc096671405af5d3072977b04314c14`
      is 181,384,107 bytes, runs as UID/GID 1001 on Node 22.23.0, contains no
      application source, Git metadata, environment file or product docs,
      exposes no top-level Jest runtime, and passes the static runtime contract.
      Its disposable clean-database verifier
      fails only at the previously recorded historical
      `20260615000000_ride_max_broadcast_drivers_config` ordering defect; this
      does not invalidate the current migrated-database proof, but the image is
      not recorded as an end-to-end runtime-verifier PASS. Nothing was pushed,
      deployed or run against staging/production. Backend commit `db5a37a`
      then closes the four marketplace notification crash gaps with a
      transactionally inserted, deduplicated and leased PostgreSQL outbox. Its
      configurable 1–500 delivery budget defaults to 100, expired claims are
      reclaimed in bounded order, retries use capped backoff, and a durable
      admin alert is retained when no authorised operator currently exists.
      On disposable PostgreSQL, all **265** migrations are current, all **102**
      release-preflight indexes are valid, the aggregate diagnostic reports
      **36** workloads and **38** scheduler indexes, and both new planner checks
      select their partial indexes with index-only scans. The exact committed
      tree passes the pinned Node **22.23.0** production build, typecheck,
      **216/216 suites and 4,388/4,388 tests**, and lint with zero errors and 52
      existing warnings. Exact stripped runtime image
      `sha256:6a13f366340f313929c898e90111bc6f913dc3207db95977ed15bcb213cff149`
      is 181,396,214 bytes, runs as UID/GID 1001 on Node 22.23.0, and contains
      no application source, Git metadata, environment file, product docs,
      or top-level Jest runtime. TypeScript remains transitive in the pnpm store
      and is therefore not claimed absent. Nothing was pushed, deployed or run
      against staging/production. Backend commit `875f1e3` then bounds daily
      Paystack settlement reconciliation to at most **100 × 50 = 5,000** rows
      and **100** individually timed requests, rejects inconsistent or oversized
      provider pages, and fails closed instead of persisting a partial money
      report. A source-AST regression contract inventories all **46** cron entry
      points as **36 active**, **9 explicitly deferred** and **1 fail-closed**;
      adding a cron without a reviewed classification now fails the suite. The
      exact committed tree passes the pinned Node **22.23.0** production build,
      typecheck, **217/217 suites and 4,392/4,392 tests**, and lint with zero
      errors (seven source-only warnings; 52 when tests are included locally).
      Exact stripped runtime image
      `sha256:a0f1e6f6551c3e46086f0fc6d8ed7225ca8d700f6bc88d2c5386d141f7761686`
      is 181,397,162 bytes and runs as the unprivileged `myshop` user on Node
      22.23.0. Nothing was pushed, deployed or run against staging/production.
      Backend commit `d0ce598` then closes the source observability gap for
      connection saturation and distributed-worker identity. It validates and
      defense-in-depth bounds each process's PostgreSQL pool, owns the underlying
      pool explicitly, and exports total, idle, active, waiting, minimum and
      maximum values. The command Redis client and both Socket.IO Redis clients
      export separate readiness and pending-command gauges. An AST contract
      requires every deployment-wide lease to retain one of **22** exact
      reviewed metric names. On pinned Node **22.23.0**, the exact committed
      tree passes **218/218 suites and 4,399/4,399 tests**, API source/E2E and
      package typechecks, production build, and lint with zero errors and 52
      existing warnings. Exact stripped runtime image
      `sha256:154669575bd721c3893bc42cc18633575109273b104d97321265351472132dc2`
      is 181,400,839 bytes and runs as UID/GID 1001. No staging or production
      system was touched. Provider-side Neon/Redis limits and production-shaped
      saturation measurements remain required.
      Backend commit `16e4247` then closes the remaining source-level
      scheduled-worker evidence gap: a regression contract maps all **36**
      active cron entry points to an aggregate-only PostgreSQL or Redis capacity
      marker, while the read-only disposable-database diagnostic reports **53**
      durable-workload measurements, **53** required index states and **48**
      planner-only `EXPLAIN`s. A last-success timestamp gauge now makes a leased
      worker that stops completing visible across replicas. Escrow release no
      longer selects future holds, and missing-hold recovery selects only the
      approved ride or artisan completion authorities so old incomplete
      bookings cannot permanently starve later completed work from its bounded
      batch. The exact committed tree passes the pinned Node **22.23.0**
      production build, API source/E2E plus config/database typechecks,
      **218/218 suites and 4,418/4,418 tests**, and lint with zero errors and 52
      existing warnings. Exact stripped runtime image
      `sha256:f984d7e3a86342f31ba81aaa82c1c15dd3ef7250221f846fbde1af40320d8a00`
      is 181,401,463 bytes and runs as UID/GID 1001. No staging or production
      system was touched.
      Backend commit `a650682` then gives **all 36 active cron entry points**
      an exact, observable deployment-wide Redis lease while preserving their
      PostgreSQL/Redis row claims and compare-and-set transitions as the final
      effect authority. This prevents each future API replica from repeating
      every candidate scan, fails closed when shared lease authority is
      unavailable, and retains safe takeover on later ticks. The AST contract
      maps each exact cron method to one of 36 bounded metric names, so a new or
      misplaced lease fails the suite. The committed tree again passes the
      pinned Node **22.23.0** production build, API source/E2E plus
      config/database typechecks, **218/218 suites and 4,418/4,418 tests**, and
      lint with zero errors and 52 existing warnings. Exact stripped runtime
      image
      `sha256:8fdf75d0814a73a3767cb0ffdf5ab0453b9af5cd7f9930c0153d73beefbc62ec`
      is 181,405,453 bytes and runs as UID/GID 1001. No staging or production
      system was touched; live lease takeover and drain rate remain unproven.
      Keep this item open only for production-shaped backlog, query-plan,
      throughput, scheduler-lag and database-pool proof.
- [x] Elect one deployment-wide owner for every active scheduler before scaling
      API replicas, while retaining row-level claims so worker failover remains
      safe. Local backend commit `a650682`; not pushed or deployed.
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
- Follow-up lifecycle inventory found that the Client app had no shared
  foreground authority: mounted Activity, job, bid, artisan-location,
  ride-tracking and payment-settlement safety nets could continue requesting
  after the app moved to the background. The Client now publishes exact
  resumed/non-resumed state, all of those REST paths pause while backgrounded,
  and its general ride/job Socket.IO connection disconnects until resume.
  Calls retain their separate call socket, Provider location retains its
  business-required background writer, and foreground cadences are unchanged.
  The previously uncancelled Client socket connection-state subscription is
  now disposed, preventing repeated login/provider lifecycles from multiplying
  room-rejoin emissions. The Provider active-job acknowledgement poll is also
  foreground-only. A transport follow-up removed duplicate raw Socket.IO
  payload and connection-ID logging from general, call and chat transports;
  Provider diagnostics retain only a bounded event name, not coordinates,
  messages, booking/call IDs or network credentials. Full gates pass
  **162/162 API-client**, **96/96 Client** and **175/175 Provider** tests; all
  three analyzers report no issues, and no deployment or store state changed.
  This hardening strengthens already checked mobile items and does not increase
  the capacity score.
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

The fail-closed load-harness predecessor passes **18/18** local and
pinned-Node-22 tests. The current wrapper passes **22/22** on local Node 24,
including production-host refusal, target/commit binding, exact-role fixtures,
provider epoch/sequence checks, call participant uniqueness, Cloudflare TURN
preflight, geofence/clean-database/Redis nonce authority, scenario sizing,
explicit routing isolation, inherited-secret stripping and private external
artifact enforcement. The end-to-end runner contract injects database, Redis,
JWT, k6-cloud and Maps credentials into its parent environment and proves k6
receives none of them. The guarded target-local provisioner refuses shared
staging, production hosts, the Ashanti production geofence, real-user data,
mismatched database/Redis nonces, repository output paths and existing output
files. Current contracts also prove exact exporter allowlists,
release/API/database/Redis-namespace snapshot binding, owner-only artifacts and
no completion manifest after a partial exporter failure. A new execution test
proves the exact target-class/service/release topology gate runs before both the
first snapshot and k6, fails closed without either action, and binds only its
SHA-256 fingerprint into both manifests; it also exposed and fixed the
non-executable nested-runner invocation. The same execution test now proves an
incomplete, stale or mismatched owner policy fails before any snapshot or k6.
After a run, the offline evaluator refuses changed digests, workload-kind drift,
timing/binding mismatch and any exceeded count/growth/age limit, retaining only
bounded issue codes and fingerprints. The focused exporter/evaluator gate
passes **15/15**, including the real CLI preflight under a stripped
environment. Review also found that preflight and capture initially used
different Redis-namespace hash formulas; they now share one
domain-separated implementation and an exact regression vector. The final
decision report is now also bound to the exact private k6 result fingerprint and
byte size; k6 failure skips ready evaluation while preserving after-state
capture, and a post-preflight policy-byte change is rejected. The complete
**22/22** load boundary now passes in the Bash-capable Node **22.23.1** image;
the prior topology validator, PostgreSQL and Redis exporters, and owner-policy
evaluator pass **27/27** together under the same runtime. The current
provider-neutral topology/exporter/evaluator increment passes **28/28** in the
Bash-capable pinned Node **22.23.1** image. An earlier Alpine diagnostic that
could not launch Bash-dependent checks was rejected and is not counted. Real
isolated-service evidence remains open.

The call scenario also now fails unless every accepted delivery is a unique,
well-scoped exact-peer probe and at least one sender/receiver pair is served by
different opaque process IDs. The target flag that exposes those ephemeral IDs
is schema-forbidden in production and default-off elsewhere, and each load
socket must explicitly request it. This closes a local evidence-integrity gap
only: no 100/250/500-call run, media-quality test, replica fault, backlog
reconciliation or provider-capacity observation has occurred.

The first k6 1.3.0 smoke correctly failed after three invalid-key Google Routes
requests exposed that routing was not isolated. No live credential was used.
Ride scenarios now require an explicit four-hour synthetic cache covering all
18 ordered workload routes; Google routing remains a separate approved,
cost-bounded canary. A completely fresh clone then passed provisioning, live
preflight and smoke at **9/9 checks**, **0/7 failed HTTP requests** and
**133.23 ms p99**. Reconciliation found one terminal ride and zero active
rides/jobs, and logs proved route-cache hits rather than a provider failure.
This is single-replica harness evidence only; no pilot, call-concurrency or
100k-DAU capacity claim is closed.

### Phase D — rollout

Canary the exact reviewed backend/mobile artifacts, observe the approved window,
then expand gradually. Stop on lost/duplicate accepted work, money mismatch,
provider Online/session divergence, sustained latency/error/backlog thresholds,
or missing alerts. The 100k-DAU claim remains unproven until the completed load
evidence record is signed by the release, backend/SRE and payments owners.

## 6. Decisions still required

| Decision                                         | Status       |
| ------------------------------------------------ | ------------ |
| Approved peak traffic model and 2x headroom      | **Required** |
| Actual Render plan/replica/autoscaling budget    | **Required** |
| Current Redis region/tier/HA/capacity            | **Required** |
| Current Neon compute tier and connection ceiling | **Required** |
| Highest private Android/iOS build codes          | **Required** |
| Real DPC registration number                     | **Required** |
| Named load, incident-abort and release owners    | **Required** |
| Maximum accepted in-app call duration/retention  | **Approved 2026-07-23; implementation/proof required** |
| Per-booking concurrent non-terminal call policy  | **Approved 2026-07-23; implementation/proof required** |
| Per-socket call-signal rate/burst safety limit   | **Approved 2026-07-23; implementation/proof required** |
| Per-socket chat message/typing rate/burst limit  | **Required** |
| Per-socket location-event rate/burst limit       | **Required** |
| Overdue accepted scheduled-job catch-up action   | **Required** |

The owner approved the three call decisions on 2026-07-23. They were not
inferred from the capacity ladder and remain unimplemented until an isolated
call-policy successor passes its clock, idempotency, cross-replica Redis,
reconnect-storm and mobile-compatibility gates.
Current source retains every call session for a fixed **30 minutes**, even
though TURN credentials default to two hours; it does not renew an accepted
session or expose an owner-approved maximum. It also permits multiple
non-terminal sessions for the same booking and has no per-socket signalling
rate/burst authority beyond the 100 KB Socket.IO packet ceiling and shared
connection cap. The audited terminal-state and payload protections do not
choose any of those product/operational rules.

The scheduled-job decision is narrower than the already approved containment.
`FF_SCHEDULED_JOBS=false` prevents new scheduled-job creation while preserving
the lifecycle of an already accepted obligation. Candidate `8cfe1f7…` retains
the change that
the no-show sweep from a 15-minute window to a bounded catch-up query over all
overdue `confirmed` rows. That can correctly recover a missed cron tick, but it
can also auto-cancel legacy overdue rows immediately after deployment. The
existing aggregate-only, read-only scheduled-work diagnostic reports the exact
count and oldest age without exposing account or job identifiers. Do not disable
the complete lifecycle worker, deploy the catch-up behavior, or infer a legacy
resolution rule until that aggregate is reviewed and the owner decides the
action.

The recovery paths do not currently close the duration gap. The API returns
the original TURN credentials for the lifetime of the Redis session and has no
credential-refresh endpoint or credential expiry in its response. Mobile
reconnect replays cached SDP and ICE candidates, but does not install refreshed
ICE servers or perform a true ICE restart. Cloudflare's current Realtime TURN
guidance says the credential TTL must exceed the longest expected call, supports
refresh through peer-connection configuration, recommends ICE restart for
allocation disruption, and warns that an allocation disconnects shortly after
credential expiry. Therefore the accepted-call deadline, Redis retention, TURN
TTL, refresh/restart path and user warning must be one reviewed contract; merely
increasing `APP_CALL_TTL_SECS` is not a complete fix.

The chat and location decisions are likewise not inferred from the mobile
cadences. Current source has the shared deployment-wide connection cap and a
100 KB Socket.IO packet ceiling, but no owner-approved per-socket message,
typing or location-event rate/burst authority. Payload validation and mobile
request coalescing do not substitute for an abuse/capacity limit.

The HTTP call-session creation endpoint is covered by the authenticated global
Redis sliding window of 300 requests per minute, keyed by authenticated user.
That broad budget is shared with the caller's other API requests and is not a
call-specific control: `POST /calls` creates a new random call and sends a new
incoming alert on every successful invocation. There is no per-booking
non-terminal uniqueness or idempotent replay. After connection, Socket.IO
`call:signal` events do not pass through the HTTP guard.

The audited client can replay up to 128 queued call signals immediately after a
reconnect; current signalling does not pace that replay. Client and provider
chat typing is locally debounced to one positive update per three seconds, while
ordinary messages are human initiated and limited to 2,000 characters. The
provider normally produces a genuinely newer driver socket fix about every four
seconds. None of these client cadences is server authority.

The socket GPS path is materially heavier than a relay. Each accepted event can
perform current-driver and active-ride reads, authoritative PostGIS/Redis
location writes, GPS-history operations, optional trip-trail SQL, ETA reads and
room broadcasts. The separate REST location path rejects more than one driver
update every two seconds, but the socket ingestion method does not use that
control. An authenticated buggy or hostile socket can therefore multiply
database and Redis work until the shared infrastructure saturates.

These are the pilot controls. Only the three call rows are owner-approved;
chat and location controls remain proposals:

| Control                  | Evidence-based proposal                                                                                                                                                                                                | Status                                                     |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| Accepted in-app call     | Two-hour operational maximum with a user warning at 1h55 and server-enforced end at 2h; internal session/TURN authority retained through 2h15 so the forced-end tombstone remains queryable for 15 minutes; never persist signalling content | **Approved 2026-07-23; clock/TURN/device proof required** |
| Booking call concurrency | Exactly one `ringing` or `accepted` call per booking; a repeated same-participant start returns that session idempotently; a new call is permitted after a terminal state while the booking remains active             | **Approved 2026-07-23; atomic cross-replica proof required** |
| Call signalling          | Per authenticated participant: burst capacity 160 (covers the bounded 128-signal reconnect queue), plus a 300-event rolling-minute ceiling; exceedance rejects and meters the event without disconnecting the call | **Approved 2026-07-23; reconnect-storm proof required** |
| Chat messages            | Per authenticated role account: 10 messages per 10 seconds and 30 per minute; reject excess with a stable retryable acknowledgement                                                                                    | **Owner approval required**                                |
| Chat typing              | Per authenticated role account: 6 updates per 10 seconds and 30 per minute; silently coalesce excess best-effort typing state rather than fail the chat                                                                | **Owner approval required**                                |
| Driver socket location   | Per current driver Online epoch: token-bucket capacity 3, refilling one event every 2 seconds; reject excess before profile, geofence, database or history work while preserving the latest legitimate fix             | **Owner approval and GPS-jitter/load proof required**      |

The implementation must be shared across replicas, use Redis server time, key
sustained limits to authenticated role/session authority so reconnecting cannot
reset them, fail closed if admission authority is unavailable, bound Redis
latency, avoid raw identifiers in logs/metrics, and include stable client
handling. Short per-socket burst state may supplement but must not replace the
identity/session limit.
