# Surge display and driver map

The client fare estimate uses an arrow beside the inclusive price, with the multiplier available through its tooltip and accessibility label. There is no separate surge announcement banner. Promo prices keep their original strike-through presentation.

The driver home map displays orange-to-red polygons using the effective multiplier. Manual and automatic areas are clipped to their ride region. Automatic areas are localized pickup-demand hotspots; an operational region is never used as an automatic surge shape. Overlapping operational regions use the same priority, size, and ID ordering as ride-region resolution. Higher surge areas are subtracted from lower ones, preserving holes instead of stacking color or multipliers.

## Backend dependency

Deploy the matching backend changes in `myshop` before testing a new provider build:

- `GET /v1/surge/areas`: `generatedAt` and `areas`, each containing `id`, `regionId`, `name`, `source`, `multiplier`, `expiresAt`, and Polygon/MultiPolygon GeoJSON geometry.
- `surge:areas_changed`: socket invalidation sent to authenticated drivers after a manual change commits or automatic evaluation is stored. The app refetches authority rather than painting the event payload.
- `Cache-Control: no-store` prevents intermediaries from retaining old map snapshots.

While the driver map is visible, refreshes happen on invalidation, reconnect, resume, and every 10 seconds. Coverage has a maximum 25-second lease anchored to request start and is pruned every second, including during an outage. Backgrounding, logout/session replacement, and screen disposal clear the map feed and stop its timers. A missing endpoint leaves the map unshaded.

Automatic surge is evaluated every 15 seconds, using local pickup demand and available drivers inside `SURGE_AUTO_RADIUS_METERS` (default 2,000 metres, supported range 250–5,000). The existing demand/supply thresholds, weather uplift and caps remain in force. Weather is queried at each hotspot. Festive/event crowds are measured through local demand, while existing manual event-area multipliers remain supported; this does not add a separate holiday calendar.

A rider counts once: a requested ride supersedes their quote, and accepted/in-progress riders stop contributing unmet quote demand. Quote locations expire after five minutes, and a rider's latest location supersedes an older area's intent. Busy/offline/stale-location/review drivers do not inflate local supply. Automatic snapshots expire after 45 seconds and stale evaluators cannot overwrite newer authority. Quotes and heatmaps consume the same hotspot radius; outside every active area, automatic pricing stays at 1.0×.

Deploying ignores legacy region-wide Redis cache entries. No schema migration is required. The first localized snapshots warm from active requests and newly geolocated quote intents.

## Verification

Validated client estimate layouts and surge price disclosure, driver polygon/expiry/lifecycle behavior, backend surge and gateway regressions, and real PostGIS geometry. The PostGIS regressions use session-local temporary tables and no persistent changes. They verify separate neighborhoods in one region, rider deduplication, supply eligibility, and geographic map/pricing agreement. Run it with `SURGE_GEOMETRY_TEST_DATABASE_URL` set to a local PostGIS database and Jest targeting `surge-map-geometry.integration.spec.ts` and `local-surge-demand.integration.spec.ts`.

For device testing, toggle a manual surge on/off, wait for an automatic evaluation to change, pan across the area boundary, compare overlapping multipliers, and interrupt/reconnect the provider connection. Confirm both builds target the API version containing the area feed.
