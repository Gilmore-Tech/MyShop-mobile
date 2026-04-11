# Engineering Design Document

## MyShop — Ride-Hailing & Artisan Marketplace Platform

**Version:** 1.1 — Reconciled with PRD v2.1  
**Company:** Gilmore Technologies  
**Pilot Region:** Ashanti Region, Ghana  
**Date:** March 2026  
**Status:** CONFIDENTIAL — FOR INTERNAL USE ONLY

---

| Item             | Value                        |
| ---------------- | ---------------------------- |
| Document         | Engineering Design Document  |
| Version          | 1.1                          |
| PRD Reference    | PRD v2.1 — March 2026        |
| Previous Version | EDD v1.0 (based on PRD v2.0) |
| Author           | Engineering Team             |
| Pilot Region     | Ashanti Region, Kumasi       |

### v1.1 Changelog (changes from v1.0)

| #   | Change                                                                       | Reason                                                                         |
| --- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| 1   | Architecture changed from microservices to modular monolith                  | Team size (2-4) makes 14 separate services operationally impractical for pilot |
| 2   | Batch payout time corrected: 22:00 → 18:00 GMT, retries: 19:30, 20:00, 06:00 | Aligned with PRD v2.1 Section 7.4.1                                            |
| 3   | Primary keys changed to UUIDv7 (time-sortable)                               | Better B-tree index performance, chronological ordering for feeds/history      |
| 4   | Money storage standardized to INTEGER pesewas                                | Eliminates floating-point errors in currency calculations                      |
| 5   | Audit columns added: created_by, updated_by on all tables                    | Accountability for admin actions, dispute resolution                           |
| 6   | Soft delete via deleted_at TIMESTAMPTZ (null = active)                       | Matches PRD 90-day retention requirement                                       |
| 7   | Supplement request rules formalized: one per job, pattern tracking           | PRD v2.1 Sections 4.5.2, 4.5.3, edge cases #56, #57                            |
| 8   | Saved locations normalized to separate table (was JSONB)                     | Enables PostGIS POINT, individual CRUD, last_used_at ordering                  |
| 9   | Provider documents extracted to separate table with versioning               | Supports re-verification, document expiry tracking, review workflow            |
| 10  | Translations table added for dynamic i18n content                            | PRD Section 11.2 requires language updates without app releases                |
| 11  | Flutter apps moved to separate repo (not in monorepo)                        | Different toolchains; Turborepo can't orchestrate Dart builds                  |
| 12  | PostGIS geometry handled via Prisma Unsupported + raw SQL helpers            | Prisma has no native PostGIS support; typed helper functions bridge the gap    |

---

## 1. Introduction

### 1.1 Purpose

This Engineering Design Document (EDD) translates the Product Requirements Document (PRD v2.1) for the MyShop Ride-Hailing & Artisan Marketplace Platform into a concrete technical architecture, system design, and implementation plan. It serves as the primary technical reference for the engineering team during the 3-month pilot in the Ashanti Region.

### 1.2 Scope

The EDD covers the end-to-end technical design for all five system components defined in the PRD:

