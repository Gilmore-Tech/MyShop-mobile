# Backend Changes Needed — Ride Matching & Lifecycle

Discovered while debugging the rider/driver flow on `myshop-mobile`. Mobile workarounds are in place where possible, but the items below need backend work for the system to be reliable in production.

Ordered by impact: P0 = causes user-visible bugs today, P1 = simplifies the mobile, P2 = nice-to-have UX.

---

## P0-0 — `prisma.ride.update()` rejects `commissionPesewas` on `complete`

### Problem
`PATCH /v1/rides/:id/status` with `{status: "completed"}` 500s with:

```
PrismaClientValidationError: Unknown argument `commissionPesewas`.
  at RideStatusService.updateStatus (apps/api/dist/modules/ride/ride-status.service.js:116)
```

The service is trying to write `commissionPesewas` to the `Ride` row, but the `Ride` Prisma model doesn't have that column — only `finalFarePesewas` is recognised. The ride therefore stays in `in_progress` indefinitely; the mobile recovery bridge keeps restoring it on every relaunch, and the driver is stuck on the active-ride screen.

Reproduction: drive any test ride to `in_progress`, tap End Trip.

### Proposed change
Pick one in `apps/api/src/modules/ride/ride-status.service.ts` near the `completed` branch:

- **(preferred)** Drop `commissionPesewas` from the `prisma.ride.update({ data })` call and write it to the related earnings/payout table instead. Commission is a payout concern, not a ride field.
- Add a `commissionPesewas Int?` column to the `Ride` model in `prisma/schema.prisma` and run a migration. Quick fix if you want the field on the ride row.
- Compute commission at read time from `finalFarePesewas × commissionRate` and don't persist it.

### Mobile impact
Mobile shipped a temporary escape hatch — kebab → "Cancel ride" on the active-ride screen — that calls `PATCH /rides/:id/cancel` best-effort and clears local state regardless. Once the backend fix lands, drivers can finish trips normally and the cancel hatch becomes a true cancel-only path.

---

## P0-1 — Stuck "busy" state cleanup

### Problem
When a driver accepts a ride but never advances it (app crash, force-quit, network drop), the ride sits in `accepted` indefinitely and the driver remains flagged `busy`. All subsequent ride requests in that driver's area return `NO_DRIVERS_AVAILABLE` even though the driver appears online in the app. We hit this in QA after the bounce-back bug forced an accept loop.

### Proposed change
Pick one (or both):

**A. Server-side timeout per status** (preferred)
- If a ride sits in `accepted` for more than **120s** without transitioning to `driver_en_route`, auto-cancel with reason `driver_no_progress`, free the driver (`busy → online`), and re-emit the request to the next driver in the matcher pool.
- Same idea for `driver_en_route → arrived_at_pickup` (e.g. 15min timeout) and `arrived → in_progress` (e.g. 10min).

**B. Driver-initiated cancel before pickup**
- Add `PATCH /rides/:id/cancel` permission for the assigned driver pre-pickup (currently the docs only allow client cancel).
- Body: `{ reason: string }`. Backend response: `{ status: 'cancelled' }`. Free the driver afterwards.

### Mobile impact
- Mobile already has an active-ride-recovery bridge (`active_ride_recovery_bridge.dart`) that calls `GET /rides/:id` on app start. Once `(A)` is in place, the recovery flow will see `cancelled` and clear cleanly. Without it, the only recovery path is to manually intervene in the DB.

---

## P0-2 — `ride:decline` event (or server-side acceptance window)

### Problem
The driver-side acceptance window is currently a **22-second client-only timer**. When it expires, the screen pops back to home but the **backend never finds out**. The matcher keeps re-broadcasting to the same driver until something else times it out, blocking reassignment to the next driver.

### Proposed change
Pick one:

**A. Explicit decline event** (preferred — gives matcher fast signal)
- Driver socket emits `ride:decline { rideId }`.
- Backend ack: `{ ok: true }`.
- Backend reaction: remove this driver from the candidate set for this ride and immediately try the next eligible driver.

**B. Server-side acceptance window**
- Backend tracks per-driver `assignedAt` timestamp; if no `ride:accept` ack within **20s**, mark this driver as having declined and try the next.
- This is more resilient (works even if driver app crashes) but loses the ability to distinguish "ignored" from "explicit decline" for analytics.

Recommend implementing **both** — A for fast happy-path, B as a safety net.

