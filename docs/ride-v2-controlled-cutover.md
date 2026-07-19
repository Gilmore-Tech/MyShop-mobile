# Ride V2 controlled cutover runbook

Status: **not authorized or rehearsed**. BR-38 forbids an ordinary rolling
deployment. Complete this on staging first and retain the evidence before a
production window is approved.

## Entry gates

- [ ] Pin the reviewed backend, client, and provider commits and immutable build
      artifacts. Record the database migration set and rollback artifact.
- [ ] Confirm both reviewed client and provider releases are available and their
      mandatory minimum-version gates are active. Prove old clients cannot reach
      ride creation without the BR-37 booking key and old providers cannot advertise
      ride-offer receipt capability or go Online.
- [ ] Apply/revert the additive migrations on an isolated production-size clone.
      Prove both concurrent indexes, constraints, query plans, and multi-replica
      lock behavior. Recreate the local `test:ride-cutover-safety` scenario on
      the clone: closed-gate direct insert refusal plus both exact active-ride
      cutover refusals must leave driver/session/token/ride/offer state unchanged.
- [ ] Take and identify a database PITR point. Confirm the old backend artifact
      remains deployable against the additive schema.
- [ ] Close the Redis topology blocker, alerts, dashboards, on-call coverage,
      customer notice, and rollback decision owner.
- [ ] Prove physical Android and iOS receipt/recovery behavior, including delayed,
      duplicate, background, terminated, locked, reconnect, and lost-response cases.

## Mandatory-build contract to pin before the window

- [ ] Record exact positive release build numbers for client Android/iOS and
      provider Android/iOS. Do not reuse the current `1.3.11+20` build identity.
- [ ] Record and independently open the exact reviewed HTTPS store URLs for all
      supported app/platform pairs. A positive minimum without its corresponding
      store URL must fail backend configuration validation.
- [ ] Configure, but do not activate on the draining old backend, the four
      minimums `MOBILE_MIN_BUILD_CLIENT_ANDROID`,
      `MOBILE_MIN_BUILD_CLIENT_IOS`, `MOBILE_MIN_BUILD_PROVIDER_ANDROID`, and
      `MOBILE_MIN_BUILD_PROVIDER_IOS`, plus the corresponding four
      `MOBILE_STORE_URL_*` values.
- [ ] Prove the pinned builds send `X-MyShop-App`, `X-MyShop-Platform`, and
      `X-MyShop-Build` on first-party API calls and that missing, malformed,
      spoofed-role, or below-minimum metadata receives the stable
      `426 APP_UPDATE_REQUIRED` contract.
- [ ] Confirm enforcement covers `POST /rides`, affected `/media/*`,
      `POST /notifications/register-device`, `POST /providers/availability`,
      `POST /location/update`, `POST /location/driver/batch`, and
      `POST /location/artisan/update`. The last three are the provider app's
      actual GPS-based online paths; guarding only `/providers/availability`
      does not block an old provider build.
- [ ] Prove dispatch requires both an active v1 delivery token and v1 capability
      bound to the provider's current authenticated online/location session.
      A persistent `offer_receipt_version=1` token row by itself is insufficient:
      an old or downgraded app can otherwise remain a candidate and burn each
      ten-second delivery window.

## Phase A — pause new bookings and drain

- [ ] Set audited platform config `rides_enabled=false`. Do **not** use global
      `maintenance_mode`: it would also block active-trip lifecycle calls.
- [ ] Verify a genuinely new `POST /rides` returns
      `503 RIDE_BOOKING_PAUSED`, while same-key recovery, ride tracking, acceptance,
      status transitions, cancellation, payment, and safety endpoints still work.
- [ ] Wait for cache invalidation to be observed by every replica, then prove the
      new-ride counter remains zero.
- [ ] Drain or explicitly resolve every actionable protocol-0 ride. Do not stop
      the old backend while a requested or active legacy ride remains.
- [ ] Run the read-only preflight below twice, separated by at least one complete
      legacy worker interval. Both snapshots must show zero actionable protocol-0
      rides and zero open offers before proceeding.

```sql
SELECT dispatch_protocol_version, status, COUNT(*) AS rides
FROM rides
WHERE deleted_at IS NULL
  AND status IN (
    'requested', 'accepted', 'driver_en_route', 'arrived_at_pickup', 'in_progress'
  )
GROUP BY dispatch_protocol_version, status
ORDER BY dispatch_protocol_version, status;

SELECT state, COUNT(*) AS offers
FROM ride_offers
WHERE state IN ('delivering', 'active')
GROUP BY state
ORDER BY state;

SELECT key, value, updated_at
FROM platform_config
WHERE key = 'rides_enabled';
```

