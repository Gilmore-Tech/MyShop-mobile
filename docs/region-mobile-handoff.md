# Provider Region Selection — Mobile Handoff

> **Audience:** Flutter **Provider App** team (driver + artisan signup). The Client App is **not** affected.
> **Backend status:** Implemented on `staging` (additive, backward-compatible); available on `https://myshop-api-test.onrender.com` after the next deploy.
> **Urgency:** Non-blocking. Shipped apps keep working with no change — see [§5 Backward compatibility](#5-backward-compatibility). Pick this up whenever the provider-signup screen is next touched.

---

## TL;DR

The platform is region-scoped (Ashanti pilot). The backend now lets a **provider pick their home region at signup**. Two small mobile changes, **provider flows only**:

1. **Fetch** the region list from a new public endpoint `GET /v1/regions`.
2. **Send** the chosen region as an optional `regionId` on the existing `POST /auth/register` payload.

That's it. No client-app change, no new auth, no breaking change. During the pilot the list returns a single region (Ashanti), so the UX can be a pre-selected/single-option picker today and naturally supports multiple regions later.

---

## 1. Background — what changed and why

"Region" is now two distinct things on the backend; **mobile only deals with the first**:

- **Home region** (this handoff): which region a provider *belongs to* — selected once at signup, used for ownership/verification scoping (a regional ops manager sees their region's providers). Stored on the driver/artisan.
- **Activity region** (backend-only): which region a *specific ride/job physically happened in*, resolved automatically from the booking GPS. Mobile does nothing for this — it's stamped server-side.

Previously no region was captured from anyone; every provider was silently assigned the single pilot region. This change makes the home region an explicit, provider-chosen value.

---

## 2. Endpoint reference

### 2.1 List active regions

**`GET /v1/regions`** — **Public** (no bearer token; call it before/during signup). Server-cached ~5 min.

#### Response (standard envelope)

```json
{
  "success": true,
  "data": {
    "regions": [
      { "id": "8e9f1c14-2b35-4a90-9e31-1c8f3d7e2a55", "name": "Ashanti", "code": "ashanti" }
    ]
  },
  "error": null,
  "meta": { ... }
}
```

| Field  | Type   | Notes                                                        |
| ------ | ------ | ----------------------------------------------------------- |
| `id`   | string (UUID) | Send this back as `regionId` on register.            |
| `name` | string | Display label for the picker (e.g. "Ashanti").              |
| `code` | string | Stable slug (e.g. "ashanti"); handy as a key, not for send. |

> Pilot returns exactly one region. Render it as a single pre-selected option (or a disabled picker) now; the same code handles N regions when we expand.

### 2.2 Register with a home region

**`POST /auth/register`** — unchanged except for one **new optional field**:

| Field      | Type          | Required | Notes                                                                                              |
| ---------- | ------------- | -------- | -------------------------------------------------------------------------------------------------- |
| `regionId` | string (UUID) | optional | **Providers only** (`driver`/`artisan`). The `id` from `GET /v1/regions`. Ignored for `client`.    |

- Omit it and the backend defaults to the active pilot region (current behaviour).
- An invalid/inactive `regionId` is rejected at the **verify-otp** step (not at register) with `INVALID_REGION` (400) — see [§4](#4-error-handling).

---

## 3. Mobile changes

### 3.1 DTO — add `regionId` to `RegisterRequest`

[`packages/api_client/lib/src/models/auth_dtos.dart`](../../myshop-mobile/packages/api_client/lib/src/models/auth_dtos.dart) — mirror the existing optional-field pattern (`referralCode`, `rideCategories`):

```dart
class RegisterRequest {
  const RegisterRequest({
    // ...existing params...
    this.rideCategories,
    this.regionId, // NEW — provider home region (driver/artisan only)
    this.shopCapacity,
    this.maxConcurrentJobs,
  });

  // ...existing fields...
  final String? regionId; // provider only — region UUID from GET /v1/regions

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{ /* ...existing required... */ };
    // ...existing optional spreads...
    if (rideCategories != null) json['rideCategories'] = rideCategories;
    if (regionId != null) json['regionId'] = regionId; // NEW
    // ...
    return json;
  }
}
```

### 3.2 Add a region client + provider

Add a tiny `getRegions()` to the api_client (alongside the other auth/reference calls) hitting `GET /v1/regions`, returning a `List<Region>` (`id`, `name`, `code`). No auth header needed. Cache it in app state for the signup session.

### 3.3 UI — one signup step (both provider roles)

Add a region selector to the provider registration flow, used by **both** driver and artisan paths:

- Driver: alongside [`driver_categories_step.dart`](../../myshop-mobile/apps/provider/lib/src/features/registration/widgets/driver_categories_step.dart) / `driver_profile_step.dart`.
- Artisan: alongside `artisan_business_step.dart` / `artisan_profile_step.dart`.
- Carry the selected `regionId` in [`registration_controller.dart`](../../myshop-mobile/apps/provider/lib/src/features/registration/providers/registration_controller.dart) (same as `rideCategories`) and pass it into the `RegisterRequest`.

With a single pilot region, this can be a pre-selected, read-only confirmation rather than a full chooser — but wire the value through so multi-region needs no rework.

> **Do not** add region to the **Client** sign-up ([`apps/client/.../auth/screens/sign_up_screen.dart`](../../myshop-mobile/apps/client/lib/src/features/auth/screens/sign_up_screen.dart)). Clients have no region.

---

## 4. Error handling

| Code            | HTTP | When                                                              | Mobile handling                                                                 |
| --------------- | ---- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `INVALID_REGION`| 400  | Returned from **`/auth/verify-otp`** if the sent `regionId` is unknown/inactive | Practically only a stale-cache edge case. Re-fetch `GET /v1/regions`, ask the user to re-select, retry. |

Note the validation fires at **verify-otp**, not register (register only stashes the payload + sends the OTP). Surface it on the OTP screen, not the form.

---

## 5. Backward compatibility

This is **fully additive**. The production app (v1.2.0) sends no `regionId`; the backend defaults those providers to the active pilot region exactly as before. There is **no migration deadline** and no risk to shipped builds — adopt when convenient.

---

## Ready-to-paste ticket

> **[Provider App] Add home-region selection to provider signup**
>
> **Why:** Backend now captures a provider's home region at signup (region-scoped platform). Additive + backward-compatible; current builds unaffected.
>
> **Scope (provider app only — client app excluded):**
> 1. api_client: add `getRegions()` → `GET /v1/regions` (public, no auth), returns `[{id,name,code}]`; cache for the signup session.
> 2. api_client: add optional `regionId` to `RegisterRequest` + `toJson()` (only emit when non-null).
> 3. Provider registration: add a region step (shared by driver + artisan), thread `regionId` through `registration_controller`, include it in the register call. Single pilot region → render as pre-selected/confirm.
> 4. Handle `INVALID_REGION` (400) on the OTP screen: re-fetch regions, re-select, retry.
>
> **Out of scope:** client sign-up; any "activity region" handling (backend stamps it from GPS automatically).
>
> **Contract:** see `docs/region-mobile-handoff.md` and `docs/mobile-api-endpoints.md` (REGIONS + POST /auth/register).
> **Acceptance:** new provider signup sends a valid `regionId`; omitting it still succeeds (defaults to pilot region); client signup unchanged.
