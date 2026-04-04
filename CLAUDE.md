# CLAUDE.md — MyShop Mobile
## Flutter Monorepo | Client App + Provider App
### Gilmore Technologies

> **Read this file first.** It is the single source of truth for AI-assisted development on the `myshop-mobile` repository.

---

## 1. Project Overview

MyShop is a dual-sided ride-hailing and artisan services marketplace platform targeting the Ashanti Region of Ghana, with Kumasi as the pilot city. This repository contains the two Flutter mobile applications:

- **Client App** — Consumer-facing app for booking rides and requesting artisan services (34 screens)
- **Provider App** — Role-siloed app where drivers see a ride-hailing interface and artisans see a marketplace interface (28 screens)

Both apps share common packages for models, API communication, UI components, and business logic.

**Core product goals:**
- Reliable, GPS-tracked ride-hailing with upfront fare estimates
- Verified artisan marketplace with bidding, ratings, and escrow-protected payments
- Instant MoMo payouts for providers
- Safety-first with emergency features, phone masking, and live tracking
- Bilingual support (English + Twi) at launch

**Target users:** Clients (Ama — urban professional, smartphone), Providers (Kofi — driver, Abena — artisan)

**Business context:** 3-month open beta pilot in Ashanti Region. 20% platform commission on all transactions. No ads or subscriptions during pilot.

---

## 2. Architecture Overview

### 2.1 Monorepo Structure (Melos)

```
myshop-mobile/
├── apps/
│   ├── client_app/           # Client-facing Flutter app (34 screens)
│   │   ├── lib/
│   │   │   ├── app/          # App entry, router, DI
│   │   │   ├── features/     # Feature modules (auth, rides, services, profile, etc.)
│   │   │   ├── l10n/         # Localisation (English + Twi)
│   │   │   └── main.dart
│   │   ├── assets/
│   │   ├── test/
│   │   ├── integration_test/
│   │   └── pubspec.yaml
│   │
│   └── provider_app/         # Provider-facing Flutter app (28 screens)
│       ├── lib/
│       │   ├── app/          # App entry, router, DI, role picker
│       │   ├── features/     # Feature modules (auth, driver/, artisan/, earnings, profile)
│       │   ├── l10n/         # Localisation (English + Twi)
│       │   └── main.dart
│       ├── assets/
│       ├── test/
│       ├── integration_test/
│       └── pubspec.yaml
│
├── packages/
│   ├── myshop_core/          # Shared models, enums, constants, utils
│   ├── myshop_ui/            # Design system: theme, shared widgets, brand components
│   ├── myshop_api/           # API client, DTOs, endpoint definitions, interceptors
│   └── myshop_domain/        # Use cases, repository interfaces, domain entities
│
├── .claude/                  # AI development tooling
│   ├── mcp/
│   ├── plugins/
│   ├── agents/
│   └── commands/
│
├── melos.yaml                # Monorepo workspace config
├── pubspec.yaml              # Root pubspec
├── analysis_options.yaml     # Shared lint rules
├── CLAUDE.md                 # This file
└── README.md
```

### 2.2 App Responsibilities

| App | Screens | Key Features |
|-----|---------|--------------|
| Client App | 34 | Registration, map-first home, ride booking, multi-stop rides, artisan services tab, bidding flow, active booking tracking, in-app chat, payments, loyalty, safety, profile |
| Provider App — Driver View | ~14 | Registration + verification, online/offline toggle, ride requests, navigation, fare meter, earnings dashboard, payout settings |
| Provider App — Artisan View | ~14 | Registration + verification, online/offline toggle, job requests, bidding, supplement requests, navigation, earnings dashboard, payout settings |

### 2.3 Shared Package Responsibilities

| Package | Purpose |
|---------|---------|
| `myshop_core` | Domain models (User, Ride, Job, Bid, Payment), enums (RideStatus, JobStatus, UserRole, PaymentMethod), constants, validators, formatters (GHS currency, Ghana phone numbers) |
| `myshop_ui` | MyShop design system — ThemeData, brand colors, typography, reusable widgets (MyShopButton, MyShopCard, MyShopInput, StatusBadge, RatingStars), loading skeletons, error/empty states |
| `myshop_api` | Dio-based API client, request/response DTOs, endpoint constants, auth interceptor (token refresh), error mapping, WebSocket client for real-time tracking |
| `myshop_domain` | Repository interfaces, use cases (RequestRide, SubmitBid, ProcessPayment), business logic that is shared across both apps |

