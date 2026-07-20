# Staging Release Candidate Runbook

This is the remaining operator sequence for the 24-hour candidate. It does not
authorize a production deployment. Stop at the first failed gate and preserve
the evidence; never repair staging by pointing it at production resources.

## Required inputs

- Exact reviewed backend, mobile, and admin commit SHAs.
- A staging database snapshot and its protected direct migration URL.
- Dedicated staging Redis, Firebase/storage, callback URLs, and namespaces.
- The two approved tester phone numbers for live Arkesel SMS and WhatsApp OTP.
- Separately owner-approved staging and production values for
  `OTP_DELIVERY_GLOBAL_LIMIT_PER_MINUTE` and
  `OTP_DELIVERY_PHONE_CHANNEL_LIMIT_PER_10_MINUTES`; defaults are not approval.
- A non-secret fingerprint proving `ENCRYPTION_KEY` is present and valid.
- A dedicated staging metrics bearer secret and an approved external scraper;
  never record the secret in release evidence.
- The highest private App Store Connect and Play Console build numbers.
- A named release commander and a separate device tester.
- Explicit owner authorization before any **live Paystack money movement**.

Record SHA and resource identifiers in the private operations inventory. Do not
paste credentials, phone numbers, MoMo destinations, provider references, or
database URLs into this checklist, logs, issues, or chat.

## 0. Package the reviewed source trees

This gate happens before suspending or mutating staging. The 2026-07-19
inventory established these release-branch bases after fetching `origin/staging`:

- mobile: `f88f43c85e52ecf9f7d69b0f6e0a500665a0edcb`;
- backend: `1f1ada8b7ad3b9b8ab937fe8fab3dad611aae7bd`;
- admin: `78fabd15d8235e399dba45933bbe125b13c81077`.

The mobile worktree HEAD `d200d3d…` is one merge commit behind by graph but its
committed tree is byte-identical to current mobile staging. Create the release
branch from `f88f43c…`; do not base the PR on the old feature-branch graph or
re-include the already-merged overlay work.

1. Freeze all three working trees while packaging. Use one release PR per
   repository and review the backend in schema/migration, API/domain,
   infrastructure/runtime, and test/evidence slices even if they land together.
2. Stage explicit reviewed paths only. Never use blanket `git add .` for this
   candidate. The mobile `packages/incoming_request_overlay/android/.gradle/`
   directory is generated and ignored. The untracked, unreferenced
   `apps/api/src/common/services/provider-verification.ts` inside the mobile
   repository is outside the mobile architecture and must not enter a release
   commit unless its provenance and destination are independently approved.
3. Review intentional deletions: backend removes the duplicate safety welfare
   service in favour of the marketplace authority and removes the unsafe local
   JWT/direct-database load seeders; admin removes the unreferenced generic
   create-user dialog. Reject any additional unexplained deletion.
4. Re-run conflict, whitespace, secret-pattern, generated-file, large-file, and
   binary-diff checks after staging files. The inventory found no unresolved
   paths, changed binaries, changed files above 500 KB, or high-confidence
   secret-pattern additions; that checkpoint does not cover later edits.
5. From each resulting clean commit, rerun the recorded full backend, mobile,
   and admin gates. Record the exact commit and tree SHAs. A test result from a
   dirty predecessor is supporting evidence, not the deploy approval for the
   committed artifact.
6. Open the three PRs with auto-deploy still disabled. The second developer must
   compare the PR path inventory with this checklist and explicitly confirm the
   disabled-feature flags before merge.

## 1. Freeze and fingerprint

1. Disable staging auto-deploy and suspend the staging API.
2. Confirm production health and active-work dashboards remain stable.
3. Record staging API/admin SHAs, mobile build numbers, database snapshot ID,
   Render service ID, Redis database ID, and geofence fingerprint.
4. Prove staging and production database/Redis fingerprints differ using the
   PII-free procedure in the backend staging-isolation runbook.
