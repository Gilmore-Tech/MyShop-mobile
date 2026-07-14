# CallKit / PushKit rollout notes

Status as of 2026-07-14:

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
  - client + provider Dart handling for native CallKit accept/decline/end events;
  - client + provider in-app call route/screen shell.
  - client + provider call screens listen to `/calls` call-state updates so peer
    accept/decline/end closes the opposite side promptly.
  - Android `call_incoming` notifications open `/calls/:callId` with explicit
    Accept and Decline controls; opening the screen no longer accepts the call;
  - native CallKit accept/decline/end actions are persisted until Dart handles
    and acknowledges them, including terminated-app cold starts;
  - duplicate PushKit/FCM reports for the same call are ignored by CallKit;
  - call socket rooms wait for connection and rejoin after reconnect;
  - accept/decline/end bridge actions retry transient backend failures;
  - Release/Profile builds use the production APNs entitlement file.
  - Android `call_incoming` uses the call category, full-screen intent, and
    Android 14+ full-screen special-access request flow;
  - WebRTC audio capture/playback and `/calls` offer/answer/ICE signaling are
    connected in both apps, including mute, speaker, and CallKit audio session;
  - backend retains the iOS FCM fallback even after APNs accepts a VoIP push,
    because APNs acceptance does not prove that CallKit displayed it.
  - backend generates short-lived Cloudflare TURN credentials once per call,
    caches them with the call session, and falls back safely when Cloudflare is
    unavailable;
  - client + provider validate and pass the returned ICE servers to WebRTC,
    with public STUN retained only as a fallback.

## Call reliability fix checklist

Code complete in the current mobile/backend worktrees:

- [x] Handle Android `call_incoming` before generic foreground/background
  notification suppression in both apps.
- [x] Add Android call-category full-screen intent handling, lock-screen wake,
  full-screen special-access prompting, call-specific notification IDs, expiry,
  cancellation, and terminated-app tap replay.
- [x] Show explicit Accept/Decline controls on incoming Android calls and wait
  for backend `accepted` state before starting WebRTC.
- [x] Join the iOS call socket as soon as PushKit reports the incoming call so
  caller-side cancellation can dismiss CallKit before the receiver answers.
- [x] Send a data-only `call_ended` control push to an untouched receiver and
  exempt live call-control messages from the generic notification rate limit.
- [x] Make accept/decline/end transitions atomic, restrict accept/decline to the
  callee, and prevent delayed TURN generation from resurrecting terminal calls.
- [x] Buffer early SDP/ICE, replay the caller offer and all gathered candidates
  when the peer joins, and redact TURN/SDP/IP details from mobile socket logs.
- [x] Forward CallKit audio-session activation to WebRTC in both iOS apps.
- [x] Add an outgoing ringback tone and stop it on accept, decline, end, error,
  or screen disposal.
- [x] Automatically leave both call screens after a remote terminal event;
  navigation now happens before optional snackbar presentation so missing or
  stale messenger state cannot strand the UI on `Ended`.
- [x] Give Android calls a dedicated, versioned notification channel that uses
  the device's selected ringtone and repeats until accept, decline, end, or
  timeout. Job/ride request sounds remain on their separate provider channel.
- [x] Audit call targeting: the backend resolves only the accepted booking's
  client and assigned driver/artisan, pushes only to the callee's active
  `(userId, role)` devices, and authorizes socket rooms/signaling per call
  participant. No call path uses a driver/rider broadcast topic.
- [x] Audit and align `artisan_job` parity: both client and artisan active-job
  screens start the shared call flow with the accepted job ID, the backend
  resolves the assigned artisan, provider delivery uses the `artisan` role,
  and terminal navigation returns to the active job. In-app calling now remains
  visible even when an optional public phone number is absent.
- [x] Enforce the full JWT `(userId, role)` identity on every call REST action,
  socket join, and signaling operation. A dual-role provider authenticated as
  a driver cannot join or control that user's artisan call, and vice versa.
- [x] Remove both FCM and PushKit rows on role logout/session takeover and
  rebind a reused PushKit token away from previous accounts/roles so a stale
  provider identity cannot keep ringing after a role or account change.
- [x] Restore the exact artisan job after call termination, including cold
  starts, query-only route changes, stale cached jobs, failed recovery, and
  overlapping recovery requests. Client returns seed a valid back stack before
  opening the active-job screen.
- [x] Hide call actions until an incoming session join resolves, preserve the
  terminal session before navigation, prevent repeated taps from creating
  parallel calls for one booking, and end a newly-created call if its launching
  screen disappears before navigation.
- [x] Reject stale incoming-call pushes and cap call-push TTL at 60 seconds.
- [x] Commit the new backend call-control/state-ordering fixes (`c669572`) on
  `feature/voip-call-reliability`.
- [x] Push `feature/voip-call-reliability` to origin.
- [x] Commit and push the backend artisan identity/token closure (`adf0243`) on
  `feature/voip-call-reliability`.
- [x] Commit and push the mobile call reliability/artisan parity changes on
  `feature/voip-callkit-mobile`; nothing goes directly to `staging`.
