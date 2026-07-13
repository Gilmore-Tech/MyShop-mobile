# CallKit / PushKit rollout notes

Status as of 2026-07-13:

- Backend has VoIP token storage and APNs VoIP delivery:
  - `POST /v1/notifications/register-voip-device`
  - `DELETE /v1/notifications/register-voip-device`
  - `POST /v1/calls`
  - `POST /v1/calls/:id/join`
  - `POST /v1/calls/:id/accept`
  - `POST /v1/calls/:id/decline`
  - `POST /v1/calls/:id/end`
  - Socket namespace: `/calls`
- Mobile branch `feature/voip-callkit-mobile` has the first iOS foundation:
  - shared app-call REST service in `api_client`;
  - shared Flutter bridge for iOS VoIP/CallKit events;
  - client + provider PushKit token registration through the existing FCM auth bridge;
  - client + provider native PushKit delegate and CallKit provider;
  - iOS `voip` + `audio` background modes.

Verified locally:

- `flutter analyze apps/client`
- `flutter analyze apps/provider`
- `flutter build ios --debug --no-codesign` from `apps/client`
- `flutter build ios --debug --no-codesign` from `apps/provider`

Next mobile slices:

1. Handle bridge call events in Dart:
   - `callAccepted` → `POST /calls/:id/accept`, open call screen;
   - `callDeclined` → `POST /calls/:id/decline`;
   - `callEnded` → `POST /calls/:id/end`.
2. Add `call.incoming` / `call_incoming` FCM fallback handling for Android and iOS when VoIP delivery is unavailable.
3. Build the in-app call screen and connect `/calls` socket signaling.
4. Add real audio/WebRTC provider integration behind the call screen.
5. Add release checklist:
   - Apple developer portal app IDs must have Push Notifications enabled;
   - APNs VoIP key/env vars must be configured on backend;
   - bundle IDs must match backend `APNS_VOIP_CLIENT_BUNDLE_ID` and `APNS_VOIP_PROVIDER_BUNDLE_ID`;
   - test with TestFlight/device because PushKit does not behave fully on simulator.
