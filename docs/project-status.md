# MyShop Mobile — Project Status

> Last updated: **2026-04-12**
> Backend: `https://myshop-api-2hy2.onrender.com/v1/` (healthy)

---

## Overall Progress

| Area | Status | Notes |
|------|--------|-------|
| Auth (Provider App) | **Done** | Real backend wired, token refresh working |
| Auth (Client App) | Not started | Shares api_client package, needs UI + wiring |
| Driver Home | **API wired** | Real name/avatar from profile, earnings from API (fallback to zeros), empty states for trips & ride requests |
| Artisan Home | **API wired** | Real name/avatar/categories from profile, earnings from API, empty states for jobs & offers |
| Earnings Dashboard | **API wired** | Real today/week earnings, commission computed, payouts show empty state |
| Earnings Reports | Empty states | Summary/chart/breakdown show zeros — no detailed endpoint yet |
| Trips History | Empty state | "No trips yet" — no trip history endpoint |
| Account Settings | **API wired** | Real name/phone/email/avatar, KYC/verification/police status from profile, earnings in performance card |
| Vehicle Info | **API wired** | Real make/model/year/plate/color from driver profile |
| Payout Methods | **Partial API** | Real payout method from profile if set, empty states for balance & history |
| Profile / Account | **Partial API** | Identity card + compliance wired, edit/documents screens still no API |
| Rides (Client) | Not started | Screens are TODO stubs |
| Rides (Driver) | UI done, no mock | Mock ride request removed, empty until WebSocket wired |
| Jobs (Client) | Not started | Screens are TODO stubs |
| Jobs (Artisan) | UI scaffolding | Job/bid screens exist, no data |
| Chat | UI scaffolding | Static mock conversations, no messaging |
| Notifications | Not started | FCM initialized but no token registration |
| Payments | Not started | Flutterwave SDK added, unused |
| Location Sync | Partial | GPS streaming works, not sent to backend |
| WebSocket | Not started | No Socket.IO implementation |
| Verification/KYC | UI only | Document upload screens exist, no S3 calls |

---

## Backend API Integration

### Integrated (12 of 67 endpoints)

| Endpoint | Method | Used By |
|----------|--------|---------|
| `/auth/register` | POST | Provider App |
| `/auth/login/driver` | POST | Provider App |
| `/auth/login/artisan` | POST | Provider App |
| `/auth/verify-otp` | POST | Provider App |
| `/auth/refresh` | POST | Provider App (auto via interceptor) |
| `/auth/check-phone` | POST | Provider App |
| `/auth/recover` | POST | api_client (service method exists, no UI) |
| `/users/me` | GET | Provider App (bootstrap + post-login + all screens) |
| `/users/me` | PUT | Provider App (edit profile screen — name & email) |
| `/payments/earnings` | GET | Provider App (home + earnings dashboard + account settings) |
| `/verification/documents` | POST | Provider App (profile photo + document upload via presigned S3 URL) |
| `/verification/status` | GET | Provider App (documents verification screen — doc statuses) |

### Not Yet Integrated (57 endpoints + 4 WebSocket channels)

#### Shared Endpoints (13 remaining)
- `GET /users/me/saved-locations` — client saved places
- `POST /users/me/saved-locations`
- `PUT /users/me/saved-locations/:id`
- `DELETE /users/me/saved-locations/:id`
- `GET /users/me/emergency-contacts`
- `POST /users/me/emergency-contacts`
- `PUT /users/me/emergency-contacts/:id`
- `DELETE /users/me/emergency-contacts/:id`
- `GET /notifications` — notification history
- `PATCH /notifications/:id/read`
- `POST /notifications/register-device` — FCM token
- `GET /chat/:bookingType/:bookingId/messages`
- `POST /chat/:bookingType/:bookingId/messages`
- `PATCH /chat/messages/:messageId/read`
- `POST /communication/call` — masked calls
- `POST /emergency` — SOS trigger
- `POST /emergency/:id/recording`
- `POST /ratings`
- `GET /config/:key`
- `GET /surge/current`

