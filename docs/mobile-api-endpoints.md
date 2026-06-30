# Mobile App ↔ Backend Integration Contract

> **For Claude Code**: Use this file as the source of truth when integrating the Flutter mobile apps with the NestJS backend. Every endpoint lists its exact path, auth requirement, required/optional fields with types, and expected response shape. All endpoints are prefixed with `/v1`. All money values are in **pesewas** (integer). All timestamps are ISO 8601 UTC.

---

## Enums

```dart
// Registration
enum RegistrationType { client, driver, artisan }

// Payment
enum PaymentMethod { momo_mtn, momo_telecel, momo_airteltigo, card, cash }

// Booking
enum BookingType { ride, artisan_job }

// Location
enum LocationType { home, work, favourite }

// Provider
enum OnlineStatus { online, offline }
enum ShopCapacity { solo, multi }
enum PayoutPreference { instant, batch }

// Device
enum DevicePlatform { ios, android }

// Language
enum LanguagePref { en, tw }

// Ride status flow
enum RideStatus { requested, driver_en_route, arrived_at_pickup, in_progress, completed, cancelled }

// Job status flow
enum JobStatus { open, queued, confirmed, artisan_en_route, arrived, in_progress, artisan_marked_complete, completed, cancelled }

// Verification
enum VerificationStatus { pending, approved, rejected, suspended }
enum KycStatus { not_started, pending, verified, failed }
enum PoliceCheckStatus { not_started, pending, clear, flagged, disqualified }
enum DocumentType { drivers_licence, vehicle_registration, roadworthiness_certificate, national_id, profile_photo, trade_certificate, business_registration, portfolio_photo, ghana_card }
enum MimeType { image_jpeg, image_png, application_pdf } // "image/jpeg", "image/png", "application/pdf"

// Promo
enum PromoType { percentage_discount, fixed_discount, free_ride, bonus_points }
```

---

## Response Envelope

Every API response follows this structure:

```json
{
  "success": true,
  "data": { ... },
  "error": null,
  "meta": { "page": 1, "limit": 20, "total": 100, "totalPages": 5 }
}
```

On error:
```json
{
  "success": false,
  "data": null,
  "error": { "code": "ERROR_CODE", "message": "Human-readable message", "details": {} }
}
```

---

# SHARED ENDPOINTS (Both Client & Provider Apps)

---

## AUTH

### POST /auth/register
> Register a new account. Sends OTP to phone. **Public endpoint. Rate limit: 20/60s.**

**Required fields:**
- `phone` (string) — Ghana phone number, e.g. `"+233241234567"`
- `fullName` (string) — User's full name
- `type` (RegistrationType) — `"client"`, `"driver"`, or `"artisan"`
- `privacyPolicyAccepted` (boolean) — Must be `true`. Ghana DPA consent requirement.

**Optional fields:**
- `email` (string) — Valid email. Must be unique across all users.
- `referralCode` (string) — Format: `MYSHOP-XXXXXX` (6 uppercase alphanumeric). Only for clients.

**Conditionally required (artisan only):**
- `categories` (string[]) — Array of category UUIDs. Min 1 item. Required when `type = "artisan"`.
- `shopCapacity` (string) — `"solo"` or `"multi"`. Optional, defaults to `"solo"`.
- `maxConcurrentJobs` (int) — Range: 2-3. Only relevant when `shopCapacity = "multi"`.

**Response:**
```json
{ "message": "OTP sent", "phone": "+233241234567" }
```

**Error codes:** `CLIENT_ACCOUNT_EXISTS` (409), `DRIVER_ACCOUNT_EXISTS` (409), `ARTISAN_ACCOUNT_EXISTS` (409), `EMAIL_ALREADY_EXISTS` (409), `CATEGORIES_REQUIRED` (400), `INVALID_CATEGORY` (400)

> **Note:** Register is for **new accounts only**. Existing users must use the role-specific login endpoints below.

---

### POST /auth/login/client
> Client login — sends OTP to a registered client phone number. **Public endpoint. Rate limit: 20/60s.**

**Required fields:**
- `phone` (string) — Ghana phone number, e.g. `"+233241234567"`

**Response:**
```json
{ "message": "OTP sent", "phone": "+233241234567" }
```

**Error codes:** `ACCOUNT_NOT_FOUND` (404), `CLIENT_PROFILE_NOT_FOUND` (404)

> **Client App only.** Use this endpoint on the login screen. After OTP is sent, verify with `POST /auth/verify-otp`.

---

### POST /auth/login/driver
> Driver login — sends OTP to a registered driver phone number. **Public endpoint. Rate limit: 20/60s.**

**Required fields:**
- `phone` (string) — Ghana phone number, e.g. `"+233241234567"`

**Response:**
```json
{ "message": "OTP sent", "phone": "+233241234567" }
```

**Error codes:** `ACCOUNT_NOT_FOUND` (404), `DRIVER_PROFILE_NOT_FOUND` (404)

> **Provider App only.** Use this endpoint on the driver login screen.

---

### POST /auth/login/artisan
> Artisan login — sends OTP to a registered artisan phone number. **Public endpoint. Rate limit: 20/60s.**

**Required fields:**
- `phone` (string) — Ghana phone number, e.g. `"+233241234567"`

**Response:**
```json
{ "message": "OTP sent", "phone": "+233241234567" }
```

**Error codes:** `ACCOUNT_NOT_FOUND` (404), `ARTISAN_PROFILE_NOT_FOUND` (404)

> **Provider App only.** Use this endpoint on the artisan login screen.

---

### POST /auth/verify-otp
> Verify OTP and receive JWT tokens. Shared by both register and login flows. **Public endpoint. Rate limit: 20/60s.**

**Required fields:**
- `phone` (string) — Same phone used in register or login
- `otp` (string) — Exactly 6 digits, e.g. `"123456"`

**Response:**
```json
{
  "accessToken": "eyJ...",
  "refreshToken": "eyJ..."
}
```

**Token expiry (role-based):**
- Access token: **15 minutes** (all roles)
- Refresh token (client): **365 days** — persistent session, stays logged in until app data is cleared
- Refresh token (driver/artisan): **7 days** — shorter session + auto-logout after **6 hours of inactivity**

Token payload: `{ sub: userId, role: "client"|"driver"|"artisan", phone: "+233..." }`

**Error codes:** `OTP_EXPIRED` (401), `INVALID_OTP` (401), `ACCOUNT_NOT_FOUND` (401 — login intent, user deleted), `ACCOUNT_EXISTS` (409 — register intent, profile already exists)

---

### POST /auth/refresh
> Get a new access token. **Public endpoint.**

**Required fields:**
- `refreshToken` (string) — Valid refresh token