### 2.4 Backend Communication

The mobile apps communicate with the NestJS backend (in the `myshop` monorepo) via REST API and WebSockets.

- **Base URL:** Configured per environment in app config
- **Auth:** JWT access token + refresh token, stored in Flutter Secure Storage
- **Real-time:** WebSocket connection for live ride/job tracking, location broadcasting, bid notifications
- **Maps:** Google Maps SDK for rides (client + driver), Mapbox SDK for artisan navigation

---

## 3. Reference Documents

The product and engineering specifications live in the backend monorepo. Reference them via GitHub:

| Document | Location | When to Check |
|----------|----------|---------------|
| PRD v2.1 | `https://raw.githubusercontent.com/Gilmore-Tech/MyShop/main/docs/PRD.md` | Feature requirements, user flows, business rules, edge cases |
| EDD v1.1 | `https://raw.githubusercontent.com/Gilmore-Tech/MyShop/main/docs/EDD.md` | API endpoints, data models, system architecture, algorithm specs |
| DB Schema | `https://raw.githubusercontent.com/Gilmore-Tech/MyShop/main/docs/schema.sql` | Table structures, enums, relationships |
| Architecture | `https://raw.githubusercontent.com/Gilmore-Tech/MyShop/main/docs/architecture.md` | Endpoint map, cache patterns, service registry |

> **Rule:** Check the PRD for what a screen should do. Check the EDD for the API contract the screen calls. Check the schema for the data shape you'll receive.

---

## 4. Technology Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| Framework | Flutter | 3.x (latest stable) |
| Language | Dart | 3.x (latest stable) |
| State Management | Riverpod | 2.x (with code generation) |
| Navigation | GoRouter | Latest |
| API Client | Dio | Latest |
| Local Storage | Flutter Secure Storage (auth tokens), SharedPreferences (settings) | Latest |
| Maps — Rides | Google Maps Flutter SDK | Latest |
| Maps — Artisan | Mapbox GL Flutter | Latest |
| Payments | Flutterwave Flutter SDK | Latest |
| Push Notifications | Firebase Cloud Messaging (FCM) | Latest |
| Analytics | Firebase Analytics | Latest |
| Crash Reporting | Firebase Crashlytics | Latest |
| Image Handling | cached_network_image, image_picker | Latest |
| Localisation | flutter_localizations + intl (ARB files) | Built-in |
| Dependency Injection | Riverpod (ProviderScope) | Via Riverpod |
| Code Generation | build_runner, freezed, json_serializable, riverpod_generator | Latest |
| Monorepo | Melos | Latest |
| Testing | flutter_test, mocktail, integration_test | Built-in |
| Linting | flutter_lints (very_good_analysis or custom) | Latest |

---

## 5. Design System & Style Guide

### 5.1 Brand Identity

MyShop is **trustworthy, accessible, and proudly Ghanaian**. The visual language is clean and modern with warm, bold gold accents. The experience should feel as polished as Uber or Bolt but unmistakably local.

### 5.2 Color Palette (from Figma)

```dart
// Primary (from Figma)
static const primaryGold = Color(0xFFF5A623);       // Primary accent — CTAs, active tabs, tags, highlights
static const primaryGoldDark = Color(0xFFD48E1A);   // Pressed state
static const darkSlate = Color(0xFF46535D);          // Dark accent — icon backgrounds (rides), inactive nav
static const darkText = Color(0xFF161A1D);           // Primary text, headings
static const offWhite = Color(0xFFF6F7F8);           // Sheet/card backgrounds

// Semantic
static const success = Color(0xFF27AE60);            // Completed, online, verified
static const warning = Color(0xFFF2994A);            // Pending, caution, surge active
static const error = Color(0xFFEB5757);              // Error, emergency, suspended
static const info = Color(0xFF2F80ED);               // Informational, links

// Surface
static const surfaceWhite = Color(0xFFFFFFFF);       // Card surfaces
static const surfaceGrey = Color(0xFFF3F5F6);        // Subtle backgrounds, icon circles
static const textPrimary = Color(0xFF161A1D);        // Primary text (darkText)
static const textSecondary = Color(0xFF555E68);      // Secondary/caption text
static const textOnPrimary = Color(0xFFFFFFFF);      // Text on primaryGold
```

### 5.3 Typography