#### Client App Endpoints (18 remaining)
- `POST /rides/estimate` — fare estimate
- `POST /rides` — book ride
- `GET /rides/:id`
- `PATCH /rides/:id/cancel`
- `PATCH /rides/:id/stops` — add stop
- `GET /rides/:id/share`
- `POST /rides/:id/dispute`
- `GET /rides/track/:shareToken` — public tracking
- `POST /jobs` — create artisan job
- `GET /jobs/:id`
- `GET /jobs/:id/bids`
- `PATCH /jobs/:id/select-bid`
- `PATCH /jobs/:id/supplement/respond`
- `PATCH /jobs/:id/confirm`
- `PATCH /jobs/:id/cancel`
- `POST /jobs/:id/dispute`
- `POST /payments/initiate`
- `GET /payments/:id/status`
- `POST /payments/:id/tip`
- `POST /payments/:id/retry`
- `POST /payments/:id/dispute`
- `GET /loyalty/transactions`
- `POST /loyalty/redeem`
- `GET /referrals/my-code`
- `GET /referrals/history`
- `POST /promos/validate`

#### Provider App Endpoints (13 remaining)
- `POST /location/update` — driver GPS broadcast
- `PATCH /rides/:id/status` — advance ride state
- `PATCH /rides/:id/cancel` (driver)
- `PATCH /rides/:id/stops/:stopId/decline`
- `PATCH /rides/:id/stops/:stopId/arrived`
- `PATCH /rides/:id/stops/:stopId/departed`
- `POST /jobs/:id/bids` — artisan submit bid
- `PATCH /jobs/:id/status` — advance job state
- `POST /jobs/:id/supplement`
- `PATCH /jobs/:id/confirm-schedule`
- `POST /jobs/:id/escalate`
- `PATCH /jobs/:id/welfare-check/respond`
- `PATCH /jobs/:id/cancel` (artisan)
- `GET /payments/payouts` — payout history

#### WebSocket Channels (4 remaining)
- `ws:///v1/location/track` — driver GPS broadcast
- `ws:///v1/rides/:id/live` — live ride tracking
- `ws:///v1/jobs/:id/live` — live job tracking
- `ws:///v1/chat/:bookingId` — real-time chat

---

## Infrastructure Status

| Component | Status | Details |
|-----------|--------|---------|
| Dio HTTP client | **Done** | Base URL, timeouts, JSON headers configured |
| Auth interceptor | **Done** | Bearer token injection, auto-refresh on 401 |
| Logging interceptor | **Done** | Dev-only request/response logger |
| Token storage | **Done** | Flutter Secure Storage (Keychain / EncryptedSharedPrefs) |
| Response envelope parser | **Done** | `ApiResponse<T>`, `ApiError`, `PaginationMeta` |
| Error exception hierarchy | **Done** | `ApiException`, `UnauthorizedException`, `NetworkException`, etc. |
| Environment config | **Done** | `--dart-define=API_BASE_URL` support |
| EarningsService | **Done** | `GET /payments/earnings` with fallback to empty |
| VerificationService | **Done** | `POST /verification/documents` + S3 upload + `GET /verification/status` |
| currentUserProvider | **Done** | Convenience provider extracting AuthUser from auth state |
| profileCompletionProvider | **Done** | Computes real % from profile fields (name, photo, KYC, vehicle, etc.) |
| documentUploadProvider | **Done** | Manages upload state per document type with loading/success tracking |
| WebSocket client | Not started | Socket.IO dependency added, no implementation |
| Firebase (Provider) | Partial | `firebase_core` initialized, FCM not wired |
| Firebase (Client) | Not started | TODO in main.dart |
| Google Maps SDK | **Done** | Integrated in driver home screen |

---

## App Screens Status

### Provider App (28 screens)