**Response:**
```json
{ "accessToken": "eyJ..." }
```

**Error codes:** `TOKEN_EXPIRED` (401), `INVALID_TOKEN` (401), `USER_NOT_FOUND` (401), `SESSION_INACTIVE` (401 — provider only, returned after 6h of no API activity)

---

### POST /auth/recover
> Recover a soft-deleted account within 24h. **Public endpoint.**

**Required fields:**
- `phone` (string) — Phone of deleted account

**Response:**
```json
{ "message": "Account successfully recovered" }
```

**Error codes:** `ACCOUNT_NOT_FOUND` (404), `RECOVERY_EXPIRED` (410)

---

## USER PROFILE

### GET /users/me
> Get current user profile with all linked role profiles. **Auth: Bearer.**

**No request body.**

**Response:**
```json
{
  "id": "uuid",
  "phone": "+233241234567",
  "email": "user@example.com",
  "fullName": "Kofi Mensah",
  "languagePref": "en",
  "status": "active",
  "privacyPolicyAcceptedAt": "2024-01-15T10:30:00Z",
  "deletedAt": null,
  "recoveryDeadline": null,
  "createdAt": "...",
  "updatedAt": "...",
  "client": {
    "id": "uuid",
    "loyaltyPointsBalance": 0,
    "referralCode": "MYSHOP-ABC123",
    "preferredPaymentMethod": null,
    "ghanaCardVerified": false
  },
  "driver": {
    "id": "uuid",
    "verificationStatus": "pending",
    "kycStatus": "not_started",
    "policeCheckStatus": "not_started",
    "onlineStatus": "offline",
    "serviceRadiusKm": 5.0,
    "payoutPreference": "instant",
    "licenceNumber": null,
    "licenceExpiry": null
  },
  "artisan": {
    "id": "uuid",
    "verificationStatus": "pending",
    "kycStatus": "not_started",
    "policeCheckStatus": "not_started",
    "onlineStatus": "offline",
    "serviceRadiusKm": 5.0,
    "shopCapacity": "solo",
    "maxConcurrentJobs": 1,
    "payoutPreference": "instant",
    "completedJobsCount": 0,
    "cancellationCount30d": 0,
    "serviceCategories": [
      {
        "categoryId": "uuid",
        "category": {
          "id": "uuid",
          "name": "Plumbing",
          "slug": "plumbing",
          "minBidPesewas": 3000,
          "isActive": true
        }
      }
    ]
  }
}
```
> `client`, `driver`, `artisan` are `null` if the user doesn't have that role.

---

### PUT /users/me
> Update profile fields. **Auth: Bearer.**

**Optional fields (send only what changed):**
- `fullName` (string)
- `email` (string) — Must be unique
- `languagePref` (LanguagePref) — `"en"` or `"tw"`

**Response:** Same shape as `GET /users/me`.

**Error codes:** `EMAIL_ALREADY_EXISTS` (409)

---

### PUT /users/me/driver
> Update driver-specific profile fields (vehicle info, licence, payout). **Auth: Bearer (driver only).**
>
> **STATUS: PENDING BACKEND IMPLEMENTATION** — Mobile app is wired and ready. Backend needs to add this endpoint.

**Optional fields (send only what changed):**
- `vehicleMake` (string) — e.g. "Toyota"
- `vehicleModel` (string) — e.g. "Corolla"
- `vehicleYear` (string) — e.g. "2019"
- `vehiclePlate` (string) — e.g. "GR-1234-22"
- `vehicleColor` (string) — e.g. "White"
- `licenceNumber` (string) — Driver's licence number
- `licenceExpiry` (string) — ISO 8601 date
- `serviceRadiusKm` (number) — Range: 1.0 to 50.0
- `payoutPreference` (PayoutPreference) — `"instant"` or `"batch"`
- `payoutMethod` (string) — e.g. `"momo_mtn"`
- `payoutAccountNumber` (string) — MoMo number or bank account

**Response:** Same shape as `GET /users/me`.

**Error codes:** `DRIVER_PROFILE_REQUIRED` (403)

---

### DELETE /users/me
> Soft-delete account. 24h recovery window, purged after 90 days. **Auth: Bearer.**

**No request body.**

**Response:**
```json
{
  "message": "Account deactivated. You have 24 hours to recover it.",
  "recoveryDeadline": "2024-01-16T10:30:00Z"
}
```

**Error codes:** `CLAWBACK_BALANCE_OUTSTANDING` (400)

---

## SAVED LOCATIONS (Client only)

### GET /users/me/saved-locations
> List all saved locations, ordered by most recently used. **Auth: Bearer.**

**No request body.**

**Response:**
```json
[
  {
    "id": "uuid",
    "label": "Home",
    "locationType": "home",
    "latitude": 6.6885,
    "longitude": -1.6244,
    "addressText": "15 Independence Ave, Kumasi",
    "lastUsedAt": "2024-01-20T14:00:00Z",
    "createdAt": "..."
  }
]
```

**Error codes:** `CLIENT_PROFILE_REQUIRED` (403)

---

### POST /users/me/saved-locations
> Save a new location. **Auth: Bearer.**

**Required fields:**
- `label` (string) — e.g. "Home", "Auntie's Place"
- `locationType` (LocationType) — `"home"`, `"work"`, or `"favourite"`
- `latitude` (number) — Range: -90 to 90
- `longitude` (number) — Range: -180 to 180

**Optional fields:**
- `addressText` (string) — Human-readable address

**Response (201):** Created location object (same shape as list items above).

---

### PUT /users/me/saved-locations/:id
> Update a saved location. **Auth: Bearer.**

**Optional fields (send only what changed):**
- `label` (string)
- `latitude` (number) — Range: -90 to 90
- `longitude` (number) — Range: -180 to 180
- `addressText` (string)

**Response:** Updated location object.

**Error codes:** `SAVED_LOCATION_NOT_FOUND` (404)

---

### DELETE /users/me/saved-locations/:id
> Delete a saved location. **Auth: Bearer.**

**No request body. Response: 204 No Content.**

**Error codes:** `SAVED_LOCATION_NOT_FOUND` (404)

---

## EMERGENCY CONTACTS

### GET /users/me/emergency-contacts
> List emergency contacts, primary first. **Auth: Bearer.**

**No request body.**

**Response:**
```json
[
  {
    "id": "uuid",
    "name": "Kofi Mensah",
    "phone": "+233241234567",
    "relationship": "Brother",
    "isPrimary": true,
    "createdAt": "..."
  }
]
```

---

### POST /users/me/emergency-contacts
> Add emergency contact. **Auth: Bearer.**

**Required fields:**
- `name` (string) — Contact's full name
- `phone` (string) — Contact's phone number

