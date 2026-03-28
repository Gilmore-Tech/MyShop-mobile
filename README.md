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

# Run Client App
cd apps/client && flutter run

# Run Provider App
cd apps/provider && flutter run
```

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
