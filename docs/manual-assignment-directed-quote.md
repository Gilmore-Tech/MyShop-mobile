# Implementation Plan — Manual Assignment via Directed Quote

**Goal:** When ops manually assigns an artisan to a job that got no bids, let the
assigned artisan **submit a bid (quote)** and continue the normal flow
(client accepts → confirmed → work), instead of the current "instant-confirm at
an ops-set price."

**Status:** Proposed. Backend-led; mobile is mostly ready.

---

## 1. Does this affect the existing flow?

Short answer: **mostly additive and low-risk.** The normal bidding flow, payment,
and escrow are untouched. There is exactly **one** behavioral change (the assign
endpoint), which we gate behind a mode flag so nothing changes until ops opts in.

| Area | Impact | Why |
| --- | --- | --- |
| Normal bidding (`open` jobs) | **None** | All changes to `submitBid`/`selectBid` are additive branches keyed on `admin_assigned`; the `open` path is unchanged. |
| Payment / escrow | **None** | Payment is collected **only at completion** (`payment.service.ts:387-394`), never at confirmation. Both `selectBid` and `assignJob` already defer it. Routing confirm through `selectBid` is payment-neutral. |
| Client "new bid" UX | **Reused as-is** | `submitBid` already notifies the client with `job.bid_received` (`bid.service.ts:383-390`). A directed quote rides the same path — no new client notification needed. |
| `admin_assigned` status | **Already supported** | It's a *ghost state*: defined in `CANCELLABLE_STATUSES` + `PRE_ACCEPTANCE_STATUSES` (`job-cancellation.service.ts:34,44`) and the bid-visibility guard (`marketplace.service.ts:480`), but **nothing ever sets it today**. We're activating existing scaffolding. |
| `originalBidPesewas` | **Bug fixed as a bonus** | `assignJob` never sets `originalBidPesewas` (only `selectBid` does, `bid.service.ts:803`), which the supplement logic reads (`supplement.service.ts:179`). Routing confirm through `selectBid` sets it correctly. |
| Bid-window expiry cron | **None** | `expireBidWindows` only touches `open` jobs (`bid.service.ts:882`); an `admin_assigned` job is invisible to it. |
| Staleness / reminder crons | **Gap to fill** | No reaper acts on `admin_assigned`, so a directed job where the artisan never quotes would sit forever. **New fallback timer required** (see step B5). |
| Assign endpoint (`POST /admin/jobs/:id/assign`) | **Behavioral change** | Today it instant-confirms. We add a `mode` so the old behavior is preserved by default; ops opts into `request_quote`. No in-repo admin UI consumes it yet (`apps/admin/src` has no reference), so coordination is with the separate admin dashboard only. |
| Cancellation of a directed job | **Minor** | `admin_assigned` is "pre-acceptance free cancel" (no fee) — desired — but the assigned artisan currently isn't notified on a pre-acceptance cancel. We add a notification since they were contacted by phone. |

**Net:** no regression to the live bidding/payment paths. The only true change is
the opt-in assignment mode plus a new fallback reaper.

---

## 2. Design

Support **two assignment modes** and let mobile branch on the resulting job status:

- `request_quote` (new): job → `admin_assigned`, assigned artisan quotes →
  client accepts → `confirmed`. Mobile routes to the **bid screen**.
- `confirm` (current): job → `confirmed` at an ops-set price. Mobile routes to the
  **active-job screen**.

Mobile already routes `job.manually_assigned` to the bid screen; after hydrating
the job it branches on `status` (`admin_assigned` → quote; `confirmed` → active),
which also fixes the existing "assigned job wrongly lands on the bid screen" issue.

Reused primitives: `submitBid` (fires `job.bid_received` to client), `selectBid`
(confirms + sets `originalBidPesewas`), the client's existing bid-review UI, and
the mobile `JobStatus.adminAssigned` enum + bid-draft reconciliation.

### Key product decisions
1. **Client accepts the quote (recommended)** vs auto-accept. Recommend client
   accepts — keeps price consent and reuses `selectBid` untouched.
2. **Quote window + fallback.** If the artisan doesn't quote within
   `job_directed_quote_window_secs`, revert to `pending_admin` for ops to reassign.
3. **One directed job per artisan** — extend the active-set check to include
   `admin_assigned` so an artisan isn't directed to two jobs at once.
4. **Single assigned artisan** to start; assigning 2–3 for competing quotes is a
   later extension.

---

## 3. Backend implementation steps

### B1 — `AssignJobDto` (`dto/assign-job.dto.ts`)
- Add `mode?: 'confirm' | 'request_quote'` (default `'confirm'` → no behavior change).
- Keep `agreedPricePesewas` optional; document it's only honored for `mode='confirm'`.
  (Optionally reject it when `mode='request_quote'`.)

### B2 — `assignJob` (`admin.service.ts:2075`)
- Branch on `dto.mode`:
  - `'confirm'`: unchanged (current instant-confirm path).
  - `'request_quote'`: set `status='admin_assigned'`, `assignedArtisanId`,
    `assignedByAdmin`, `assignedAt`, `lastActivityAt`. Do **not** set price/`confirmedAt`.
- Keep the Redis lock acquire/release and the 3-channel `job.manually_assigned`
  notification (artisan). Adjust copy/payload to signal "quote requested" in this mode.