### Mobile impact
- Once shipped, the driver app's `_decline()` (in `apps/provider/lib/src/features/driver_home/screens/ride_request_screen.dart`) will emit `ride:decline` instead of just popping the screen.

---

## P0-3 — Stop re-broadcasting the same request to the same driver

### Problem
Provider logs show `ride:request` AND `ride:new` for the same `rideId` firing 3+ times to the same driver within ~10s. Mobile dedupes via `surfacedRideIdsProvider`, but the network/CPU waste and the matcher's confused state are still real.

### Proposed change
- The matcher should notify each candidate driver **exactly once** per ride.
- After their acceptance window expires (P0-2), move to the next candidate.
- Don't fan out the same request to the same socket more than once.

### Mobile impact
- The mobile dedupe set can stay (defensive), but the symptom goes away.

---

## P0-4 — Loosen location-update throttle OR raise Redis TTL

### Problem
- Current config: driver location entry has **5s TTL** in Redis (per EDD §5.3); REST `POST /location/update` is rate-limited to **1 per 3s**.
- The driver app heartbeats every 4s. Any single throttled POST (which we observed in logs as `ThrottlerException: Too Many Requests`) means the entry expires before the next successful write → driver invisible to the matcher → `NO_DRIVERS_AVAILABLE` even when stationary and online.

### Proposed change
Pick one:
- **Raise TTL to 10–15s.** The matcher tolerance for slightly older fixes is fine; even 15s old is acceptable for ride matching.
- **OR loosen throttle to 1 per 2s.** Gives the 4s heartbeat enough headroom that one missed POST doesn't kill the entry.

Recommend the TTL change — it's a single config flip and addresses the root cause.

### Mobile impact
- Mobile heartbeat already at 4s with `socket.emit` between fixes; nothing to change client-side.

---

## P1-1 — `GET /drivers/me/active-ride` endpoint

### Problem
There's no driver-side equivalent of "what ride am I currently on?" — `GET /rides/:id` requires knowing the id. Mobile currently persists the rideId in `SharedPreferences` to recover from crashes, but this:
- Doesn't survive app reinstall.
- Doesn't work if the driver signs in on a new device.
- Drifts if the backend cleans up a ride server-side without the app knowing.

### Proposed change
- New endpoint: `GET /drivers/me/active-ride`.
- Auth: Bearer (driver only).
- Response 200 (active ride exists): full Ride entity (same shape as `GET /rides/:id`).
- Response 200 (no active ride): `{ data: null }`.
- "Active" = ride status in `[accepted, driver_en_route, arrived_at_pickup, in_progress]` AND `assignedDriverId == me`.

### Mobile impact
- Replace the SharedPreferences round-trip in `active_ride_recovery_bridge.dart` with a single call to this endpoint. Simpler, more correct, no local-state drift risk.

---

## P1-2 — Drop the legacy `ride:request` event

### Problem
Backend emits both `ride:request` (legacy) AND `ride:new` for every driver notification. Mobile has to listen to both and dedupe. Each event also has a slightly different payload shape (`pickupLat` vs `pickupLatitude`).

### Proposed change
- Pick `ride:new` as canonical (richer payload, includes `clientName`, `clientPhotoUrl`).
- Deprecate `ride:request` — remove after one mobile release cycle.
- Document the canonical event in the EDD.

### Mobile impact
- Drop the `..off('ride:request') ..on('ride:request', ...)` lines once deprecated.

---

## P1-3 — Confirm rider socket events are wired

### Problem
Mobile assumes the following but we haven't been able to verify all of them in QA (the rider was sometimes stuck on the matching screen even after the driver accepted, before our recent fixes):

### Required events
On the rider's tracking room (joined via `client:track:ride { rideId }`):

| Event           | When                                  | Payload                                        |
|-----------------|---------------------------------------|------------------------------------------------|
| `ride:accepted` | Driver `ride:accept` succeeds         | `{ rideId, driver: { name, vehicle, plateNumber, rating, eta, ... }, baseFare, distanceFare, bookingFee, totalFare, distanceKm, paymentMethod }` |
| `ride:status`   | Every backend status transition       | `{ rideId, status: 'driver_en_route' \| 'arrived_at_pickup' \| 'in_progress' \| 'completed' \| 'cancelled' \| 'no_drivers' }` |