5. Confirm these release fences remain false:
   `FF_USSD_CHANNEL`, `FF_BATCH_PAYOUTS`, `FF_PROVIDER_AGGREGATE_PAYOUTS`,
   `FF_ROLE_ACCOUNT_REWARDS`, `FF_CANCELLATION_CONSEQUENCES`,
   `FF_SESSION_RECOVERY`, `FF_ROLE_ACCOUNT_RECOVERY`, support/dispute
   attachments, and active-trip fallback. The admin artifact must initially use
   `NEXT_PUBLIC_FF_ROLE_ACCOUNT_RECOVERY=false`. Confirm the obsolete
   `ROLE_ACCOUNT_RECOVERY_ENABLED` flag is absent and legacy
   `POST /v1/auth/recover` remains unregistered and returns 404. Only the new
   OTP-bound exact-role endpoints may be enabled later for the controlled
   staging recovery journey. Confirm automatic permanent role purge remains a
   fail-closed no-op for this release; an overdue inventory count never
   authorizes deletion.

## 2. Run database preflights while staging is suspended

From the reviewed backend SHA, point `DIRECT_DATABASE_URL` only at the protected
staging direct endpoint and run each file with `psql -v ON_ERROR_STOP=1`:

```text
packages/database/scripts/preflight-provider-vehicle-cutover.sql
packages/database/scripts/preflight-role-account-separation.sql
packages/database/scripts/preflight-role-account-recovery-deadlines.sql
packages/database/scripts/preflight-role-account-recovery-workflow.sql
packages/database/scripts/preflight-role-account-communication.sql
packages/database/scripts/preflight-ride-fare-policy-snapshot.sql
packages/database/scripts/preflight-ride-promo-settlement.sql
packages/database/scripts/preflight-refund-dispute-settlement.sql
packages/database/scripts/preflight-paystack-refund-routing.sql
packages/database/scripts/preflight-online-ride-provider-indexes.sql
```

Each reviewed script independently enables immediate psql failure, disables
paging, and begins a database-enforced `REPEATABLE READ READ ONLY` transaction
with a two-minute statement timeout and five-second lock timeout. Its output is
aggregate-only. Do not weaken those controls, add identifier flags, or capture
the output in a public/shared log.

Required outcomes:

- no unsafe vehicle/document authority requiring inferred approval;
- no ambiguous role ownership or cross-role contact ownership;
- no active role with a recovery deadline and no deleted role with a missing or
  non-exact `deletedAt + 2,160 hours` recovery deadline; any overdue count is
  inventory only because automatic purge remains disabled;
- no false exact-role binding, restored-but-still-pending request, provider
  recovery marked approved before final verification, pending provider left
  Online, or unaccepted recovery request past its database deadline;
- no active ride missing its valid immutable booking-time fare policy;
- no unsafe promo/refund economics;
- `duplicate_paystack_refund_id_groups = 0`;
- each of the 66 manifest-controlled populated-table indexes is either
  `missing` before its pending migration or `valid` with the exact reviewed
  table/definition after it; an `invalid` state is always a stop;
- every unresolved or ambiguous refund count is explained and reconciled before
  migration; do not print the underlying identifiers.

If a count is non-zero, stop. Resolve it through an approved, auditable operator
procedure; never add a migration that silently chooses an owner, vehicle,
document, refund, or Paystack outcome.

Before touching a protected environment, the exact reviewed backend tree must
also pass its disposable local release gate:

```text
sh infrastructure/test/run-api-e2e.sh
```

Require both `Release preflight read-only execution and aggregate-output proof
passed` and `Ride cutover gate and zero-mutation refusal proof passed` in
addition to the migration, drift, seed, online-index, and API E2E results. Both
proofs intentionally refuse every database except local `myshop_test`; do not
weaken their guards or point them at staging/production.

## 3. Migrate before deploying the API