**Optional fields:**
- `relationship` (string) — e.g. "Brother", "Wife"
- `isPrimary` (boolean) — Default: false. Setting `true` auto-unsets existing primary.

**Response (201):** Created contact object.

---

### PUT /users/me/emergency-contacts/:id
> Update emergency contact. **Auth: Bearer.**

**Optional fields (send only what changed):**
- `name` (string)
- `phone` (string)
- `relationship` (string)
- `isPrimary` (boolean)

**Response:** Updated contact object.

**Error codes:** `EMERGENCY_CONTACT_NOT_FOUND` (404)

---

### DELETE /users/me/emergency-contacts/:id
> Delete emergency contact. **Auth: Bearer.**

**No request body. Response: 204 No Content.**

**Error codes:** `EMERGENCY_CONTACT_NOT_FOUND` (404)

---

## NOTIFICATIONS

### GET /notifications
> Get notification history, paginated. **Auth: Bearer.**

**Optional query params:**
- `page` (int) — Default: 1
- `limit` (int) — Default: 20, max: 100

**Response:** Paginated list with `meta: { page, limit, total, totalPages }`.

---

### PATCH /notifications/:id/read
> Mark a single notification as read. **Auth: Bearer.**

**No request body.**

**Response:** Updated notification object.

**Error codes:** `NOTIFICATION_NOT_FOUND` (404)

---

### POST /notifications/register-device
> Register or refresh FCM push token. Call on every app launch. **Auth: Bearer.**

**Required fields:**
- `fcmToken` (string) — FCM token, max 4096 chars
- `platform` (DevicePlatform) — `"ios"` or `"android"`

**Response:** Device registered confirmation.

---

## COMMUNICATION

### GET /chat/:bookingType/:bookingId/messages
> Get chat history for a ride or job. **Auth: Bearer.**

**Path params:**
- `bookingType` (string) — `"ride"` or `"artisan_job"`
- `bookingId` (string) — UUID

**No request body.**

**Response:** Array of message objects in chronological order.

**Error codes:** `NOT_A_PARTICIPANT` (403), `BOOKING_NOT_FOUND` (404)

---

### POST /chat/:bookingType/:bookingId/messages
> Send a chat message (REST fallback when WebSocket unavailable). **Auth: Bearer.**

**Path params:** Same as GET above.

**Required fields:**
- `message` (string) — 1 to 2000 characters

**Response (201):** Created message object.

**Error codes:** `NOT_A_PARTICIPANT` (403), `BOOKING_NOT_FOUND` (404), `CHAT_CHANNEL_CLOSED` (410)

---

### PATCH /chat/messages/:messageId/read
> Mark a chat message as read. **Auth: Bearer.**

**No request body.**

**Response:** Read receipt recorded.

**Error codes:** `CANNOT_READ_OWN_MESSAGE` (403), `MESSAGE_NOT_FOUND` (404)

---

### POST /communication/call
> Initiate a masked phone call. Neither party sees the other's real number. **Auth: Bearer.**

**Required fields:**
- `bookingType` (string) — `"ride"` or `"artisan_job"`
- `bookingId` (string) — UUID

**Response (201):**
```json
{
  "maskedCallId": "uuid",
  "maskedNumber": "+233...",
  "sessionId": "..."
}
```

**Error codes:** `NOT_A_PARTICIPANT` (403), `BOOKING_NOT_FOUND` (404), `BOOKING_COMPLETED` (410)

---

## SAFETY

### POST /emergency
> Trigger emergency. Shares GPS with contacts, alerts admin, auto-calls 191. **Auth: Bearer.**

**Required fields:**
- `bookingType` (string) — `"ride"` or `"job"`
- `bookingId` (string) — UUID
- `latitude` (number) — -90 to 90
- `longitude` (number) — -180 to 180

**Response:**
```json
{
  "initiatePoliceCall": true,
  "startRecording": true
}
```
> Mobile app should: (1) dial 191 if `initiatePoliceCall` is true, (2) start audio/video recording if `startRecording` is true.

---

### POST /emergency/:id/recording
> Get presigned S3 URL to upload emergency recording. **Auth: Bearer.**

**No request body.**

**Response:**
```json
{ "uploadUrl": "https://s3...presigned..." }
```
> Upload via HTTP PUT to `uploadUrl`. Expires in 30 minutes.

**Error codes:** `NOT_EMERGENCY_OWNER` (403), `EMERGENCY_NOT_FOUND` (404)

---

## RATINGS

### POST /ratings
> Submit a rating for a completed ride/job. 24h blind window — ratings revealed to both parties only after both have rated or 24h passes. **Auth: Bearer.**

**Required fields:**
- `bookingType` (string) — `"ride"` or `"artisan_job"`
- `bookingId` (string) — UUID
- `stars` (int) — 1 to 5

**Optional fields:**
- `comment` (string) — Max 1000 chars

**Response (201):**
```json
{ "revealed": false }
```
> `revealed: true` means both parties have now rated and can see each other's ratings.

**Error codes:** `ALREADY_RATED` (409), `RATING_WINDOW_CLOSED` (410), `BOOKING_NOT_COMPLETED` (410)

---

## PLATFORM CONFIG

### GET /config/:key
> Get a single runtime config value. **Public endpoint (no auth).**

**No request body.**

**Response:**
```json
{ "key": "MIN_BID_PLUMBING", "value": 3000 }
```

**Error codes:** `CONFIG_KEY_NOT_FOUND` (404)

---

## SURGE PRICING

### GET /surge/current
> Get current surge multiplier. **Public endpoint (no auth).**

**No request body.**

**Response:**
```json
{ "multiplier": 1.5 }
```
> Returns `1.0` when no surge is active. Multiply ride fare estimate by this value.

---

---

# CLIENT APP ENDPOINTS

---

## RIDE-HAILING

### POST /rides/estimate
> Get fare estimate before booking. **Auth: Bearer.**

**Required fields:**
- `pickupLat` (number) — -90 to 90
- `pickupLng` (number) — -180 to 180
- `dropoffLat` (number) — -90 to 90
- `dropoffLng` (number) — -180 to 180

**Optional fields:**
- `stops` (array of objects) — Intermediate stops. Each object: `{ lat: number, lng: number }`

**Response:**
```json
{
  "distanceKm": 12.4,
  "durationMins": 25,
  "surgeMultiplier": 1.0,
  "categories": [
    {
      "slug": "regular",
      "name": "Regular",
      "description": "Everyday cars at the best price",
      "capacityPersons": 4,
      "estimatedFarePesewas": 1500,
      "pickupEtaMins": 5,
      "driversAvailable": true
    },
    {
      "slug": "comfort",
      "name": "Comfort",
      "description": "Newer cars with extra space",
      "capacityPersons": 4,
      "estimatedFarePesewas": 2100,
      "pickupEtaMins": 8,
      "driversAvailable": false
    }
  ],
  "surgeReason": "high_demand",
  "surgeZoneName": "Adum"
}
```

