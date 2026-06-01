# Earnings Module — Mobile Handoff

> **Audience:** Flutter Provider App team (driver + artisan flows).
> **Backend status:** All 6 PRs merged; available on `staging-api.myshop.com.gh` after the next deploy.
> **Migration deadline:** Legacy `GET /v1/payments/earnings` is deprecated and forwards to `/earnings/summary` for **one release window**. Cut over before the next backend release or the deprecated route disappears.

---

## TL;DR

The single `GET /v1/payments/earnings` endpoint is being replaced by **three** purpose-built endpoints. Each one matches a specific surface in the app:

| Surface | Endpoint | Cache (server) |
|---|---|---|
| Driver/Artisan **homepage card** ("Today's earnings") | `GET /v1/payments/earnings/today-card` | 60s |
| Earnings tab **top card** (available balance + sparkline) | `GET /v1/payments/earnings/summary` | 5min |
| Earnings tab **detailed report** (filterable, full graph) | `GET /v1/payments/earnings/report` | 5min for presets, none for custom ranges |

All three accept an optional `?role=driver|artisan` query param. **You should pass it explicitly for dual-role users** to make the intended provider scope unambiguous.

---

## 1. Why three endpoints?

Each surface has a different cardinality, freshness expectation, and response shape:

- The **today-card** is hit on every app open by every active driver — it must be tiny and fresh. 60-second TTL ensures a freshly-completed trip lands on the dashboard near-instantly.
- The **summary** is the earnings tab's headline view — needs the available balance plus a small sparkline; 5-minute TTL is fine.
- The **report** has heavyweight aggregations and a custom-range filter — 90-day cap, no cache for custom ranges (the keyspace is unbounded), but presets still cached.

Putting all three into one mega-endpoint with mode flags would entangle these very different cache strategies and force the today-card path to ship report-shaped JSON on every request.

---

## 2. Dual-role isolation — important behaviour change

A user with **both** a driver and an artisan profile (a single phone number per CLAUDE.md §8) will now see **strictly mutually exclusive** earnings per role. The old endpoint silently returned only the driver's earnings, dropping the artisan's. The new endpoints fix this:

- **DTO `?role=…` overrides the JWT.** When the mobile is showing the artisan view, pass `?role=artisan`. When showing the driver view, pass `?role=driver`.
- **JWT role is the fallback.** When `?role=` is omitted, the backend falls back to the JWT's `role` claim — already populated from the existing role-picker login screen.
- **Strict isolation:** `?role=driver` for a user without a driver profile returns **404 PROVIDER_NOT_FOUND** — never falls back to the artisan side. Same in reverse.

**Recommended mobile approach:** the active role is a known value in client state after the role-picker. Always pass it explicitly on every earnings request, even for single-role users, so a future second profile doesn't leak earnings data across roles.

---

## 3. Endpoint reference

All endpoints require Bearer auth. All money values are in **pesewas** (integer; GHS 1 = 100 pesewas). All ISO timestamps are UTC.

### 3.1 Today-card — homepage

**`GET /v1/payments/earnings/today-card?role=driver|artisan`**

#### Request

| Query param | Type | Required | Notes |
|---|---|---|---|
| `role` | `driver` \| `artisan` | optional | Defaults to JWT role. |

#### Response 200

```json
{
  "role": "driver",
  "date": "2026-04-28",
  "tripsCount": 7,
  "hoursWorkedMinutes": 215,
  "tipsEarnedPesewas": 1500,
  "netEarningsPesewas": 24500
}
```

For an artisan, `tripsCount` is omitted and replaced by `jobsCount`. Otherwise the shape is identical.

#### Field semantics