| Screen | UI | Data | API |
|--------|----|------|-----|
| Splash | Done | N/A | N/A |
| Onboarding | Done | N/A | N/A |
| Role Picker | Done | N/A | N/A |
| Phone Input | Done | N/A | Real |
| OTP Verification | Done | N/A | Real |
| Driver Registration | Done | Local draft | N/A |
| Artisan Registration | Done | Local draft | N/A |
| Driver Home (map) | Done | Real name/avatar, API earnings, empty trips | **Real + empty states** |
| Artisan Home | Done | Real name/avatar/categories, API earnings, empty jobs | **Real + empty states** |
| Ride Request (incoming) | Done | No mock ride (null) | Waiting for WebSocket |
| Active Ride | Done | Receives ride via provider | No API calls yet |
| Ride Complete | Done | Mock TripSummary | None |
| Job Request | Done | Mock | None |
| Bid Submission | Done | Mock | None |
| Active Job | Done | Mock | None |
| Driver Earnings | Done | Real today/week from API, empty payouts | **Real + empty states** |
| Artisan Earnings | Done | Mock chart | None |
| Earnings Reports | Done | Zeros + empty states | **Empty states** |
| Trips History | Done | Empty state | **Empty state** |
| Messages List | Done | Mock conversations | None |
| Chat | Partial | Mock | None |
| Account Settings | Done | Real profile, real KYC/verification, real earnings | **Real + empty states** |
| Edit Profile | Done | Real data + editable name/email + photo upload | **Real (PUT /users/me + S3 upload)** |
| Vehicle Info | Done | Real vehicle data + real completion % | **Real** |
| Business Info | Done | N/A | None |
| Documents / KYC | Done | Real doc statuses + upload flow + real completion % | **Real (presigned S3 + status)** |
| Payout Methods | Done | Real method from profile, empty history | **Partial real** |
| Notification Settings | Done | N/A | None |

### Client App (34 screens)

| Screen | Status |
|--------|--------|
| All screens | ~90% are TODO stubs. Auth flow shares api_client but has no UI wiring. |

---

## What's Next (Recommended Priority)

### Priority 1 — Complete Provider App Core Loop
1. ~~**Home screens API wiring**~~ ✅ Done — real user data + earnings + empty states
2. ~~**Earnings dashboard**~~ ✅ Done — real today/week earnings from API
3. ~~**Profile screens**~~ ✅ Done — real user data in account settings, vehicle info, payouts
4. **Driver location broadcast** — Wire `POST /location/update` to send GPS every 5s when online
5. ~~**Verification/documents**~~ ✅ Done — presigned S3 upload + status endpoint + real completion %
6. **Payout history** — Wire `GET /payments/payouts` to replace empty state

### Priority 2 — Real-Time Infrastructure
7. **WebSocket client** — Implement Socket.IO for ride/job tracking and chat
8. **FCM integration** — Register device token via `POST /notifications/register-device`
9. **Notification handler** — Route push notifications to correct screens

### Priority 3 — Ride Flow (Driver Side)
10. **Ride request handling** — Listen for incoming requests via WebSocket
11. **Ride status management** — Wire `PATCH /rides/:id/status` for state transitions
12. **Trip history** — Replace empty state with real trip list endpoint

### Priority 4 — Job Flow (Artisan Side)
13. **Job feed** — Wire incoming job requests
14. **Bid submission** — Wire `POST /jobs/:id/bids`
15. **Job status management** — Wire `PATCH /jobs/:id/status`

### Priority 5 — Client App
16. **Auth UI** — Build login/register screens using shared api_client
17. **Ride booking flow** — Fare estimate → book → track → complete
18. **Services/jobs flow** — Create job → review bids → track → confirm

### Priority 6 — Payments & Polish
19. **Payment integration** — Flutterwave/Paystack for MoMo + card
20. **Chat** — Real-time messaging via WebSocket
21. **Loyalty/referrals** — Client-side features
22. **Emergency/safety** — SOS trigger, recording upload
