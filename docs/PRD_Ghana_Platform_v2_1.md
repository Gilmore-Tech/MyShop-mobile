# 🇬🇭 Product Requirements Document

## Gilmore Technologies Ride-Hailing & Artisan Marketplace Platform

**Version:** 2.1  
**Pilot Region:** Ashanti Region, Ghana  
**Date:** March 2026  
**Status:** CONFIDENTIAL — FOR INTERNAL USE ONLY

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [User Personas](#2-user-personas)
3. [Platform Architecture Overview](#3-platform-architecture-overview)
4. [Client App — Feature Requirements](#4-client-app--feature-requirements)
5. [Provider App — Feature Requirements](#5-provider-app--feature-requirements)
6. [USSD Channel — Feature Requirements](#6-ussd-channel--feature-requirements)
7. [Payment Architecture](#7-payment-architecture)
8. [Admin Dashboard — Feature Requirements](#8-admin-dashboard--feature-requirements)
9. [Safety & Security](#9-safety--security)
10. [Notification Strategy](#10-notification-strategy)
11. [Localisation](#11-localisation)
12. [Edge Case Policy Register](#12-edge-case-policy-register)
13. [Distribution & Pilot Strategy](#13-distribution--pilot-strategy)

---

## 1. Executive Summary

This Product Requirements Document (PRD) defines the complete product scope, feature requirements, user flows, and business rules for a Ghanaian-first mobile platform that combines ride-hailing and an artisan services marketplace into a single ecosystem.

The platform consists of three distinct applications sharing a common backend infrastructure:

- **Client App** (Flutter — iOS & Android): The consumer-facing application through which clients book rides and request artisan services.
- **Provider App** (Flutter — iOS & Android): A role-siloed application where drivers see a pure ride-hailing interface and artisans see a pure marketplace interface — with zero overlap between the two experiences.
- **Admin Dashboard** (React — Web): A multi-level administrative interface for platform management, provider verification, dispute resolution, and operational oversight.

> **Pilot Scope:** The platform will launch as a 3-month open beta pilot in the Ashanti Region of Ghana, targeting Kumasi and surrounding areas. The pilot focuses exclusively on the Ashanti market before national scale-up.

---

### 1.1 Problem Statement

| #   | Problem                                                                           | Platform Solution                                                                    |
| --- | --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| 1   | Unreliable, untracked ride-hailing with no fare transparency or safety guarantees | GPS-tracked rides with upfront fare estimates, safety features, and verified drivers |
| 2   | No trusted, structured way to find and hire verified local artisans               | Verified artisan marketplace with bidding, ratings, and escrow-protected payments    |
| 3   | Digital exclusion of feature phone users and those without data access            | USSD channel for artisan service requests, accessible on any mobile phone            |

---

### 1.2 Strategic Goals

- Build the most trusted ride-hailing and artisan marketplace platform in Ghana.
- Drive financial inclusion by enabling verified gig workers to earn consistently with instant payouts.
- Bridge the digital divide via USSD support for feature phone and offline users.
- Establish market dominance in Ashanti Region within 3 months before national expansion.

---

### 1.3 Success Metrics — Pilot (3 Months)

| Metric                       | Target              |
| ---------------------------- | ------------------- |
| Registered clients           | 5,000+              |
| Verified drivers onboarded   | 200+                |
| Verified artisans onboarded  | 300+                |
| Completed rides              | 10,000+             |
| Completed artisan jobs       | 3,000+              |
| Average client app rating    | 4.2+ stars          |
| Provider retention rate      | 70%+                |
| USSD service requests        | 500+                |
| Payment success rate         | 98%+                |
| Average ride completion time | Under 8 mins pickup |

---

## 2. User Personas

### 2.1 Client — Ama (Urban Professional)

> _Age 28 | Location: Adum, Kumasi | Phone: iPhone 13 | Tech-savvy, time-poor professional who uses ride-hailing daily and frequently needs home repair services._

- Needs a reliable, trackable ride to work every morning.
- Wants to book a plumber or electrician without calling around manually.
- Values transparent pricing, driver verification, and in-app payment.
- Shares ride status with family for safety.

---

### 2.2 Client — Kweku (Feature Phone User)

> _Age 45 | Location: Suame, Kumasi | Phone: Nokia 3310 | Informal trader who cannot afford a smartphone or data plan but needs artisan services regularly._

- Dials USSD short code to request a mechanic or plumber.
- Pays via MTN Mobile Money.
- Receives SMS confirmations and provider contact details.
- Confirms job completion via USSD session.

---

### 2.3 Provider — Kofi (Driver)

> _Age 32 | Location: Bantama, Kumasi | Vehicle: Toyota Corolla 2018 | Full-time driver, previously worked with informal taxi operators._

- Wants consistent ride requests without paying weekly fees to a taxi union.
- Needs instant payouts to MoMo after each ride.
- Values a clean, Uber-style app with no marketplace confusion.
- Tracks earnings and peak hours via the analytics dashboard.

---

### 2.4 Provider — Abena (Artisan — Electrician)

> _Age 38 | Location: Asokwa, Kumasi | Shop: Solo worker, 8 years experience | Runs a small electrical services business with no online presence._

- Wants new clients without word-of-mouth only.
- Sets her own service radius and bids on jobs that match her skills.
- Receives instant MoMo payout after job confirmation.
- Builds reputation through verified ratings and completed job history.

---

### 2.5 Admin — Regional Operations Manager

> _Role: Regional Admin | Region: Ashanti | Responsibilities: Provider verification, live map oversight, manual job assignment, regional reporting._

- Reviews and approves provider verification documents.
- Monitors live ride and job activity on the admin map.
- Manually assigns jobs when no artisan bids.
- Generates weekly regional performance reports.

---

## 3. Platform Architecture Overview

The platform is composed of three distinct applications sharing a single backend. Each application serves a clearly defined user group with no feature overlap between provider roles.

| Application                 | Platform                      | Primary Users                                         |
| --------------------------- | ----------------------------- | ----------------------------------------------------- |
| Client App                  | Flutter (iOS + Android)       | Clients booking rides and artisan services            |
| Provider App — Driver View  | Flutter (iOS + Android)       | Verified drivers (ride-hailing only)                  |
| Provider App — Artisan View | Flutter (iOS + Android)       | Verified artisans (marketplace only)                  |
| Admin Dashboard             | React Web Application         | Super Admin, Regional Admin, Ops Admin, Support Agent |
| USSD Channel                | Telco-integrated USSD Gateway | Feature phone users requesting artisan services       |

---

### 3.1 Account & Role Model

- A single person may hold a Client account AND a Driver account AND an Artisan account simultaneously.
- Each account type is treated as a completely separate entity — no shared data, no overlapping flows.
- A person cannot create more than one account of the same type using the same identity details.
- At login on the Provider App, users with dual provider registrations (driver + artisan) are shown a role picker screen before being routed to their respective dashboard.
- Provider role is locked at the first signup screen and cannot be changed post-registration.

> **Identity Rule:** Phone number is the primary identity anchor. A phone number can be associated with at most one Driver account and one Artisan account. Duplicate accounts of the same type are blocked with a clear error message.

---

### 3.2 Pilot Constraints

- Geographic scope: Ashanti Region only for the 3-month pilot.
- All GPS matching, radius calculations, and zone-based USSD location data are scoped to Ashanti.
- Rides or artisan jobs requested from outside Ashanti are outside pilot scope.
- Admin dashboard Regional Admin role is scoped to Ashanti data only.

---

## 4. Client App — Feature Requirements

### 4.1 Registration & Authentication

- Client registration requires: phone number + email address only.
- OTP verification sent to phone number during signup.
- No ID verification required for clients at registration.
- Banned clients attempting re-registration with a new SIM are required to complete Ghana Card verification before proceeding.
- Login via phone number + OTP (passwordless).
- Login once, until app data is deleted (like WhatsApp).

---

### 4.2 Home Screen — Map-First UI

- Full-screen Google Maps as the default home view.
- Ride destination search bar prominently displayed.
- Saved locations (Home, Work, Favourites) accessible from the search bar.
- Bottom navigation bar with four tabs: Home (Rides) | Services | Activity | Profile.
- A persistent floating mini-card appears above the bottom navigation bar when there is an active ride or active artisan job. Tapping the card expands the full tracking view.
- Rides and artisan jobs are tracked independently — both mini-cards can be visible simultaneously.

---

### 4.3 Ride-Hailing Flow

- Client enters destination in the search bar.
- App displays estimated fare (calculated from time + distance) and estimated pickup time.
- Client confirms booking.
- System broadcasts request to nearby available drivers within their set radius.
- If no driver accepts, system expands radius and retries.
- If still no driver found, client is notified: "No drivers available in your area. Please try again."
- Driver accepts — client sees driver name, photo, vehicle details, and live GPS tracking.
- 3-minute free cancellation window from driver acceptance. Fee applies after.
- Client can add additional stops at booking or mid-ride.
- On stop additions outside Ashanti pilot region, client is warned and driver given option to decline.
- Driver marks ride complete — client rates driver and optionally tips.

---

### 4.4 Multi-Stop Rides

- Clients can add multiple stops during booking.
- Clients can also add stops mid-ride at any point.
- Fare recalculates automatically for each added stop.
- Driver receives updated route on their navigation.
- Driver may decline a mid-ride stop if it is outside their service area or outside the Ashanti pilot region. Ride then continues to the original destination.

---

### 4.5 Services Tab — Artisan Marketplace

The Services tab is a completely separate flow from the ride-hailing home screen. No map is shown. The experience is card-based and category-driven.

- Client taps Services tab — full-screen category grid is shown.
- Available categories: Towing, Electrician, Mechanic, Seamstress (Fashion), Painter, Masonry, Carpenter, Plumber, Satellite/Dish TV Installer, Repairs (Laptops, Fridge, AC, TV, Phone).
- Client selects a category, describes the job, optionally adds photos, and sets a preferred time (immediate or scheduled).
- Client sets their location by dropping a pin (Mapbox) or entering an address.
- System checks artisan availability in the selected category before creating the request. If zero artisans are registered in that category within the region, client is informed immediately: "No [category] artisans are available in your area yet. We'll notify you when one joins." Job is created in a 'queued' status for admin visibility.
- Request is sent to up to 3 nearest available artisans simultaneously.
- Each artisan has 5 minutes to submit a bid. Maximum 3 bids per job.
- Client reviews incoming bids alongside artisan profiles, ratings, and portfolio.
- Client selects preferred artisan — job is confirmed and artisan is notified.
- If zero bids received after 5 minutes, job escalates to admin queue for manual assignment.

#### 4.5.1 Bid Pricing Guardrails

- Each artisan service category has a platform-defined minimum bid amount, configurable by Super Admin (e.g., minimum GHS 30 for an electrician, GHS 50 for masonry).
- Bids below the category minimum are rejected with a clear error message to the artisan.
- Bids above GHS 5,000 are flagged for admin review before being shown to the client.
- Minimum bid amounts are stored in a `service_categories` configuration table and are adjustable without code deployment.

#### 4.5.2 How Bids Work — Materials & Estimation

The bid is a **single total amount** submitted by the artisan. It is expected to cover both labour and any materials the artisan estimates will be required for the job. There is no separate materials line item at bid time.

**Artisan bidding process:**

- The artisan reviews the client's job description and photos.
- Using their professional experience, the artisan estimates: labour time + likely materials needed.
- They roll both into one total bid amount, optionally adding a message to explain what is included.
- The bid is the artisan's professional commitment to complete the described job at that price.

**Example:**

> Client posts: "Living room rewiring — light switches not working, wiring may be faulty."
> Artisan bids: GHS 180 with message: "Includes inspection, circuit rewiring, and standard materials (wire, switches). If fault is more extensive than described, I will notify you before proceeding."

#### 4.5.3 Material Cost Supplement Request

In situations where the artisan arrives and discovers the actual scope of the job requires significantly more materials than the original estimate, they may submit a **single material cost supplement request** before starting work.

**Rules:**

- Only **one supplement request is permitted per job**. Once a supplement is submitted (approved or rejected), no further supplement requests can be raised for the same job.
- The supplement must be submitted **before the artisan begins work**. Supplements cannot be raised mid-job or after completion.
- The supplement request must include: the additional amount requested and a clear reason explaining what additional materials are needed and why they were not foreseeable from the original description.
- The client receives an in-app notification and must approve or reject the supplement before the artisan proceeds.
- If the client approves: the `agreed_price` is updated to the original bid plus the supplement amount. The artisan proceeds.
- If the client rejects: the artisan either proceeds within the original agreed price (doing what is possible within scope) or both parties may agree to cancel. Admin mediates if there is a dispute.
- Artisans who frequently submit supplements after winning bids are flagged in the admin dashboard for pattern review. Supplement frequency is tracked as a metric on artisan profiles and is visible to admins.

#### 4.5.4 Scheduled Job Reminders & No-Show Protocol

For artisan jobs scheduled in advance (`scheduled_for` is not null), the platform runs a confirmation and reminder chain:

- **T minus 24 hours:** Push notification sent to the artisan — "You have a confirmed job tomorrow at [time] in [location]. Tap to confirm you'll be there." If the artisan does not confirm within 4 hours (by T-20h), admin is alerted to arrange a replacement.
- **T minus 2 hours:** Reminder push notification sent to both client and artisan.
- **T plus 30 minutes (artisan is late):** If the artisan has not marked 'en_route' in the app, the job auto-escalates to the admin queue and the client is notified: "Your artisan hasn't confirmed they're on the way. Our team is finding you an alternative."
- Artisan no-show is treated as a cancellation and counts toward the 3-cancellation suspension threshold.

#### 4.5.5 Artisan Job Cancellation Window

- Clients have a 30-minute free cancellation window after selecting a bid (before artisan marks en_route).
- After 30 minutes, or once the artisan marks 'en_route' (whichever comes first), cancellation incurs a fee of 20% of the agreed price, paid to the artisan as compensation for lost time.
- Artisan-side cancellation rules remain unchanged (3-cancellation suspension threshold applies).

#### 4.5.6 Job Staleness Timeout

- If an artisan job remains in 'in_progress' status for more than 8 hours with no status update, both parties receive a check-in push notification asking for a status update.
- After 24 hours in 'in_progress' with no response, the job auto-escalates to the admin queue.
- After 48 hours with no response from either party, the payout is frozen and the job is flagged for manual admin review.

---

### 4.6 Active Booking Tracking

- Persistent floating mini-card above bottom nav shows active booking status at all times.
- Rides and artisan jobs each have independent tracking cards.
- Tapping mini-card expands full tracking screen with live provider location, ETA, and communication tools.
- Client can share ride/job status with trusted contacts via a shareable link.
- Share link remains active for the estimated duration of the ride/job plus a 30-minute buffer, then expires automatically.

---

### 4.7 Communication

- In-app chat available between client and provider during active jobs/rides.
- Masked phone calls available — neither party sees the real phone number.
- Communication channel closes automatically when job/ride is marked complete.

---

### 4.8 Payments

- Payment has both in-app and cash options.
- Supported methods: MTN Mobile Money, Telecel Cash, AirtelTigo Money, Visa/Mastercard, Bank Transfer, Flutterwave Wallet.
- Ride fares are calculated on time + distance. Fare is displayed as an estimate before booking and finalised at trip end.
- Artisan job payment is released after dual confirmation (both client and provider confirm completion).
- Fractional fares are always rounded up to the nearest whole Ghana Cedi.
- Platform commission (20%) is always calculated on the pre-promo fare, not the discounted amount.
- Optional tip can be added after job/ride completion. Tip is processed separately.
- Promo codes and referral discounts applicable at checkout.

#### 4.8.1 Ride Fare Disputes

- Clients can dispute a ride fare within 2 hours of ride completion (same window as artisan disputes).
- Admin reviews the GPS trail against the optimal Google Maps route for the same origin and destination.
- If the actual route exceeds the optimal route by more than 30% in distance (excluding known detours such as road closures), admin may issue a partial refund covering the excess fare.
- Standard dispute and clawback flow applies.

#### 4.8.2 Provider-Initiated Disputes (Non-Confirmation)

- If a client does not confirm job completion within 4 hours of the artisan marking complete, the artisan can escalate to admin.
- Admin reviews evidence (photos, chat history, timestamps) and can force-release payment if the job is deemed complete.
- This prevents clients from withholding confirmation to avoid payment.

---

### 4.9 Loyalty Programme

- Clients earn points for every completed ride and artisan job.
- Points are redeemable as discounts on future bookings.
- Point balance visible in Profile tab.
- Referral programme: client earns bonus points when a referred user completes their first booking.
- Drivers and artisans have access to loans and other incentives, meeting some conditions (e.g. number of rides/jobs completed in a week, high rate of in-app payment over cash payments).

---

### 4.10 Safety Features

- Emergency button accessible during any active ride or job.
- Emergency button requires two-step confirmation (tap button, then tap Confirm on next screen) to prevent accidental activation.
- On emergency confirmation: GPS location shared with emergency contact, admin alerted immediately, Ghana Police 191 called automatically, live audio/video recording triggered.
- Emergency recordings stored on secure cloud server — accessible to admin and law enforcement only.
- Ride/job status shareable link available at all times during active bookings.
- All phone numbers masked — neither party ever sees the other's real number.

---

### 4.11 Saved Locations & Preferences

- Clients can save named locations: Home, Work, and custom favourites.
- Saved locations appear as quick-select options in the ride destination search.
- Preferred payment method can be saved for faster checkout.

---

## 5. Provider App — Feature Requirements

> **Role Isolation Principle:** The Provider App is a single Flutter application that renders two completely different navigation stacks based on the provider's registered role. A driver sees exclusively the ride-hailing interface. An artisan sees exclusively the marketplace interface. There is zero UI overlap between the two experiences.

### 5.1 Provider Registration & Onboarding

- Role selection (Driver or Artisan) is the first screen of the registration flow.
- Role is permanently locked after selection — cannot be changed post-registration.
- A person may register as both a Driver and an Artisan using the same phone number and email. They will see a role picker screen at login.

**Driver Verification Requirements**

- Valid Ghana driver's licence (photo upload) + input of license number and date of expiry.
- Vehicle registration document (photo upload).
- National ID document (photo upload).
- Vehicle roadworthiness certificate (photo upload).
- Profile photo.
- Background/criminal check consent and submission.
- All documents are reviewed and approved by admin before the driver account is activated.

**Artisan Verification Requirements**

- Trade certificate or proof of qualification (photo upload).
- Business registration doc, if applicable.
- National ID document (photo upload).
- Portfolio of past work (minimum 3 photos).
- Profile photo.
- Background/criminal check consent and submission.
- All documents are reviewed and approved by admin before the artisan account is activated.

#### 5.1.1 Background Check Process

- Digital KYC and identity verification is performed via Smile Identity (or equivalent provider) at registration. Automated, completes within minutes.
- A parallel Ghana Police Criminal Records Bureau background check is initiated for all provider accounts. Turnaround is typically 2–4 weeks.
- Providers may begin accepting jobs after digital KYC clears and document verification is approved by admin.
- If the police background check returns disqualifying information after the provider has started working, the account is immediately suspended pending admin review.
- Disqualifying offenses include: violent crimes, fraud, sexual offenses, and any offenses involving minors. The full list of disqualifying offenses must be defined and documented by legal counsel before pilot launch.

---

### 5.2 Driver View — Ride-Hailing Interface

- Driver goes online/offline via a prominent toggle on the home screen.
- When online, driver's GPS location is continuously broadcast to the matching system.
- Incoming ride requests appear as full-screen notifications with client pickup location, estimated distance, and estimated earnings.
- Driver has a defined acceptance window to accept or decline each request.
- After accepting: full navigation to pickup point via Google Maps.
- Driver marks client as picked up to start the fare meter.
- Live fare accumulates based on time + distance during the ride.
- Multi-stop rides: driver receives updated route on each stop addition by client.
- Driver may decline a mid-ride stop added outside their service area — ride reverts to original destination.
- Driver marks ride complete at drop-off.
- Surge pricing multiplier displayed clearly on the driver's home screen when active.

#### 5.2.1 Driver Online/Offline Lock During Active Rides

- Once a ride is in 'accepted', 'en_route', or 'in_progress' status, the driver's online/offline toggle is locked to 'online' and disabled in the UI.
- If the driver force-closes the app mid-ride, it is treated identically to a connectivity drop — the same 2-minute grace period and escalation flow applies.
- The toggle is re-enabled only after the ride is completed, cancelled, or escalated to admin.

**Driver Cancellation Policy**

- Drivers may cancel an accepted ride before pickup.
- 3 cancellations within a rolling 30-day period triggers a temporary suspension pending admin review.
- Cancellation reason is required and recorded for admin audit.

**Driver Disconnection Policy**

- If a driver loses connectivity during an active ride, a 2-minute grace period begins.
- If connectivity is restored within 2 minutes, the ride continues seamlessly.
- If connectivity is not restored within 2 minutes, the incident is escalated to the admin queue for manual intervention.

---

### 5.3 Artisan View — Marketplace Interface

- Artisan sets their service categories, service radius, and shop capacity during profile setup.
- Shop capacity options: Solo worker (1 concurrent job max) or Multi-worker shop (up to 3 concurrent jobs).
- Artisan can toggle online/offline at any time. System blocks new requests when artisan is offline.
- Incoming job requests show: service category, job description, client location, and client-provided photos.
- Artisan has 5 minutes to submit a bid. Bid includes price and optional message to client.
- Maximum 3 bids are collected per job — once 3 bids are in, no further bids are accepted.
- If the artisan is selected by the client, they receive a job confirmation notification.
- Artisan navigates to client location using Mapbox.
- For jobs where materials cost more than quoted, artisan can submit **one** material cost supplement request before starting work. Client must approve in-app before work proceeds. Only one supplement request is permitted per job — no further supplements can be raised once one has been submitted.
- Artisan marks job complete — triggers client confirmation request.
- Payment released after both client and artisan confirm completion.

#### 5.3.1 Artisan In-Home Welfare Check

- Artisans are required to mark 'arrived' in the app when they reach the client's location.
- If an artisan marks 'arrived' but does not mark 'complete' or send any app activity for more than 3 hours, the system sends an automated welfare check push notification: "Are you okay? Tap to confirm."
- If no response is received within 15 minutes of the welfare check, admin is alerted with the artisan's last known GPS location and job details.
- This flow supplements (does not replace) the emergency button, which remains available at all times.

**Artisan Cancellation & Rating Policy**

- Same 3-cancellation suspension rule applies to both on-demand and advance-scheduled artisan jobs.
- Artisans with a rating below 3.5 stars (minimum 15 completed jobs) receive an in-app warning.
- Artisans with a rating below 3.0 stars are suspended pending admin review.

---

### 5.4 Provider Analytics Dashboard

| Metric               | Description                                                    |
| -------------------- | -------------------------------------------------------------- |
| Total Earnings       | Daily, weekly, and monthly earnings breakdown after commission |
| Completed Jobs/Rides | Total count with trend over time                               |
| Ratings Breakdown    | Average star rating with individual review history             |
| Cancellation Rate    | Percentage of accepted jobs/rides cancelled                    |
| Peak Hours Heatmap   | Visual map of busiest request times by hour and day            |
| Payout History       | Full log of all payouts with timestamps and amounts            |

---

### 5.5 Instant Payouts

- Providers receive payouts immediately after job/ride completion and dual confirmation.
- Platform commission of 20% is deducted before payout.
- Flutterwave transaction fees are absorbed by the platform — built into the commission model.
- Providers choose their payout preference: Instant (per job/ride) or End-of-day batch.
- Both payout options are free for providers — no convenience fee charged.
- Instant payouts delivered to MoMo wallet within 30–60 seconds of confirmation.
- In the event of a payment gateway failure, funds are held in micro-escrow and retried automatically.

---

## 6. USSD Channel — Feature Requirements

> **Purpose:** The USSD channel extends the platform to feature phone users and those without smartphone data access — a significant segment of the Ashanti Region population. USSD supports artisan service requests only. Ride-hailing is not available via USSD.

### 6.1 Registration via USSD

- User dials the platform short code for the first time.
- System detects an unregistered phone number.
- An OTP is sent to the user's phone via SMS.
- User enters the OTP in the active USSD session to verify identity.
- OTP verification is required on first registration only — never again after that.
- User selects their current area from a list of Ashanti zones.
- Registration is complete. Account is created and linked to their phone number.

> **Account Linking:** If a USSD-registered user later downloads the Client App and signs up with the same phone number, their USSD account is automatically linked to their app account. Booking history, zone preference, and account status carry over seamlessly.

---

### 6.2 Location Handling

- USSD has no GPS capability. Location is handled via zone selection.
- On every service request, the system presents the user's last-used area and asks them to confirm or change it.
- This ensures accuracy regardless of the user's current location within Ashanti.
- Zone list covers all major areas within Ashanti Region.

---

### 6.3 Supported USSD Flows

| Flow                    | Description                                                                            |
| ----------------------- | -------------------------------------------------------------------------------------- |
| Request Artisan Service | Select category, confirm location, submit request. Receive artisan assignment via SMS. |
| Check Booking Status    | User dials in to check the status of their most recent or active booking.              |
| Cancel Booking          | User dials in and selects cancel. Cancellation confirmed via SMS.                      |
| Make MoMo Payment       | User initiates payment within USSD session. Supports MTN, Vodafone, AirtelTigo only.   |
| View History            | User views their last 5 bookings and their statuses.                                   |
| Confirm Job Completion  | User dials in after artisan marks job complete to confirm and release payment.         |

---

### 6.4 Notification Strategy for USSD Users

| Event                                        | Channel               |
| -------------------------------------------- | --------------------- |
| OTP delivery                                 | SMS                   |
| Booking confirmed                            | SMS                   |
| Artisan assigned (with name + masked number) | SMS                   |
| Job status update                            | SMS                   |
| Payment deducted receipt                     | SMS                   |
| Check booking status                         | USSD (user-initiated) |
| Cancel a booking                             | USSD (user-initiated) |
| View history                                 | USSD (user-initiated) |
| Job completion confirmation                  | USSD (user-initiated) |

---

### 6.5 USSD Session Management

- USSD sessions have a maximum duration of 180 seconds (telco standard).
- If a session times out mid-booking, the partial session state is saved server-side for 5 minutes.
- If the user redials within 5 minutes, the system detects the same phone number and offers to resume the session.
- Power outages or network drops: same number redial within 3 minutes offers session resume.
- Authentication from borrowed phones: OTP sent to registered number — must be received on registered SIM.

---

### 6.6 USSD Payment Handling

- MoMo only: MTN Mobile Money, Vodafone Cash, AirtelTigo Money.
- Payment initiated within the USSD session.
- If client's MoMo balance is insufficient at payment time, job is held and client is given 24 hours to top up and retry.
- If client locks their MoMo PIN during payment: provider is notified, job is flagged as payment pending, and client is given 24 hours to resolve.
- If confirmation SMS is delayed by the telco: micro-escrow auto-releases after 2 hours if no dispute is raised.

---

### 6.7 Languages

- English and Twi supported at launch.
- User selects preferred language during registration.
- Language preference stored and applied to all subsequent sessions.

---

## 7. Payment Architecture

### 7.1 Payment Gateway

Flutterwave serves as the primary payment gateway, providing a unified API for all supported payment methods under a single integration.

| Payment Method     | Supported For                               |
| ------------------ | ------------------------------------------- |
| MTN Mobile Money   | Collections (clients) + Payouts (providers) |
| Telecel Cash       | Collections (clients) + Payouts (providers) |
| AirtelTigo Money   | Collections (clients) + Payouts (providers) |
| Visa / Mastercard  | Collections (clients) only                  |
| Bank Transfer      | Collections (clients) + Payouts (providers) |
| Flutterwave Wallet | Collections (clients) only                  |

#### 7.1.1 Foreign Currency Card Payments

- During the pilot, card payments are accepted in GHS only. Flutterwave handles currency conversion for non-GHS cards, and the FX markup (typically 2.5–3.8%) is absorbed by the platform within the 20% commission.
- If the FX margin makes a transaction unprofitable (commission earned is less than FX cost), the platform absorbs the loss during the pilot period.
- Post-pilot: evaluate whether to restrict card payments to GHS-denominated cards, add a visible FX surcharge at checkout, or absorb the cost permanently. This is flagged as a post-pilot business decision.

---

### 7.2 Micro-Escrow Model

- Client initiates payment at job/ride completion.
- Funds are held in micro-escrow for the duration of payment processing (typically 30–60 seconds).
- Flutterwave confirms receipt of funds.
- Platform deducts 20% commission (inclusive of Flutterwave transaction fees).
- Net amount is pushed to provider's preferred payout method instantly.
- To the user, this feels instant — the micro-escrow window is invisible to both parties.

> **Gateway Failure Protocol:** If Flutterwave experiences downtime after both parties confirm, funds remain in micro-escrow. The system enters a retry queue, attempting payout every 30 minutes. Admin is alerted after 2 failed retries. Provider is notified of the delay with an estimated resolution time.

---

### 7.3 Commission & Fee Structure

| Item                     | Rule                                                            |
| ------------------------ | --------------------------------------------------------------- |
| Platform commission      | 20% of transaction value deducted from provider payout          |
| Commission basis         | Always calculated on pre-promo fare, never post-discount amount |
| Flutterwave gateway fees | Absorbed by platform — built into the 20% commission model      |
| Instant payout fee       | Free for providers — no convenience fee charged                 |
| Tip processing           | Processed separately after completion, zero commission on tips  |
| Fractional fare rounding | Always rounded up to nearest whole Ghana Cedi                   |

---

### 7.4 Provider Payout Options

- Providers choose their payout preference in their profile settings.
- **Instant:** payout triggered immediately after each job/ride confirmation. Delivered within 30–60 seconds.
- **End-of-day batch:** all earnings accumulated and paid in a single transfer at 18:00 GMT daily.
- Both options are free — no fees charged to providers.

#### 7.4.1 Batch Payout Failure Handling

- Batch payouts run at 18:00 GMT (aligned with Ghana local time year-round, as Ghana does not observe daylight saving).
- If the batch job fails: automatic retries at 19:30, 20:00, and 06:00 the next morning.
- If all retries fail, admin is alerted immediately and funds are held — they do not silently roll into the next day's batch.
- All batch executions are logged in a `batch_payout_runs` audit table with status, provider count, total amount, and failure reason.

---

### 7.5 Dispute & Refund Policy

- All payment disputes are reviewed and decided by the admin team.
- Client must raise a dispute within 2 hours of job/ride completion.
- During dispute review, only the disputed job's amount is frozen. Provider's other earnings remain accessible.
- If admin approves a refund after provider has already been paid: platform absorbs the refund and claws back the amount from the provider's next payout.
- Provider is notified of any clawback with a clear explanation before it is processed.

#### 7.5.1 Unrecoverable Clawback Balances

- If a provider has an outstanding clawback balance, their account cannot be deactivated or soft-deleted until the balance is settled.
- Clawback balances under GHS 100 are absorbed by the platform as a write-off if the provider has been inactive for more than 90 days.
- Clawback balances above GHS 100 on inactive accounts are escalated to admin for manual resolution, which may include direct contact with the provider or referral to a collections process.

---

### 7.6 Insufficient Balance Handling

- If client's MoMo balance is insufficient at payment: job is held in pending state and client is given 24 hours to top up and retry.
- Provider is notified of the payment hold immediately.
- If payment is not completed within 24 hours, admin is notified and the case is escalated for manual resolution.
- If tip payment bounces (provider wallet full or inactive): tip is held in platform wallet and retried automatically. No action required from either party.

---

## 8. Admin Dashboard — Feature Requirements

### 8.1 Admin Level Structure

| Level   | Role           | Key Capabilities                                                                                                                                   |
| ------- | -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| Level 1 | Super Admin    | Full platform access — billing, config, commission rates, all reports, all user management, all admin account management, DPA compliance oversight |
| Level 2 | Regional Admin | Ashanti region data only — live map, regional reports, provider verification and approval, regional user management                                |
| Level 3 | Ops Admin      | Manual job assignments, live map view, user suspensions, platform-wide announcements, provider online/offline status                               |
| Level 4 | Support Agent  | Dispute handling, refund initiation (up to threshold), read-only access to user data and booking history                                           |

---

### 8.2 Provider Verification Workflow

- Provider submits documents and background check consent during registration.
- Regional Admin or Super Admin receives a verification queue notification.
- Admin reviews all submitted documents within the dashboard.
- Admin approves or rejects the application with a mandatory reason note.
- Provider is notified of the outcome via push notification and WhatsApp.
- Approved providers gain full access to their provider dashboard.
- Rejected providers are shown the rejection reason and may resubmit corrected documents.

> **Fraud Protocol:** If fraudulent or doctored documents are discovered post-approval, the admin initiates an investigation workflow. Super Admin reviews evidence, decides on account suspension and potential earnings clawback, and can flag the case for legal action. No automatic clawback occurs without admin review.

---

### 8.3 Manual Job Assignment

- Triggered when zero artisan bids are received within 5 minutes on a service request.
- Job appears in the Ops Admin's manual assignment queue.
- Admin selects an available artisan from a filtered list and assigns them.
- Real-time lock applied: once an admin opens a job for assignment, it is greyed out for all other admins to prevent race conditions.
- Assigned artisan receives an in-app notification, SMS alert, and a phone call to confirm availability.
- If the assigned artisan declines, admin selects an alternative.

---

### 8.4 Live Map

- Available to Regional Admin, Ops Admin, and Super Admin.
- Displays all active rides and active artisan jobs as live GPS markers.
- Regional Admin view is scoped to Ashanti region only — enforced at API level.
- Clicking any marker shows full job/ride details and provider information.
- Used for real-time operational oversight and emergency response coordination.

---

### 8.5 User Management

- Suspend or ban any user (client or provider) with a mandatory reason note.
- Suspended provider accounts do not affect the same person's client account.
- Soft delete: deleted accounts are deactivated and data retained for 90 days before permanent purge. A 24-hour recovery window is available.
- Re-verification can be triggered for any provider based on complaints or rating drops.
- Rating threshold enforcement: below 3.5 stars triggers an automatic warning. Below 3.0 stars triggers automatic suspension pending admin review (minimum 15 completed jobs before thresholds apply).

---

### 8.6 Reporting & Analytics

- Super Admin: full platform revenue reports, commission earnings, user growth, provider performance, payment success rates.
- Regional Admin: Ashanti-scoped versions of all reports.
- All reports exportable as CSV or PDF.
- Dashboard shows real-time KPIs: active rides, active jobs, pending verifications, open disputes.
- Artisan supplement frequency is tracked per artisan profile and is visible in the admin reporting suite. Artisans with a high supplement rate relative to their completed jobs are flagged for pattern review.

---

### 8.7 Platform Configuration

- Super Admin can adjust platform commission rates (takes effect on new bookings only, not retroactively).
- Super Admin can set and adjust the platform-wide minimum artisan service radius.
- Super Admin can activate or deactivate surge pricing rules.
- Super Admin can set and adjust minimum bid amounts per artisan service category.
- Ops Admin can broadcast announcements to all users via push notification.
- Support Agent can initiate refunds up to a defined threshold — amounts above threshold require Ops Admin or Super Admin approval.

---

## 9. Safety & Security

### 9.1 Emergency Button

Accessible at all times during an active ride or artisan job. Two-step confirmation required: tap the emergency button, then tap Confirm on the next screen. On confirmation, the following actions are triggered simultaneously:

- GPS location is shared with the user's pre-registered emergency contact.
- Admin is alerted immediately with full ride/job details and live location.
- Ghana Police Service (191) is called automatically via the device.
- Live audio and video recording is triggered and uploaded to secure cloud storage.

> **Emergency Recording Storage:** All emergency recordings are stored on a secure, encrypted cloud server. Access is strictly limited to platform admin and law enforcement with a valid legal request. Recordings are retained for a minimum of 90 days.

#### 9.1.1 Provider Emergency Button

- The Provider App includes an identical emergency button for both driver and artisan views.
- Same two-step confirmation flow and same triggered actions (GPS sharing, admin alert, police call, recording).
- Artisans entering clients' homes face equivalent safety risk to clients — the emergency button must be available to both parties.
- Provider emergency activations are logged and treated with equal priority to client emergency activations.

---

### 9.2 Phone Number Masking

- Neither clients nor providers ever see each other's real phone numbers.
- All calls are routed through the platform's masked calling infrastructure.
- Masked numbers are active only for the duration of the active job/ride.

---

### 9.3 Location Sharing

- Clients can share a live tracking link with trusted contacts at any time during an active booking.
- Share links automatically expire when the ride/job is marked complete plus a 30-minute buffer.
- Multiple trusted contacts can be registered for emergency notifications.

---

### 9.4 Ratings Integrity — Blind Rating Window

- Both parties have 24 hours to submit a rating after job/ride completion.
- Ratings are revealed to both parties only after both have submitted, or after the 24-hour window closes — whichever comes first.
- If only one party submits a rating, it is applied after the window closes without waiting for the other.
- This prevents retaliatory ratings and encourages honest feedback.

---

### 9.5 Data Privacy & Ghana DPA Compliance

- The platform will register with the Ghana Data Protection Commission before pilot launch.
- A comprehensive privacy policy will be displayed and accepted during user registration (explicit consent flow).
- Users will be informed of what data is collected, how it is used, and their rights under the Ghana Data Protection Act.
- Personal data (GPS locations, payment details, identity documents) is encrypted at rest and in transit.
- Emergency recordings are treated as highly sensitive data with strict access controls.
- Users may request data deletion — subject to retention requirements for legal and dispute purposes.

---

### 9.6 Client Identity Verification for Artisan Jobs

- Unlike ride-hailing (where pickup is in a public location), artisan jobs require artisans to enter private residences.
- Ghana Card verification is optional but incentivised (e.g., verified clients shown as 'ID Verified' to artisans, artisans can choose to only accept jobs from verified clients, discounts, etc).

---

## 10. Notification Strategy

| Event                               | Channel                                   |
| ----------------------------------- | ----------------------------------------- |
| Ride/job request accepted           | Push notification                         |
| Driver/artisan en route             | Push notification                         |
| Driver/artisan arrived              | Push notification                         |
| Ride/job started                    | Push notification                         |
| Ride/job completed                  | Push notification + WhatsApp              |
| Payment received                    | Push notification + WhatsApp              |
| Payment receipt / invoice           | Email                                     |
| Weekly earnings summary (providers) | Email                                     |
| Bid received (artisan jobs)         | Push notification                         |
| Job assigned by admin               | Push notification + WhatsApp + Phone call |
| Account suspended/banned            | Push notification + WhatsApp + Email      |
| Verification approved/rejected      | Push notification + WhatsApp + Email      |
| Emergency alert (admin)             | Push notification + SMS                   |
| Promo code / offer                  | Push notification                         |
| USSD booking confirmed              | SMS                                       |
| USSD artisan assigned               | SMS                                       |
| USSD OTP                            | SMS                                       |
| Scheduled job reminder (T-24h)      | Push notification                         |
| Scheduled job reminder (T-2h)       | Push notification                         |
| Scheduled job no-show escalation    | Push notification + Admin alert           |
| Artisan welfare check               | Push notification                         |
| Provider emergency activation       | Push notification + SMS (to admin)        |
| Supplement request received         | Push notification (to client)             |
| Supplement approved/rejected        | Push notification (to artisan)            |

---

## 11. Localisation

### 11.1 Supported Languages

| Language | Status                           |
| -------- | -------------------------------- |
| English  | Full — all three apps at launch  |
| Twi      | Full — all three apps at launch  |
| Ga       | Phased — post-pilot via i18n CMS |
| Ewe      | Phased — post-pilot via i18n CMS |
| Dagbani  | Phased — post-pilot via i18n CMS |
| Hausa    | Phased — post-pilot via i18n CMS |
| Fante    | Phased — post-pilot via i18n CMS |

---

### 11.2 i18n Architecture

- All user-facing strings are managed via an i18n CMS layer.
- New languages and string updates can be deployed without a new app release.
- Language selection available in app settings — defaults to device language if supported.
- USSD menus support English and Twi at launch, language selected during registration.

---

## 12. Edge Case Policy Register

The following table documents all resolved edge case decisions agreed during the product scoping process. Items marked with ★ are additions from the v2.0 and v2.1 review.

| #    | Scenario                                                      | Resolution                                                                                                                                                                                          |
| ---- | ------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1    | Same phone creates second driver account                      | Blocked with clear error message explaining why                                                                                                                                                     |
| 2    | Suspended driver uses client app                              | Client account unaffected — suspension is provider-side only                                                                                                                                        |
| 3    | Fake verification docs discovered post-activation             | Admin investigates first, then decides on clawback                                                                                                                                                  |
| 4    | Banned client re-registers with new SIM                       | Ghana Card verification required to proceed                                                                                                                                                         |
| 5    | USSD zone outdated after app link                             | Zone confirmed or changed at every request — not assumed                                                                                                                                            |
| 6    | Driver reconnects at 1min 55sec of grace period               | Ride continues if reconnection within 2-minute window                                                                                                                                               |
| 7    | Mid-ride stop added outside Ashanti                           | Client warned; driver given option to decline the stop                                                                                                                                              |
| 8    | Surge activates after booking, before acceptance              | Surge applies to new requests only — existing booking fare locked                                                                                                                                   |
| 9    | Driver marks complete; client disputes drop-off               | Admin reviews GPS trail and timestamps to adjudicate                                                                                                                                                |
| 10   | Client adds major mid-ride detour                             | Driver may decline; ride continues to original destination                                                                                                                                          |
| 11   | Fractional fare (e.g. GHS 47.30)                              | Always rounded up to nearest whole Ghana Cedi                                                                                                                                                       |
| 12   | Client cancels after driver accepts                           | 3-minute free cancellation window; fee applies after                                                                                                                                                |
| 13   | Client never responds to 3 bids                               | Bids expire after 5–10 minutes; artisans notified                                                                                                                                                   |
| 14   | Job bigger than described on arrival                          | Artisan submits one supplement request before starting; admin mediates price disputes                                                                                                               |
| 15   | Artisan marks complete; job only 80% done                     | Binary — fully complete or not; no partial payments                                                                                                                                                 |
| 16   | Double-booking same artisan                                   | Solo: 1 job max; Multi-worker: up to 3 concurrent jobs                                                                                                                                              |
| 17   | Materials cost more than quoted                               | Artisan submits one supplement request before starting work; client approves in-app; only one supplement per job is permitted                                                                       |
| 18   | Admin assigns artisan who never bid                           | In-app notification + SMS + phone call to confirm                                                                                                                                                   |
| 19   | Artisan sets extremely small radius                           | Admin sets platform-wide minimum floor radius                                                                                                                                                       |
| 20   | Artisan cancels advance-scheduled job                         | Same 3-cancellation rule as on-demand jobs                                                                                                                                                          |
| 21   | Payment gateway down post-completion                          | Micro-escrow holds funds; retry queue every 30 mins; admin alerted                                                                                                                                  |
| 22   | Client MoMo insufficient post-completion                      | Job held; client given 24 hours to top up and pay                                                                                                                                                   |
| 23   | Tip bounces — provider wallet full                            | Tip held in platform wallet; retried automatically                                                                                                                                                  |
| 24   | Flutterwave charges transaction fees                          | Platform absorbs — built into 20% commission rate                                                                                                                                                   |
| 25   | Refund approved; provider already paid                        | Platform absorbs; claws back from provider's next payout                                                                                                                                            |
| 26   | Promo reduces fare below commission threshold                 | Commission calculated on pre-promo fare always                                                                                                                                                      |
| 27   | Emergency button pressed accidentally                         | Two-step confirmation prevents false alarms                                                                                                                                                         |
| 28   | Emergency recording storage                                   | Secure cloud; admin and law enforcement access only                                                                                                                                                 |
| 29   | Physical altercation protocol                                 | OPEN DECISION — pre-launch business development required                                                                                                                                            |
| 30   | Location share link expires mid-ride                          | Link tied to estimated duration + 30-minute buffer                                                                                                                                                  |
| 31   | USSD session times out mid-booking                            | Partial session saved 5 mins; resumes on redial                                                                                                                                                     |
| 32   | USSD confirmation SMS delayed by telco                        | Micro-escrow auto-releases after 2 hours if no dispute                                                                                                                                              |
| 33   | USSD user locks MoMo PIN during payment                       | Notify provider + flag job + give client 24 hours                                                                                                                                                   |
| 34   | USSD user dials from borrowed phone                           | OTP sent to registered number — must be received on registered SIM                                                                                                                                  |
| 35   | Power outage drops USSD session                               | Same number redial within 3 minutes offers session resume                                                                                                                                           |
| 36   | Two admins assign same artisan simultaneously                 | Real-time lock — job greys out once one admin opens it                                                                                                                                              |
| 37   | Regional admin accesses data outside Ashanti                  | Enforced at both API level and UI level                                                                                                                                                             |
| 38   | Super admin accidentally deletes user account                 | Soft delete — data retained 90 days before permanent purge                                                                                                                                          |
| 39   | Provider withdraws before dispute resolved                    | Only disputed job amount frozen; rest of wallet accessible                                                                                                                                          |
| 40   | New criminal info emerges post-verification                   | Re-verification triggered by complaint or rating drop threshold                                                                                                                                     |
| 41   | Driver intentionally goes offline mid-ride                    | Online toggle locked during active ride; force-close treated as disconnection with 2-min grace period                                                                                               |
| 42   | Artisan job stuck in 'in_progress' for 8+ hours               | Auto check-in notification at 8h; admin escalation at 24h; payout freeze at 48h                                                                                                                     |
| 43   | Artisan bids below category minimum                           | Bid rejected with error message; minimum set per category by Super Admin                                                                                                                            |
| 44 ★ | Artisan bids above GHS 5,000                                  | Bid flagged for admin review before shown to client                                                                                                                                                 |
| 45   | Zero artisans registered in requested category                | Client informed immediately; job created in 'queued' status for admin visibility                                                                                                                    |
| 46   | Scheduled artisan no-show                                     | T-24h confirmation, T-2h reminder, T+30min auto-escalation; counts as cancellation                                                                                                                  |
| 47   | Client cancels confirmed artisan job after 30 mins            | 20% of agreed price paid to artisan as compensation                                                                                                                                                 |
| 48   | Client does not confirm artisan job completion within 4 hours | Artisan can escalate to admin; admin may force-release payment                                                                                                                                      |
| 49   | Ride fare disputed due to inefficient route                   | Admin compares GPS trail vs optimal route; partial refund if >30% excess distance                                                                                                                   |
| 50   | Foreign currency card payment with high FX markup             | Platform absorbs FX cost within commission during pilot; post-pilot decision required                                                                                                               |
| 51   | Provider deactivates account with outstanding clawback        | Account deactivation blocked until clawback settled; under GHS 100 written off after 90 days inactive                                                                                               |
| 52   | Batch payout job fails at 18:00                               | Retries at 19:30, 20:00, 06:00; admin alerted; does not silently roll to next day                                                                                                                   |
| 53   | Retaliatory rating after poor experience                      | Blind 24-hour rating window; ratings revealed only after both submit or window closes                                                                                                               |
| 54   | Artisan unresponsive for 3+ hours after marking 'arrived'     | Automated welfare check notification; admin alerted if no response within 15 minutes                                                                                                                |
| 55   | Client identity for artisan home visits                       | OPEN DECISION — Ghana Card verification for artisan bookings under review                                                                                                                           |
| 56 ★ | Artisan submits multiple supplement requests on one job       | Only one supplement request permitted per job. Once submitted (approved or rejected), no further supplements can be raised. Artisan must proceed at original price or negotiate cancellation.       |
| 57 ★ | Artisan repeatedly underquotes to win bids then supplements   | Supplement frequency tracked per artisan profile. Artisans with abnormally high supplement rates relative to completed jobs are flagged for admin review. Pattern visible in admin reporting suite. |

---

## 13. Distribution & Pilot Strategy

### 13.1 App Distribution

- Client App: Apple App Store + Google Play Store.
- Provider App: Apple App Store + Google Play Store.
- Admin Dashboard: Web application — access via browser, no app store listing.

---

### 13.2 Pilot Strategy

- Open beta: any user in the Ashanti Region can sign up from day one.
- No invite codes or waitlist — maximise early adoption.
- Pilot duration: 3 months.
- Geographic scope: Ashanti Region only.
- Success metrics tracked weekly and reviewed against targets in Section 1.3.

---

### 13.3 Monetisation — Pilot

- Commission only: 20% of every completed ride and artisan job.
- No ads, boosted listings, or subscription tiers during the pilot.
- Post-pilot monetisation options (featured listings, subscriptions) flagged for review based on pilot data.

---

### 13.4 Compliance

- Ghana Data Protection Commission registration completed before pilot launch.
- Privacy policy, data consent flows, and terms of service integrated into registration for all user types.
- Legal review by a qualified Ghanaian tech lawyer recommended as a pre-launch requirement.
- Payment services compliance with Bank of Ghana regulations for mobile money and card processing.

---

_Document Version: 2.1 | Additions from v2.1: Materials estimation and bidding flow clarified (Section 4.5.2), supplement request rules formalised — one supplement per job, supplement pattern tracking added (Section 4.5.3), Edge Cases #56 and #57 added, supplement notification events added to Section 10, supplement tracking added to Admin Reporting (Section 8.6)._