| Field | Source | Notes |
|---|---|---|
| `date` | UTC midnight today (Ghana = UTC+0, no DST) | YYYY-MM-DD |
| `tripsCount` / `jobsCount` | `rides` / `artisan_jobs` table | Counts completed bookings with `completedAt` today. Includes cash trips. |
| `hoursWorkedMinutes` | `(completedAt − startedAt)` summed | **Active trip/job time only** — does NOT include time online waiting for a ride. Idle session tracking will land in a future release. |
| `tipsEarnedPesewas` | `payments.tipPesewas` summed | Filter: `paymentStatus IN ('escrowed','completed')`, `createdAt` today. |
| `netEarningsPesewas` | `payments.netPayoutPesewas` summed | Same filter as tips. Post-commission. |

#### Errors

| Code | Status | When |
|---|---|---|
| `ROLE_NOT_RESOLVED` | 400 | No `?role=`, no JWT role, can't tell who is asking. |
| `PROVIDER_NOT_FOUND` | 404 | The user has no profile for the requested role. |

---

### 3.2 Summary — earnings tab top card

**`GET /v1/payments/earnings/summary?period=today|week|month&role=…`**

#### Request

| Query param | Type | Required | Notes |
|---|---|---|---|
| `period` | `today` \| `week` \| `month` | **required** | Drives the graph and the "selected period" net earnings figure. |
| `role` | `driver` \| `artisan` | optional | Defaults to JWT role. |

#### Response 200

```json
{
  "role": "driver",
  "period": "week",
  "startDate": "2026-04-21T12:00:00.000Z",
  "endDate": "2026-04-28T12:00:00.000Z",
  "availableBalancePesewas": 8000,
  "todayAvailableBalancePesewas": 2000,
  "weeklyAvailableBalancePesewas": 15000,
  "netEarningsPesewas": 50000,
  "paidOutPesewas": 40000,
  "series": [
    { "bucketStart": "2026-04-22T00:00:00.000Z", "netPesewas": 5000 },
    { "bucketStart": "2026-04-23T00:00:00.000Z", "netPesewas": 0 },
    { "bucketStart": "2026-04-24T00:00:00.000Z", "netPesewas": 10000 }
  ],
  "granularity": "day"
}
```

#### Field semantics

| Field | Notes |
|---|---|
| `availableBalancePesewas` | **Period-agnostic** (same value for all 3 periods). Sum of `escrowed` payments where `escrowReleasedAt IS NOT NULL` — money the provider can withdraw right now. **Cash trips never appear here** (driver already has the cash in hand). |
| `todayAvailableBalancePesewas` | Net earnings from today only — always shown alongside the period selection so the user sees today's contribution. |
| `weeklyAvailableBalancePesewas` | Net earnings over the last 7 days. Same intent as `todayAvailableBalancePesewas`. |
| `netEarningsPesewas` | Net earnings over the **selected period** (`period` query param). |
| `paidOutPesewas` | Money already disbursed to the provider in the period. Excludes cash. Use the `Payout` table's `completedAt` for exact reconciliation; this is a dashboard figure. |
| `series` | One bucket per day for `period=today\|week\|month`. **Already gap-filled** by the backend — days with no activity have `netPesewas: 0`. Plot directly. |
| `granularity` | Always `"day"` for preset periods. |

#### Errors

Same as today-card.

---

### 3.3 Report — detailed report view

**`GET /v1/payments/earnings/report?{period|from+to}&granularity=…&role=…`**

This is the heavyweight endpoint: gross/net/commission/tips/avg-fare + full graph. Two ways to call it:

**Mode A — Preset period:**
```
GET /v1/payments/earnings/report?period=week&role=driver
```

**Mode B — Custom date range:**
```
GET /v1/payments/earnings/report?from=2026-01-01&to=2026-01-31&role=driver
GET /v1/payments/earnings/report?from=2026-01-01&to=2026-03-15&granularity=week&role=driver
```

#### Request

