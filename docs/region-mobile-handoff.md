# Multi-region mobile contract

The platform now operates in more than one server-authoritative operational
boundary. Ashanti supports rides and artisan jobs. Bono initially supports rides
inside the Sunyani launch boundary; jobs stay hidden and blocked there.

## Two region meanings

- Provider home region: selected during registration and sent as `regionId`. It controls verification/admin ownership only.
- Current operational region: resolved by the backend from trusted GPS. It controls service availability, matching, promos, and announcements.

Clients do not select or permanently enroll in a region. Providers do not need
an admin transfer when travelling. Both roles automatically use the services of
the boundary they are physically inside.

## Endpoints

`GET /v1/regions` is public and returns:

```json
{
  "success": true,
  "data": {
    "regions": [
      {
        "id": "region-uuid",
        "name": "Bono Region",
        "code": "BON",
        "ridesEnabled": true,
        "jobsEnabled": false,
        "serviceAreaName": "Sunyani launch v1"
      }
    ]
  }
}
```

`POST /v1/regions/resolve` requires an authenticated client, driver, or artisan:

```json
{
  "latitude": 7.3349,
  "longitude": -2.3268,
  "service": "rides"
}
```

It returns the current region or `null` when the point is outside an enabled
boundary. Mobile must use the returned `ridesEnabled`/`jobsEnabled` values and
must not infer availability from a saved home region.

## Ride pricing

Affected Sunyani nursing-college trips include:

```json
{
  "remoteAreaAdjustment": {
    "label": "Nursing & Midwifery Training College - Sunyani remote-area adjustment",
    "amountPesewas": 1500,
    "ratePercent": 30,
    "matchedAt": "pickup"
  }
}
```

Render this as a separate positive fare row only when the object contains a
positive integer amount. Do not calculate it locally. The server applies it
once, excludes it from discounts/commission, and includes it in the total.
Ordinary trips omit the object, so mobile must omit both the row and wording.

The provider incoming-request screen receives pins and server-authored pickup
distance/ETA. The nursing-college pickup exception may search farther, but the
app does not choose or display a different algorithm.

## Compatibility and test matrix

- Older Ashanti apps remain API-compatible because all new response fields are additive.
- New apps must test Ashanti rides/jobs, Bono rides, Bono jobs-disabled UI, outside-boundary handling, provider roaming, an ordinary Bono fare, and pickup/dropoff remote-area fares.
- Region identity and prices always come from the API. Never cache them as permanent account attributes.