- [ ] Merge the feature branch through the normal review workflow and deploy
  the latest backend feature commit (including `c669572` and `adf0243`) before
  device testing; do not push directly to `staging`.
- [ ] Install fresh mobile builds on both physical devices before retesting.

Physical-device acceptance matrix (do not mark complete from simulator/unit
tests):

- [ ] iOS to Android while Android is foregrounded.
- [ ] iOS to Android while Android is backgrounded, terminated, and locked.
- [ ] Android to iOS while iOS is foregrounded, backgrounded, terminated, and
  locked.
- [ ] Caller hangs up before answer in both directions; receiver stops ringing
  immediately and no delayed alert reappears.
- [ ] Receiver declines and caller shows Declined in both directions.
- [ ] Either participant ends an accepted call in both directions; the peer
  briefly receives the terminal state and automatically leaves the call screen.
- [ ] Android uses the selected device ringtone for incoming calls in foreground,
  background, terminated, and locked states, and stops it on every exit path.
- [ ] A second unrelated rider/provider account receives no push and cannot join
  or signal the call; multiple devices for the intended callee may all ring.
- [ ] A dual-role provider signed in under the wrong role cannot join, accept,
  decline, end, or signal the other role's call and does not retain a stale
  PushKit alert after logout/role change.
- [ ] On an accepted artisan job, test client-to-artisan and artisan-to-client
  calls, including accept, decline, remote end, Android ringtone, iOS CallKit,
  carrier-data audio, and return to the active-job screen.
- [ ] Receiver accepts and both parties hear each other over Wi-Fi.
- [ ] Receiver accepts and both parties hear each other with both phones on
  separate carrier-data connections; logs show a connected ICE state and, when
  required, a `relay` candidate without printing credentials or addresses.
- [ ] Outgoing ringback starts only while status is `ringing` and stops on every
  terminal/accepted path.
- [ ] Microphone mute, speaker routing, Bluetooth, audio interruption, and
  Wi-Fi/mobile-data handoff behave correctly.

Verified locally:

- `flutter analyze apps/client`
- `flutter analyze apps/provider`
- `flutter analyze packages/api_client`
- `flutter analyze packages/shared_ui`
- `flutter build ios --debug --no-codesign` from `apps/client`
- `flutter build ios --debug --no-codesign` from `apps/provider`
- `xcrun swiftc -parse` for both iOS `AppDelegate.swift` files
- `pnpm --filter @myshop/api typecheck` from the backend repo
- focused backend call, TURN, notification, FCM, and APNs tests (83 tests)
- focused artisan call-role and token-lifecycle backend suites (52 tests)
- targeted ESLint for all eight artisan closure backend files
- focused `api_client` call-service and RTC tests (9 tests)
- focused `shared_ui` call-view and call-button tests (6 tests)
- `git diff --check` in both the mobile and backend repositories

Still pending locally:

- Android packaging did not complete during this pass: the first build hit a
  Flutter engine-cache sandbox permission error, and the approved retry was
  interrupted after a long build. Fresh Android device builds remain part of
  the physical-device acceptance pass below.

## Cloudflare TURN rollout checklist

- [x] Create Cloudflare TURN key and API token.
- [x] Add `CLOUDFLARE_TURN_KEY_ID`, `CLOUDFLARE_TURN_API_TOKEN`, and
  `CLOUDFLARE_TURN_TTL_SECONDS` to Render.
- [x] Validate TURN configuration and TTL in backend config.
- [x] Generate time-limited ICE credentials on the backend without exposing the
  permanent Cloudflare token.
- [x] Cache credentials in the authenticated call session and reuse them for
  both participants.
- [x] Return Cloudflare ICE servers from call start/join/accept responses.
- [x] Consume validated ICE servers in the mobile WebRTC peer connection.
- [x] Retain STUN fallback when TURN is unconfigured or temporarily unavailable.
- [x] Add backend credential/session tests and mobile response-parsing tests.
- [x] Commit and deploy the backend TURN changes to Render (the tested API
  returned Cloudflare ICE credentials).
- [x] Confirm Render starts with all three Cloudflare variables present (TURN
  credentials were generated successfully for the tested call).
- [ ] Run a real iOS-to-Android and Android-to-iOS call on separate carrier or
  restrictive Wi-Fi networks; verify audio in both directions.
- [ ] Confirm backend logs show credential generation without logging secrets.
- [ ] Confirm accept, decline, end, timeout, and reconnect behavior on both apps.

Next mobile slices:

1. Commit and push both call feature branches, then merge/deploy them through
   the normal review workflow and install fresh client/provider builds on both
   devices.
2. Complete the direction, lifecycle, cancellation, and carrier-data device
   matrix above using one correlated call ID per test.
3. Add ICE restart for network handoff, then cover audio interruption,
   Bluetooth route, and WebRTC reconnection with device tests.
4. Add release checklist:
   - Apple developer portal app IDs must have Push Notifications enabled;
   - APNs VoIP key/env vars must be configured on backend;
   - bundle IDs must match backend `APNS_VOIP_CLIENT_BUNDLE_ID` and `APNS_VOIP_PROVIDER_BUNDLE_ID`;
   - test with TestFlight/device because PushKit does not behave fully on simulator.