| Query param | Type | Required | Notes |
|---|---|---|---|
| `period` | `today` \| `week` \| `month` | one of period OR (from+to) | Mutually exclusive with `from`/`to`. |
| `from` | ISO date `YYYY-MM-DD` | with `to` | Inclusive start. |
| `to` | ISO date `YYYY-MM-DD` | with `from` | Inclusive end. **Range capped at 90 days.** |
| `granularity` | `day` \| `week` \| `month` | optional | Override for graph buckets. Auto-derived if omitted: span ≤31d → day, ≤90d → week. |
| `role` | `driver` \| `artisan` | optional | Defaults to JWT role. |

#### Response 200

```json
{
  "role": "driver",
  "startDate": "2026-04-21T00:00:00.000Z",
  "endDate": "2026-04-28T00:00:00.000Z",
  "granularity": "day",
  "grossEarningsPesewas": 100000,
  "netEarningsPesewas": 80000,
  "commissionChargedPesewas": 20000,
  "tipsEarnedPesewas": 5000,
  "tripsCompleted": 10,
  "averageFarePesewas": 10000,
  "hoursWorkedMinutes": 540,
  "trendPct": 33.33,
  "series": [
    {
      "bucketStart": "2026-04-22T00:00:00.000Z",
      "grossPesewas": 50000,
      "netPesewas": 40000,
      "commissionPesewas": 10000,
      "tipsPesewas": 2000,
      "count": 5
    },
    {
      "bucketStart": "2026-04-23T00:00:00.000Z",
      "grossPesewas": 0,
      "netPesewas": 0,
      "commissionPesewas": 0,
      "tipsPesewas": 0,
      "count": 0
    }
  ]
}
```

For an artisan, `tripsCompleted` is omitted and replaced by `jobsCompleted`.

#### Field semantics

| Field | Notes |
|---|---|
| `grossEarningsPesewas` | **Includes cash AND in-app trips.** Sum of `payments.grossAmountPesewas`. |
| `netEarningsPesewas` | Gross minus commission. Sum of `payments.netPayoutPesewas`. |
| `commissionChargedPesewas` | 20% platform commission on pre-promo fare. |
| `tipsEarnedPesewas` | Tips received in the window. |
| `tripsCompleted` / `jobsCompleted` | Count of completed bookings (rides for drivers, artisan_jobs for artisans). |
| `averageFarePesewas` | `gross / count`, integer-rounded. **Returns 0 when count = 0** (safe to display directly). |
| `hoursWorkedMinutes` | Sum of `(completedAt − startedAt)` over completed bookings in the window. Same caveat as today-card — active trip time only. |
| `trendPct` | Percentage delta vs the previous **equal-length** window. **`null` when the previous window was 0** (no division by zero); render as `—` or hide the badge. |
| `series` | Time-series for the graph. Already gap-filled. Each bucket carries gross/net/commission/tips/count so the same data drives multiple chart layers. |

#### Errors

| Code | Status | When |
|---|---|---|
| `EARNINGS_RANGE_AMBIGUOUS` | 400 | Both `period` and `from`/`to` provided. |
| `EARNINGS_RANGE_INVALID` | 400 | Only one of `from`/`to`; or `to < from`; or no range provided. |
| `EARNINGS_RANGE_TOO_LARGE` | 400 | Custom range exceeds 90 days. |
| `ROLE_NOT_RESOLVED` | 400 | Same as today-card. |
| `PROVIDER_NOT_FOUND` | 404 | Same as today-card. |

---

## 4. UI mapping

This is what each endpoint feeds. Use this as a checklist while implementing.

### Driver homepage — "Today's earnings" card

```
GET /v1/payments/earnings/today-card?role=driver
```

- **Trips** = `tripsCount`
- **Hours** = `hoursWorkedMinutes / 60` (e.g. "3h 35m")
- **Tips** = `tipsEarnedPesewas` (display as GHS via `pesewasToGhs()`)
- **Today's net (headline)** = `netEarningsPesewas`

### Artisan homepage — same card, different label

```
GET /v1/payments/earnings/today-card?role=artisan
```

- **Jobs** = `jobsCount`
- All other fields identical.

### Earnings tab — top "Available balance" card

