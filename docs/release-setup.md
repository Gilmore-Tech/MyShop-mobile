# Release Setup — MyShop Mobile

> **One-time setup runbook.** Follow each section in order. After this is done, shipping a release is `git tag v1.0.X && git push --tags` and the GitHub Actions workflow handles the rest, dropping the build into Play Console Internal Testing + TestFlight Internal. You smoke-test there, then click "Promote" once per release.

This document covers:
- Android upload keystore + Play Console
- Apple Developer + Fastlane Match for iOS signing
- The exhaustive list of GitHub Secrets to paste
- A first-build smoke test
- The day-to-day release flow once it's wired
- Key rotation when something leaks
- Promoting from Internal → Production / App Review

Estimated one-time work on your side: **3–6 hours**, mostly waiting on Apple's UI. After that, releases are free.

---

## Part 0 — Big picture

```
.env.prod (your laptop only)             GitHub Secrets (CI)
  GOOGLE_MAPS_API_KEY_CLIENT_ANDROID →   GOOGLE_MAPS_API_KEY_CLIENT_ANDROID
  GOOGLE_MAPS_API_KEY_CLIENT_IOS     →   GOOGLE_MAPS_API_KEY_CLIENT_IOS
  GOOGLE_MAPS_API_KEY_PROVIDER_ANDROID → GOOGLE_MAPS_API_KEY_PROVIDER_ANDROID
  GOOGLE_MAPS_API_KEY_PROVIDER_IOS   →   GOOGLE_MAPS_API_KEY_PROVIDER_IOS
  MAPS_ANDROID_CERT_SHA1_CLIENT      →   MAPS_ANDROID_CERT_SHA1_CLIENT
  MAPS_ANDROID_CERT_SHA1_PROVIDER    →   MAPS_ANDROID_CERT_SHA1_PROVIDER
  API_BASE_URL                       →   API_BASE_URL
  MAPBOX_ACCESS_TOKEN                →   MAPBOX_ACCESS_TOKEN
  MAPBOX_STYLE_URL                   →   MAPBOX_STYLE_URL
                                    KEYSTORE_BASE64
                                    KEYSTORE_PASSWORD
                                    KEY_ALIAS
                                    KEY_PASSWORD
                                    MATCH_PASSWORD
                                    MATCH_REPO_DEPLOY_KEY
                                    APP_STORE_CONNECT_API_KEY_*
                                    PLAY_SERVICE_ACCOUNT_JSON
```

Every value above is consumed by `tool/build.sh` or the workflow YAML. The build pipeline itself doesn't care whether values come from a file on your laptop or from GitHub Secrets — same `tool/build.sh`, same outputs.

---

## Part 1 — Android signing (keystore + Play Console)

**Time: 1–2 hours, mostly Play Console UI**

### 1.1 Generate the upload keystore

You'll create one keystore with two key entries (one per app). Keeping them in a single `.jks` is fine and simplifies the CI matrix.

```bash
cd ~/secure   # or anywhere outside the repo
keytool -genkey -v \
  -keystore myshop-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias client-upload

keytool -genkey -v \
  -keystore myshop-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias provider-upload
```

You'll be prompted for:
- **Keystore password** — long random string. Save it in a password manager.
- **Key password** — can match the keystore password (fewer things to memorise).
- **Distinguished name** — `CN=Gilmore Technologies, OU=Mobile, O=Gilmore Technologies, L=Kumasi, ST=Ashanti, C=GH` or similar. Doesn't need to be exact; users never see this.

**Critical:** the keystore is **un-recoverable** if lost — Google Play uses it to identify your app's identity forever. Back it up in two places (password manager + encrypted external drive). If you lose it, you cannot publish new versions of the same app; you have to publish a new app with a new package name. Apple is more forgiving here; Google is not.

### 1.2 Wire signing into both apps

Edit each app's `android/app/build.gradle.kts` (or `build.gradle`) — they currently sign release builds with the debug key, which Play Console will reject.

