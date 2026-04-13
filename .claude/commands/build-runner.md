# /build-runner — Run Code Generation

## Usage
```
/build-runner           # Run across entire monorepo
/build-runner [package] # Run for specific package only
```

## What This Command Does

1. **Runs `build_runner` to generate code for:**
   - Freezed models (`.freezed.dart` + `.g.dart` files)
   - Riverpod providers (`.g.dart` files from `@riverpod` annotations)
   - JSON serialization (`fromJson` / `toJson`)
   - Any other build_runner generators in use

2. **Execution:**

```bash
# Full monorepo generation
melos run generate

# Which runs in each package/app:
# dart run build_runner build --delete-conflicting-outputs

# Specific package only
cd packages/myshop_core && dart run build_runner build --delete-conflicting-outputs
```

3. **Post-generation checks:**
   - Runs `melos run analyze` to verify no analysis errors introduced
   - Reports any generation failures with the specific package and error

## When to Run

- After creating or modifying any `@freezed` model
- After creating or modifying any `@riverpod` annotated provider
- After adding `@JsonSerializable` to a class
- After changing any field in a Freezed model
- After adding new enum values used in JSON serialization

## Troubleshooting

If generation fails:
1. Check for syntax errors in the annotated file
2. Ensure all imports are correct (part directives match)
3. Delete `.dart_tool` and retry: `melos clean && melos bootstrap && melos run generate`
4. Check that `build.yaml` (if it exists) doesn't have conflicting configurations
