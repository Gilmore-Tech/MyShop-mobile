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

Tag a version and push — GitHub Actions builds signed AABs + IPAs and uploads them to Play Console Internal Testing + TestFlight Internal. You smoke-test there, then click "Promote" once per release.

```bash
$EDITOR apps/client/pubspec.yaml apps/provider/pubspec.yaml  # bump version
git commit -am "chore(release): v1.0.1"
git tag v1.0.1 && git push --tags
```

**One-time setup** (keystore, Apple Developer, Fastlane Match, GitHub Secrets): see [docs/release-setup.md](docs/release-setup.md). Budget 3–6 hours mostly waiting on Apple's UI.

## Apps

| App | Bundle ID | Store Listing | Description |
|-----|-----------|---------------|-------------|
| MyShop | com.gilmoretechnologies.myshop.client | Separate listing | Consumers: book rides, hire artisans |
| MyShop Provider | com.gilmoretechnologies.myshop.provider | Separate listing | Drivers & artisans: accept jobs, earn |

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