**For `apps/client/android/app/build.gradle.kts`:**

```kotlin
// Top of file, after existing imports:
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // ... existing config ...

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            // ... existing release flags ...
        }
    }
}
```

The Gradle file reads from `apps/client/android/key.properties` — a small file that points at the keystore and holds the passwords. **This file is gitignored.**

Locally, create `apps/client/android/key.properties`:

```properties
storePassword=<the keystore password>
keyPassword=<the key password>
keyAlias=client-upload
storeFile=/Users/ayiks/secure/myshop-upload.jks
```

Repeat for `apps/provider/android/`:
- Apply the same `build.gradle.kts` change.
- Create `apps/provider/android/key.properties` with `keyAlias=provider-upload`.

In CI, the workflow regenerates these files from secrets before building.

### 1.3 Get the SHA-1 fingerprints

You need two SHA-1 values per app:
- **Upload key** (from the keystore you just made)
- **Play App Signing key** (Google generates this after your first upload)

For the upload key:
```bash
keytool -list -v -keystore ~/secure/myshop-upload.jks -alias client-upload
keytool -list -v -keystore ~/secure/myshop-upload.jks -alias provider-upload
```

Copy the `SHA1:` line for each. You'll add both fingerprints to your Google Maps key restriction in Part 4.

### 1.4 Create the apps in Play Console