`surgeReason` and `surgeZoneName` are optional. Mobile only requires
`surgeMultiplier`; values above `1.05` show the high-demand banner.

**Error codes:** `OUTSIDE_PILOT_REGION` (400), `ROUTE_NOT_FOUND` (400), `MAPS_API_ERROR` (400)

---

### POST /rides
> Create a ride booking. Triggers driver matching and broadcast. **Auth: Bearer (client only).**

**Required fields:**
- `pickupLat` (number) — -90 to 90
- `pickupLng` (number) — -180 to 180
- `dropoffLat` (number) — -90 to 90
- `dropoffLng` (number) — -180 to 180
- `paymentMethod` (PaymentMethod) — `"momo_mtn"`, `"momo_telecel"`, `"momo_airteltigo"`, `"card"`, or `"cash"`

**Optional fields:**
- `pickupAddress` (string) — Human-readable pickup address
- `dropoffAddress` (string) — Human-readable dropoff address
- `rideCategory` (string) — Category slug selected from `/rides/estimate`
- `promoCode` (string) — Promo code to apply

**Response (201):**
```json
{
  "rideId": "uuid",
  "status": "requested",
  "estimatedFarePesewas": 1500,
  "prePromoFarePesewas": 1500,
  "discountPesewas": 0,
  "commissionPesewas": 300,
  "surgeMultiplier": 1.0,
  "distanceKm": 12.4,
  "durationMins": 25,
  "pickupEtaMins": 5,
  "shareToken": "abc123",
  "driversNotified": 3
}
```

**Error codes:** `NO_DRIVERS_AVAILABLE` (400), `INVALID_PROMO_CODE` (400), `PROMO_CODE_EXHAUSTED` (400), `OUTSIDE_PILOT_REGION` (400), `CLIENT_PROFILE_REQUIRED` (403)

---

### GET /rides/:id
> Get full ride details with live status. **Auth: Bearer (ride client or assigned driver only).**

**No request body.**

**Response:** Full ride entity — status, driver info, vehicle, pickup/dropoff, stops, fare, GPS trail, all timestamps.

**Error codes:** `NOT_YOUR_RIDE` (403), `RIDE_NOT_FOUND` (404)

---

### PATCH /rides/:id/cancel
> Cancel a ride. Free within 3 minutes of driver acceptance, fee after. **Auth: Bearer.**

**Required fields:**
- `reason` (string) — 1 to 500 characters

**Response:**
```json
{
  "status": "cancelled",
  "cancellationFeePesewas": 0,
  "driverSuspended": false
}
```

**Error codes:** `RIDE_NOT_CANCELLABLE` (400), `NOT_YOUR_RIDE` (403), `RIDE_NOT_FOUND` (404)

---

### PATCH /rides/:id/stops
> Add a stop to an active ride. Driver may decline. **Auth: Bearer (client only).**

**Required fields:**
- `latitude` (number) — -90 to 90
- `longitude` (number) — -180 to 180

**Optional fields:**
- `addressText` (string)

**Response:**
```json
{
  "stopId": "uuid",
  "newFarePesewas": 1800,
  "outsidePilotRegion": false
}
```

**Error codes:** `RIDE_NOT_ACTIVE` (400), `NOT_YOUR_RIDE` (403), `RIDE_NOT_FOUND` (404)

---

### GET /rides/:id/share
> Get a shareable tracking link. Active for ride duration + 30 min buffer. **Auth: Bearer (client only).**

**No request body.**

**Response:**
```json
{
  "shareUrl": "https://app.myshop.com.gh/track/abc123",
  "shareToken": "abc123",
  "expiresAt": "2024-01-15T12:00:00Z"
}
```

---

### POST /rides/:id/dispute
> Dispute ride fare within 2 hours of completion. **Auth: Bearer (client only).**

**Required fields:**
- `reason` (string) — 10 to 500 characters

**Optional fields:**
- `details` (string) — Max 2000 characters

**Response (201):**
```json
{
  "disputeId": "uuid",
  "status": "open",
  "amountFrozenPesewas": 1500
}
```

**Error codes:** `DISPUTE_WINDOW_EXPIRED` (400), `RIDE_NOT_COMPLETED` (400), `DISPUTE_ALREADY_OPEN` (409)

---

### GET /rides/track/:shareToken
> Public ride tracking via shared link. **No auth required.**

**No request body.**

**Response:**
```json
{
  "status": "in_progress",
  "pickupAddress": "KNUST Gate",
  "dropoffAddress": "Kejetia Market",
  "driverGpsLat": 6.6885,
  "driverGpsLng": -1.6244,
  "estimatedFarePesewas": 1500
}
```

**Error codes:** `SHARE_LINK_NOT_FOUND` (404), `SHARE_LINK_EXPIRED` (410)

---

## ARTISAN MARKETPLACE (Jobs)

### POST /jobs
> Create an artisan job request. **Auth: Bearer (client only).**

**Required fields:**
- `categoryId` (string) — UUID of an active service category
- `description` (string) — Max 2000 characters
- `latitude` (number) — -90 to 90
- `longitude` (number) — -180 to 180

**Optional fields:**
- `photos` (string[]) — Array of S3 URLs for job photos
- `addressText` (string) — Human-readable address
- `scheduledFor` (string) — ISO 8601 datetime. Must be >= 2 hours from now.
- `promoCode` (string)

**Response (201):**
```json
{
  "jobId": "uuid",
  "status": "open",
  "shareToken": "xyz789",
  "artisansNotified": 3,
  "message": null
}
```
> `status` is `"queued"` if no artisans available. Check `message` field for explanation.

**Error codes:** `INVALID_CATEGORY` (400), `OUTSIDE_PILOT_REGION` (400), `INVALID_SCHEDULE_TIME` (400), `CLIENT_PROFILE_REQUIRED` (403)

---

### GET /jobs/:id
> Get full job details. **Auth: Bearer (job client or assigned artisan only).**

**No request body.**

**Response:** Full job entity — status, artisan info, bids, supplements, all timestamps.

**Error codes:** `NOT_YOUR_JOB` (403), `JOB_NOT_FOUND` (404)

---

### GET /jobs/:id/bids
> View bids submitted by artisans. **Auth: Bearer (job owner only).**

**No request body.**