```
GET /v1/payments/earnings/summary?period=<selected>&role=<active>
```

- **Available balance (big number)** = `availableBalancePesewas`
- **Today's contribution** = `todayAvailableBalancePesewas`
- **This week** = `weeklyAvailableBalancePesewas`
- **Selected-period net (when user switches today/week/month)** = `netEarningsPesewas`
- **Sparkline graph** = `series[].netPesewas`
- **Withdraw CTA** is enabled when `availableBalancePesewas > 0` — wires to `POST /v1/payments/payouts/request`.

### Earnings tab — "View detailed report"

```
# Preset path (default tab)
GET /v1/payments/earnings/report?period=week&role=<active>

# Custom date range (date-picker UI)
GET /v1/payments/earnings/report?from=2026-04-01&to=2026-04-15&role=<active>
```

- **Gross earnings** = `grossEarningsPesewas`
- **Net earnings** = `netEarningsPesewas`
- **Commission** = `commissionChargedPesewas`
- **Tips** = `tipsEarnedPesewas`
- **Trips/Jobs** = `tripsCompleted` / `jobsCompleted`
- **Average fare** = `averageFarePesewas`
- **Trend badge** = `trendPct` (hide or render `—` when `null`)
- **Performance graph** = `series[]` — bar/line per bucket. Use `granularity` to label x-axis (daily / weekly / monthly).
- **Hours worked** (optional but free) = `hoursWorkedMinutes`

---

## 5. Date-range picker UX guidance

The custom range path is capped at 90 days server-side. Recommended client-side handling:

1. **Disable dates more than 90 days apart** in the picker so the user can't trigger `EARNINGS_RANGE_TOO_LARGE` accidentally.
2. **Format dates as `YYYY-MM-DD`** (ISO 8601 date only — no time, no timezone). The backend treats `from` and `to` as inclusive.
3. **Default the picker** to "Last 7 days" when opened — same window as `period=week` but lets the user reach for older windows naturally.
4. If you want to surface the auto-derived granularity to the user (e.g. "Showing weekly buckets"), read it from the response's `granularity` field.

---

## 6. Caching, offline behaviour, and refresh

The server caches the today-card for 60s and the summary/report (preset paths only) for 5 minutes. The cache is invalidated automatically on every payment status flip via webhook, so figures will be fresh after a trip settles even before the TTL expires.

**Mobile-side recommendations:**

- **Pull-to-refresh** on each surface (today-card, summary, report) is the simplest way to force-fetch.
- **Don't cache aggressively client-side** — the server cache TTLs are short by design. A 60-second client-side cache on the today-card is fine; longer adds little value.
- **Custom-range responses are not cached server-side.** Don't hammer the endpoint — debounce date-picker changes by ~300ms before firing the request.
- **No offline support needed for v1** — earnings figures aren't useful when stale. Show a clear empty state on network failure.

---

## 7. Migration plan from the legacy endpoint

The legacy `GET /v1/payments/earnings?period=…` still works but:

- Is marked `deprecated: true` in OpenAPI.
- Emits a `WARN` log on every hit so backend can spot stragglers.
- Forwards to `/earnings/summary` internally — **the response shape has CHANGED** (it's now the new `EarningsSummaryResponse`, not the old one). If you were reading any of these fields from the old endpoint, they no longer exist:
  - `totalEarningsPesewas` → use `netEarningsPesewas`
  - `totalTipsPesewas` → not on summary; use `/earnings/report` and read `tipsEarnedPesewas`
  - `totalCommissionPesewas` → same; use `/earnings/report`
  - `completedRides` → use `/earnings/today-card` (`tripsCount`) or `/earnings/report` (`tripsCompleted`)
  - `peakHours[]` → **dropped entirely**. Was unused by the mobile app.
  - `trendPct` → moved to `/earnings/report`.

**Do NOT keep calling the legacy endpoint.** It will be deleted in the next backend release. Migration is straightforward — each old call site maps cleanly to one of the three new endpoints based on which fields you were actually reading.

---

## 8. Sample code (Dart-flavoured pseudocode)

```dart
class EarningsApi {
  final HttpClient http;
  final String? activeRole; // 'driver' | 'artisan' from role-picker state

  Future<TodayCardResponse> getTodayCard() async {
    final res = await http.get('/v1/payments/earnings/today-card', query: {
      if (activeRole != null) 'role': activeRole,
    });
    return TodayCardResponse.fromJson(res.body);
  }

  Future<SummaryResponse> getSummary(EarningsPeriod period) async {
    final res = await http.get('/v1/payments/earnings/summary', query: {
      'period': period.name,
      if (activeRole != null) 'role': activeRole,
    });
    return SummaryResponse.fromJson(res.body);
  }

  Future<ReportResponse> getReportByPreset(EarningsPeriod period) async {
    final res = await http.get('/v1/payments/earnings/report', query: {
      'period': period.name,
      if (activeRole != null) 'role': activeRole,
    });
    return ReportResponse.fromJson(res.body);
  }

  Future<ReportResponse> getReportByRange(DateTime from, DateTime to) async {
    final res = await http.get('/v1/payments/earnings/report', query: {
      'from': _ymd(from),
      'to': _ymd(to),
      if (activeRole != null) 'role': activeRole,
    });
    return ReportResponse.fromJson(res.body);
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
```

---

## 9. Testing checklist

Before you ship, confirm each of these manually against `staging-api.myshop.com.gh`:

- [ ] **Driver homepage** card displays trips, hours, tips, today's net for a real driver account.
- [ ] **Artisan homepage** card swaps "trips" for "jobs"; otherwise identical layout.
- [ ] **Cash trips** appear in the today-card's `tripsCount` (count is sourced from the rides table, not payments — cash trips count) but **NOT** in `availableBalancePesewas` on the summary card (cash is already in the driver's hand).
- [ ] **Available balance ≥ 0** at all times. After a withdrawal completes, it drops on the next refresh.
- [ ] **Period switcher** (today/week/month) on the summary card refetches and updates the sparkline.
- [ ] **Detailed report** preset tabs (Daily / Weekly / Monthly) load distinct data and the graph re-buckets correctly.
- [ ] **Custom date range picker** ≤ 90 days returns a valid response; the graph buckets adapt (e.g. 60-day range → weekly buckets).
- [ ] **91-day range** returns 400 with `EARNINGS_RANGE_TOO_LARGE` — show a helpful inline error, don't crash.
- [ ] **Average fare = 0** when the period has zero completed trips — UI shows "—" or "GHS 0.00" cleanly.
- [ ] **Trend badge** hides or shows "—" when `trendPct` is null (first-week new driver).
- [ ] **Dual-role test:** if you have a test account with both driver and artisan profiles, switching the role-picker re-fetches with `?role=…` and shows different totals.
- [ ] **Offline / no-data states** for each surface render without crashing.

---

## 10. Open questions / known limitations

- **Hours-worked excludes idle online time.** Currently it's the sum of `(completedAt − startedAt)` over completed trips — driver waiting between trips isn't counted because there's no online-session tracking yet. If product wants true shift hours, that's a separate backend ticket (new `driver_sessions` table).
- **`getPayoutHistory`** (`GET /v1/payments/payouts`) is still role-agnostic for dual-role users — it returns payouts across both roles. Backend ticket pending.
- **Index sanity check** on `payments(provider_id, provider_type, created_at)` is being run on staging before the report endpoint goes live in production. Expect a small `EXPLAIN` PR if needed.

---

## Contact

Backend changes shipped across 6 PRs (1: resolver extraction; 2: scaffolding; 3: today-card; 4: summary; 5: report; 6: legacy deprecation). Full plan at `/Users/ayiks/.claude/plans/so-we-have-to-piped-wadler.md`. Questions on shape or semantics — ping #payments-backend.