1. Run `prisma migrate status` against the verified staging direct endpoint.
2. Drain every driver and artisan Offline through the reviewed application or
   operator path, then use an aggregate-only query to prove both Online counts
   are zero. Do not clear, fabricate, or infer a provider session. Migration
   `20260718275000_provider_location_session_sequence` intentionally raises
   `PROVIDER_LOCATION_SESSION_CUTOVER_BLOCKED` before any DDL if either role is
   still Online; any non-zero count or that error is a hard stop.
3. Apply all **196** reviewed migrations with `prisma migrate deploy`.
4. Run the schema-drift verifier against the isolated release database.
5. Re-run the Paystack-refund-routing preflight and verify the unique index is
   present.
6. Verify `rides_enforce_booking_gate` is a `BEFORE INSERT` trigger on `rides`,
   its reviewed function reads `platform_config.rides_enabled`, and the value
   remains false. The API must return stable `503 RIDE_BOOKING_PAUSED` for a new
   booking while same-key recovery and active-ride lifecycle APIs remain usable.
7. Verify the protected Ghana-wide staging boundary fingerprint.
8. Keep `RUN_MIGRATIONS_ON_BOOT=false` and `SEED_DATABASE=false`.

The 66 standalone online-build migrations must each contain exactly one
`CREATE [UNIQUE] INDEX CONCURRENTLY` statement, and the four reviewed legacy
removals must each contain exactly one `DROP INDEX CONCURRENTLY IF EXISTS`
statement. If one fails, stop deployment, preserve the migration error and
catalog output, and run the read-only online-index preflight. Only after an
authorized operator confirms an invalid/not-ready build remnant may they run
`repair-invalid-online-ride-provider-indexes.sql`, then mark that exact failed
migration rolled back with `prisma migrate resolve --rolled-back <name>` and
retry `migrate deploy`. Never drop a valid index, add `IF NOT EXISTS`, or mark a
migration applied unless the exact index is ready, valid, table-bound, and
matches the reviewed definition.

Do not resume an old Render build. Deploy the exact reviewed SHA with the saved
environment, then verify the running SHA and `/v1/health` dependencies.

Before deployment, build the API image from that clean reviewed SHA and run
`infrastructure/docker/verify-runtime-image.sh <image>`. Retain the image digest,
Node version, UID/GID and ownership result, migration/seed output, TLS Redis and
geofence/prefix checks, readiness response, and SIGTERM disconnect evidence.
Generate an SBOM for that exact digest and complete the approved license and
vulnerability review. Do not use an external scanner that uploads private image
or package metadata without explicit owner authorization.

Before allowing any paid OTP send, keep `OTP_DELIVERY_MODE=off`, deploy, and
prove the kill switch returns the stable disabled result without contacting a
carrier. Then set staging only to `allowlist`, enter the two exact E.164 tester
numbers directly in Render as `OTP_DELIVERY_ALLOWLIST`, and apply the separately
approved staging caps. Never paste the numbers into evidence and never use
`live` mode for this two-developer test. Confirm production remains `off` with
its separately approved caps recorded in the private operations inventory.

## 4. Installed-build acceptance order

Use internal-track/TestFlight builds with unused private build numbers.

1. **Authentication:** client/provider login, delayed delivery, explicit
   SMS-to-WhatsApp resend, wrong OTP, cooldown, and unregistered-number signup
   redirect. The UI must never say a code was sent without carrier acceptance.
   Alternate requests between both tester numbers and replicas; prove the
   combined rolling caps, circuit open/one-probe/close behavior, and immediate
   `off` kill switch. Inspect Redis through an authorized aggregate/key-pattern
   check and prove no raw phone number appears in an OTP key. Correlate carrier
   accepted, delivered/failed, and verified timestamps without recipient/code
   values, and verify delivery/cost alerts reach the named operator.
   Keep `FF_SESSION_RECOVERY=false`: a blocked-device conflict must expose no
   recovery capability, both apps must hide Contact support, and the public
   recovery route must fail closed. The durable resolving saga is locally
   crash-consistent, but do not enable it until this exact pinned artifact has
   passed two-replica process/Redis fault injection, lease takeover, installed-
   app, operator, audit, and rollback proof.