**Response:**
```json
[
  {
    "bidId": "uuid",
    "amountPesewas": 5000,
    "message": "I can fix this today",
    "status": "pending",
    "expiresAt": "2024-01-15T10:35:00Z",
    "artisan": {
      "id": "uuid",
      "name": "Abena Mensah",
      "profilePhotoUrl": "https://s3...",
      "completedJobsCount": 47,
      "categories": ["Electrician"],
      "averageRating": 4.6,
      "ratingCount": 38
    }
  }
]
```

**Error codes:** `NOT_JOB_OWNER` (403), `JOB_NOT_FOUND` (404)

---

### PATCH /jobs/:id/select-bid
> Client selects the winning bid. **Auth: Bearer (client only).**

**Required fields:**
- `bidId` (string) — UUID of the chosen bid

**Response:**
```json
{
  "jobId": "uuid",
  "status": "confirmed",
  "artisanId": "uuid",
  "agreedPricePesewas": 5000,
  "confirmedAt": "2024-01-15T10:36:00Z"
}
```

**Error codes:** `JOB_NOT_OPEN` (400), `BID_NOT_FOUND` (400), `BID_NOT_PENDING` (400), `NOT_JOB_OWNER` (403)

---

### PATCH /jobs/:id/supplement/respond
> Approve or reject artisan's material cost supplement. **Auth: Bearer (client only).**

**Required fields:**
- `decision` (string) — `"approved"` or `"rejected"`

**Response:**
```json
{
  "supplementId": "uuid",
  "decision": "approved",
  "respondedAt": "...",
  "updatedAgreedPrice": 7000
}
```

**Error codes:** `SUPPLEMENT_ALREADY_RESPONDED` (400), `NOT_JOB_OWNER` (403)

---

### PATCH /jobs/:id/confirm
> Client confirms job completion. Triggers payment release via dual confirmation. **Auth: Bearer (client only).**

**No request body.**

**Response:**
```json
{
  "jobId": "uuid",
  "status": "completed",
  "clientConfirmedAt": "..."
}
```

**Error codes:** `ARTISAN_HAS_NOT_MARKED_COMPLETE` (400), `NOT_JOB_OWNER` (403)

---

### PATCH /jobs/:id/cancel
> Cancel a job. Free within 30 min of bid selection, 20% fee after. **Auth: Bearer.**

**Optional fields:**
- `reason` (string) — Max 500 chars. **Required for artisan cancellations.**

**Response:**
```json
{
  "jobId": "uuid",
  "status": "cancelled",
  "cancellationFeePesewas": 0,
  "cancelledAt": "..."
}
```

**Error codes:** `JOB_NOT_CANCELLABLE` (400), `REASON_REQUIRED` (400), `NOT_YOUR_JOB` (403)

---

### POST /jobs/:id/dispute
> Dispute a job within 2 hours of completion. **Auth: Bearer.**

**Required fields:**
- `reason` (string) — 10 to 500 characters

**Optional fields:**
- `details` (string) — Max 2000 characters

**Response (201):**
```json
{
  "disputeId": "uuid",
  "status": "open",
  "amountFrozenPesewas": 5000
}
```

**Error codes:** `DISPUTE_WINDOW_EXPIRED` (400), `JOB_NOT_COMPLETED` (400), `DISPUTE_ALREADY_OPEN` (409)

---

## PAYMENTS (Client)

### POST /payments/initiate
> Initiate payment for a ride or job. **Auth: Bearer (client only).**

**Required fields:**
- `bookingType` (string) — `"ride"` or `"artisan_job"`
- `bookingId` (string) — UUID
- `paymentMethod` (PaymentMethod) — `"momo_mtn"`, `"momo_telecel"`, `"momo_airteltigo"`, `"visa"`, `"mastercard"`

**Conditionally required:**
- `momoPhone` (string) — Required when paymentMethod is `momo_*`. Format: `"+233..."` or `"0..."`.
- `cardToken` (string) — Required when paymentMethod is `"visa"` or `"mastercard"`. Tokenised card reference.

**Response (201):**
```json
{
  "paymentId": "uuid",
  "status": "processing",
  "authorizationUrl": "https://paystack..."
}
```
> `authorizationUrl` is only present for card payments. Open in WebView for 3D Secure.

**Error codes:** `MOMO_PHONE_REQUIRED` (400), `CARD_TOKEN_REQUIRED` (400), `BOOKING_NOT_FOUND` (404), `PAYMENT_ALREADY_INITIATED` (409)

---

### GET /payments/:id/status
> Check payment status. **Auth: Bearer (payment client or booking provider only).**

**No request body.**

**Response:**
```json
{
  "id": "uuid",
  "bookingType": "ride",
  "bookingId": "uuid",
  "grossAmountPesewas": 1500,
  "prePromoAmountPesewas": 1500,
  "promoDiscountPesewas": 0,
  "commissionPesewas": 300,
  "netPayoutPesewas": 1200,
  "tipPesewas": 0,
  "paymentMethod": "momo_mtn",
  "paymentStatus": "completed",
  "createdAt": "...",
  "updatedAt": "..."
}
```

**Error codes:** `NOT_YOUR_PAYMENT` (403), `PAYMENT_NOT_FOUND` (404)

---

### POST /payments/:id/tip
> Add a tip after ride/job completion. Zero commission on tips. **Auth: Bearer (client only).**

**Required fields:**
- `amountPesewas` (int) — Min: 1. Full amount goes to provider.

**Response (201):**
```json
{
  "tipId": "uuid",
  "paymentId": "uuid",
  "status": "pending",
  "amountPesewas": 200
}
```

**Error codes:** `NOT_YOUR_PAYMENT` (403), `PAYMENT_NOT_FOUND` (404), `TIP_ALREADY_PENDING` (409)

---

### POST /payments/:id/retry
> Retry a failed MoMo payment. **Auth: Bearer (client only).**

**No request body.**

**Response (201):**
```json
{ "paymentId": "uuid", "status": "processing" }
```

**Error codes:** `PAYMENT_NOT_RETRYABLE` (400), `RETRY_WINDOW_EXPIRED` (400), `CARD_RETRY_NOT_SUPPORTED` (400)

---

### POST /payments/:id/dispute
> Raise payment dispute within 2 hours. **Auth: Bearer (client only).**

**Required fields:**
- `reason` (string) — Max 1000 characters

**Optional fields:**
- `evidenceUrls` (string[]) — Array of S3 URLs

**Response (201):**
```json
{
  "disputeId": "uuid",
  "status": "open",
  "amountFrozenPesewas": 1500
}
```

**Error codes:** `DISPUTE_WINDOW_EXPIRED` (400), `PAYMENT_NOT_COMPLETED` (400), `DISPUTE_ALREADY_OPEN` (409)

---