```dart
// Font Families (from Figma):
//   Body/Headings: Google Fonts — Roboto
//   Bottom Nav Labels: Google Fonts — Raleway
//
// Display:    Roboto 28sp Bold      — Splash, onboarding headlines
// H1:        Roboto 24sp Bold      — Screen titles
// H2:        Roboto 20sp SemiBold  — Section headers
// H3:        Roboto 18sp Bold      — Card titles, modal headers
// Body1:     Roboto 14sp SemiBold  — Primary body text, list titles
// Body2:     Roboto 12sp Regular   — Secondary text, descriptions
// Caption:   Roboto 10sp Regular   — Timestamps, hints, small labels
// Button:    Roboto 14sp Medium    — Button labels
// Overline:  Roboto 10sp Black     — Section labels (SPECIAL OFFERS, RECENT PLACES) — uppercase, 1.4 tracking
// NavLabel:  Raleway 10sp Bold/Regular — Bottom nav tab labels
```

### 5.4 Spacing Scale

```dart
// 4dp base unit
// xs:  4dp   — Icon padding, tight gaps
// sm:  8dp   — Between related elements
// md:  16dp  — Standard padding, card content padding
// lg:  24dp  — Section spacing
// xl:  32dp  — Screen edge padding (horizontal)
// xxl: 48dp  — Between major sections
```

### 5.5 Component Patterns

- **Buttons:** Rounded rectangle (8dp radius), full-width primary CTA at bottom of screens, minimum 48dp touch target
- **Cards:** 12dp radius, subtle shadow (elevation 2), offWhite or surfaceWhite background
- **Inputs:** Outlined style, 8dp radius, 48dp height, clear error states below field
- **Bottom Navigation:** 4 tabs (Client: Home, Services, Activity, Profile | Provider: Home, Earnings, Activity, Profile)
- **Loading States:** Skeleton shimmer — never use spinners
- **Empty States:** Illustration + message + CTA button
- **Error States:** Inline error with retry button — never just a red screen
- **Floating Mini-Card:** Persistent above bottom nav during active rides/jobs — 60dp height, tappable to expand

### 5.6 Accessibility (WCAG 2.1 AA)

- Minimum contrast ratio 4.5:1 for text, 3:1 for large text and UI components
- All interactive elements minimum 48dp × 48dp touch target
- Semantic labels on all interactive widgets (Semantics widget)
- Support for screen readers (TalkBack / VoiceOver)
- No information conveyed by color alone — always pair with icon or text

### 5.7 UX Principles

1. **Map-first for rides, card-first for services** — Never mix the two paradigms
2. **One action per screen** — Each screen has one clear primary CTA
3. **Progressive disclosure** — Show essentials first, details on tap
4. **Offline-graceful** — Show cached data with stale indicator, never a blank screen
5. **Ghana-context** — GHS formatting (₵), Ghana phone format (+233), Twi language parity
6. **Speed over perfection** — Optimistic UI updates, confirm in background

---

## 6. Code Conventions

### 6.1 Dart / Flutter

**File naming:** `snake_case.dart` — e.g., `ride_booking_screen.dart`, `payment_method_card.dart`

**Class naming:** `PascalCase` — e.g., `RideBookingScreen`, `PaymentMethodCard`

**Variable/method naming:** `camelCase` — e.g., `currentRide`, `submitBid()`

**Constants:** `camelCase` with `k` prefix for local, or static const in a class — e.g., `MyShopColors.primaryGold`

**Enum naming:** `PascalCase` enum, `camelCase` values — e.g., `RideStatus.inProgress`

**Private members:** Prefix with underscore — e.g., `_rideController`

### 6.2 Feature Module Structure

Every feature follows this structure inside `lib/features/{feature_name}/`:

```
features/
└── rides/
    ├── data/
    │   ├── ride_repository_impl.dart
    │   └── ride_remote_data_source.dart
    ├── domain/
    │   ├── ride_entity.dart
    │   └── ride_repository.dart
    ├── presentation/
    │   ├── screens/
    │   │   ├── ride_booking_screen.dart
    │   │   └── ride_tracking_screen.dart
    │   ├── widgets/
    │   │   ├── fare_estimate_card.dart
    │   │   └── driver_info_card.dart
    │   └── providers/
    │       ├── ride_booking_provider.dart
    │       └── ride_tracking_provider.dart
    └── rides.dart              # Barrel file exporting public API
```

### 6.3 Rules