- Client App (Flutter — iOS & Android) — separate repository
- Provider App — Driver View & Artisan View (Flutter — iOS & Android) — separate repository
- Admin Dashboard (React — Web) — in backend monorepo
- USSD Channel (Telco-integrated gateway via Africa's Talking)
- Shared Backend API & Infrastructure (NestJS modular monolith)

### 1.3 Audience

Backend engineers, mobile engineers, DevOps/SRE, QA, product managers, and technical leadership.

### 1.4 References

- PRD v2.1 — MyShop Ride-Hailing & Artisan Marketplace Platform (March 2026)
- Flutterwave API Documentation (v3)
- Smile Identity Integration Guide
- Google Maps Platform SDK for Flutter
- Mapbox Flutter SDK
- Africa's Talking USSD/SMS API Documentation
- Firebase Cloud Messaging Admin SDK

---

## 2. System Architecture Overview

### 2.1 Architecture Decision: Modular Monolith

**Change from v1.0**: The v1.0 EDD specified a full microservices architecture with 14 independently deployable services. For the pilot phase with a 2-4 person team, this has been revised to a **modular monolith** — a single NestJS application with 14 domain-bounded modules that mirror the original service boundaries.

**Rationale**: 14 separate services would require complex inter-service communication (HTTP/gRPC), separate deployments, distributed tracing for debugging, and a service mesh — all disproportionate overhead for a small team on a 3-month pilot. The modular monolith preserves clean domain boundaries while running in a single process with shared database connections and in-process function calls.

**Extraction path**: Each module is designed with clear interfaces (exported services, no direct database access across module boundaries). Post-pilot, high-traffic modules (e.g., Location, Payment) can be extracted into standalone services with the module boundary becoming an API boundary.

### 2.2 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        CLIENTS                                       │
│  ┌──────────┐  ┌──────────────┐  ┌────────────┐  ┌──────────────┐  │
│  │Client App│  │ Provider App │  │Admin Panel │  │USSD (AT SMS) │  │
│  │ (Flutter) │  │  (Flutter)   │  │  (React)   │  │Feature Phones│  │
│  └────┬─────┘  └──────┬───────┘  └─────┬──────┘  └──────┬───────┘  │
└───────┼────────────────┼────────────────┼────────────────┼──────────┘
        │                │                │                │
        └────────────────┼────────────────┼────────────────┘
                         │     HTTPS/WSS  │
                    ┌────┴────────────────┴────┐
                    │   NestJS API (Port 3000)  │
                    │  JWT Auth · Throttling    │
                    │  Swagger · Validation     │
                    └────────────┬─────────────┘
                                 │
    ┌────────────────────────────┼────────────────────────────┐
    │         14 DOMAIN MODULES (in-process)                  │
    │                                                         │
    │  auth · user · verification · ride · marketplace        │
    │  payment · notification · ussd · location               │
    │  communication · safety · rating · admin                │
    │  platform-config                                        │
    └─────────┬──────────┬──────────┬────────────────────────┘
              │          │          │
    ┌─────────┴──┐ ┌─────┴────┐ ┌──┴──────────┐
    │PostgreSQL  │ │ Redis 7  │ │ RabbitMQ    │
    │16 + PostGIS│ │          │ │             │
    └────────────┘ └──────────┘ └─────────────┘
```

### 2.3 Technology Stack

| Layer              | Technology                           | Version | Justification                                                                    |
| ------------------ | ------------------------------------ | ------- | -------------------------------------------------------------------------------- |
| Mobile Apps        | Flutter (Dart)                       | 3.x     | Single codebase for iOS & Android; strong ecosystem in Africa                    |
| Admin Dashboard    | React + TypeScript                   | 19.x    | Rich component ecosystem; Vite for fast dev; TanStack Query + Zustand            |
| Backend            | NestJS (TypeScript)                  | 11.x    | Modular architecture, decorators, DI, Swagger auto-generation                    |
| ORM                | Prisma                               | 7.x     | Type-safe queries, migrations, schema-first                                      |
| Primary Database   | PostgreSQL + PostGIS                 | 16      | ACID compliance; PostGIS for geospatial queries (radius matching, geofencing)    |
| Cache / Real-time  | Redis                                | 7       | Driver location (geospatial), session state, OTP storage, rate limiting, pub/sub |
| Message Queue      | RabbitMQ                             | 3.x     | Async processing: notifications, payouts, bid expiry timers, scheduled jobs      |
| Object Storage     | AWS S3                               | —       | Verification documents, portfolio photos, emergency recordings                   |
| Push Notifications | Firebase Cloud Messaging             | —       | Cross-platform push with topic-based targeting                                   |
| SMS/USSD           | Africa's Talking                     | —       | Leading USSD/SMS gateway in West Africa; Ghana telco integration                 |
| Payments           | Flutterwave                          | v3 API  | Unified API for MoMo (MTN, Telecel, AirtelTigo), cards, bank transfer            |
| KYC/Identity       | Smile Identity                       | —       | Ghana Card verification, facial matching, liveness detection                     |
| Maps (Rides)       | Google Maps Platform                 | —       | Navigation, geocoding, Distance Matrix API for fare calculation                  |
| Maps (Artisan)     | Mapbox                               | —       | Cost-effective for pin-drop location selection in marketplace                    |
| Monitoring         | Prometheus + Grafana                 | —       | Metrics, alerting, SLA dashboards                                                |
| Logging            | Structured logging (Pino via NestJS) | —       | Centralized log aggregation                                                      |
| CI/CD              | GitHub Actions                       | —       | Automated build, test, deploy pipelines                                          |
| Cloud              | AWS (af-south-1 Accra)               | —       | Low latency for Ghana users; data residency compliance                           |
| Monorepo           | Turborepo + pnpm                     | —       | Fast builds, workspace linking                                                   |
| Containerization   | Docker (multi-stage)                 | —       | Optimized production images                                                      |

### 2.4 Deployment Architecture

The platform is deployed on containerized infrastructure in the AWS Africa (Cape Town / Accra) region:

- Single NestJS application containerized via Docker with multi-stage builds
- Deployed on ECS Fargate with horizontal autoscaling based on CPU/request metrics
- PostgreSQL on RDS with automated backups and point-in-time recovery
- Redis on ElastiCache with cluster mode for high availability
- RabbitMQ on AmazonMQ
- CDN (CloudFront) for static assets and media files
- Blue-green deployments for zero-downtime releases
- GitHub Actions CI/CD: auto-deploy to staging on merge to main, manual approval for production

### 2.5 Repository Structure

**Backend monorepo** (Turborepo + pnpm):

- `apps/api/` — NestJS modular monolith (14 domain modules)
- `apps/admin/` — React admin dashboard
- `packages/database/` — Prisma 7 client + UUIDv7 extension + PostGIS helpers
- `packages/shared-types/` — TypeScript enums and interfaces (mirrors DB)
- `packages/utils/` — Phone normalization, money helpers, constants
- `packages/config/` — Zod-validated environment configuration

**Flutter repo** (separate):

- `client_app/` — Consumer-facing app
- `provider_app/` — Driver and artisan app
- `packages/` — Shared Dart packages (API client, models, theme)

API contract shared via OpenAPI/Swagger specification auto-generated from NestJS decorators.

---

## 3. Service Decomposition (Domain Modules)

The backend is organized into 14 domain-bounded modules. Each module owns its routes, services, and business logic. Modules communicate via direct service injection (in-process), not HTTP.

### Auth Module

User registration, OTP verification (passwordless login via Africa's Talking SMS), JWT token issuance (access: 15min, refresh: 30d), role-based access control, session management. Handles the identity rule: phone number is the primary anchor; at most one Driver account and one Artisan account per phone number. Banned clients re-registering with a new SIM must complete Ghana Card verification (PRD edge case #4).

### User Module

Profile management for clients, drivers, and artisans. Saved locations (normalized table with PostGIS POINT), preferred payment methods, language preferences, and emergency contacts. Manages account suspension, banning, soft-delete (90-day retention via `deleted_at` timestamp), and the 24-hour recovery window. Provider accounts with outstanding clawback balances cannot be deactivated (PRD edge case #51).

### Verification Module

Provider document uploads to S3 with SHA-256 hash for tamper detection, admin review workflow via `provider_documents` table (versioned, with status tracking), Smile Identity KYC integration (Ghana Card verification webhook), Ghana Police background check status tracking. Manages the two-phase verification: immediate digital KYC then asynchronous police check with post-activation suspension if disqualifying info emerges.

### Ride Module

Ride lifecycle management: booking, driver matching (Redis GEOSEARCH with configurable radius expansion), fare estimation (Google Maps Distance Matrix API — base + distance + time formula), multi-stop routing, surge pricing (configurable by Super Admin), 3-minute free cancellation window, driver disconnection 2-minute grace period, GPS trail recording for dispute resolution, and online/offline toggle lock during active rides (PRD edge case #41). Fare locked at booking for surge — if surge activates after booking but before acceptance, original fare preserved (PRD edge case #8). All fares in pesewas, rounded UP to nearest whole GHS.

### Marketplace Module

Artisan job lifecycle: category-based requests with zero-artisan detection, bid collection (max 3 bids per job, 5-minute window), bid pricing guardrails (category minimum from `service_categories` table, GHS 5,000 admin review flag), scheduled job reminders (T-24h confirmation, T-2h reminder, T+30min no-show escalation), job staleness timeout (8h check-in, 24h admin escalation, 48h payout freeze), material cost supplement requests (one per job maximum — enforced by database UNIQUE constraint on `supplement_requests.job_id`), supplement frequency tracking per artisan profile (`supplement_count` and `completed_jobs_count` columns for pattern detection), 30-minute free cancellation window with 20% fee after, and dual confirmation for job completion.

### Payment Module

Flutterwave integration for collections (MoMo: MTN, Telecel/"VODAFONE", AirtelTigo/"TIGO"; cards; bank transfer) and payouts. Micro-escrow model — funds held invisibly during processing. 20% commission calculated ALWAYS on pre-promo fare (never post-discount). Money stored as INTEGER pesewas throughout. Instant payouts within 30-60 seconds. Batch payouts at **18:00 GMT** daily with retries at **19:30, 20:00, and 06:00** (next morning). Tip processing with zero commission and auto-retry for bounced tips. Dispute/refund management with 2-hour dispute window, clawback tracking from provider's next payout, and clawback write-off rules (under GHS 100 after 90 days inactive). FX costs absorbed by platform during pilot for non-GHS card payments.

### Notification Module

Multi-channel notification dispatch: push (Firebase Cloud Messaging), SMS (Africa's Talking), WhatsApp (Business API), email (AWS SES), and in-app. Event-driven — listens to domain events from other modules via RabbitMQ. Manages notification routing rules per event type as defined in PRD Section 10. Handles scheduled job reminders, welfare check notifications, supplement request/response notifications, and emergency alerts.

### USSD Module

Africa's Talking USSD gateway integration. Session state management in Redis (180-second max session, 5-minute resume window). Zone-based location handling (no GPS — user selects from 20 Ashanti Region zones). Supported flows: request artisan service, check booking status, cancel booking, MoMo payment, view last 5 bookings, confirm job completion. English and Twi language support at launch. All confirmations sent via SMS. Account auto-linking when USSD user later downloads Client App.

### Location Module

Real-time driver GPS tracking: locations cached in Redis via GEOADD with 5-second TTL per driver. PostGIS-backed geospatial queries for radius matching via typed helper functions (`findDriversWithinRadius`, `findArtisansWithinRadius`). Pilot region geofencing using Ashanti Region GeoJSON boundary (`isWithinPilotRegion`). WebSocket broadcasting for live client tracking and admin live map feed.

### Communication Module

In-app chat via WebSocket — channels created on job/ride acceptance, auto-closed on completion. Masked phone call routing via Africa's Talking Voice — neither party sees the other's real number. Session-scoped virtual numbers active only during active bookings.

### Safety Module

Emergency button handling: two-step confirmation, GPS broadcast to emergency contacts, admin alert, Ghana Police 191 auto-dial trigger, live audio/video recording to encrypted S3 bucket (90-day minimum retention). Artisan welfare check automation: if artisan marks 'arrived' but shows no activity for 3 hours, automated push notification sent; if no response within 15 minutes, admin alerted with last known GPS. Job staleness monitoring: 8-hour check-in, 24-hour admin escalation, 48-hour payout freeze. Provider emergency activations logged with equal priority to client emergencies.

### Rating Module

Blind 24-hour rating window: both parties have 24 hours to submit. Ratings revealed only after both submit or window closes, whichever comes first. Prevents retaliatory ratings. Rating threshold monitoring: 3.5-star warning at 15+ completed jobs, 3.0-star auto-suspension. Reveal cron runs every 15 minutes.

### Admin Module

Multi-level admin operations (Super Admin L1, Regional Admin L2, Ops Admin L3, Support Agent L4). Provider verification queue with document review. Manual job assignment with Redis distributed lock (120-second TTL prevents race conditions — job greys out for other admins). Live map API with real-time GPS markers (region-scoped for L2 admins). User management (suspend/ban with mandatory reason, audit log). Reporting/analytics engine (pilot success metrics, revenue, provider performance including supplement rate). Platform configuration (commission rates, surge rules, minimum artisan radius, category bid minimums). Announcement broadcasting. All admin actions logged in `audit_log` table.

### Platform Config Module

Centralized runtime configuration: all business rules stored in `platform_config` table. Values cached in Redis with 5-minute TTL. Config checked first at DB level, falling back to environment variables. All thresholds, rates, limits, and timers are adjustable without code deployment per PRD requirement. Includes: commission rates, fare formula parameters, cancellation windows, bid windows, staleness thresholds, rating thresholds, batch payout schedule, clawback write-off limits, and pilot region boundaries.

---

## 4. Data Model Design

### 4.1 Design Decisions (v1.1)

| Decision            | Choice                                                 | Rationale                                                                                                                               |
| ------------------- | ------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| Primary keys        | UUIDv7 (time-sortable, RFC 9562)                       | Globally unique across modules, chronologically sortable for B-tree indexes, generated at application layer via Prisma Client Extension |
| Money storage       | INTEGER in pesewas (100 = GHS 1.00)                    | Eliminates floating-point errors; all calculations use integer arithmetic                                                               |
| Soft delete         | `deleted_at TIMESTAMPTZ` (NULL = active)               | PRD requires 90-day retention before purge; timestamp encodes both "is deleted" and "when"                                              |
| Audit columns       | `created_at`, `updated_at`, `created_by`, `updated_by` | Accountability for admin actions, dispute resolution, provider verification                                                             |
| Geospatial          | PostGIS GEOMETRY(Point, 4326)                          | Native PostgreSQL spatial indexing; radius queries via ST_DWithin                                                                       |
| Encryption          | AES-256 for Ghana Card numbers (BYTEA column)          | Application-layer encryption; never stored as plaintext                                                                                 |
| i18n                | Dedicated `translations` table                         | Queryable, supports missing-translation reports, admin-manageable                                                                       |
| Phone normalization | Generated column + application function                | Consistent +233XXXXXXXXX format at both DB and application layer                                                                        |

### 4.2 Schema Summary

| Metric            | Count                                                               |
| ----------------- | ------------------------------------------------------------------- |
| Tables            | 40                                                                  |
| Custom enum types | 32                                                                  |
| Indexes           | 90 (including GiST spatial indexes)                                 |
| Database views    | 5                                                                   |
| Triggers          | 26 (auto-update timestamps)                                         |
| Helper functions  | 2 (update_updated_at, normalize_ghana_phone)                        |
| Seed data sets    | 3 (14 service categories, 20 USSD zones, 48 platform config values) |

### 4.3 Core Entity Groups

**Identity**: `users` (identity anchor) → `clients`, `drivers`, `artisans` (1:1 per role). `emergency_contacts` (1:N per user). `saved_locations` (1:N per client with PostGIS POINT).

**Provider Verification**: `provider_documents` (versioned, with status tracking, review workflow, expiry dates). `provider_suspensions` (history with trigger type and reinstatement).

**Service Categories**: `service_categories` (admin-configurable minimums and flags) ↔ `artisan_service_categories` (many-to-many junction).

**Ride-Hailing**: `rides` (full lifecycle with PostGIS pickup/dropoff/gps_trail, share token) → `ride_stops` (multi-stop with mid-ride addition tracking).

**Artisan Marketplace**: `artisan_jobs` (full lifecycle with PostGIS location, scheduled_for, dual confirmation timestamps, admin assignment) → `bids` (max 3 per job, with expiry) → `supplement_requests` (one per job, enforced by UNIQUE constraint on job_id).

**Payments**: `payments` (micro-escrow with pre-promo tracking, polymorphic booking reference) → `tips` (separate, zero commission, auto-retry). `payouts` (instant or batch) → `batch_payout_runs` (18:00 GMT with retry tracking). `disputes` → `clawbacks` (blocks deactivation).

**Ratings**: `ratings` (blind 24-hour window with reveal timestamp, unique per rater per booking).

**Safety**: `emergency_events` (with PostGIS GPS, recording URL, admin acknowledgment). `welfare_checks` (3-hour inactivity trigger with response tracking).

**Communication**: `chat_messages` (per booking). `masked_calls` (session-scoped virtual numbers).

**Notifications**: `notifications` (multi-channel with delivery status tracking).

**USSD**: `ussd_zones` (20 Ashanti areas). `ussd_sessions` (state machine in JSONB, 5-minute resume). `ussd_accounts` (auto-links to client on app download).

**Admin**: `admin_users` (4-level RBAC). `audit_log` (all admin actions). `admin_job_locks` (distributed lock for manual assignment).

**Promos & Loyalty**: `promo_codes` (percentage/fixed/free ride/bonus points). `promo_redemptions` (usage tracking). `loyalty_transactions` (points ledger). `referrals` (one per user).

**Platform Config**: `platform_config` (key-value with JSONB, cached in Redis). `translations` (entity_type + entity_id + field + locale → value). `surge_rules` (configurable by Super Admin).

### 4.4 Key Indexes

- **Spatial (GiST)**: `drivers.current_location`, `artisans.current_location`, `rides.pickup_location`, `artisan_jobs.location` — filtered to online, verified, non-deleted records
- **Composite**: `rides(status, driver_id)`, `artisan_jobs(category_id, status)`, `payments(booking_type, booking_id)`, `artisan_jobs(scheduled_for)` for reminder crons
- **Unique constraints**: `users.phone_normalized`, `bids(job_id, artisan_id)`, `supplement_requests(job_id)` — enforces one supplement per job at DB level, `ratings(booking_type, booking_id, rater_id)`
- **Partial indexes**: Only index online+verified+non-deleted drivers/artisans for matching queries; only index pending bids for expiry cron

### 4.5 Data Retention & Deletion

- Soft-deleted accounts: data retained 90 days with 24-hour recovery window, then permanent purge via nightly cron
- Emergency recordings: minimum 90 days retention on encrypted S3 bucket
- Provider accounts with outstanding clawback balances: cannot be deactivated until settled; clawbacks under GHS 100 written off after 90 days of provider inactivity; above GHS 100 escalated for manual admin resolution
- USSD sessions: short-lived (5-minute TTL in Redis), no long-term retention needed
- Audit log: retained indefinitely (partitioned by month post-pilot for performance)

---

## 5. API Design

### 5.1 API Gateway

All client-facing traffic enters through the NestJS application which provides:

- JWT-based authentication with role-aware guards (client, driver, artisan, admin L1-L4)
- Rate limiting via @nestjs/throttler: 100/min default, 20/min for auth, 30/min for payments
- Request validation via class-validator DTOs — all inputs validated, no raw request body access
- Regional Admin API scoping enforced at service level (Ashanti-only data filter)
- API versioning via URL path prefix (`/v1/`)
- Swagger/OpenAPI documentation auto-generated at `/docs` (non-production only)
- Standard response envelope: `{ success: boolean, data?: T, error?: { code, message, details }, meta?: { page, limit, total } }`

### 5.2 Core API Endpoints (56 total)

#### Auth (3 endpoints)

| Method | Path                | Auth   | Description                                                 |
| ------ | ------------------- | ------ | ----------------------------------------------------------- |
| POST   | /v1/auth/register   | Public | Client, driver, or artisan registration with OTP initiation |
| POST   | /v1/auth/verify-otp | Public | OTP verification and JWT issuance                           |
| POST   | /v1/auth/refresh    | Public | Token refresh                                               |

#### Users (5 endpoints)

| Method | Path                            | Auth   | Description                                          |
| ------ | ------------------------------- | ------ | ---------------------------------------------------- |
| GET    | /v1/users/me                    | Bearer | Current user profile                                 |
| PUT    | /v1/users/me                    | Bearer | Update profile, saved locations, emergency contacts  |
| GET    | /v1/users/me/saved-locations    | Bearer | Get saved locations (Home, Work, Favourites)         |
| GET    | /v1/users/me/emergency-contacts | Bearer | Get emergency contacts                               |
| DELETE | /v1/users/me                    | Bearer | Soft delete account (90-day retention, 24h recovery) |

#### Verification (4 endpoints)

| Method | Path                                   | Auth    | Description                    |
| ------ | -------------------------------------- | ------- | ------------------------------ |
| POST   | /v1/verification/documents             | Bearer  | Upload verification documents  |
| GET    | /v1/verification/status                | Bearer  | Check verification status      |
| POST   | /v1/verification/kyc/callback          | Webhook | Smile Identity KYC webhook     |
| POST   | /v1/verification/police-check/callback | Webhook | Police background check result |

#### Rides (8 endpoints)

| Method | Path                  | Auth   | Description                                  |
| ------ | --------------------- | ------ | -------------------------------------------- |
| POST   | /v1/rides/estimate    | Bearer | Fare estimation (origin, destination, stops) |
| POST   | /v1/rides             | Bearer | Create ride booking                          |
| GET    | /v1/rides/:id         | Bearer | Get ride details with live status            |
| PATCH  | /v1/rides/:id/cancel  | Bearer | Cancel ride (enforces 3-min free window)     |
| PATCH  | /v1/rides/:id/stops   | Bearer | Add mid-ride stop                            |
| PATCH  | /v1/rides/:id/status  | Bearer | Driver: update ride status                   |
| POST   | /v1/rides/:id/dispute | Bearer | Client: dispute ride fare (2-hour window)    |
| GET    | /v1/rides/:id/share   | Bearer | Get shareable tracking link                  |

#### Marketplace (12 endpoints)

| Method | Path                            | Auth   | Description                                             |
| ------ | ------------------------------- | ------ | ------------------------------------------------------- |
| POST   | /v1/jobs                        | Bearer | Create artisan job request                              |
| GET    | /v1/jobs/:id                    | Bearer | Get job details                                         |
| GET    | /v1/jobs/:id/bids               | Bearer | Get bids for a job                                      |
| POST   | /v1/jobs/:id/bids               | Bearer | Artisan: submit bid (validates min, GHS 5K flag)        |
| PATCH  | /v1/jobs/:id/select-bid         | Bearer | Client: accept a bid                                    |
| PATCH  | /v1/jobs/:id/status             | Bearer | Update job status                                       |
| POST   | /v1/jobs/:id/supplement         | Bearer | Artisan: request material cost supplement (one per job) |
| PATCH  | /v1/jobs/:id/supplement/respond | Bearer | Client: approve or reject supplement                    |
| PATCH  | /v1/jobs/:id/confirm            | Bearer | Client: confirm job completion (dual confirmation)      |
| POST   | /v1/jobs/:id/dispute            | Bearer | Dispute job (2-hour window)                             |
| POST   | /v1/jobs/:id/escalate           | Bearer | Artisan: escalate non-confirmation (4-hour window)      |
| PATCH  | /v1/jobs/:id/cancel             | Bearer | Cancel job (30-min free, 20% fee after)                 |

#### Payments (6 endpoints)

| Method | Path                              | Auth    | Description                                |
| ------ | --------------------------------- | ------- | ------------------------------------------ |
| POST   | /v1/payments/initiate             | Bearer  | Initiate MoMo/card payment via Flutterwave |
| GET    | /v1/payments/:id/status           | Bearer  | Payment status check                       |
| POST   | /v1/payments/:id/tip              | Bearer  | Add tip post-completion (zero commission)  |
| GET    | /v1/payments/earnings             | Bearer  | Provider: earnings dashboard               |
| GET    | /v1/payments/payouts              | Bearer  | Provider: payout history                   |
| POST   | /v1/payments/webhooks/flutterwave | Webhook | Flutterwave payment/payout webhook         |

#### Other REST Endpoints (7 endpoints)

| Method | Path                        | Auth   | Description                      |
| ------ | --------------------------- | ------ | -------------------------------- |
| POST   | /v1/ratings                 | Bearer | Submit rating (blind 24h window) |
| GET    | /v1/notifications           | Bearer | Notification history             |
| PATCH  | /v1/notifications/:id/read  | Bearer | Mark notification as read        |
| POST   | /v1/location/update         | Bearer | Driver: update GPS location      |
| GET    | /v1/chat/:type/:id/messages | Bearer | Get chat messages for a booking  |
| POST   | /v1/chat/:type/:id/messages | Bearer | Send a chat message              |
| POST   | /v1/emergency               | Bearer | Trigger emergency event          |

#### USSD (1 endpoint)

| Method | Path              | Auth        | Description                    |
| ------ | ----------------- | ----------- | ------------------------------ |
| POST   | /v1/ussd/callback | Public (AT) | Africa's Talking USSD callback |

#### Admin (14 endpoints)

| Method | Path                           | Auth     | Description                                     |
| ------ | ------------------------------ | -------- | ----------------------------------------------- |
| GET    | /v1/admin/verifications        | L1-L2    | Provider verification queue                     |
| PATCH  | /v1/admin/verifications/:id    | L1-L2    | Approve/reject provider                         |
| GET    | /v1/admin/jobs/unassigned      | L1,L3    | Unassigned jobs queue                           |
| POST   | /v1/admin/jobs/:id/assign      | L1,L3    | Manual job assignment with lock                 |
| POST   | /v1/admin/jobs/:id/lock        | L1,L3    | Lock job for assignment                         |
| GET    | /v1/admin/live-map             | L1-L3    | Live map data feed                              |
| PATCH  | /v1/admin/users/:id/suspend    | L1-L3    | Suspend user with reason                        |
| PATCH  | /v1/admin/users/:id/ban        | L1       | Ban user permanently                            |
| GET    | /v1/admin/disputes             | L1,L3-L4 | Open disputes                                   |
| PATCH  | /v1/admin/disputes/:id/resolve | L1,L3-L4 | Resolve dispute                                 |
| GET    | /v1/admin/reports/overview     | L1-L2    | Platform overview KPIs                          |
| GET    | /v1/admin/reports/revenue      | L1       | Revenue and commission report                   |
| GET    | /v1/admin/reports/providers    | L1-L2    | Provider performance (includes supplement rate) |
| POST   | /v1/admin/announcements        | L1,L3    | Broadcast push announcement                     |

#### Config (3 endpoints)

| Method | Path            | Auth   | Description             |
| ------ | --------------- | ------ | ----------------------- |
| GET    | /v1/config      | L1     | Get all platform config |
| GET    | /v1/config/:key | Bearer | Get single config value |
| PATCH  | /v1/config/:key | L1     | Update config value     |

#### Health (1 endpoint)

| Method | Path       | Auth   | Description             |
| ------ | ---------- | ------ | ----------------------- |
| GET    | /v1/health | Public | DB + Redis health check |

### 5.3 WebSocket Channels

| Path                        | Auth           | Purpose                                                             |
| --------------------------- | -------------- | ------------------------------------------------------------------- |
| ws://api/v1/location/track  | Bearer         | Driver GPS broadcasting (5-second intervals while online)           |
| ws://api/v1/rides/:id/live  | Bearer         | Client ride tracking (driver position, ETA updates)                 |
| ws://api/v1/jobs/:id/live   | Bearer         | Client artisan job tracking                                         |
| ws://api/v1/chat/:bookingId | Bearer         | In-app messaging (auto-created on acceptance, closed on completion) |
| ws://api/v1/admin/live-map  | Bearer (L1-L3) | Admin dashboard live marker stream                                  |

## 6. Ride-Hailing Engine Design

### 6.1 Driver Matching Algorithm

When a client creates a ride request, the matching engine follows this sequence:

1. Query Redis for all online drivers within a configurable initial radius (default 3 km, from `platform_config.ride_initial_match_radius_km`) of the client's pickup location using GEOSEARCH.
2. Filter results by driver status (must be 'available', not mid-ride) and verify the driver's `service_radius_km` covers the pickup point.
3. Rank eligible drivers by proximity (nearest first).
4. Broadcast the ride request to the top N nearest eligible drivers simultaneously via WebSocket.
5. Each driver has a configurable acceptance window (default 15 seconds, from `platform_config.ride_driver_acceptance_window_secs`) to accept.
6. First driver to accept is assigned. All other drivers' notifications are dismissed.
7. If no driver accepts, expand the search radius by 2 km increments (configurable: `ride_radius_expansion_km`) up to a maximum of 10 km (`ride_max_match_radius_km`) and retry.
8. If no driver is found after maximum radius expansion, notify the client: "No drivers available in your area. Please try again."

### 6.2 Fare Calculation

Fares are computed using the Google Maps Distance Matrix API for estimates and actual GPS trail data for final fares.

**Formula**: `fare = base_fare + (distance_km × per_km_rate) + (duration_mins × per_min_rate)`

All formula parameters are stored in `platform_config` and adjustable without code deployment:

- `ride_base_fare_pesewas`: 300 (GHS 3.00)
- `ride_per_km_pesewas`: 150 (GHS 1.50)
- `ride_per_min_pesewas`: 20 (GHS 0.20)

**Rules**:

- Estimated fare: calculated from Distance Matrix API response (shown before booking)
- Final fare: calculated from actual GPS trail distance and ride duration
- Surge: `final_fare × surge_multiplier` (configurable by Super Admin)
- Multi-stop: fare recalculated incrementally at each added stop
- Rounding: all fractional fares rounded UP to nearest whole GHS via `roundUpToGhs()` (PRD edge case #11)
- Surge lock: fare locked at booking time — if surge activates after booking but before acceptance, the original fare is preserved (PRD edge case #8)
- All values stored as INTEGER pesewas, never floats

### 6.3 Cancellation & Disconnection

**Client cancellation**: 3-minute free window from driver acceptance (`ride_cancellation_free_window_secs`). After 3 minutes, a cancellation fee is charged.

**Driver cancellation**: 3 cancellations in a rolling 30-day window (`cancellation_rolling_period_days`) triggers automatic suspension pending admin review. Reason required and logged.

**Driver disconnection**: if a driver loses connectivity during an active ride, a 2-minute grace period starts (`ride_disconnection_grace_secs`). If connectivity returns within 2 minutes, the ride continues seamlessly. If not, the incident escalates to the admin queue. Force-closing the app mid-ride is treated identically to a connectivity drop (PRD edge case #41).

**Online toggle lock**: once a ride is in 'accepted', 'driver_en_route', or 'in_progress' status, the driver's online/offline toggle is locked to 'online' and disabled in the UI. Re-enabled only after the ride is completed, cancelled, or escalated.

---

## 7. Artisan Marketplace Engine Design

### 7.1 Job Request & Bid Lifecycle

1. Client selects a service category, provides description, optional photos, location (pin-drop via Mapbox or address text), and preferred time (immediate or scheduled).
2. System checks artisan availability: if zero artisans in the category within the region, client is informed immediately and job is created in 'queued' status for admin visibility (PRD edge case #45).
3. For available categories: request sent to up to 3 nearest available artisans simultaneously (via `findArtisansWithinRadius` PostGIS helper).
4. Each artisan has 5 minutes (`job_bid_window_secs`) to submit a bid. Bids validated against category minimum (`service_categories.min_bid_pesewas`). Bids above GHS 5,000 (`service_categories.high_bid_flag_pesewas`) flagged for admin review with status 'admin_review' (PRD edge case #44).
5. Maximum 3 bids collected per job (`job_max_bids`) — once 3 bids are received, no further bids accepted. Enforced by counting existing bids before accepting new ones.
6. Client reviews bids with artisan profile, rating, and portfolio — selects preferred artisan.
7. If zero bids received after 5 minutes, job escalates to admin queue for manual assignment.

### 7.2 Material Cost Supplement Request (v1.1 addition)

Per PRD v2.1 Sections 4.5.2-4.5.3:

**Bid structure**: The bid is a single total amount covering both labour and estimated materials. No separate materials line item at bid time.

**Supplement rules**:

- Only ONE supplement request is permitted per job — enforced at database level via `UNIQUE(job_id)` constraint on `supplement_requests` table
- Must be submitted BEFORE the artisan begins work (status must be 'confirmed' or 'arrived', not 'in_progress')
- Must include: additional amount (pesewas) and clear reason
- Client must approve or reject in-app before artisan proceeds
- If approved: `artisan_jobs.agreed_price_pesewas` updated to original bid + supplement
- If rejected: artisan proceeds at original price or both parties may agree to cancel
- On submission: `artisans.supplement_count` incremented for pattern tracking (PRD edge case #57)

**Pattern detection**: Artisans with a high `supplement_count / completed_jobs_count` ratio are flagged in admin reporting. Visible in the admin provider performance report.

### 7.3 Scheduled Job Handling

For jobs with a `scheduled_for` timestamp, the notification chain runs as follows:

- **T-24h**: Push notification to artisan to confirm attendance. If no confirmation by T-20h (`job_scheduled_confirm_deadline_hours`), admin alerted to arrange replacement.
- **T-2h**: Reminder push notification to both client and artisan.
- **T+30min**: If artisan has not marked 'en_route' (`job_noshow_escalation_mins`), job auto-escalates to admin queue and client notified. No-show counts toward 3-cancellation suspension threshold.

### 7.4 Job Staleness & Welfare Checks

**Job staleness timeout** (tracked via `artisan_jobs.last_activity_at`):

- 8 hours with no status update: both parties receive check-in push notification
- 24 hours: job auto-escalates to admin queue
- 48 hours: payout frozen, job flagged for manual admin review

**Artisan welfare check** (tracked via `artisan_jobs.arrived_at`):

- If artisan marks 'arrived' but no app activity for 3 hours: automated welfare check push notification
- If no response within 15 minutes: admin alerted with artisan's last known GPS and job details via `welfare_checks` table
- This supplements (does not replace) the emergency button

### 7.5 Cancellation Rules

- Client free cancellation: 30 minutes after selecting a bid, before artisan marks 'en_route' (`job_cancellation_free_window_secs`)
- After 30 minutes or once artisan marks 'en_route' (whichever first): 20% of agreed price paid to artisan as compensation (`job_cancellation_fee_percent`)
- Artisan cancellation: same 3-cancellation rolling threshold applies to both on-demand and scheduled jobs

---

## 8. Payment System Design

### 8.1 Micro-Escrow Flow

All payments flow through a micro-escrow model invisible to users:

1. Client's payment initiated via Flutterwave (MoMo, card, or bank transfer)
2. Funds held in platform escrow account on Flutterwave (payment status: 'escrowed')
3. Release conditions: Rides — on ride completion. Artisan jobs — on dual confirmation (both parties confirm)
4. Platform deducts 20% commission (calculated on `pre_promo_amount_pesewas`, inclusive of Flutterwave fees)
5. Net payout pushed to provider's MoMo wallet or bank account
6. Instant payouts: within 30-60 seconds. Batch payouts: aggregate and disburse at **18:00 GMT**

### 8.2 Batch Payout Processing (v1.1 corrected)

**Corrected from v1.0**: Batch payout time is **18:00 GMT** (not 22:00 GMT as stated in v1.0). Ghana does not observe daylight saving, so GMT = local time year-round.

**Retry schedule** (aligned with PRD v2.1 Section 7.4.1):

- Primary run: **18:00 GMT**
- Retry 1: **19:30 GMT**
- Retry 2: **20:00 GMT**
- Retry 3: **06:00 GMT** (next morning)

If all retries fail: admin alerted immediately, funds HELD — they do not silently roll into the next day's batch. All batch runs logged in `batch_payout_runs` table with status, provider count, total amount, and failure reason.

### 8.3 Dispute & Refund Handling

- Disputes must be raised within 2 hours of job/ride completion (`dispute_window_hours`)
- Only the disputed amount is frozen — provider's other earnings remain accessible (PRD edge case #39)
- Ride fare disputes: admin compares GPS trail to optimal Google Maps route; if actual route exceeds optimal by more than 30% in distance (`dispute_route_excess_threshold_percent`), partial refund covering excess fare may be issued
- Provider-initiated disputes for non-confirmation: if client does not confirm artisan job completion within 4 hours (`job_client_confirm_deadline_hours`), artisan can escalate; admin reviews evidence and can force-release payment
- Clawback from already-paid providers: platform absorbs refund initially, then deducts from provider's next payout with prior notification. Provider notified BEFORE clawback processed.
- Account deactivation blocked while clawback balance is outstanding. Clawbacks under GHS 100 (`clawback_writeoff_threshold_pesewas`) written off after 90 days inactive (`clawback_writeoff_inactive_days`). Above GHS 100: escalated for manual resolution.

### 8.4 Commission Structure

| Item                | Rule                                                                                     |
| ------------------- | ---------------------------------------------------------------------------------------- |
| Platform commission | 20% of transaction value (`commission_rate_percent`)                                     |
| Commission basis    | ALWAYS calculated on `pre_promo_amount_pesewas`, never post-discount (PRD edge case #26) |
| Flutterwave fees    | Absorbed by platform — built into the 20% commission model (PRD edge case #24)           |
| Instant payout fee  | Free for providers — no convenience fee charged                                          |
| Tips                | Processed separately, zero commission, full amount to provider                           |
| Fractional fares    | Always rounded UP to nearest whole GHS (PRD edge case #11)                               |

### 8.5 Foreign Currency Handling (Pilot)

Card payments accepted in GHS only. Flutterwave handles FX conversion for non-GHS cards (typically 2.5-3.8% markup). Platform absorbs FX cost within commission during pilot. If a transaction becomes unprofitable (commission < FX cost), platform absorbs the loss. Post-pilot evaluation required (PRD edge case #50).

---

## 9. USSD Channel Technical Design

### 9.1 Integration Architecture

The USSD channel integrates via Africa's Talking USSD API through a dedicated callback endpoint (`POST /v1/ussd/callback`). Session state stored in Redis with 5-minute TTL for resume capability.

**Constraints**: 180-second max session (telco-enforced), 160-character safe screen limit, 2-second max response time, numbers-only input (except job description free text).

### 9.2 Supported Flows

Artisan service requests only — ride-hailing is not available via USSD. Seven flows: request artisan service (zone → category → description → confirm), check booking status, cancel booking, MoMo payment, view last 5 bookings, confirm job completion, and zone change.

### 9.3 Language Support

English and Twi at launch. Language selected during registration, persists across sessions. All Twi text uses GSM 7-bit characters (no diacritics in USSD menus). Menus paginated with max 6 options per screen.

### 9.4 Session Resume

If a session times out mid-flow, partial state saved in Redis for 5 minutes. User redialing within 5 minutes is offered to resume. Power outage/network drop: same number redial within 3 minutes offers resume. Authentication from borrowed phones: OTP sent to registered number only.

### 9.5 Account Linking

When a USSD-registered user later downloads the Client App and signs up with the same phone number, the USSD account is automatically linked. Booking history, zone preference, and account status carry over via `ussd_accounts.linked_to_app` flag.

---

## 10. Safety & Security Architecture

### 10.1 Emergency System

Emergency button available to both clients and providers during active rides/jobs. Two-step confirmation prevents accidental activation. On confirmation: GPS shared with emergency contacts, admin alerted with full booking details, Ghana Police 191 auto-dial triggered, live audio/video recording uploaded to encrypted S3 bucket. Provider emergency activations logged with equal priority. Recordings retained minimum 90 days.

### 10.2 Data Encryption

- In transit: TLS 1.3 for all connections
- At rest: Ghana Card numbers encrypted with AES-256 (BYTEA column, application-layer encryption). Database-level encryption via RDS encryption at rest. S3 bucket encryption for all stored media.
- Log redaction: phone numbers, emails, OTPs, Ghana Card numbers, payment details, auth headers — all masked in logs

### 10.3 Authentication & Access Control

- Passwordless: phone number + OTP (6-digit, 5-minute expiry, max 3 attempts)
- JWT: access tokens (15 minutes), refresh tokens (30 days), issuer: `myshop-api`
- Admin: separate JWT secrets, password-based login with bcrypt (12 rounds)
- RBAC: 4-level admin model enforced at guard level. Regional Admin queries filtered to Ashanti at service level.
- All admin actions logged in `audit_log` table

### 10.4 Ghana DPA Compliance

Registration with Ghana Data Protection Commission before pilot launch. Explicit consent flow during registration. Users may request data deletion (subject to retention). Soft-deleted data purged after 90 days via nightly cron. Emergency recordings: strict access controls (admin + law enforcement only).

---

## 11. Admin Dashboard Technical Design

React 18 SPA with TypeScript, Vite build tool, TanStack Query for server state, Zustand for client state, Recharts for KPI visualizations, Google Maps JS API for live operations map. Role-aware route guards filter menu items and data access per admin level. Real-time updates via WebSocket for live map markers and verification queue.

---

## 12. Notification Engine

Event-driven microservice pattern within the modular monolith. Listens to domain events via RabbitMQ and dispatches across five channels: push (Firebase), SMS (Africa's Talking), WhatsApp (Business API), email (AWS SES), and in-app. Channel routing rules per event type as defined in PRD Section 10. Scheduled job reminders triggered by cron jobs checking `artisan_jobs.scheduled_for`. Rate-limited per user per channel to prevent spam.

---

## 13. Localisation & Internationalisation

All user-facing dynamic content (category names, USSD menus, announcements) managed via `translations` table: `entity_type + entity_id + field + locale → value`. Static app UI strings managed via Flutter ARB files and React i18n bundles. English and Twi fully supported at launch. Post-pilot languages (Ga, Ewe, Dagbani, Hausa, Fante) added via the translations table without app releases. Feature flags control language availability (`FF_LANGUAGE_GA`, etc.).

---

## 14. Testing Strategy

### 14.1 Testing Layers

- **Unit Tests**: All business logic — fare calculations, bid validation, cancellation window checks, rating threshold logic, commission calculations, phone normalization. Target: 80%+ code coverage for API, 90%+ for utils.
- **Integration Tests**: Module-to-module communication, Flutterwave payment flows (sandbox), Smile Identity KYC callbacks, Africa's Talking USSD/SMS, Firebase push delivery.
- **End-to-End Tests**: Full ride lifecycle, full artisan job lifecycle (including bid, selection, supplement, completion, dual confirmation, payout), USSD complete flow, admin verification workflow.
- **Load Tests**: Simulate 200+ concurrent drivers, 5,000+ registered clients, peak ride requests, batch payout processing. Target: sub-500ms p99 latency for core endpoints.
- **Security Tests**: OWASP Top 10, JWT validation, RBAC enforcement, regional data scoping, encrypted data handling.

### 14.2 Critical Test Scenarios

73 required test scenarios mapped to PRD edge cases across 7 feature categories: rides (15 scenarios), marketplace (22), payments (15), auth/accounts (6), USSD (9), admin (8). Full scenario list documented in `.claude/plugins/testing-qa.md`.

---

## 15. Monitoring & Observability

- **Metrics**: Prometheus with Grafana dashboards — request latency (p50/p95/p99), error rates, active rides/jobs, payment success rate, payout latency, driver online count, bid submission rate
- **Logging**: Structured JSON logging with correlation IDs across module boundaries. Sensitive fields redacted.
- **Alerting**: Critical alerts for: payment gateway failures, emergency activations, batch payout failures, service downtime
- **Business KPIs**: Real-time dashboard showing pilot success metrics against targets from PRD Section 1.3

---

## 16. Open Decisions Requiring Resolution

| #   | Decision                                                            | Engineering Impact                                                                     | Status                                |
| --- | ------------------------------------------------------------------- | -------------------------------------------------------------------------------------- | ------------------------------------- |
| 1   | Client identity verification for artisan jobs (PRD #55)             | Determines whether Ghana Card verification is blocking or a badge for artisan bookings | 🚫 Open — needs decision before pilot |
| 2   | Physical altercation protocol (PRD #29)                             | Requires defining escalation rules, evidence collection, law enforcement integration   | 🚫 Open — needs business development  |
| 3   | Disqualifying offenses list for background checks (PRD 5.1.1)       | Impacts verification module auto-suspension triggers on police check results           | 🚫 Open — needs legal counsel         |
| 4   | Post-pilot FX handling for foreign currency card payments (PRD #50) | May require visible FX surcharge at checkout — engineering lead time needed            | Deferred to post-pilot                |
| 5   | Post-pilot monetisation options (featured listings, subscriptions)  | Requires data model extensions, admin config, new provider-facing UI                   | Deferred to post-pilot                |

---

## 17. Glossary

| Term    | Definition                                  |
| ------- | ------------------------------------------- |
| DPA     | Ghana Data Protection Act                   |
| EDD     | Engineering Design Document                 |
| FX      | Foreign Exchange                            |
| GHS     | Ghana Cedi                                  |
| JWT     | JSON Web Token                              |
| KYC     | Know Your Customer                          |
| MoMo    | Mobile Money                                |
| OTP     | One-Time Password                           |
| Pesewas | Ghana Cedi subunit (100 pesewas = GHS 1.00) |
| PostGIS | PostgreSQL Geospatial Extension             |
| PRD     | Product Requirements Document               |
| RBAC    | Role-Based Access Control                   |
| SPA     | Single Page Application                     |
| USSD    | Unstructured Supplementary Service Data     |
| UUIDv7  | Time-sortable UUID per RFC 9562             |

---

_Document Version: 1.1 | Reconciled with PRD v2.1. Key changes: modular monolith architecture, batch payout time corrected to 18:00 GMT, supplement request rules formalized, UUIDv7 primary keys, pesewas money storage, PostGIS via Prisma Unsupported + typed helpers, normalized saved locations and provider documents tables, translations table for i18n._