## LOYALTY & REFERRALS (Client)

### GET /loyalty/transactions
> Loyalty points history. **Auth: Bearer. Role: `client` only.**

**Optional query params:**
- `page` (int) — Default: 1
- `limit` (int) — Default: 20

**Response:** Paginated list. Transaction types: `earned_ride`, `earned_job`, `earned_referral`, `redeemed`, `expired`, `adjusted`.

---

### POST /loyalty/redeem
> Redeem loyalty points as a discount on a booking. **Auth: Bearer. Role: `client` only.**

**Required fields:**
- `points` (int) — Positive integer
- `bookingType` (string) — `"ride"` or `"job"`
- `bookingId` (string) — UUID

**Response:**
```json
{ "discountPesewas": 500, "newBalance": 150 }
```

**Error codes:** `INSUFFICIENT_LOYALTY_POINTS` (400), `BOOKING_ALREADY_REDEEMED` (400)

---

### GET /referrals/my-code
> Get client's referral code and shareable deep link. **Auth: Bearer. Role: `client` only.**

**No request body.**

**Response:**
```json
{
  "code": "MYSHOP-ABC123",
  "shareLink": "https://app.myshop.com.gh/ref/MYSHOP-ABC123"
}
```

---

### GET /referrals/history
> Referral history with bonus status. **Auth: Bearer. Role: `client` only.**

**No request body.**

**Response:**
```json
[
  {
    "refereeId": "uuid",
    "refereeName": "Ama Serwaa",
    "completed": true,
    "bonusAwarded": true
  }
]
```

---

## PROMO CODES (Client)

### POST /promos/validate
> Validate a promo code and preview discount. **Auth: Bearer.**

**Required fields:**
- `code` (string) — The promo code
- `bookingType` (string) — `"ride"` or `"artisan_job"`

**Optional fields:**
- `fareAmountPesewas` (int) — Min: 0. Needed to calculate percentage-based discounts.

**Response:**
```json
{
  "discountPesewas": 300,
  "discountPercent": 20,
  "promoType": "percentage_discount",
  "bonusPoints": 0
}
```

**Error codes:** `PROMO_NOT_FOUND` (404), `PROMO_EXPIRED` (400), `PROMO_MAX_USES_REACHED` (400), `PROMO_WRONG_SCOPE` (400), `PROMO_MIN_AMOUNT_NOT_MET` (400), `PROMO_MAX_USES_PER_USER_REACHED` (400)

---

---

# PROVIDER APP ENDPOINTS

---

## VERIFICATION & ONBOARDING

### POST /verification/documents
> Get presigned S3 upload URL for a verification document. **Auth: Bearer. Rate limit: 10/60s.**

**Required fields:**
- `providerType` (string) — `"driver"` or `"artisan"`
- `documentType` (DocumentType) — See Enums section. E.g. `"drivers_licence"`, `"national_id"`, `"trade_certificate"`, `"portfolio_photo"`
- `fileName` (string) — Original file name
- `mimeType` (MimeType) — `"image/jpeg"`, `"image/png"`, or `"application/pdf"`
- `fileSize` (int) — Bytes. Range: 1 to 10485760 (10 MB max)

**Optional fields:**
- `fileHash` (string) — SHA-256 hex digest for integrity verification
- `expiresAt` (string) — ISO 8601 date for document expiry (e.g. licence expiry)

**Response (201):**
```json
{
  "documentId": "uuid",
  "uploadUrl": "https://s3...presigned...",
  "expiresIn": 3600,
  "s3Key": "documents/driver/uuid/drivers_licence/uuid.jpg"
}
```
> Upload the file via **HTTP PUT** to `uploadUrl`. URL expires in 1 hour.

**Error codes:** `INVALID_FILE_TYPE` (400), `FILE_TOO_LARGE` (400), `PROVIDER_PROFILE_REQUIRED` (403)

---

### GET /verification/status
> Check verification progress and all document statuses. **Auth: Bearer.**

**No request body.**

**Response:**
```json
{
  "driver": {
    "id": "uuid",
    "verificationStatus": "pending",
    "kycStatus": "not_started",
    "policeCheckStatus": "not_started",
    "licenceNumber": "DL-12345",
    "licenceExpiry": "2027-12-31"
  },
  "artisan": null,
  "documents": [
    {
      "id": "uuid",
      "providerType": "driver",
      "documentType": "drivers_licence",
      "fileUrl": "documents/driver/uuid/...",
      "status": "uploaded",
      "reviewedBy": null,
      "reviewedAt": null,
      "rejectionReason": null,
      "expiresAt": "2027-12-31",
      "version": 1,
      "isCurrent": true,
      "createdAt": "..."
    }
  ]
}
```

---

## LOCATION (Driver)

### POST /location/update
> Broadcast GPS position and online/offline status. Call every 5 seconds when driver is online. **Auth: Bearer. Role: `driver` only. Rate limit: 1 per 3 seconds.**

**Required fields:**
- `latitude` (number) — -90 to 90
- `longitude` (number) — -180 to 180
- `status` (OnlineStatus) — `"online"` or `"offline"`

**Response:** Location updated confirmation.

**Error codes:** `OUTSIDE_PILOT_REGION` (400), `TOGGLE_LOCKED_ACTIVE_RIDE` (400), `DRIVER_PROFILE_REQUIRED` (403)

---

## RIDE MANAGEMENT (Driver)

### GET /rides/:id
> Get ride details assigned to this driver. **Auth: Bearer (ride client or assigned driver only).**

**No request body.**

**Response:** Full ride entity — pickup, dropoff, stops, client info, fare, GPS trail.

**Error codes:** `NOT_YOUR_RIDE` (403), `RIDE_NOT_FOUND` (404)

---

### PATCH /rides/:id/status
> Advance ride through the status machine. **Auth: Bearer (assigned driver only).**

**Required fields:**
- `status` (string) — Next status. Valid transitions: `"driver_en_route"` → `"arrived_at_pickup"` → `"in_progress"` → `"completed"`

**Conditionally required:**
- `currentLat` (number) — Required when `status = "completed"`. Range: -90 to 90.
- `currentLng` (number) — Required when `status = "completed"`. Range: -180 to 180.

**Response:**
```json
{
  "status": "completed",
  "finalFarePesewas": 1500
}
```
> `finalFarePesewas` is only present when status = `"completed"`.

**Error codes:** `INVALID_STATUS_TRANSITION` (400), `NOT_ASSIGNED_DRIVER` (403), `RIDE_NOT_FOUND` (404)

---

### PATCH /rides/:id/cancel
> Driver cancels accepted ride before pickup. 3 cancellations in 30 days = suspension. **Auth: Bearer (assigned driver).**