- **Strict types always.** No `dynamic` unless absolutely necessary (e.g., JSON parsing). Use `Object?` if type is truly unknown.
- **Riverpod for all state.** No StatefulWidgets for business logic. StatefulWidget is acceptable only for animations, form controllers, and focus nodes.
- **Freezed for all models.** Every data class uses `@freezed` for immutability, copyWith, equality, and JSON serialization.
- **No print() in production code.** Use a logger package (e.g., `logger` or custom wrapper).
- **Handle all error states.** Every API call must have loading, success, and error handling in the UI.
- **Dispose all controllers.** TextEditingController, ScrollController, AnimationController — always dispose in State.dispose().
- **Const constructors everywhere possible.** Use `const` for widgets and objects that don't change.
- **Extract widgets at 80+ lines.** If a widget's build method exceeds 80 lines, extract into smaller widgets.

---

## 7. Repository Etiquette

### 7.1 Branch Strategy

```
main                          # Production-ready, protected
├── develop                   # Integration branch (PRs merge here first)
│   ├── feature/MSP-{id}-{desc}    # Feature branches
│   ├── fix/MSP-{id}-{desc}        # Bug fix branches
│   └── chore/MSP-{id}-{desc}      # Refactor, config, tooling
```

**Examples:**
- `feature/MSP-42-ride-booking-screen`
- `fix/MSP-55-map-marker-alignment`
- `chore/MSP-60-update-riverpod`

### 7.2 Commit Convention

```
type(scope): subject

Types: feat, fix, refactor, style, test, chore, docs
Scopes: client, provider, core, ui, api, domain, melos, ci

Examples:
feat(client): add ride booking screen with fare estimate
fix(provider): fix artisan bid submission validation
refactor(core): extract GHS currency formatter to shared package
test(client): add unit tests for ride booking provider
```

### 7.3 PR Process

- All PRs target `develop` (not `main`)
- All PRs reviewed and merged by Ayiks (technical lead)
- PR title follows commit convention: `feat(client): add ride booking screen`
- PR must pass: lint, analyze, tests, build verification
- PR description must include: what changed, screens affected, screenshots/recordings for UI changes

### 7.4 Code Review Checklist

- [ ] Follows feature module structure
- [ ] Riverpod providers are properly scoped (autoDispose where appropriate)
- [ ] All strings are localised (no hardcoded English or Twi)
- [ ] Loading, error, and empty states handled
- [ ] Touch targets ≥ 48dp
- [ ] Const constructors used where possible
- [ ] No print() statements
- [ ] Tests cover happy path + at least one error path

---

## 8. Constraints & Policies

### 8.1 Performance Targets

| Metric | Target |
|--------|--------|
| App cold start | < 3 seconds |
| Screen transition | < 300ms |
| API response rendering | < 500ms after response |
| Map load (Google Maps) | < 2 seconds |
| Image load (cached) | < 200ms |
| Image load (network, first time) | < 3 seconds |
| App size (APK) | < 50MB |
| App size (IPA) | < 80MB |
| Memory usage (idle) | < 150MB |
| Battery drain (1hr active use) | < 10% |

### 8.2 Offline Behaviour

- Cache last-known user profile, recent rides/jobs, saved locations
- Show cached data with "Last updated X ago" indicator when offline
- Queue actions (rating submissions, profile updates) for sync when back online
- Ride booking and artisan requests REQUIRE connectivity — show clear offline message
- Map tiles cached for last-viewed area

### 8.3 Mobile-Specific Constraints

- **Location permissions:** Required for rides (client + driver), optional for artisan clients (they can drop a pin manually)
- **Background location:** Required for drivers when online — must handle battery optimization restrictions on Android OEMs (Xiaomi, Samsung, Huawei)
- **Push notifications:** Required for all users — FCM for both platforms
- **Camera access:** Required for providers (document upload), optional for clients (job photos)
- **Phone call:** Required for emergency button (auto-dial 191)
- **Deep links:** Support for ride/job share links opening in-app

### 8.4 Security Policies

- JWT tokens stored in Flutter Secure Storage (Keychain on iOS, EncryptedSharedPreferences on Android)
- Never log tokens, passwords, or payment details
- Certificate pinning for API communication
- Biometric authentication option for app unlock (fingerprint / Face ID)
- Mask all phone numbers in UI — backend handles masking, client never sees real numbers

### 8.5 Platform-Specific Notes