2. **Role separation and deleted-role recovery:** coexist
   client/driver/artisan sessions; confirm profile,
   referrals, loyalty, emergency contacts, chats, calls, sockets, and deletion
   remain exact-role scoped. Delete one test role only after the active-work and
   liability preconditions pass; prove the private phone-auth identity and both
   sibling roles remain usable, the deleted role cannot log in or be restored
   through the suspension-reinstatement route, and the stored recovery deadline
   is exactly `deletedAt + 2,160 hours`.
   - With `FF_ROLE_ACCOUNT_RECOVERY=false`, both new OTP endpoints and every
     admin recovery mutation must fail closed. Registration must keep returning
     `ROLE_ACCOUNT_RETAINED` without sending a registration OTP or creating a
     second role.
   - Apply the approved timing rule: user filing and named regional Admin
     intake must both occur before the 2,160-hour deadline. Timely intake
     preserves the recovery while Coordinator/RM review finishes afterward;
     the provider remains Offline until RM final approval and no post-intake
     auto-expiry or rejection is inferred. Build the exact admin artifact with
     `NEXT_PUBLIC_FF_ROLE_ACCOUNT_RECOVERY=true`, then enable
     `FF_ROLE_ACCOUNT_RECOVERY=true` only on staging. File the exact deleted
     role from the client/provider app with the allowlisted phone and device.
     Prove a lost verification response reuses one request key, a different
     device cannot replay it, wrong/expired OTPs do not file a request, and no
     response or admin view exposes a sibling role or private auth identity.
   - For a client, prove only global Operations/Super Admin can approve and only
     that client becomes active. For a provider, prove only a named Admin in the
     provider region can intake it, documents return to pending review, the
     provider stays Offline with no session/location/vehicle authority, the
     category Coordinator reviews, and the Regional Manager alone gives final
     approval. Back Officer, global higher roles with an injected permission,
     wrong-region Admin, wrong-category Coordinator, and sibling-role tokens
     must all fail closed.
   - Confirm there is no recovery reject/dismiss control. Client and provider
     pre-intake actions after the database deadline must expire/fail closed.
     Exercise the approved post-intake timing rule exactly; do not infer it.
     Re-run the aggregate recovery preflight, then return the flag to false
     unless the release commander explicitly approves continued staging
     exposure.
