# MyShop Mobile — Ride-Hailing & Artisan Marketplace

Flutter monorepo containing the Client App and Provider App for the MyShop platform by Gilmore Technologies.

## Structure

```
myshop-mobile/
├── apps/
│   ├── client/              # Consumer-facing app (book rides & artisan services)
│   └── provider/            # Provider app (drivers & artisans)
├── packages/
│   ├── api_client/          # HTTP & WebSocket API services
│   ├── shared_models/       # Data models, enums, DTOs (Freezed)
│   ├── shared_ui/           # Theme, design tokens, reusable widgets
│   └── shared_utils/        # Phone format, money helpers, validators
├── docs/
│   └── setup-walkthrough.md # Developer setup guide
└── melos.yaml               # Workspace configuration
```

## Quick Start

```bash
# Prerequisites: Flutter 3.27+, Dart 3.6+, Melos
dart pub global activate melos

# Bootstrap all packages
melos bootstrap

# Run via tool/run.sh — passes API keys from .env.dev
cp .env.dev.example .env.dev    # one-time, then fill in real values
tool/run.sh client              # runs apps/client
tool/run.sh provider            # runs apps/provider
```

Plain `flutter run` works but produces an app with empty Google Maps + Mapbox keys; autocomplete and maps will fail silently. Use `tool/run.sh` unless you've passed the `--dart-define`s manually.

## Releasing

Releases are explicit GitHub Actions dispatches from the reviewed `main` commit.
First check the highest private build number for the selected app in both store
consoles and choose a larger unused number. Dispatch both platform workflows
with that same app selection and build number; they upload only to Play Console
Internal Testing and TestFlight Internal. Smoke-test there before manually
promoting either store build.

```bash
RELEASE_BUILD_NUMBER=<unused-number-above-both-private-store-values>
RELEASE_SOURCE_COMMIT=$(git rev-parse origin/main)
gh workflow run release-android.yml --ref main \
  -f app=both -f build_number="$RELEASE_BUILD_NUMBER" \
  -f expected_source_sha="$RELEASE_SOURCE_COMMIT"
gh workflow run release-ios.yml --ref main \
  -f app=both -f build_number="$RELEASE_BUILD_NUMBER" \
  -f expected_source_sha="$RELEASE_SOURCE_COMMIT"
```

Do not create a release tag: tags do not trigger these workflows. For exact
source/build gates and **one-time setup** (keystore, Apple Developer, every
Provider extension profile, Fastlane Match, and GitHub Secrets), see
[docs/release-setup.md](docs/release-setup.md).

## Apps

| App | Bundle ID | Store Listing | Description |
|-----|-----------|---------------|-------------|
| MyShop | com.gilmoretech.myshopclient | Separate listing | Consumers: book rides, hire artisans |
| MyShop Provider | com.gilmoretech.myshopprovider | Separate listing | Drivers & artisans: accept jobs, earn |

## Tech Stack

| Category | Technology |
|----------|-----------|
| Framework | Flutter 3.27+ / Dart 3.6+ |
| State Management | Riverpod 2 + code generation |
| Navigation | GoRouter |
| Networking | Dio + Socket.IO |
| Maps (Rides) | Google Maps Flutter |
| Maps (Artisan) | Mapbox Flutter |
| Payments | Flutterwave Flutter SDK |
| Push | Firebase Cloud Messaging |
| Storage | flutter_secure_storage + SharedPreferences |
| Serialization | Freezed + json_serializable |
| Monorepo | Melos |