## Phase B — stop every old worker

- [ ] Suspend/stop the old API service and prove all old replicas and cron workers
      have exited. Capture the Render event, old image/commit, stop time, and owner.
- [ ] Re-run the actionable-ride query directly against PostgreSQL. If any row is
      non-zero, remain stopped and resolve it under the incident owner; do not deploy
      mixed workers.
- [ ] Verify the migration executor uses the direct database endpoint and the API
      service has boot migrations and seeding disabled.

## Phase C — migrate and start V2 closed

- [ ] Apply the reviewed migrations once. Verify Prisma reports no pending or
      failed migration.
- [ ] Verify the migration forced the database `rides_enabled` value to `false`.
      Invalidate only that environment's resolved `config:rides_enabled` Redis
      cache entry and prove a direct read cannot return a stale `true` before
      any V2 process starts.
- [ ] Verify `rides_enforce_booking_gate` is the reviewed `BEFORE INSERT` trigger
      on `rides`. A stale/legacy writer must not be able to bypass the closed
      gate; the reviewed API must map its `RIDE_BOOKING_DISABLED` database
      refusal to stable `503 RIDE_BOOKING_PAUSED` without affecting recovery or
      active-ride lifecycle endpoints.
- [ ] Verify `ride_offers`, booking-idempotency columns, partial unique indexes,
      due-work indexes, and constraints exist with their reviewed definitions.
- [ ] While every old worker is stopped and rides remain closed, run the reviewed
      environment-scoped capability reset: set every stored driver
      `offer_receipt_version` to `0`, force idle drivers/artisans Offline, and
      clear their matching GEO/heartbeat membership. Record only counts and the
      approved script hash. Do not reset or expose FCM token values.
- [ ] Start only the pinned V2 backend artifact with `rides_enabled=false`, all
      four approved minimum-build values active, and no old replica. Health must
      show PostgreSQL and Redis `ok`.
- [ ] Prove an installed old provider cannot register receipt capability or
      become Online through availability, foreground GPS, background batch, or
      artisan GPS calls. Prove the pinned provider build first re-registers its
      token/capability into a newly issued authenticated online/location session,
      then becomes Online. Offline, logout, token downgrade/revocation, and a
      superseding session must fence the old capability. The server must return
      a stable, actionable failure instead of showing Online when no current
      capability exists.
- [ ] Run authenticated staging canaries: unused booking-key lookup returns the
      stable 404; a lost create response resolves to the same ride; a reused key with
      a changed body returns 409; one provider receipts within ten seconds and gets a
      fresh database-clock 45 seconds; delayed/duplicate actions stay idempotent.
- [ ] Prove restart, Redis loss, worker lease recovery, five-minute matching
      cutoff, two-minute never-ready cleanup, and no duplicate ride/offer/driver
      holder under real PostgreSQL concurrency.

## Phase D — reopen gradually

- [ ] Re-prove the client and provider minimum-version gates from installed old
      builds before reopening, including process-already-running and locally
      cached Online states. A store listing is not enforcement evidence.
- [ ] Set `rides_enabled=true`, confirm every replica observes it, and allow only
      the two approved staging testers first.
- [ ] Observe ride-create, offer-delivery, receipt, decision, expiry, cancellation,
      duplicate-suppression, latency, error, DB-pool, Redis, and notification metrics.
- [ ] Stop and roll back on any duplicate ride/holder, lost ride, stale client
      state, protocol-0 write, elevated latency/error rate, or unverifiable worker.
- [ ] Expand the canary only after the approved observation window; production
      remains a separate approval.

## Rollback boundary

- [ ] Immediately set `rides_enabled=false` and keep V2 running long enough to
      drain or explicitly resolve any protocol-1 work.
- [ ] If **no** protocol-1 ride was created, the old artifact may be restored
      after every V2 worker stops; retain the additive database columns/tables.
- [ ] If any protocol-1 ride exists, do not start the old worker against it. Keep
      bookings paused, use the pinned V2 artifact to resolve work, and follow the
      incident/PITR decision. Never improvise a destructive down-migration on live
      ride data.