3. **Provider eligibility:** independently approved documents, Coordinator to
   Regional Manager approval, expired/replacement document behavior, two
   vehicles with separate insurance/roadworthiness, mandatory fresh selection,
   notification reachability, and authoritative Offline.
   - Open Admin → Vehicle Verification. For every **Legacy migrations** row,
     compare the previous make/model/year/plate/colour with the stored evidence,
     open every listed current roadworthiness/insurance document, select all
     evidence that belongs to that exact vehicle, and tick the explicit
     ownership confirmation. If the driver has already submitted an explicit
     vehicle, select that exact target and bind the retained evidence without
     changing any vehicle/category state. Otherwise choose its requested ride
     categories and create the pending vehicle. Never use this flow to infer
     missing ownership or approve a document, vehicle, category, or expiry.
   - If retained approved roadworthiness/insurance evidence has no expiry,
     use the Vehicle Verification expiry control only when the date is readable
     on that exact document; otherwise require a new upload. For every private
     vehicle-document upload, require confirmation to reach `pending_review`
     without a `STORAGE_VERIFICATION_UNAVAILABLE` response before treating the
     storage path as release-ready.
   - Apply `20260720010000_enforce_vehicle_document_three_stage_review` before
     this test. For a newly uploaded insurance document, require Admin approval
     to produce `confirmed` (not `approved`), the rides Coordinator to produce
     `coordinator_validated`, and only the Regional Manager to produce
     `approved`. The repair migration must place any earlier Admin-only vehicle
     approval at the Coordinator step rather than asking the driver to upload it
     again.
   - Coordinator forwards the migrated vehicle, Regional Manager finalizes it,
     and each vehicle category is approved separately. Missing/expired evidence
     is uploaded against the new vehicle through the normal review path. Re-run
     an aggregate-only `driver_vehicle_backfill_preflight` count and require
     `backfill_required = 0` before reopening rides. A non-zero result is a
     release stop; do not print driver/document identifiers into shared logs.
   - On the installed provider build, pull to refresh **My Vehicles**, confirm
     the migrated car is displayed without the legacy-migration notice, select
     it during Go Online, and prove the driver becomes matchable only after all
     document, vehicle, category, notification and location checks pass.
   - Leave the driver home map visible while profile, legal-consent, socket/FCM,
     Online/Offline and active-work state refresh. Require one stable native map
     controller, no visible blinking and no repeated startup
     `getCurrentPosition` calls. Then force one genuine GPS timeout and verify
     the last-known fix remains visible without remounting the map.
   - Keep `PILOT_REGION_CHECK_DISABLED=false`. With a valid fix no more than
     30 seconds old and no worse than 50 metres, prove driver and artisan Online
     succeeds inside the current boundary and returns `OUTSIDE_PILOT_REGION`
     outside it without changing stored location or availability.
   - Change the boundary between a stored fix and a cached-location Go Online
     attempt; the current boundary must be rechecked. An idle provider outside
     the boundary must still be able to go Offline.
   - While Online, send a newer driver fix and then an older direct, socket, and
     background-batch fix. The older fix must report it was not accepted and
     must not alter PostgreSQL location/time, Redis GEO/heartbeat, ride trail,
     degradation state, or rider/admin broadcasts. Repeat for artisan direct
     updates.
   - Reconnect/re-authenticate and reopen Online, then replay a socket update
     carrying the prior driver Online epoch. It must fail without mutation.
     Repeat the old-epoch proof for direct driver and artisan requests.
   - For both roles, prove Go Online returns a new server epoch and sequence
     zero; send the next exact sequence, then replay that sequence and skip
     ahead once. Only strictly increasing samples inside the current epoch may
     mutate location or any secondary effect. A duplicate or old epoch must not
     refresh session liveness or Redis heartbeat.
   - Go Offline and prove the database clears the role's epoch, authenticated
     session ID, sequence, and session timestamps. Confirm a subsequent direct
     heartbeat cannot turn an Offline provider Online.
   - For every driver arrival/start/completion and artisan
     arrival/start/mark-complete checkpoint, send a device fix no older than
     15 seconds and no worse than 30 metres. Prove missing, stale, inaccurate,
     or invalid proof fails before mutation; prove one proof cannot skip two
     checkpoints; and prove a same-status idempotent replay remains safe.
   - Permanently invalidate one non-final provider FCM token and prove the role
     stays Online through another eligible token. Then invalidate the final
     exact-role token during active work: only that provider role must become
     Offline, its location/session/Redis authority must clear, sibling roles
     must remain untouched, and the active ride/job must still finish. Register
     a replacement token while an older send is failing and prove the stale
     failure cannot deactivate the replacement.
   - For driver and artisan separately, go Online, kill the app process, and
     relaunch. Restoration must wait for Firebase readiness, make no automatic
     notification/location/overlay permission prompt, obtain a fresh BR-30 fix,
     and revalidate the exact role account plus all server eligibility. A driver
     must restore only with the retained selected vehicle. Repeat with a missing
     vehicle, stale/inaccurate/denied location, expired or unapproved evidence,
     RM rejection, role/account mismatch, Firebase delay, and network failure;
     each failure must consume the stale intent, leave or explicitly fail to
     confirm Offline truthfully, and show only stable actionable copy. Repeat
     during active ride/job recovery and prove current work is not discarded.
