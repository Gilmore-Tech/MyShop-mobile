# /new-screen — Scaffold a New Flutter Screen

## Usage
```
/new-screen [app] [feature] [screen_name]

Examples:
/new-screen client rides ride_booking
/new-screen client services service_request
/new-screen provider driver ride_request
/new-screen provider artisan job_bidding
```

## What This Command Does

1. **Validates inputs:**
   - App must be `client` or `provider`
   - Feature must be an existing feature module or creates a new one
   - Screen name must be snake_case

2. **Creates the following files:**

```
apps/{app}_app/lib/features/{feature}/
├── presentation/
│   ├── screens/
│   │   └── {screen_name}_screen.dart       # ConsumerWidget with loading/error/data states
│   ├── widgets/
│   │   └── .gitkeep                        # Placeholder for extracted widgets
│   └── providers/
│       └── {screen_name}_provider.dart     # Riverpod provider stub
├── data/
│   └── .gitkeep                            # Placeholder for repository impl
├── domain/
│   └── .gitkeep                            # Placeholder for repository interface
└── {feature}.dart                          # Barrel file
```

3. **Screen file template includes:**
   - ConsumerWidget with `const` constructor
   - `ref.watch` on the screen's provider
   - `.when()` pattern with loading skeleton, error state, and data rendering
   - Localisation import
   - Design system imports (MyShopColors, MyShopTypography, MyShopSpacing)

4. **Provider file template includes:**
   - `@riverpod` annotation
   - `AsyncValue` return type
   - Stub `build()` method with TODO

5. **Updates GoRouter:**
   - Adds route entry to `apps/{app}_app/lib/app/router.dart`
   - Route path follows convention: `/{feature}/{screen_name}` or `/{feature}` for index screens

6. **Creates test stubs:**
```
apps/{app}_app/test/features/{feature}/
├── presentation/
│   ├── screens/
│   │   └── {screen_name}_screen_test.dart  # Widget test with pumpApp
│   └── providers/
│       └── {screen_name}_provider_test.dart # Provider test stub
```

7. **Reminds developer to:**
   - Add localisation strings to `app_en.arb` and `app_tw.arb`
   - Run `melos run generate` for Riverpod codegen
   - Read the design system plugin before implementing the UI
   - Check PRD for the feature requirements
   - Check EDD for the API contract

## Post-Scaffold Steps

After running this command:
```bash
melos run generate     # Generate Riverpod provider code
melos run analyze      # Verify no analysis errors
```