**Required fields:**
- `reason` (string) — 1 to 500 characters

**Response:**
```json
{ "status": "cancelled", "cancellationFeePesewas": 0, "driverSuspended": false }
```

---

### PATCH /rides/:id/stops/:stopId/decline
> Decline a mid-ride stop added by client. **Auth: Bearer (assigned driver).**

**No request body.**

**Response:**
```json
{ "newFarePesewas": 1500 }
```

**Error codes:** `CANNOT_DECLINE_BOOKING_STOP` (400), `STOP_ALREADY_DECLINED` (400), `NOT_ASSIGNED_DRIVER` (403)

---

### PATCH /rides/:id/stops/:stopId/arrived
> Mark arrival at a multi-stop waypoint. **Auth: Bearer (assigned driver).**

**No request body.**

**Response:**
```json
{ "arrivedAt": "2024-01-15T11:00:00Z" }
```

---

### PATCH /rides/:id/stops/:stopId/departed
> Mark departure from a multi-stop waypoint. **Auth: Bearer (assigned driver).**

**No request body.**

**Response:**
```json
{ "departedAt": "2024-01-15T11:05:00Z" }
```

---

## ARTISAN JOB MANAGEMENT (Artisan)

### Admin-Assignment Flow — **QUESTIONS FOR BACKEND**

**Context:** When a job posts but receives no bids before the 5-minute window
expires, an admin manually assigns an artisan. That artisan then submits a
price (via what we currently treat as "bidding") to continue the flow.

Before we can finish wiring the mobile UI, we need answers on:

1. **Status for "awaiting admin assignment"** — what's the job's `status`
   between "bid window expired with zero bids" and "admin has picked an
   artisan"? We're currently seeing `pending_admin` in the wild — is that
   the one? Or does `pending_admin` mean something else (e.g. a bid amount
   needing admin approval when it exceeds GHS 5,000, per the original spec
   for `POST /jobs/:id/bids`)?

2. **Status after admin picks an artisan** — what's the job's `status` once
   the admin has assigned but the artisan hasn't yet quoted? Is it still
   `pending_admin`, a new `admin_assigned`, or does it jump to `open` with
   `assignedArtisanId` set?

3. **Event name** — when the admin assigns a job to a specific artisan,
   which WebSocket event fires into the `artisan:{userId}` room? We'd
   expect something like `job:admin_assigned` or reuse `job:new`. Please
   confirm the event name and payload shape.

4. **How does the artisan quote?** — same `POST /jobs/:id/bids` endpoint,
   or a dedicated one? If same, the backend must allow bids on the
   admin-assigned status. We currently gate the UI on `status == open`
   only and reject everything else with a "Not biddable" banner.

5. **Expiry** — does the admin-assigned artisan get a fresh N-minute window
   to quote, or is it open-ended? Please return an `expiresAt` (or
   `quoteDeadline`) on the job or the event payload so we can render a
   countdown.

6. **Decline path** — if the admin-assigned artisan declines the
   assignment, what happens? Does the job go back to pending-admin, get
   re-broadcast, or auto-cancel? Is there a dedicated endpoint
   (`POST /jobs/:id/decline-assignment`) or do we reuse `PATCH /jobs/:id/cancel`?

7. **Acceptance after the artisan quotes** — when the admin-assigned
   artisan submits their price, is it auto-accepted (since the admin
   already picked them) or does the client still need to confirm? This
   determines whether the job status jumps straight to `confirmed` or
   needs an intermediate state.

8. **Timeline fields in `GET /jobs/:id`** — we'd like explicit timestamps
   for every transition. Please include:
   - `openedAt` (initial post)
   - `bidWindowExpiredAt` (zero-bid fallback kicked in)
   - `adminAssignedAt` + `adminAssignedArtisanId`
   - `quotedAt` (admin-assigned artisan submitted their price)
   - Existing: `confirmedAt`, `artisanEnRouteAt`, `arrivedAt`, `startedAt`,
     `completedAt`

   So the mobile can render a proper status timeline without guessing.

9. **`myBid.status` values** — what's the full set? So far we've seen
   `submitted`, `pending`, `pending_review`, `accepted`, `rejected`,
   `expired`, `withdrawn`. For the admin-assigned path, is it the same
   enum or is there a `quoted` / `admin_quoted` variant?

Once these are confirmed, we'll finalise the mobile `JobStatus` enum and
bid-gating logic to match.

---

### GET /jobs (artisan scope) — **PENDING BACKEND ENRICHMENT**

When called by an artisan token, the backend should:

1. **Scope the list** to jobs the artisan is actually associated with — jobs
   they've bid on, been matched to, or been assigned. Do NOT return arbitrary
   open jobs in the area; those surface via WebSocket `job:new` only.

2. **Attach a `myBid` object** to each job the artisan has bid on:
   ```json
   {
     "id": "...",
     "status": "open",
     // ... standard job fields ...
     "myBid": {
       "bidId": "uuid",
       "amountPesewas": 17500,
       "etaMinutes": 20,
       "durationMinutes": 120,
       "message": "...",
       "status": "submitted",    // submitted | accepted | rejected | expired | withdrawn
       "createdAt": "2024-01-15T10:30:00Z",
       "expiresAt": "2024-01-15T10:35:00Z"
     }
   }
   ```

Without `myBid` attached, the mobile app falls back to a local (SharedPreferences)
bid tracker to render the "Bids" tab accurately. Adding `myBid` is the source
of truth and lets the app stay consistent across devices.

---

### GET /jobs/:id
> Get incoming job request details. **Auth: Bearer (job client or assigned artisan only).**

**No request body.**

**Response:** Full job entity — category, description, photos, client location, bids, supplements. When called by an artisan, include `myBid` as described above.

**Error codes:** `NOT_YOUR_JOB` (403), `JOB_NOT_FOUND` (404)

---

### POST /jobs/:id/bids
> Submit a bid within the 5-minute bidding window. Max 3 bids per job. **Auth: Bearer. Role: `artisan` only.**

**Required fields:**
- `amountPesewas` (int) — Min: 1. Must be >= category minimum bid (check via `GET /config/:key`).
- `etaMinutes` (int) — **PENDING BACKEND** — Artisan's estimated arrival time in minutes. Range: 1–180.
- `durationMinutes` (int) — **PENDING BACKEND** — Artisan's estimated job duration in minutes. Range: 15–1440.

**Optional fields:**
- `message` (string) — Message to the client explaining the bid.

**Response (201):**
```json
{
  "bidId": "uuid",
  "status": "pending",
  "amountPesewas": 5000,
  "etaMinutes": 20,
  "durationMinutes": 120,
  "expiresAt": "2024-01-15T10:35:00Z",
  "createdAt": "2024-01-15T10:30:00Z"
}
```
> `status` is `"admin_review"` if bid exceeds GHS 5,000 (500000 pesewas).