- Extend the "one active manual job per artisan" guard: add `admin_assigned` to the
  set checked (`ACTIVE_MANUAL_JOB_STATUSES`, line 201) so a second direct assignment
  is blocked while the first is awaiting a quote.

### B3 — `submitBid` (`bid.service.ts:173`, guard at line 226)
- Replace the `status !== 'open'` guard with: allow when `status === 'open'`
  **or** (`status === 'admin_assigned'` **and** `artisan.id === job.assignedArtisanId`).
  Any other artisan on an `admin_assigned` job → `403 NOT_ASSIGNED_ARTISAN`.
- Keep all existing checks (capacity `CAPACITY_ACTIVE_STATUSES`, min/max bid, dedupe).
- No new client notification needed — the existing `job.bid_received` (lines 383-390)
  fires automatically and tells the client a quote arrived.

### B4 — `selectBid` (`bid.service.ts:727`, guard at line 761)
- Allow `status` in `['open', 'admin_assigned']` (currently `open` only).
- No other change: it already sets `status='confirmed'`, `artisanId`,
  `agreedPricePesewas`, `originalBidPesewas`, `confirmedAt`, rejects other bids,
  and notifies the winning artisan (`job.bid_selected`).

### B5 — New fallback reaper (time-based cron, no outbox needed)
- Add a `@Cron` method (mirror `scheduled-job-reminder.service.ts`) that finds
  `admin_assigned` jobs whose `assignedAt` is older than
  `job_directed_quote_window_secs` **and** have no pending bid → revert to
  `pending_admin`, clear assignment fields, notify client + admin (`job.escalated`).
- Optionally: `admin_assigned` jobs that received a quote but the client hasn't
  accepted in `job_directed_accept_window_secs` → reminder to client / admin alert.

### B6 — Cancellation (`job-cancellation.service.ts`)
- When a client cancels an `admin_assigned` job, notify the **assigned artisan**
  (e.g. `job.cancelled_pre_acceptance`) since ops already contacted them. Keep the
  no-fee pre-acceptance treatment.

### B7 — Config keys (`platform_config` + allow-list + `.env.example`)
- `job_directed_quote_window_secs` (e.g. 1800)
- `job_directed_accept_window_secs` (e.g. 3600)
- Seed + add to the platform-config allow-list.

### B8 — Audit & docs
- Keep the `job.manually_assigned` audit row; add `mode` to `details`.
- Update living docs (architecture endpoint note, admin-module, CHANGELOG).

---

## 4. Mobile implementation steps (provider app)

Most of this already exists; changes are small.

### M1 — Push routing (`core/services/fcm_service.dart`, `typeJobManuallyAssigned` ~L697)
- Hydrate the job via `GET /jobs/:id`, then **branch on status**:
  - `admin_assigned` → `/job-request` (bid/quote screen — current target, now correct).
  - `confirmed` → `hydrateAndGoToActiveJob()` (active-job screen).

### M2 — Bid screen (`features/artisan_home/screens/job_request_screen.dart`)
- When `job.isAdminAssigned` && status `admin_assigned`, show a banner:
  "MyShop asked you to quote this job" and keep the normal bid form.

### M3 — Notification copy (`core/services/local_notification_service.dart`)
- Fix fallback title/body to assignment/quote language; add `typeJobManuallyAssigned`
  to the urgent set for time-sensitive delivery.

### M4 — Job lists (`features/artisan_jobs/`)
- Ensure an `admin_assigned` job surfaces (it returns from `listJobs`). Add it to the
  "New" or "Bids" tab filter; today `admin_assigned` is neither `isActive` nor completed.

### M5 — Post-quote
- Existing `submittedBids` / `bidStatus` banner handles the "pending → accepted"
  transition; on `job:status=confirmed` the existing active-job flow takes over. No new work.

**Client app:** no change required — `job.bid_received` + the bid-review/`select-bid`
UI already exist. Verify the `pending_admin → bid_received` transition renders cleanly.

---

## 5. Admin dashboard (separate repo) coordination
- Add a choice in the assignment modal: **"Request a quote"** (sends
  `mode='request_quote'`, hides the price field) vs **"Assign & set price"**
  (current `mode='confirm'`). Default per ops preference.

---

## 6. Tests
- **Backend unit:** `submitBid` on `admin_assigned` (assigned artisan ok; others 403);
  `selectBid` on `admin_assigned` → confirmed + `originalBidPesewas` set; `assignJob`
  `request_quote` sets `admin_assigned` + notifies + blocks 2nd direct assignment;
  reaper reverts a stale `admin_assigned`; client `job.bid_received` fires on directed quote;
  cancel of `admin_assigned` notifies the assigned artisan.
- **Mobile:** push routing branch (admin_assigned vs confirmed); bid screen assigned-mode banner.

---

## 7. Rollout sequence (each step is independently safe)
1. **Backend** behind `mode` (default `confirm` = zero behavior change) + reaper + tests. Ship.
2. **Mobile** status-branch (handles both `confirmed` and `admin_assigned`). Ship.
3. **Admin dashboard** adds the mode toggle.
4. Flip ops to `request_quote`.

---

## 8. Open risks / things to confirm
- Confirm "free pre-acceptance cancel" is the desired policy for a directed job the
  artisan has been phoned about (B6 softens the UX by notifying them).
- Other artisans can *view* an `admin_assigned` job (visibility guard) but cannot
  bid (B3 identity guard). Optionally exclude `admin_assigned` from any artisan feed.
- Decide quote/accept window lengths (B7) with ops.