- **iOS:** Minimum iOS 15.0, handle location permission changes in Settings, handle App Tracking Transparency
- **Android:** Minimum API 24 (Android 7.0), handle battery optimization whitelisting prompts, handle exact alarm permissions for scheduled job reminders

---

## 9. Testing Instructions

### 9.1 Running Tests

```bash
# Run all tests across the monorepo
melos run test

# Run tests for a specific package/app
cd apps/client_app && flutter test
cd apps/provider_app && flutter test
cd packages/myshop_core && dart test
cd packages/myshop_ui && flutter test

# Run with coverage
melos run test:coverage

# Run integration tests (requires running emulator)
cd apps/client_app && flutter test integration_test/
```

### 9.2 Test Structure

```
test/
├── features/
│   └── rides/
│       ├── data/
│       │   └── ride_repository_impl_test.dart
│       ├── presentation/
│       │   ├── providers/
│       │   │   └── ride_booking_provider_test.dart
│       │   └── screens/
│       │       └── ride_booking_screen_test.dart
│       └── domain/
│           └── request_ride_usecase_test.dart
├── helpers/
│   ├── pump_app.dart          # Helper to wrap widgets with providers, theme, localisation
│   ├── mock_providers.dart    # Common Riverpod provider overrides
│   └── test_data.dart         # Shared test fixtures
└── golden/                    # Golden test files (if using)
```

### 9.3 Coverage Requirements

| Package/App | Minimum Coverage |
|-------------|-----------------|
| myshop_core | 90% |
| myshop_domain | 85% |
| myshop_api | 80% |
| myshop_ui | 70% (widget tests) |
| client_app | 75% |
| provider_app | 75% |

### 9.4 Required Test Scenarios

For every new screen:
- Widget renders without error
- Loading state displays skeleton
- Error state displays error widget with retry
- Empty state displays empty widget with CTA
- Primary CTA triggers correct provider action
- Navigation to/from screen works correctly

For every new provider:
- Initial state is correct
- Success state updates correctly
- Error state handled correctly
- Loading state transitions correctly

---

## 10. Local Development Setup

### 10.1 Prerequisites

```
Flutter SDK: 3.x (latest stable channel)
Dart SDK: 3.x (bundled with Flutter)
Melos: latest (dart pub global activate melos)
Xcode: 15+ (for iOS builds)
Android Studio: latest (for Android builds + emulators)
CocoaPods: latest (for iOS dependencies)
Java: 17 (for Android Gradle)
```

### 10.2 First-Time Setup

```bash
# 1. Clone the repo
git clone git@github.com:Gilmore-Tech/MyShop-mobile.git
cd myshop-mobile

# 2. Install Melos globally
dart pub global activate melos

# 3. Bootstrap the monorepo (installs all dependencies)
melos bootstrap

# 4. Generate code (Freezed models, Riverpod providers, JSON serialisation)
melos run generate

# 5. Copy environment config
cp .env.example .env.local
# Edit .env.local with your API base URL, Google Maps key, Mapbox token, etc.

# 6. Run the client app
cd apps/client_app
flutter run

# 7. Run the provider app (in a separate terminal)
cd apps/provider_app
flutter run
```

### 10.3 Useful Commands

```bash
melos bootstrap          # Install deps + link packages
melos run generate       # Run build_runner across all packages
melos run test           # Run all tests
melos run analyze        # Run dart analyze across all packages
melos run format         # Check formatting
melos run format:fix     # Fix formatting
melos clean              # Clean all packages
melos run test:coverage  # Run tests with coverage
```

---

## 11. Deployment

### 11.1 Environments

| Environment | Backend URL | Trigger | Notes |
|-------------|------------|---------|-------|
| Development | `http://localhost:3000` | Local | Local backend via docker-compose |
| Staging | `https://staging-api.myshop.com.gh` | Merge to `develop` | CI builds + TestFlight / Internal Track |
| Production | `https://api.myshop.com.gh` | Tag release on `main` | App Store + Play Store submission |

### 11.2 Build & Release

```bash
# iOS (staging)
flutter build ios --release --flavor staging --dart-define=ENV=staging

# iOS (production)
flutter build ios --release --flavor production --dart-define=ENV=production

# Android (staging)
flutter build appbundle --release --flavor staging --dart-define=ENV=staging

# Android (production)
flutter build appbundle --release --flavor production --dart-define=ENV=production
```

---