1. Go to <https://play.google.com/console>. If you don't have a developer account, sign up ($25 one-time).
2. Create app → **MyShop Client** → Free / App / Other regulations as appropriate.
3. Set up store presence: privacy policy URL, content rating questionnaire, target audience, app category (Maps & Navigation), etc. (~30 min of forms; Play won't let you upload an AAB until enough fields are filled.)
4. Production track → Countries → choose Ghana (only) for the pilot.
5. **Internal Testing track** → create → add yourself + reviewers as testers via email. This is where every CI build will land first.
6. Repeat steps 2–5 for **MyShop Provider**.

Don't upload anything yet — wait until secrets are in place (Part 5).

### 1.5 Service account for CI uploads

The GitHub Actions workflow uploads to Play Console via the Google Play Developer API. You need a service account with `Release manager` permissions:

1. Go to <https://console.cloud.google.com>.
2. Create a new project (or pick an existing one). Name it `myshop-play-publisher` or similar.
3. APIs & Services → Library → enable **Google Play Android Developer API**.
4. APIs & Services → Credentials → Create Credentials → Service account.
   - Name: `play-publisher`.
   - Skip role granting at the project level — Play Console handles its own permissions.
5. Click the service account → Keys → Add Key → JSON. Download the file (it's a one-shot — save it to your password manager too).
6. Back in **Play Console** → Setup → API access → "Link Cloud project" → pick the one above. Then in the service-account list, click "Manage Play Console permissions" → grant **Admin (all permissions)** for now (you can tighten to "Release manager" once everything works).
7. The downloaded JSON file is what becomes the `PLAY_SERVICE_ACCOUNT_JSON` GitHub secret in Part 4.

---

## Part 2 — iOS signing (Apple Developer + Fastlane Match)

**Time: 2–4 hours. Apple's UI is slow.**

### 2.1 Apple Developer Program account

If you don't have one: <https://developer.apple.com/programs/>, $99/yr, takes 1–3 days to approve. Do this first.

Enroll as an Organization (Gilmore Technologies) if possible — it makes co-publishing with employees / contractors much easier later. Individual accounts work for a solo pilot but you can't add team members without converting.

### 2.2 App Store Connect entries

In <https://appstoreconnect.apple.com>:

1. My Apps → + → New App → iOS:
   - Name: **MyShop Client** (must be globally unique on the App Store; if taken, try **MyShop Ghana** or **MyShop Rides**).
   - Bundle ID: `com.gilmoretech.myshopclient` (or whatever you've already used in `apps/client/ios/Runner.xcodeproj`).
   - SKU: any string, e.g. `myshop-client-v1`.
   - User access: Full Access.
2. Repeat for **MyShop Provider** with bundle ID `com.gilmoretech.myshopprovider`.

Bundle IDs must match what's in each `apps/<app>/ios/Runner.xcodeproj/project.pbxproj`. Check with:

```bash
grep -m1 PRODUCT_BUNDLE_IDENTIFIER apps/client/ios/Runner.xcodeproj/project.pbxproj
grep -m1 PRODUCT_BUNDLE_IDENTIFIER apps/provider/ios/Runner.xcodeproj/project.pbxproj
```

If they don't match what you typed in App Store Connect, update either the Xcode project or the App Store Connect entry to align — same string everywhere.

### 2.3 App Store Connect API Key (for CI uploads)

CI uploads via `apple-actions/upload-testflight-build`, which authenticates with an API key (no Apple ID password, no 2FA prompts in CI):

1. App Store Connect → Users and Access → **Keys** → App Store Connect API → Generate API Key.
2. Name: `myshop-ci-uploader`. Access: **App Manager**.
3. Download the `.p8` file (also a one-shot — save it).
4. Copy:
   - **Issuer ID** (top of the Keys page, UUID format) → becomes `APP_STORE_CONNECT_API_ISSUER_ID` secret.
   - **Key ID** (next to the key name) → becomes `APP_STORE_CONNECT_API_KEY_ID`.
   - Contents of the `.p8` file → becomes `APP_STORE_CONNECT_API_KEY_P8` (paste the whole `-----BEGIN PRIVATE KEY-----...` block).

### 2.4 Fastlane Match — one-time setup

Match stores your signing cert + provisioning profiles in a private Git repo, encrypted with one passphrase. CI checks out that repo on every build, decrypts, installs into a temporary keychain, then signs. It's the canonical solution and removes all "expired cert breaks Friday's build" pain.

On your laptop:

```bash
# Install
brew install fastlane

# Initialise inside the mobile repo (creates fastlane/ directories per app)
cd apps/client/ios
fastlane match init

# When prompted, choose: git, then enter the URL of a NEW PRIVATE GitHub repo
# you'll create just for this — e.g. github.com/Gilmore-Tech/myshop-match (private).
# Match needs full read/write on this repo.

# Generate App Store certs + profiles (one command per app)
fastlane match appstore --app_identifier com.gilmoretech.myshopclient

cd ../../provider/ios
fastlane match appstore --app_identifier com.gilmoretech.myshopprovider
```

You'll be prompted for:
- Your Apple ID and password (one-time; Match caches a session in Keychain).
- A **Match encryption passphrase** — pick a strong one, save in password manager. This becomes the `MATCH_PASSWORD` GitHub secret.

Match writes the encrypted certs + profiles to your private Git repo. CI will check that repo out — so you also need a **deploy key** with read access to it (Part 4).

### 2.5 Push the match repo's deploy key into GitHub Secrets

Generate an SSH keypair just for CI's access to the match repo:

```bash
ssh-keygen -t ed25519 -f ~/secure/myshop-match-deploy-key -C "myshop-match-ci" -N ""
```

- Public key (`myshop-match-deploy-key.pub`) → GitHub → your `myshop-match` private repo → Settings → Deploy keys → Add deploy key → **read-only** is fine for CI checkout.
- Private key (`myshop-match-deploy-key`, no `.pub`) → becomes `MATCH_REPO_DEPLOY_KEY` GitHub secret (paste the entire file contents including `-----BEGIN OPENSSH PRIVATE KEY-----`).

---

## Part 3 — Google Maps key restrictions

**Time: 30 minutes**

Create four Google Maps API keys — one per app and platform. Google Cloud
allows one application-restriction type per key, so an Android-restricted key
cannot also carry an iOS bundle restriction.

1. <https://console.cloud.google.com> → APIs & Services → Credentials.
2. Create `myshop-client-android-maps` and restrict it to Android package
   `com.gilmoretech.myshopclient`. Add both the upload SHA-1 and Play App
   Signing SHA-1. Restrict APIs to the Android SDK and required web services.
3. Create `myshop-client-ios-maps`, restrict it to iOS bundle
   `com.gilmoretech.myshopclient`, and allow the iOS SDK plus required web
   services.
4. Repeat steps 2–3 for `com.gilmoretech.myshopprovider`.

You'll come back here once after first Play upload to add the Play App Signing SHA-1 — without it, Google Maps + Places will fail silently in production-track builds that have been re-signed by Play.

For **Mapbox**: create a public token at <https://account.mapbox.com/access-tokens/> with scopes `styles:read`, `fonts:read`, `datasets:read`, `vision:read`. URL restriction can be added there too.

---

## Part 4 — GitHub Secrets to paste

Go to **GitHub → your repo → Settings → Secrets and variables → Actions → New repository secret**. Paste each value:

| Secret name | What goes in it |
|---|---|
| `GOOGLE_MAPS_API_KEY_CLIENT_ANDROID` | Android-restricted client Maps key |
| `GOOGLE_MAPS_API_KEY_CLIENT_IOS` | iOS-restricted client Maps key |
| `GOOGLE_MAPS_API_KEY_PROVIDER_ANDROID` | Android-restricted provider Maps key |
| `GOOGLE_MAPS_API_KEY_PROVIDER_IOS` | iOS-restricted provider Maps key |
| `MAPS_ANDROID_CERT_SHA1_CLIENT` | Client Play App Signing SHA-1 |
| `MAPS_ANDROID_CERT_SHA1_PROVIDER` | Provider Play App Signing SHA-1 |
| `API_BASE_URL` | Production API URL, including `/v1` |
| `MAPBOX_ACCESS_TOKEN` | Mapbox public token |
| `MAPBOX_STYLE_URL` | `mapbox://styles/<account>/<style-id>` |
| `KEYSTORE_BASE64` | `base64 -i ~/secure/myshop-upload.jks` output, single line |
| `KEYSTORE_PASSWORD` | Keystore password from §1.1 |
| `KEY_PASSWORD` | Key password from §1.1 (often same as keystore) |
| `KEY_ALIAS_CLIENT` | `client-upload` |
| `KEY_ALIAS_PROVIDER` | `provider-upload` |
| `PLAY_SERVICE_ACCOUNT_JSON` | Entire JSON file contents from §1.5 |
| `MATCH_PASSWORD` | Match encryption passphrase from §2.4 |
| `MATCH_REPO_URL` | `git@github.com:Gilmore-Tech/myshop-match.git` (SSH form) |
| `MATCH_REPO_DEPLOY_KEY` | Contents of the private deploy key from §2.5 |
| `APP_STORE_CONNECT_API_ISSUER_ID` | From §2.3 |
| `APP_STORE_CONNECT_API_KEY_ID` | From §2.3 |
| `APP_STORE_CONNECT_API_KEY_P8` | Whole `.p8` file contents from §2.3 |

To base64-encode the keystore:

```bash
base64 -i ~/secure/myshop-upload.jks | tr -d '\n' | pbcopy
# Paste into GitHub Secrets
```

Double-check **no trailing newline** in `KEYSTORE_BASE64` — `tr -d '\n'` handles it.

---

## Part 5 — First green build (smoke test)

Before tagging an actual release, verify each piece works:

### 5.1 Local — `.env.prod` produces a release build

```bash
cd /Users/ayiks/Desktop/ayiks/gilmore/myshop-mobile
cp .env.dev.example .env.prod
# Edit .env.prod with REAL production keys (the ones from §3)
git fetch origin
git checkout main
git pull --ff-only origin main
export RELEASE_SOURCE_COMMIT="$(git rev-parse HEAD)"
export RELEASE_BUILD_NUMBER=<greater-than-both-console-values-and-23>
tool/build.sh client android
```

Expected end:
```
→ wrote release Maps configuration and source provenance to apps/client/android/gradle.properties
→ flutter build appbundle (release) for apps/client with production dart-defines
✓ Built apps/client/build/app/outputs/bundle/release/app-release.aab
Release artifact verified: client/android 1.4.1+<build> @ <reviewed-main-sha>
```

The final line is mandatory: it binds the package ID, marketing/build version,
reviewed source SHA, pinned upload identity, production endpoint and absence of
the staging endpoint to that exact AAB. Sideload the separately verified APK or
upload the AAB to Play Console Internal to confirm map and autocomplete behavior
before production promotion.

### 5.2 Local — iOS Match smoke test

```bash
cd apps/client/ios
fastlane match appstore --readonly
```

`--readonly` means "just decrypt the existing repo contents, don't generate new certs". If this command works on your laptop, it'll work in CI too.

### 5.3 CI — first dry-run

Push a throwaway pre-release tag and confirm the workflow doesn't error:

```bash
git tag v0.99.0-rc.1
git push origin v0.99.0-rc.1
```

Watch the GitHub Actions run. Expected:
- `release-android.yml` produces 2 AABs and uploads them to Play Console Internal Testing.
- `release-ios.yml` produces 2 IPAs and uploads them to TestFlight Internal.
- TestFlight build appears within ~10 minutes; Play Console Internal Testing within ~30 minutes (first-ever upload can take longer for Play to process).

If anything fails, the most likely culprit is:
- **Android signing:** `KEYSTORE_BASE64` has a trailing newline. Re-paste.
- **Match decrypt fails:** `MATCH_PASSWORD` typo OR deploy key doesn't have read access to the match repo.
- **Play upload fails:** service account doesn't have Admin permissions OR Play Console app hasn't passed its initial review for Internal Testing track (Play sometimes requires a single manual upload before API uploads work).

Delete the throwaway tag once done:

```bash
git push --delete origin v0.99.0-rc.1
git tag -d v0.99.0-rc.1
```

---

## Part 6 — Day-to-day release flow

Once Part 5 passes, every release is:

```bash
# 1. Confirm the highest private build number for this app in BOTH App Store
#    Connect and Play Console. Choose a number greater than both values. Client
#    and provider are checked independently; never infer a console value.

# 2. Build only the clean, reviewed origin/main commit that already passed
#    staging. Build 23 is treated as occupied because signed/upload-attempted
#    artifacts exist locally; still check both private store consoles because
#    either may contain a higher number.
git fetch origin
git checkout main
git pull --ff-only origin main
export RELEASE_SOURCE_COMMIT="$(git rev-parse HEAD)"
export RELEASE_BUILD_NUMBER=<greater-than-both-console-values-and-23>
tool/build.sh client android
tool/build.sh client ios
tool/build.sh provider android
tool/build.sh provider ios

# 3. Each build must end with "Release artifact verified". Fresh iOS archives
#    must also report their exact app-owned and vendor dSYM state. The historical
#    +23 files and lone Provider +24 APK are quarantined and must not be reused.
#
# 4. Tag only after the exact artifacts pass internal/device QA. Do not commit
#    after building: the tag and artifacts must identify RELEASE_SOURCE_COMMIT.
test "$(git rev-parse HEAD)" = "$RELEASE_SOURCE_COMMIT"
test -z "$(git status --porcelain --untracked-files=all)"
git tag v1.4.1
git push origin v1.4.1
```

The workflows fire on tag push, produce signed builds, upload to Internal tracks. You receive:
- **TestFlight Internal** email within ~5 min (for example, "Build 1.4.1 (21) is now available").
- **Play Console Internal Testing** link within ~30 min (or longer first time).

Smoke-test on internal devices.

### 6.1 Promoting to Production / submitting for App Review

When you've smoke-tested and want to publish:

**iOS (TestFlight Internal → App Review → App Store):**
- App Store Connect → My Apps → MyShop Client → TestFlight tab.
- Find your build → "Submit for External Testing" if you want a broader beta, OR
- App Store tab → "+ Version" → fill release notes → "Submit for Review".
- Apple Review: 24–48 hours usually.
- Once approved, you choose manual release OR auto-release.

**Android (Internal Testing → Production):**
- Play Console → Internal testing → your latest release → "Promote release" → Production.
- Add release notes → Review → Start rollout.
- Play Review: usually a few hours, sometimes 1–2 days for first releases.
- Use **staged rollout** (start at 10%) to limit blast radius if a crash shows up.

Both promotions are deliberately manual. That's the safety gate you wanted instead of direct-to-prod CI.

---

## Part 7 — Key rotation

When (not if) you need to rotate something:

| Key | When to rotate | How |
|---|---|---|
| Google Maps key | Suspected leak, or every 90 days as hygiene | Create new key in Cloud Console with same restrictions → swap value in `.env.prod` AND `GOOGLE_MAPS_API_KEY_*` secret → tag a new release → delete old key after the new build is in production for 48h. |
| Mapbox token | Same | Same pattern — create new token with same restrictions, swap value, tag, delete old. |
| Android upload keystore | **NEVER** if you can help it. Loss is unrecoverable. | If genuinely lost: contact Google Play support; they'll issue a one-time reset within 14 days. After that you publish a new app. |
| iOS distribution cert | Auto every year (Match expiry) | `fastlane match nuke distribution && fastlane match appstore` per app. Update `MATCH_PASSWORD` only if you change the passphrase. |
| App Store Connect API key | Same — Apple expires them annually | Generate fresh in App Store Connect, update the three `APP_STORE_CONNECT_*` secrets. |

---

## Part 8 — Common failure modes

**"Your build was not accepted" from Play Console** — most often signing mismatch. The AAB has to be signed by the same upload key that produced the first AAB Play ever saw. If you regenerated the keystore, Play will reject. Solution: use Play's signing-key reset (one-time, 14-day waiting period) OR ship as a new app with new package name.

**"Invalid binary" from App Store Connect** — usually a missing entitlement / Info.plist key. Most common: missing `NSLocationAlwaysAndWhenInUseUsageDescription` for the driver app's background location. Add to `apps/provider/ios/Runner/Info.plist`.

**Map shows but autocomplete returns empty** — Google Maps key not enabled for Places API. Cloud Console → API restrictions → make sure Places API is in the allowed list.

**Crashes on first launch with `Default FirebaseApp is not initialized`** — `google-services.json` (Android) or `GoogleService-Info.plist` (iOS) missing or wrong bundle ID. Re-download from Firebase Console for the production app entry.

**"Upload failed: certificate has expired"** — Match cert needs regeneration. `fastlane match nuke distribution && fastlane match appstore`.

---

## Appendix: file locations referenced

| What | Where |
|---|---|
| `tool/build.sh` | repo root |
| `tool/run.sh` | repo root (dev only) |
| `.env.dev.example` | repo root (committed) |
| `.env.dev` | repo root (gitignored, dev) |
| `.env.prod` | repo root (gitignored, prod local) |
| Keystore | NOT in repo. Locally `~/secure/myshop-upload.jks`; in CI, base64'd into `KEYSTORE_BASE64` secret. |
| Match repo | Separate private GitHub repo, NOT this one. URL in `MATCH_REPO_URL` secret. |
| `.github/workflows/release-android.yml` | repo root → `.github/workflows/` |
| `.github/workflows/release-ios.yml` | repo root → `.github/workflows/` |
| Android `key.properties` | `apps/<app>/android/key.properties` (gitignored, regenerated by CI). |
| iOS `Secrets.xcconfig` | `apps/<app>/ios/Flutter/Secrets.xcconfig` (gitignored, regenerated by `tool/build.sh`). |
