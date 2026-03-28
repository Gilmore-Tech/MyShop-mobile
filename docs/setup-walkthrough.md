# MyShop Mobile — Setup & Development Walkthrough
## For the Mobile Developer

---

## Repo & Branch Rules

| Branch | Purpose | Who |
|--------|---------|-----|
| `main` | Production-ready code | Lead merges PRs only |
| `feature/MSP-{ticket}-{desc}` | New feature work | Mobile dev creates from `main` |
| `fix/MSP-{ticket}-{desc}` | Bug fixes | Mobile dev creates from `main` |

**Rule**: Never push to `main`. All work goes through feature branches → PR → Lead reviews with Claude Code → merge.

---

## Step 1: Clone the Repo

```bash
git clone git@github.com:gilmore-technologies/myshop-mobile.git
cd myshop-mobile
```

## Step 2: Install Prerequisites

| Tool | Version | Check | Install |
|------|---------|-------|---------|
| Flutter | 3.27+ | `flutter --version` | [flutter.dev/get-started](https://flutter.dev/docs/get-started/install) |
| Dart | 3.6+ | `dart --version` | Comes with Flutter |
| Melos | Latest | `melos --version` | `dart pub global activate melos` |
| Xcode | 15+ (macOS) | `xcode-select -p` | App Store |
| Android Studio | Latest | — | [developer.android.com](https://developer.android.com/studio) |

```bash
# Verify Flutter is set up correctly
flutter doctor
# All checks should pass (or show only expected warnings)
```

## Step 3: Bootstrap the Workspace

```bash
melos bootstrap
```

This links all local packages (`api_client`, `shared_models`, `shared_ui`, `shared_utils`) and runs `flutter pub get` in every app and package.

## Step 4: Run the Apps

```bash
# Client App
cd apps/client
flutter run
# Pick your device/emulator when prompted

# Provider App (in a separate terminal)
cd apps/provider
flutter run
```

Both apps should launch with the placeholder "TODO: Add routing" screen.

## Step 5: Understand the Structure

```
myshop-mobile/
├── apps/
│   ├── client/                    # MyShop (consumer app)
│   │   ├── lib/
│   │   │   ├── main.dart          # Entry point
│   │   │   └── src/
│   │   │       ├── app/           # Root widget, routing setup
│   │   │       ├── core/          # DI, constants, routing config
│   │   │       └── features/      # Feature modules (see below)
│   │   └── pubspec.yaml
│   │
│   └── provider/                  # MyShop Provider (driver & artisan app)
│       ├── lib/
│       │   ├── main.dart
│       │   └── src/
│       │       ├── app/
│       │       ├── core/
│       │       └── features/
│       └── pubspec.yaml
│
├── packages/
│   ├── api_client/                # Dio HTTP client + WebSocket service
│   ├── shared_models/             # Freezed data models, enums, DTOs
│   ├── shared_ui/                 # Theme, colours, typography, reusable widgets
│   └── shared_utils/              # Phone format, money helpers, validators
│
└── melos.yaml
```

## Step 6: Screen Inventory

Every screen stub is already created. You translate designs to code — naming and file structure is done.

### Client App — 34 screens

| Feature | Screens | Files |
|---------|---------|-------|
| Auth | PhoneInputScreen, OtpVerificationScreen | `features/auth/screens/` |
| Onboarding | SplashScreen, WelcomeScreen | `features/onboarding/screens/` |
| Home | HomeScreen (map + bottom nav) | `features/home/screens/` |
| Ride | DestinationSearch, FareEstimate, DriverMatching, RideTracking, AddStop, RideComplete, RideDispute | `features/ride/screens/` |
| Services | Categories, JobForm, BidReview, JobTracking, SupplementReview, JobComplete, JobDispute | `features/services/screens/` |
| Activity | ActivityList, RideDetail, JobDetail | `features/activity/screens/` |
| Profile | Profile, EditProfile, SavedLocations, EmergencyContacts, PaymentMethods, LoyaltyPoints, Referral, LanguageSettings | `features/profile/screens/` |
| Notifications | NotificationsListScreen | `features/notifications/screens/` |
| Chat | ChatScreen | `features/chat/screens/` |
| Safety | EmergencyScreen, ShareTrackingScreen | `features/safety/screens/` |

### Provider App — 28 screens

| Feature | Screens | Files |
|---------|---------|-------|
| Auth | ProviderPhoneInput, ProviderOtpVerification, RoleSelection | `features/auth/screens/` |
| Onboarding | ProviderSplash, RolePicker | `features/onboarding/screens/` |
| Registration | DriverRegistration, ArtisanRegistration, DocumentUpload, VerificationStatus | `features/registration/screens/` |
| Driver Home | DriverHome (map + toggle), RideRequest, ActiveRide, DriverRideComplete | `features/driver_home/screens/` |
| Artisan Home | ArtisanHome, JobRequest, BidSubmission, ActiveJob, SupplementRequest, ArtisanJobComplete | `features/artisan_home/screens/` |
| Earnings | EarningsDashboard, PayoutHistory | `features/earnings/screens/` |
| Ratings | RatingsScreen | `features/ratings/screens/` |
| Profile | ProviderProfile, EditProviderProfile, PayoutSettings | `features/profile/screens/` |
| Notifications | ProviderNotificationsScreen | `features/notifications/screens/` |
| Chat | ProviderChatScreen | `features/chat/screens/` |
| Safety | ProviderEmergencyScreen | `features/safety/screens/` |

Every screen file includes a `/// PRD Reference: PRD X.X` comment pointing to the exact PRD section to reference for business rules.

---

## Step 7: Create Your Feature Branch

```bash
git checkout -b feature/MSP-{ticket}-{short-description}
```

Examples:
- `feature/MSP-20-client-splash-onboarding`
- `feature/MSP-25-ride-booking-flow`
- `fix/MSP-40-map-pin-offset`

---

## Working with Claude Code

### Starting a Session

```bash
cd ~/projects/myshop-mobile
claude
```

### Prompting Template — Copy and Edit

```
I'm working on ticket MSP-{number}: {ticket title}

Context:
- This is the MyShop mobile app (Flutter). Two apps share a monorepo:
  Client App (apps/client/) and Provider App (apps/provider/)
- Read docs/PRD_Ghana_Platform_v2_1.md Section {N} for business rules
- Shared packages are in packages/ (api_client, shared_models, shared_ui, shared_utils)

Task:
Implement the {ScreenName} screen at {filepath}.

Requirements:
1. {requirement from ticket/design}
2. {requirement}
3. {requirement}

Tech stack:
- State: Riverpod 2 with code generation
- Navigation: GoRouter
- HTTP: Dio via api_client package
- Maps: Google Maps (rides) / Mapbox (artisan pin-drop)
- Models: Freezed + json_serializable in shared_models
- Theme: Use shared_ui theme tokens (colours, typography, spacing)

Design notes:
- {design reference or Figma link}
- Follow Material 3 with MyShop theme from shared_ui
- Skeleton loading states, not spinners
- Support English and Twi (use intl for strings)

After implementation:
- Run `flutter analyze` — no errors or warnings
- Run `flutter test` — all tests pass
- Ensure screen matches the PRD flow described in the doc comment
```

### Example: Building the Ride Booking Flow

```
I'm working on MSP-25: Fare Estimate Screen

Context:
- Client App: apps/client/lib/src/features/ride/screens/fare_estimate_screen.dart
- Read docs/PRD_Ghana_Platform_v2_1.md Section 4.3 (Ride-Hailing Flow)

Task:
Implement the FareEstimateScreen — shows estimated fare, pickup time,
route on Google Maps, and a "Confirm Booking" button.

Requirements:
1. Accept origin and destination coordinates from the previous screen
2. Display route polyline on Google Maps
3. Show estimated fare (from API: GET /v1/rides/estimate)
4. Show estimated pickup time
5. "Confirm Booking" button calls POST /v1/rides
6. Fare displayed in GHS, formatted with formatGhs() from shared_utils
7. If no drivers available, show "No drivers available" message (edge case #45)

Use Riverpod for state. Google Maps Flutter for the map.
API calls through api_client package Dio instance.
Skeleton loading while estimate loads.
```

### Example: Building Artisan Bid Submission

```
I'm working on MSP-32: Bid Submission Screen (Provider App)

Context:
- Provider App: apps/provider/lib/src/features/artisan_home/screens/bid_submission_screen.dart
- Read docs/PRD_Ghana_Platform_v2_1.md Section 5.3 and Section 4.5.1

Task:
Implement the BidSubmissionScreen — artisan submits a bid with amount
and optional message.

Requirements:
1. Show job details: category, description, client photos, location
2. Amount input field — validate against category minimum (from API)
3. Flag warning if amount exceeds GHS 5,000 (edge case #44)
4. Optional message field (explain what bid includes)
5. Submit button calls POST /v1/jobs/:id/bids
6. Amount in GHS input but convert to pesewas for API
7. Timer showing time remaining in 5-minute bid window

Use Riverpod, Dio, shared_models for Bid model.
```

---

## Commit, Push & Pull Request

### Commit Convention

```bash
git add .
git commit -m "feat(client/ride): implement fare estimate screen with Google Maps route

- Display route polyline and estimated fare
- Confirm booking button with loading state
- Handle no-drivers-available edge case

Closes #25"
```

Format: `{type}({app}/{feature}): {description}`

Types: `feat`, `fix`, `refactor`, `style`, `test`, `chore`

Scopes: `client/auth`, `client/ride`, `client/services`, `provider/driver`, `provider/artisan`, `shared/models`, `shared/ui`

### Push and PR

```bash
git push -u origin feature/MSP-25-fare-estimate
```

Create PR on GitHub with this template:

```markdown
## What Changed
{Brief description}

## Ticket
Closes MSP-{number}

## Screenshots
{Attach screenshots or screen recording of the implemented screen}

## How to Test
1. Run `cd apps/client && flutter run`
2. {Navigation steps to reach the screen}
3. {Expected behaviour}

## Checklist
- [ ] Screen matches PRD flow (reference in doc comment)
- [ ] Uses shared_ui theme (no hardcoded colours/fonts)
- [ ] Uses shared_models for API data (Freezed classes)
- [ ] API calls go through api_client
- [ ] Skeleton loading states (not spinners)
- [ ] Works on iOS and Android
- [ ] Twi strings in i18n (or TODO marked)
- [ ] `flutter analyze` passes
- [ ] `flutter test` passes
```

---

## Daily Workflow

```
Morning:
  git checkout main && git pull
  git checkout your-branch
  git rebase main
  melos bootstrap          # if packages changed
  cd apps/client (or provider) && flutter run

Work:
  Pick ticket → create branch → open Claude Code → use template → implement → test → commit

End of day:
  Push branch → create PR if ready → update Sprint board
```

---

## Useful Commands

| Command | What |
|---------|------|
| `melos bootstrap` | Link packages & install deps |
| `melos run analyze` | Static analysis on all packages |
| `melos run format` | Format check on all packages |
| `melos run test` | Run tests in all packages |
| `melos clean` | Clean all build artifacts |
| `flutter run` | Run current app (from app dir) |
| `flutter test` | Run tests (from app dir) |
| `dart run build_runner build` | Generate Freezed/Riverpod code |
| `dart run build_runner watch` | Watch mode for code gen |

---

## Shared Packages — When to Use What

| Package | Use For | Example |
|---------|---------|---------|
| `api_client` | All HTTP calls and WebSocket connections | `ApiClient.rides.estimate(origin, dest)` |
| `shared_models` | Data classes, enums, DTOs | `Ride`, `ArtisanJob`, `Bid`, `RideStatus` |
| `shared_ui` | Theme, colours, typography, reusable widgets | `MyShopButton`, `SkeletonLoader`, `StatusBadge` |
| `shared_utils` | Formatting and validation | `formatGhs(4730)` → "GHS 47.30", `normalizePhone('+233...')` |

**Rule**: If code is used in both apps, it goes in a shared package. If it's app-specific, it stays in that app's `features/` directory.