### Ask
- Confirm the events fire and match the payload shape.
- Confirm `client:track:ride` is handled by the gateway and adds the socket to a `ride:{rideId}:client` room.
- If the payloads differ from what's listed, send the actual schema and we'll adapt — or better, document them in the EDD.

### Mobile impact
- Already coded against the contract above (see `apps/client/lib/src/core/providers/socket_provider.dart`). Any payload divergence shows up as silent failures (defaults applied), not crashes — please flag if shapes differ.

---

## P2-1 — Push ETA refreshes to the rider

### Problem
Mobile previously simulated ETA decrement with client-side timers. We removed the simulation; ETA now stays at the snapshot value from the match payload. UX is correct but static — riders don't see a live-updating "3 min away" pill.

### Proposed change
Either:
- Add a `ride:eta { rideId, etaMins }` event emitted every ~15s while the ride is `driver_en_route`, OR
- Include `etaMins` in the periodic location broadcasts the rider already gets.

### Mobile impact
- Wire the new event to `rideEtaProvider` in `apps/client/lib/src/core/providers/socket_provider.dart`.

---

## P2-2 — Surface matcher progress to the rider

### Problem
The rider currently sees only two signals: "drivers notified" (from POST `/rides`) and "accepted" (from `ride:accepted`). When the matcher is iterating through drivers (driver 1 declined, trying driver 2), the rider sees nothing — they wait on the same screen with no indication of progress.

### Proposed change
- Emit `ride:matcher_progress { rideId, attempt: int, driversTried: int, driversRemaining: int }` whenever the matcher reassigns.
- Optional: include an estimated continuation time so the UI can show "Still searching — usually 10–30s".

### Mobile impact
- Add a small "Reassigning…" indicator in the matching screen between `driverFound` and `accepted` phases.

---

## Coordination notes

- The mobile changes for P0-2 (`ride:decline`) and P1-1 (`GET /drivers/me/active-ride`) are blocked on backend. Everything else (P0-1, P0-3, P0-4) is mobile-transparent — backend ships, mobile gets healthier without any code change.
- P1-2 (event rename) needs a release-cycle handshake — backend keeps both events live until mobile drops the legacy listener.
- Recommend tracking each item as a separate ticket so progress is visible per-fix.

---

# Architectural migration target — canonical ride contract

The P0 / P1 fixes above are individually correct, but the *class* of bugs we keep hitting (matching-screen freezes, stuck active rides, status-transition rejections, lifecycle hook races, raw Prisma leaks) all stem from the same root cause: **mobile and backend each run their own ride state machine, with three reconciliation channels (sockets, REST polling, SharedPreferences) that have different latencies and failure modes.**

This section is the long-term contract we want the backend to ship so the mobile becomes a pure reflection of backend state. It supersedes piecemeal fixes once delivered. Mobile migration is phased and only starts once items 1–4 land.

## Backend deliverables

### M-1. Single canonical event: `ride:state`

Backend emits `ride:state` to both `ride:{rideId}:driver` and `ride:{rideId}:client` rooms on **every** ride state change (status transition, driver location bump, fare update, stop added/cancelled, anything observable to the participants). Payload is the **full ride snapshot** — same shape as `GET /rides/:id`:

```jsonc
{
  "rideId": "…",
  "status": "driver_en_route",
  "client": { "id", "name", "photoUrl", "rating", "tripCount", … },
  "driver": { "id", "name", "photoUrl", "rating", "vehicle", "plateNumber",
              "latitude", "longitude", "heading", "etaMins", … },
  "fare": { "estimated", "final?", "currency", "paymentMethod", … },
  "route": { "pickup": {…}, "dropoff": {…}, "stops": [...] },
  "timestamps": { "createdAt", "acceptedAt", "driverEnRouteAt",
                  "arrivedAtPickupAt", "startedAt", "completedAt",
                  "cancelledAt" }
}
```

Replaces all of: `ride:accepted`, `ride:status`, `ride:driver_location`, `driver:location`, `ride:location`, `ride:eta`, `ride:matcher_progress`. The mobile applies one snapshot — no partial mutations across multiple handlers.

Driver location is **just a field on the snapshot** that bumps every ~5 s while the ride is active.

### M-2. Idempotent `PATCH /v1/rides/:id/status`

Accept `{ desired_status }`; the backend walks the legal path in one transaction:

| Driver desires | Backend transitions through |
|---|---|
| `driver_en_route` | `accepted → driver_en_route` |
| `arrived_at_pickup` | `accepted → driver_en_route → arrived_at_pickup` (if needed) |
| `in_progress` | (ditto, then `→ in_progress`) |
| `completed` | (ditto, then `→ completed`) |