4. **Ride delivery:** foreground, background, terminated, and locked provider;
   authenticated receipt within ten seconds; 45 seconds independently for A
   then B; decline, expiry, duplicate socket/push, reconnect, and process death.
5. **Artisan lifecycle:** solo capacity one, non-solo configured capacity,
   bids/selection, arrival/start/end geofence warning, dual completion, payment,
   dispute, and payout hold.
6. **Admin:** exact-role account actions, document and vehicle two-stage queues,
   immutable approved authority, dispute detail, masked refund destination, and
   pending/failed/processed refund labels.

Any recurrence of `NOTIFICATION_REACHABILITY_REQUIRED`, a restore-online 403,
`BID_NOT_FOUND` during immediate bid selection, a lost ride, or a false document
prompt is a release stop. Capture the request correlation ID and stable error
code without personal data.

## 5. Refund and payment canaries

First use Paystack test mode or an approved fault-controlled stub to prove:

- request timeout after provider acceptance creates
  `reconciliation_required`, never resubmits, and creates no clawback;
- late success processes the exact refund once and only then creates recovery;
- late failure leaves payment blocked and creates no clawback;
- duplicate and out-of-order webhooks are idempotent;
- transaction-reference-only routing with sequential partial refunds is sent to
  manual review rather than guessed;
- cash transfer retry always verifies the deterministic reference before send;
- reversal and terminal recipient failure remain visible and reconcilable.

Only after explicit owner authorization, run one minimum-value live-safe canary
using the approved tester's OTP-verified MoMo destination. Reconcile Paystack,
`refunds`, `disputes`, `payments`, `clawbacks`, audit logs, and client/provider
notifications before continuing. Never use a provider or client who is not part
of the approved test pair.

## 6. Bounded load and rollback canary

Before any k6 request, use only the reviewed backend
`tests/load/run.sh`; do not invoke a scenario directly. The runner must verify a
healthy non-production target, the exact `/v1/health/ready` deployed commit, and
the deterministic SHA-256 binding of canonical target URL plus commit. Retain the
backend image digest separately because a commit marker alone is not an image
attestation. Run the local load contracts and compile/inspect every selected
entrypoint with the pinned k6 version before execution.

Provision fresh `myshop-load-fixture-v2` identities through a reviewed procedure
on that exact target. Every session must be server-issued and exact-role scoped;
drivers need unique approved selected vehicles, current Online epochs/sequences,
and exact-SID receipt-capable device rows. Artisans need current Online
epochs/sequences and exact-role active category authority. Never provide the
runner a JWT signing secret or direct database URL, never reuse a fixture after
its sequence/account state mutates, and never seed shared staging or production
through load tooling.
The runner must authenticate every entry against the target before k6 starts and
prove exact `/users/me` role-account ownership, provider Online epoch/next
sequence with no active work, driver selected/eligible vehicle, and artisan
active-category authority. A decoded token or offline JSON check is not proof of
server issuance.
The disposable clone must omit real Firebase credentials so synthetic device
tokens cannot trigger valid invalid-token Offline fencing. Real socket receipt is
measured here; real push delivery remains an installed-device gate.

`main`, `stress`, and webhook load are disposable-clone only and must use a
non-live Paystack webhook secret. Raw results and fixtures belong only in the
approved private evidence store. The current USSD callback is a static stub and
must not be exercised or counted as a passing load surface until the owner
confirms v1 scope and a real secured state machine passes E2E.