## 12. Common Tasks

### 12.1 Adding a New Screen

1. Identify which app (client or provider) and which feature module
2. Create screen file in `features/{feature}/presentation/screens/`
3. Create any new widgets in `features/{feature}/presentation/widgets/`
4. Create Riverpod providers in `features/{feature}/presentation/providers/`
5. Add route to GoRouter configuration in `app/router.dart`
6. Add localisable strings to ARB files (`lib/l10n/`)
7. Write widget test + provider test
8. Update barrel file (`features/{feature}/{feature}.dart`)

### 12.2 Adding a New Shared Widget

1. Create widget in `packages/myshop_ui/lib/src/widgets/`
2. Use only MyShop theme tokens (colors, typography, spacing from `MyShopTheme`)
3. Add to barrel export in `packages/myshop_ui/lib/myshop_ui.dart`
4. Write widget test in `packages/myshop_ui/test/`
5. Run `melos bootstrap` to ensure both apps can see it

### 12.3 Adding a New API Endpoint Call

1. Add endpoint constant in `packages/myshop_api/lib/src/endpoints.dart`
2. Create request/response DTOs in `packages/myshop_api/lib/src/dto/`
3. Add method to the relevant API service class
4. Create or update repository implementation in the feature's `data/` layer
5. Create or update use case in `packages/myshop_domain/` if shared, or feature's `domain/` if app-specific
6. Write tests for the repository and use case

### 12.4 Adding a New Model

1. Create Freezed model in `packages/myshop_core/lib/src/models/`
2. Add `@freezed` annotation, define fields, add `fromJson` factory
3. Run `melos run generate` to generate code
4. Export from `packages/myshop_core/lib/myshop_core.dart`
5. Write test verifying JSON serialisation round-trip

### 12.5 Adding a New Localisation String

1. Add key to `lib/l10n/app_en.arb` (English) and `lib/l10n/app_tw.arb` (Twi)
2. Run `flutter gen-l10n` (or `melos run generate`)
3. Use in widget: `AppLocalizations.of(context)!.yourKeyName`
4. Never hardcode user-facing strings — always use ARB keys

---

## 13. Living Documentation Rules

| Document | Location | Update When |
|----------|----------|-------------|
| This CLAUDE.md | Repo root | New package added, architecture change, convention change |
| README.md | Repo root | Setup steps change, new prerequisites |

**After every completed feature:**
1. Verify CLAUDE.md Section 2 reflects any new packages or structural changes
2. Verify screen counts are still accurate
3. Commit doc updates in the same PR as the feature

---

## 14. Plugins

| Plugin | File | Read When |
|--------|------|-----------|
| Flutter Design System | `.claude/plugins/flutter-design-system.md` | Building any screen or widget — colors, typography, spacing, component patterns in Dart/Flutter code |
| Flutter Dev Streamline | `.claude/plugins/flutter-dev-streamline.md` | Implementing features — Riverpod patterns, Dio patterns, GoRouter patterns, Freezed templates, error handling |

**Usage rule:** Always read the design system plugin before building UI. Always read the dev streamline plugin before writing providers, repositories, or API calls.

---

## 15. Slash Commands & Agents

### Commands

| Command | File | When to Use |
|---------|------|-------------|
| `/new-screen` | `.claude/commands/new-screen.md` | Scaffolding a new screen with all required files (screen, widgets, providers, tests, route) |
| `/build-runner` | `.claude/commands/build-runner.md` | Running code generation after model or provider changes |
| `/commit` | `.claude/commands/commit.md` | Creating a conventional commit with proper scope |

### Agents

| Agent | File | Specialisation |
|-------|------|---------------|
| Flutter UI Agent | `.claude/agents/flutter-ui.md` | Builds screens and widgets from Figma designs, enforces design system |
| Mobile Testing Agent | `.claude/agents/mobile-testing.md` | Writes widget tests, provider tests, integration tests |

---

## 16. MCP Servers

| MCP | Purpose | When It Helps |
|-----|---------|---------------|
| Figma | Pull design context (layout, spacing, colors, components) from Figma frames | Building any screen — get exact design specs from the Figma file |
| GitHub | Create issues, manage PRs, check CI status | Sprint planning, PR management, issue creation |
| Filesystem | Read/write project files | Always available for file operations |

**Setup:** See `.claude/mcp/mcp-config.json` — authenticate Figma with your Figma account credentials (separate from Claude account).