Returns the full ride entity (same shape as the snapshot). Replays of the same desired status are no-ops, not 400s.

Eliminates the mobile-side `markEnRoute` workaround (currently fired from `ActiveRideNotifier.acceptRide`), the `_hasAutoStartedEnRoute` guard, and the `INVALID_STATUS_TRANSITION` band-aids.

### M-3. Structured error envelope

Every 4xx / 5xx returns:

```json
{ "error": { "code": "INTERNAL_RIDE_UPDATE_FAILED",
             "message": "human-readable",
             "details": { "field": "commissionPesewas" } } }
```

Wrap Prisma exceptions in a Nest exception filter so a `PrismaClientValidationError` becomes `INTERNAL_RIDE_UPDATE_FAILED` with the offending column in `details.field`. Same for foreign-key errors, transaction rollbacks, etc. P0-0 was hidden as a generic 500 for hours of debugging — that's the failure mode this kills.

### M-4. `GET /v1/drivers/me/active-ride`

Already in P1-1. Re-stating because it's load-bearing for the migration: it replaces SharedPreferences-based recovery (`apps/provider/lib/src/core/providers/active_ride_recovery_bridge.dart` + `apps/provider/lib/src/features/driver_home/providers/active_ride_persistence.dart`).

Composite index on `(assigned_driver_id, status)` so the query is sub-ms at pilot scale.

### M-5. socket.io Redis adapter

Add `@socket.io/redis-adapter` against the same Redis used for geo. Required for multi-task Fargate (EDD §2.3) — without it, a rider connected to task A can't receive emits from a driver connected to task B.

## Mobile migration phases (gated on backend)

### Phase A — once M-1, M-2, M-3, M-4 ship

- Drop the 5 s `getRide` poll loop in `apps/client/lib/src/features/ride/providers/ride_provider.dart` (`requestRideAndMatchDriver`).
- Drop `activeRideDriverPollerProvider` (8 s poll fallback for driver location).
- Drop the multi-name driver-location listeners in `apps/client/lib/src/core/providers/socket_provider.dart`; replace with a single `ride:state` listener.
- Add `ActiveRideNotifier.applySnapshot(Ride)` in `apps/provider/lib/src/features/driver_home/providers/ride_request_provider.dart`. Delete `applyRemoteStatus`, `_hydrateRide`, the auto-`markEnRoute` call, and the `_hasAutoStartedEnRoute` plumbing.
- Mirror snapshot-driven state on the client: replace `applyDriverMatch` + `bookingPhaseProvider` flips with one `RideTrackingState` derived from snapshots.
- Replace SharedPreferences recovery with `GET /drivers/me/active-ride`. Delete `active_ride_persistence.dart`.

### Phase B — once M-5 + P0-3 + P0-4 ship

- Drop `surfacedRideIdsProvider` dedupe in `apps/provider/lib/src/core/providers/socket_provider.dart` (matcher is exactly-once).
- Drop the REST POST + socket emit duplication in driver heartbeat; rely on socket-only.
- Confirm zero `429` in logs over a 30-min staging soak at pilot peak.

## Bugs resolved by this migration vs. discrete bugs that aren't

**Resolved (architectural class):** matching-screen freeze on accept, "modify provider during build" crashes on tracking-screen mount, `accepted → arrived_at_pickup` rejection, auto-`markEnRoute` silently failing, stuck active ride restored on relaunch, driver photo / live-tracking event-name guessing, REST poll stamping rate limits.

**Not resolved by migration (still need targeted fixes):** P0-0 (Prisma `commissionPesewas`), P0-3 (matcher dedupe), P0-4 (location TTL math). Migration makes the next P0-0-shaped bug a 30-second diagnosis instead of a multi-turn investigation.

## Verification

- Staging load test at pilot peak: 200 simulated drivers (4 s heartbeat), 50 concurrent ride requests, 5,000 idle authenticated clients. Targets per EDD §14.1: p99 PATCH `< 500 ms`, zero 429 over 30 min, zero ride stuck in `accepted` `> 30 s`, WS disconnect rate `< 0.5 % / min`, Redis driver-geo hit rate `> 99 %`.
- Per phase, on-device end-to-end ride request → completion with backend logs showing **exactly one `ride:state` per state change** and no fallback REST hits.