The built-in 200-driver/20-artisan/500-client pilot and 2x presets are
instrumentation samples, not an approved 100,000-DAU traffic model. Driver and
artisan GPS streams run for the entire ride and job/bid workload so stale
provider eligibility cannot turn a load result into a false application failure.
Before a capacity claim, approve peak concurrency/RPS, GPS/socket mix, regional
distribution, OTP and webhook bursts, data growth, soak duration, and 2x
headroom. Record the run in the backend `docs/load-test-report.md` template.

1. Run a bounded staging load that exercises booking idempotency, sequential
   offers, location heartbeats, websocket reconnect, webhook inbox, and worker
   leases across multiple API replicas.
   - Alternate the same E.164/IP/user throttle identities across at least two
     replicas and prove one combined default/auth counter, block, and reset
     lifecycle. Inject Redis latency, loss, restart, and eviction pressure;
     authority failure must be bounded, fail closed, and alert without silently
     multiplying admission per replica.
   - Alternate one exact role account across location, chat, and calls on both
     replicas. Prove one combined eight-socket cap, deterministic over-cap error,
     immediate disconnect release, renewal, and reclamation within 90 seconds
     after killing a replica. Engine.IO polling must be rejected and every
     installed client/admin build must connect with WebSocket transport. Record
     renewal operations, Redis memory/latency, reconnect churn, rejected/dropped
     sockets, and whether ride/job requests remain lossless during each fault.
2. On the production-shaped clone, capture `EXPLAIN (ANALYZE, BUFFERS)` for the
   driver and artisan stale-liveness queries and verify the functional partial
   indexes are used with bounded pages. Capture the exact driver and artisan
   matching plans as well: geography `<->` must drive GiST KNN order; document,
   category, current-work, notification, location, session, and artisan-capacity
   predicates must all apply before `LIMIT`; and no all-candidate
   `ST_Distance(...)` sort may return. Seed nearer busy/full providers and prove
   the query walks outward to the next eligible provider without starvation.
   Do not treat either 100,000-row local microbenchmark as staging capacity proof.
3. Observe database pool saturation, Redis latency/evictions, event-loop lag,
   offer receipt delay, lost/duplicate booking rate, and dead-letter backlog.
   Before load, enable the protected scrape endpoint with a random
   `METRICS_BEARER_TOKEN` of at least 32 characters. Prove an unauthenticated
   `/v1/metrics` request returns 401, an authenticated request returns the
   Prometheus content type and the pinned version/commit marker, and the scrape
   contains no phones, account IDs, coordinates, tokens, raw URLs, or other
   fixture values. Retain baseline/load/recovery scrapes in the approved metrics
   system, not in public logs or this repository.
4. Define numeric abort thresholds and an owner before starting load. At
   minimum alert on HTTP error/latency, DB/Redis readiness failures, admission
   authority unavailability, WebSocket lease loss/reconnect churn, event-loop
   and memory saturation, Redis evictions, pool exhaustion, offer receipt loss,
   webhook/outbox lag, and duplicate money/assignment invariants. A metric
   without a tested alert and response owner is not a release gate.
5. Kill one API/worker during each leased path and prove another replica resumes
   without duplicate money movement or assignment.
6. During a deploy, require `/v1/health/ready` to fail before the terminating
   replica disappears while `/v1/health/live` remains process-only. Hold an
   in-flight HTTP request and authenticated sockets across SIGTERM; prove the
   load balancer stops new routing, work completes or reconnects to another
   replica, worker leases transfer, and PostgreSQL plus all Redis clients close
   without a connection leak.
7. Rehearse rollback by closing booking gates, draining new work, suspending the
   candidate, and restoring the prior application artifact. Do not drop the
   additive refund-routing index/columns or restore an older database snapshot
   over newer accepted work.

## Release decision

Release only when every result is attached to the exact SHA/builds, all money
and booking records reconcile, the bound-listener E2E gate passes again on the
exact staging commit, rollback is timed and proven, and the release commander signs off.
This runbook does not establish full 100k-DAU readiness; that still requires
same-region no-eviction Redis and measured production-shaped capacity evidence.