**Error codes:** `JOB_NOT_OPEN` (400), `BID_WINDOW_EXPIRED` (400), `MAX_BIDS_REACHED` (400), `BID_BELOW_MINIMUM` (400)

> **Backend action needed:** Add `etaMinutes` and `durationMinutes` columns to the `bids` table and accept them in this payload. Include them in the response and in every `bid` object returned elsewhere. The mobile app is sending them today merged into `message` as a fallback.

---

### PATCH /jobs/:id/status
> Advance job through the status machine. **Auth: Bearer (assigned artisan only).**

**Required fields:**
- `status` (string) — Next status. Valid transitions: `"artisan_en_route"` → `"arrived"` → `"in_progress"` → `"artisan_marked_complete"`

**Response:**
```json
{ "status": "arrived", "updatedAt": "..." }
```

**Error codes:** `INVALID_STATUS_TRANSITION` (400), `NOT_ASSIGNED_ARTISAN` (403)

---

### POST /jobs/:id/supplement
> Request a material cost supplement. Only one per job, must be before starting work. **Auth: Bearer (assigned artisan only).**

**Required fields:**
- `additionalAmountPesewas` (int) — Min: 1
- `reason` (string) — Max 1000 chars. Must explain what wasn't foreseeable at bid time.

**Response (201):**
```json
{
  "supplementId": "uuid",
  "status": "pending",
  "additionalAmountPesewas": 2000,
  "reason": "Additional wiring materials needed",
  "createdAt": "..."
}
```

**Error codes:** `SUPPLEMENT_TOO_LATE` (400), `NOT_ASSIGNED_ARTISAN` (403)

---

### PATCH /jobs/:id/confirm-schedule
> Confirm attendance for a scheduled job. Must be done by T-20h before appointment. **Auth: Bearer (assigned artisan only).**

**No request body.**

**Response:**
```json
{
  "jobId": "uuid",
  "artisanConfirmed24h": true,
  "artisanConfirmedAt": "..."
}
```

**Error codes:** `NOT_A_SCHEDULED_JOB` (400), `JOB_NOT_CONFIRMABLE` (400), `NOT_ASSIGNED_ARTISAN` (403)

---

### POST /jobs/:id/escalate
> Escalate when client hasn't confirmed job completion after 4 hours. **Auth: Bearer (assigned artisan only).**

**No request body.**

**Response:**
```json
{
  "escalationId": "uuid",
  "status": "submitted",
  "adminNotified": true
}
```

**Error codes:** `ESCALATION_TOO_EARLY` (400), `ALREADY_CONFIRMED` (400), `NOT_ASSIGNED_ARTISAN` (403)

---

### PATCH /jobs/:id/welfare-check/respond
> Respond to automated welfare check. Triggered after 3h with no status update at client location. **Auth: Bearer (assigned artisan only).**

**No request body.**

**Response:**
```json
{
  "jobId": "uuid",
  "welfareCheckId": "uuid",
  "resolved": true,
  "lastActivityAt": "..."
}
```

**Error codes:** `NO_OPEN_WELFARE_CHECK` (400), `NOT_ASSIGNED_ARTISAN` (403)

---

### PATCH /jobs/:id/cancel
> Artisan cancels a job. 3 cancellations in 30 days = suspension. **Auth: Bearer.**

**Required fields:**
- `reason` (string) — Max 500 chars. Required for artisan cancellations.

**Response:**
```json
{ "jobId": "uuid", "status": "cancelled", "cancellationFeePesewas": 0, "cancelledAt": "..." }
```

---

## EARNINGS & PAYOUTS (Provider)

### GET /payments/earnings
> Earnings dashboard with trend and peak hours. Cached for 5 minutes. **Auth: Bearer. Role: `driver` or `artisan` only.**

**Required query params:**
- `period` (string) — `"today"`, `"week"`, or `"month"`

**Response:**
```json
{
  "period": "week",
  "totalEarningsPesewas": 125000,
  "totalTipsPesewas": 5000,
  "totalCommissionPesewas": 25000,
  "completedRides": 18,
  "trendPct": 12.5,
  "peakHours": [
    { "hour": 8, "dayOfWeek": 1, "count": 5 },
    { "hour": 17, "dayOfWeek": 5, "count": 7 }
  ]
}
```
> `trendPct` is `null` if no previous period data exists.

---

### GET /payments/payouts
> Full payout history. **Auth: Bearer. Role: `driver` or `artisan` only.**

**No request body.**

**Response:**
```json
[
  {
    "id": "uuid",
    "amountPesewas": 12000,
    "payoutMethod": "momo_mtn",
    "payoutType": "instant",
    "payoutAccount": "+233241234567",
    "status": "completed",
    "retryCount": 0,
    "failureReason": null,
    "completedAt": "2024-01-15T10:30:00Z",
    "createdAt": "..."
  }
]
```

---

---

# WEBSOCKET CHANNELS

| Channel | Used By | Auth | Description |
|---------|---------|------|-------------|
| `ws:///v1/location/track` | Driver | Bearer | Broadcast GPS coordinates every 5s while online |
| `ws:///v1/rides/:id/live` | Client + Driver | Bearer | Live ride tracking — driver position, ETA, status changes |
| `ws:///v1/jobs/:id/live` | Client + Artisan | Bearer | Live job tracking — artisan location, status updates |
| `ws:///v1/chat/:bookingId` | Both | Bearer | Real-time in-app messaging during active ride/job |

---

# WEBHOOK ENDPOINTS (Backend-only — not called by mobile apps)

| Method | Endpoint | Called By |
|--------|----------|-----------|
| POST | `/payments/webhooks/paystack` | Paystack/Flutterwave payment confirmations |
| POST | `/verification/kyc/callback` | Smile Identity KYC results |
| POST | `/verification/police-check/callback` | Ghana Police background check results |
| POST | `/notifications/sms/delivery-report` | Arkesel SMS delivery reports |
| POST | `/notifications/email/ses-webhook` | AWS SES bounce/complaint notifications |
| POST | `/communication/call/callback` | Africa's Talking voice call events |
| POST | `/ussd/callback` | Africa's Talking USSD sessions |

---

# SUMMARY

| Category | Count |
|----------|-------|
| Shared (both apps) | 22 endpoints |
| Client App only | 18 endpoints |
| Provider App only | 16 endpoints |
| WebSocket channels | 4 channels |
| Webhooks (backend) | 7 endpoints |
| **Total** | **67 endpoints + 4 WebSocket channels** |
