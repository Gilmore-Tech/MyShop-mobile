# Backend / Mobile Ride Contract — Status & Outstanding Items

Snapshot of the rider/driver ride lifecycle from the mobile-app perspective. Reads as a checklist of what the backend ships, what the mobile depends on, and what's still outstanding. Last verified against `myshop` HEAD on 2026-04-26.

> **Before chasing any "ride is broken" report, check the deployed Render version first.** See [§5 Render deployment check](#5-render-deployment-check) — most of the bugs we used to investigate here turned out to be the deployed image lagging HEAD.

---

## 1. Landed on backend (mobile depends on these)

The items below are implemented in `myshop/apps/api/` and the mobile assumes them. If a bug looks like one of these is missing, suspect a stale Render deploy first.

| # | Item | Mobile assumption | Backend implementation |
|---|---|---|---|
| 1 | **Canonical `ride:state` event** | Single full-snapshot event drives every rider/driver state derivation. | Emitted on every status transition, on accept, on stage-timeout cancel, and per-ride throttled (5 s) during location updates. See [`ride-status.service.ts:168`](../../myshop/apps/api/src/modules/ride/ride-status.service.ts), [`location.gateway.ts`](../../myshop/apps/api/src/modules/location/location.gateway.ts), [`ride-stage-timeout.service.ts:161`](../../myshop/apps/api/src/modules/ride/ride-stage-timeout.service.ts). |
| 2 | **Idempotent `PATCH /v1/rides/:id/status`** | Mobile sends `desired_status` (e.g. `completed`) once; backend walks the ladder. Replays of the same status are no-ops, not 400s. | [`ride-status.service.ts:106-146`](../../myshop/apps/api/src/modules/ride/ride-status.service.ts) walks `STAGE_ORDER` transactionally; idempotent replay returns the current snapshot. |
| 3 | **Completion writes commission to `Payment` (not `Ride`)** | PATCH-status `completed` returns the ride entity with `finalFarePesewas`; commission is *not* a Ride column. | [`ride-status.service.ts:188-194`](../../myshop/apps/api/src/modules/ride/ride-status.service.ts) calls `paymentService.recordRideCompletion(rideId)` fire-and-forget after the transaction commits. |
| 4 | **Stage-timeout windows tunable via `PlatformConfigService`** | Driver realistically takes 4 min from `accepted`, 15 min en-route, 10 min at pickup. | [`ride-stage-timeout.service.ts:11-78`](../../myshop/apps/api/src/modules/ride/ride-stage-timeout.service.ts) reads `ride_accepted_max_secs` (default 120s), `ride_en_route_max_secs` (900s), `ride_arrived_max_secs` (600s). |
| 5 | **Stuck-busy cleanup** | If the driver disappears mid-ride, server auto-cancels and frees them. | `RideStageTimeoutService.sweepStuckStages()` runs every 30 s; cancel sets `driver.onlineStatus = 'online'`, clears matcher Redis state, emits `ride:state` + legacy events. |
| 6 | **`ride:decline` socket event** | Driver-side acceptance window expires → emit `ride:decline { rideId }` so the matcher can pivot. | [`location.gateway.ts:481-493`](../../myshop/apps/api/src/modules/location/location.gateway.ts) handler. |
| 7 | **Notified-driver dedupe** | Each candidate driver hears `ride:new` exactly once per ride; expansion-radius emit only sees new candidates. | `RIDE_NOTIFIED_KEY` Redis set in [`ride.service.ts:186-188`](../../myshop/apps/api/src/modules/ride/ride.service.ts), filtered on radius expansion at lines 630-635 / 731-735. |
| 8 | **`GET /drivers/me/active-ride`** | Driver app calls this on every `AuthAuthenticated` transition to recover a stranded mid-trip session. | [`drivers.controller.ts:23-39`](../../myshop/apps/api/src/modules/ride/drivers.controller.ts), backed by `RideService.getActiveRideForDriver()`. Composite index `(driverId, status)`. |
| 9 | **Location throttle is 2 s** | Driver heartbeats every 4 s; one missed POST is fine. | `RATE_LIMIT_TTL_SECS = 2` in [`location.service.ts:23`](../../myshop/apps/api/src/modules/location/location.service.ts). |
| 10 | **Geo entries don't auto-expire** | Driver visibility persists until explicit offline. | `redis.geoadd(DRIVERS_GEO_KEY, …)` is called without TTL; cleared via `redis.zrem` on `goOffline` ([`location.service.ts:117`](../../myshop/apps/api/src/modules/location/location.service.ts)). |
| 11 | **Per-fix `driver:location` broadcast** | Rider's marker animates on every fix; payload includes `latitude`, `longitude`, `heading`, `speed`, `etaMinutes`, `rideStatus`, `timestamp`. | [`location.gateway.ts:381-390`](../../myshop/apps/api/src/modules/location/location.gateway.ts) under `@SubscribeMessage('driver:location:update')` — note the event name. |
| 12 | **Snapshot includes driver coords** | Used to seed the rider's marker before the first per-fix event arrives. | [`ride-snapshot.service.ts:117-118`](../../myshop/apps/api/src/modules/ride/ride-snapshot.service.ts) — `driver.currentLat` / `driver.currentLng` (PostGIS-derived). |

### Wire-shape gotchas the mobile depends on

These are the field names the mobile reads from the canonical snapshot. If the backend ever renames them, mobile silently shows blanks.

- **Driver coords on snapshot**: `driver.currentLat` / `driver.currentLng` (NOT `latitude`/`longitude`).
- **Driver coords on per-fix `driver:location` event**: `latitude` / `longitude` (legacy shape, kept for backward compat).
- **Ride coords**: `pickupLat` / `pickupLng` / `dropoffLat` / `dropoffLng`. Aliases `pickupLatitude` etc. accepted by mobile parser as defensive fallback.
- **Driver-side socket emit for location**: `driver:location:update`. (Earlier mobile builds emitted `location:update` — that name has no handler and was silently dropped.)
- **Total fare**: `finalFarePesewas` after completion, `estimatedFarePesewas` before. Mobile reads `totalFare` as the canonical "what the rider paid" — backend computes this in `ride-snapshot.service.ts:122` as `finalFarePesewas ?? estimatedFarePesewas ?? 0`.

---

## 2. Outstanding — would simplify the mobile

### 2.1 Per-line fare components in `RideSnapshot`

**Problem**: snapshot returns `baseFare`, `distanceFare`, `bookingFee` as constant `0` ([`ride-snapshot.service.ts:150-152`](../../myshop/apps/api/src/modules/ride/ride-snapshot.service.ts)). The driver completion summary and rider receipt screens have UI for a per-line breakdown but currently suppress those rows because the values are zero. Without backing data the rider sees only "Total Paid" — fine for now, but the breakdown UI exists and is wasted.

**Ask**: when `status='completed'`, populate `baseFare`, `distanceFarePesewas`, `timeFarePesewas`, `surgeFarePesewas`, `taxesPesewas`, `promoDiscountPesewas`. Source from the same calculation that produces `finalFarePesewas` in `fare.service.ts`.

**Mobile impact**: receipt screens (`apps/client/lib/src/features/ride/screens/ride_complete_screen.dart`, `ride_receipt_screen.dart`, `apps/provider/lib/src/features/driver_home/screens/driver_ride_complete_screen.dart`) already render the rows when components are non-zero — they just need real numbers.

### 2.2 `GET /clients/me/active-ride` endpoint

**Problem**: rider recovery currently calls `listRides(limit: 5)` and filters for the most recent active row ([`apps/client/lib/src/core/providers/active_ride_recovery_bridge.dart:41`](../apps/client/lib/src/core/providers/active_ride_recovery_bridge.dart)). Drivers got `GET /drivers/me/active-ride` (item #8); riders need the equivalent.

**Ask**: `GET /v1/clients/me/active-ride` — auth: bearer (client only); response: full `RideSnapshot` or `{ data: null }`. "Active" = `clientId == me` AND status in `[accepted, driver_en_route, arrived_at_pickup, in_progress]`. Mirror the driver endpoint's index strategy.

**Mobile impact**: replace the listRides workaround with a single dedicated GET.

### 2.3 Drop legacy `ride:request` event

**Problem**: backend still emits both `ride:new` (canonical) and the legacy `ride:request`. Mobile listens to and dedupes both ([`apps/provider/lib/src/core/providers/socket_provider.dart:245-247`](../apps/provider/lib/src/core/providers/socket_provider.dart)).

**Ask**: deprecate after one mobile release cycle, then stop emitting.

**Mobile impact**: drop the `..off('ride:request') ..on('ride:request', ...)` lines once deprecated.

### 2.4 Push ETA refreshes (P2-1)

**Problem**: rider's "X min away" pill is seeded from the match payload and stays static until `ride:state` rolls over. The backend already computes `etaMinutes` per fix in [`location.gateway.ts:374-376`](../../myshop/apps/api/src/modules/location/location.gateway.ts) and emits `ride:eta` during `driver_en_route`; mobile just hasn't wired the listener yet.

**Mobile impact**: subscribe to `ride:eta { rideId, etaMins }` in `apps/client/lib/src/core/providers/socket_provider.dart` and route into `rideEtaProvider`. Already a tracking issue on the mobile side.

### 2.5 Surface matcher progress (P2-2)

**Problem**: while the matcher is iterating drivers (1 declined, trying 2), the rider sees no signal — they wait on the matching screen with no indication of progress.

**Ask**: emit `ride:matcher_progress { rideId, attempt, driversTried, driversRemaining }` whenever the matcher reassigns.

**Mobile impact**: small "Reassigning…" indicator on the matching screen.

### 2.6 Automatic demand-based surge engine

**Problem**: mobile already displays `surgeMultiplier`, but surge is only useful if the backend calculates it from live demand and locks it into the fare at booking time. A manual/default surge also creates trust issues: riders and drivers can see "high demand" when supply is actually normal.

**Ask**: make `POST /v1/rides/estimate` and `POST /v1/rides` call a server-side surge calculator scoped to pickup zone + ride category.

Suggested inputs:

- Demand window: requested/unmatched rides in the pickup zone during the last `surge_window_secs` (default 300).
- Supply window: online, verified, non-busy drivers for that category inside the matching radius, with heartbeat newer than the online TTL.
- Pressure score: `demand / max(availableDrivers, 1)`, with a `surge_min_requests` floor so one stranded request does not surge an empty zone.
- Signals to dampen abuse: recent acceptance rate, decline rate, and average pickup ETA can increase/decrease the score, but the demand/supply ratio should remain the main input.

Suggested multiplier tiers, all configurable via `platform_config`:

| Pressure score | Multiplier |
|---|---:|
| `< 1.2` | `1.00` |
| `1.2 - 1.79` | `1.10` |
| `1.8 - 2.49` | `1.25` |
| `2.5 - 3.49` | `1.40` |
| `>= 3.5` | `1.60` |

Guardrails:

- Cap by `surge_max_multiplier` (pilot default `1.60`, absolute admin max `2.00`).
- Add hysteresis/cooldown (`surge_cooldown_secs`, default 300) so the multiplier does not flicker every estimate call.
- Surge applies to new estimates/requests only. Persist the selected `surgeMultiplier` and `estimatedFarePesewas` on `Ride` when `POST /rides` succeeds; do not re-price a ride while it is waiting for acceptance.
- Fare formula should be deterministic and integer-safe: compute in pesewas, apply category multiplier and surge to the fare subtotal, subtract promo after commission basis is captured, then round up to the nearest whole GHS per PRD edge case #11.
- Admin can disable all surge with `surge_enabled=false`.

Mobile contract:

- Keep returning top-level `surgeMultiplier` on `POST /rides/estimate`.
- Return the same locked `surgeMultiplier` plus the locked `estimatedFarePesewas` from `POST /rides` and every `ride:state` / `GET /rides/:id` snapshot.
- Optional but useful: include `surgeReason` (`"high_demand"`, `"low_supply"`, `"long_eta"`) and `surgeZoneName` so mobile can make the banner more specific. Mobile remains compatible if these are absent.

### 2.7 Destination edit + booking-time multistops

**Problem**: mobile can now safely add mid-ride stops through `PATCH /v1/rides/:id/stops`, but related rider promises must stay backend-led so fare, route, and snapshots remain canonical:

1. **Booking-time multistops** — implemented on backend branch `feature/multistop-route-updates`: `POST /v1/rides` accepts/persists optional ordered `stops`, prices the same pickup → stops → dropoff route as estimate, includes stops in snapshots, and is gated by `ride_multistop_pretrip_enabled`. Not available to users until that backend branch is deployed and the flag is enabled.
2. **Destination edit** — there is no client endpoint to replace `dropoffLat/dropoffLng/dropoffAddress` on an active ride. This cannot be mobile-only because it must update the canonical ride, recalculate fare via Google Routes, notify driver + rider, refresh snapshots, and preserve final-fare auditability.

**Ask**:

- Deploy/test the backend booking-time multistop branch on staging, then enable `ride_multistop_pretrip_enabled` only for staging validation.
- Add a dedicated destination-edit endpoint, e.g. `PATCH /v1/rides/:id/destination`, auth client-only, active rides only:
  ```json
  {
    "dropoffLat": 6.7094,
    "dropoffLng": -1.5917,
    "dropoffAddress": "Bantama, Kumasi"
  }
  ```
- Endpoint should validate pilot region/service area, recompute route/fare, persist updated dropoff + estimated fare, emit `ride:route_updated`, then emit canonical `ride:state`.
- Response should include the full updated ride snapshot or at least `{ newFarePesewas, distanceMeters, durationSeconds }`.

**Mobile impact**:

- Pre-trip Add Stop is hidden unless `ride_multistop_pretrip_enabled` is true. When enabled, mobile sends the same ordered stops to estimate and booking.
- Destination row on the in-trip Add Stop screen must remain read-only until `PATCH /rides/:id/destination` lands.
- Mobile already treats existing backend stops as read-only and only allows editing/removing newly-added pending stops before confirmation, so the UI does not lie about route/fare state.

---

## 3. Mobile-only follow-ups (no backend dep)

For visibility — these don't need backend work, just mobile:

- **Rider tracking maintainer interval** drops to 5 s during `in_progress` (vs 12 s otherwise) to reduce the worst-case End-Trip → /ride-complete navigation lag if the canonical `ride:state` push is delayed. See [`ride_provider.dart` `activeRideTrackingMaintainerProvider`](../apps/client/lib/src/features/ride/providers/ride_provider.dart).
- **Driver socket stays connected while `busy`**, not just `online` — recovery into a mid-trip ride keeps receiving `ride:state` updates and the location heartbeat keeps firing for the rider's marker.
- **Rider recovery seeds `rideSearchProvider`** with pickup/destination from the snapshot so the tracking map's markers, polyline, and HEADING-TO overlay render after force-quit/relaunch.

---

## 4. Architectural target — mostly delivered

The "M-1 to M-5" migration plan from the original doc has largely landed:

- ✅ **M-1** Canonical `ride:state` event with full snapshots — see item #1 above.
- ✅ **M-2** Idempotent status walker — see item #2.
- 🟡 **M-3** Structured error envelope — backend wraps Prisma errors in NestJS exception filters, but mobile would benefit from a documented `{ error: { code, message, details } }` shape for every 4xx/5xx so we stop guessing at error formats. Verify by reading `apps/api/src/common/filters/`.
- ✅ **M-4** `GET /drivers/me/active-ride` — see item #8. Client equivalent in §2.2.
- ✅ **M-5** Socket.IO Redis adapter — implied by `feat(ride,api,common): canonical ride:state, idempotent status walker, multi-instance socket adapter` (commit `a8094f1`). Verify with a multi-task Fargate test before pilot peak.

Outstanding from the migration: drop the 5 s `getRide` poll loop in `apps/client/lib/src/features/ride/providers/ride_provider.dart` (`requestRideAndMatchDriver`) and the multi-name driver-location listener fallbacks now that `ride:state` is the single source of truth. Plan once §2 items land.

---

## 5. Render deployment check

The free-tier Render service deploys from GitHub but **does not auto-deploy on every push**. The deployed image can lag HEAD by days. A bug that "should be fixed in the code" often turns out to be the deployed image not reflecting recent commits.

**Verify before debugging**:

1. Check the deployed commit SHA — `curl https://staging-api.myshop.com.gh/health` (or whichever endpoint surfaces it) and compare against `git log -1 --format=%h` in `myshop`.
2. If lagging: trigger a manual deploy from the Render dashboard, OR push an empty commit to kick CI:
   ```bash
   cd ~/Desktop/ayiks/gilmore/myshop
   git commit --allow-empty -m "chore: trigger redeploy"
   git push
   ```
3. Wait ~3 min for Render to build + start, then re-test.
4. Keep in mind: Render free tier sleeps after ~15 min idle; first request after a long pause takes 30–60 s.

If you find a bug that this doc claims is fixed and the deploy is current, update §1 to reflect reality and add it to §2.

---

## 6. Coordination notes

- Track each open §2 item as a separate ticket so progress is visible per-fix.
- §1 items are mobile-transparent — backend ships, mobile gets healthier without code change.
- Any wire-shape change in §1 (field renames, event renames) needs a release-cycle handshake — keep both shapes live until mobile drops the legacy reader.
- Update this doc whenever a §2 item lands or a new mobile-affecting bug is discovered.
