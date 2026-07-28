# iOS App Review evidence — booking-scoped VoIP

Status: **not yet ready for resubmission**. Physical-device evidence and the
App Store Connect changes below remain required. Empty placeholders and
unchecked boxes are release blockers; this runbook does not claim that a video,
device pass, reviewer-account check, or territory change has been completed.

Applies to the currently rejected submissions:

- Client submission `81d226c4-3d91-4c4a-a0c4-4a431c630e98`, version
  `1.4.1 (25)`.
- Provider submission `62ea992c-4b9c-46d0-aaec-9015ad44d267`, version
  `1.4.1 (25)`.

## Evidence manifest — fill before recording

Use one active test ride shared by the supplied Client and Provider reviewer
accounts. The two accounts must be the actual participants; in-app calling is
not exposed to an unrelated account.

- Candidate source commit: `[CANDIDATE_COMMIT_SHA]`
- Client candidate version/build: `[CLIENT_VERSION_AND_BUILD]`
- Provider candidate version/build: `[PROVIDER_VERSION_AND_BUILD]`
- Active test ride ID: `[ACTIVE_RIDE_ID]`
- Client reviewer account: `[CLIENT_REVIEWER_ACCOUNT]`
- Provider reviewer account: `[PROVIDER_REVIEWER_ACCOUNT]`
- Client two-direction video: `[CLIENT_TWO_DIRECTION_VIDEO_HTTPS_URL]`
- Provider two-direction video: `[PROVIDER_TWO_DIRECTION_VIDEO_HTTPS_URL]`
- Territory evidence captured at: `[UTC_TIMESTAMP]`

Do not include passwords, access tokens, personal phone numbers, or real
customer information in a recording or screenshot.

## Exact reviewer routes, labels, and behavior

The preferred review path is an active ride because both apps expose the two
sides of the same booking.

### Client

1. Sign in with the supplied Client account.
2. Open or recover the active ride. The production app route is
   `/ride/tracking`.
3. In the tracking sheet, find **Chat with [driver first name]**. The adjacent
   green telephone icon has the accessibility label **Call driver**.
4. Tap the telephone icon.
   - If the driver has a public phone number, the sheet offers the exact
     choices **Call in app** and **Phone call**. Choose **Call in app**.
   - If no public number is present, the same icon starts the in-app call
     directly; no choice sheet appears.

The visible control is a telephone icon, not a button containing the words
“Call driver.”

### Provider

1. Sign in with the supplied Provider account.
2. Open or recover the active ride. The production app route is
   `/active-ride`.
3. In the passenger contact row, tap the green telephone icon. Its
   accessibility label is **Call passenger**.
4. If the choice sheet appears, choose the exact label **Call in app**. If the
   passenger has no public phone number, tapping the icon starts the in-app
   call directly.

Do not tell App Review to look for “Call client” on this ride route. That label
belongs to artisan-job surfaces; the active-ride control is **Call passenger**.

## Why the background modes are genuine

Both applications offer a real, booking-scoped, two-way voice feature. A call
can be initiated only between the participants of an active ride or artisan
booking; it is not a general phone, silent-push, request-alert, or keep-alive
feature.

Implementation evidence:

- Client ride control:
  `apps/client/lib/src/features/ride/widgets/ride_tracking_sheet.dart`
- Provider ride control:
  `apps/provider/lib/src/features/driver_home/screens/active_ride_screen.dart`
- Shared **Call in app** / **Phone call** chooser:
  `packages/shared_ui/lib/src/widgets/myshop_call_button.dart`
- Client and Provider WebRTC screens:
  `apps/client/lib/src/features/calls/screens/in_app_call_screen.dart` and
  `apps/provider/lib/src/features/calls/screens/in_app_call_screen.dart`
- Shared signalling and media:
  `packages/api_client/lib/src/services/app_call_rtc_service.dart`
- Native PushKit, CallKit, and WebRTC-audio setup:
  `apps/client/ios/Runner/AppDelegate.swift` and
  `apps/provider/ios/Runner/AppDelegate.swift`
- Declared modes:
  `apps/client/ios/Runner/Info.plist` and
  `apps/provider/ios/Runner/Info.plist`

Both apps register `PKPushRegistry`, report incoming calls with `CXProvider`,
and activate/deactivate `RTCAudioSession`. The `voip` mode supports delivery and
native presentation of incoming booking calls. The `audio` mode keeps an
already accepted, audible two-way WebRTC conversation running when a
participant temporarily backgrounds the app. Neither mode may be used outside
a real call.

Apple's background-mode definitions are documented in
[Configuring background execution modes](https://developer.apple.com/documentation/Xcode/configuring-background-execution-modes).
Do not remove `voip` or `audio` merely to silence review feedback while these
features remain enabled.

## Physical-device preparation

Use release/TestFlight builds and two physical iOS devices. A simulator, mocked
incoming-call screen, staged screenshot, or silent UI-only recording is not
evidence.

1. Install the exact Client and Provider candidates identified above and show
   each version/build in the recording.
2. Sign in with the reviewer accounts and verify that the active ride recovers
   after force-quit and relaunch.
3. Keep both devices on a stable network with audible volume. Use an external
   camera or another recording setup that clearly captures both screens and
   the two-way audio without exposing credentials.
4. For the first-use microphone segment, use a genuinely fresh install/device
   state so the iOS microphone prompt appears. Tap **Allow**, then prove that
   both sides can hear speech. If permission was already consumed, erase the
   test app and prepare a clean install before recording; do not fabricate or
   overlay the prompt.
5. Confirm the active ride is still valid before every direction/decline
   attempt. Create a new test ride if the previous remote-end flow closes it.
6. Put the receiving app on the Home Screen or Lock Screen *before* initiating
   the incoming-call segment, so native CallKit delivery is visible.

## Client-submission recording procedure

The Client video must contain both call directions plus decline and remote-end
behavior. Keep device identities visible or narrate them unambiguously.

### A. Client outgoing → Provider incoming

1. On the Client device, show `/ride/tracking`, the active ride identity,
   **Chat with [driver]**, and the adjacent **Call driver** telephone icon.
2. Put the Provider device on the Home Screen or Lock Screen.
3. Tap the Client icon and, if offered, tap **Call in app**.
4. On the clean first-use Client install, show the iOS microphone permission
   prompt and tap **Allow**.
5. Show the native incoming CallKit screen on the Provider device and answer
   it.
6. Speak from each side and record audible proof of two-way audio.
7. Send the Client app to the Home Screen while the accepted call remains
   connected; prove that remote speech is still audible, then reopen it.
8. End the call from the **Provider** side. Show that the Client observes the
   remote end and leaves/updates the call UI without requiring a force-quit.

### B. Provider outgoing → Client incoming

1. Put the Client device on the Home Screen or Lock Screen.
2. From Provider `/active-ride`, tap the **Call passenger** telephone icon and,
   if offered, **Call in app**.
3. Show the native incoming CallKit screen on the Client device and answer it.
   If this is the Client's first accepted incoming call, include the real
   microphone permission prompt and tap **Allow**.
4. Prove audible two-way audio.
5. Background the Client app during the accepted call, prove remote audio
   remains audible, then reopen it.
6. End the call from the **Provider** side and show the Client handles that
   remote end.

### C. Client incoming decline

1. Repeat Provider → Client while the Client is locked or backgrounded.
2. Tap **Decline** on the Client's native CallKit screen.
3. Show that the Provider side exits or reports the declined/ended call and
   that the Client is not left in an active in-app call.

## Provider-submission recording procedure

Record this from the Provider submission's perspective. It must independently
show both directions, decline, remote end, microphone permission, and
background audio.

### A. Provider outgoing → Client incoming

1. On the Provider device, show `/active-ride`, the active ride identity, and
   the **Call passenger** telephone icon.
2. Put the Client device on the Home Screen or Lock Screen.
3. Tap the Provider icon and, if offered, **Call in app**.
4. On a clean first-use Provider install, show the iOS microphone permission
   prompt and tap **Allow**.
5. Show the Client's native CallKit screen, answer, and prove audible two-way
   speech.
6. Send the Provider app to the Home Screen while connected and prove remote
   speech remains audible; then reopen it.
7. End from the **Client** side and show that Provider handles the remote end.

### B. Client outgoing → Provider incoming

1. Put the Provider device on the Home Screen or Lock Screen.
2. From Client `/ride/tracking`, tap **Call driver** and, if offered,
   **Call in app**.
3. Show the Provider's native incoming CallKit screen and answer it. If this is
   the Provider's first accepted incoming call, include the real microphone
   permission prompt and tap **Allow**.
4. Prove audible two-way audio.
5. Background Provider while the call remains accepted, prove remote audio
   remains audible, then reopen Provider.
6. End from the **Client** side and show Provider handles that remote end.

### C. Provider incoming decline

1. Repeat Client → Provider while Provider is locked or backgrounded.
2. Tap **Decline** on Provider's native CallKit screen.
3. Show that Client exits or reports the declined/ended call and Provider is
   not left in an active in-app call.

## Fresh-install, upgrade, and device matrix

“Upgrade” means install the App Store/TestFlight `1.4.1 (25)` build first,
sign in and establish its normal local state, then update in place to the exact
candidate without erasing app data. “Fresh” means a clean candidate install.
Run both paths; a fresh-install pass does not substitute for an upgrade pass.

For every row, verify launch, sign-in/session behavior, active-ride recovery,
the correct contact icon/label, outgoing call, locked/background incoming
CallKit answer, decline, remote end, and audible background conversation.
Capture the microphone prompt on the first applicable fresh run and confirm
microphone access remains functional after upgrade.

| App | Physical device | Orientation | Fresh | Upgrade from `1.4.1 (25)` |
| --- | --- | --- | --- | --- |
| Client | iPhone 17 Pro Max | Portrait | [ ] | [ ] |
| Client | iPhone 17 Pro Max | Landscape | [ ] | [ ] |
| Client | iPad Air 11-inch (M3) | Portrait | [ ] | [ ] |
| Client | iPad Air 11-inch (M3) | Landscape | [ ] | [ ] |
| Provider | iPhone 17 Pro Max | Portrait | [ ] | [ ] |
| Provider | iPhone 17 Pro Max | Landscape | [ ] | [ ] |
| Provider | iPad Air 11-inch (M3) | Portrait | [ ] | [ ] |
| Provider | iPad Air 11-inch (M3) | Landscape | [ ] | [ ] |

Record the actual iOS version and hardware identifier beside each completed
row. If exact hardware is unavailable, App Review must approve the replacement
matrix before the named-device gate is waived.

## Client ride-booking device matrix

On both named devices, in portrait and landscape, repeat with iOS Large/Extra
Large accessibility text and with the on-screen keyboard visible where
applicable. Every state must keep a visible, enabled next step except the
intentionally disabled **Calculating Fare…** state.

- [ ] Search and select coordinate-backed pickup and destination results.
- [ ] Select a coordinate-backed **RECENT** entry; confirm no fake
      coordinate-less “saved place” is offered.
- [ ] For a broad-area result, use **Choose Exact Pickup** and **Choose Exact
      Destination** and complete the matching map-pin route.
- [ ] Loading shows disabled **Calculating Fare…** without covering the cancel
      action.
- [ ] Offline and timeout failures show usable **Retry Fare Estimate** and a
      tap issues a new estimate.
- [ ] A 5xx/service failure shows sanitized copy and usable
      **Retry Fare Estimate**.
- [ ] Outside-area failure shows **Change Locations**; separately select
      **Change pickup** and **Change destination** and verify each opens the
      correct search field.
- [ ] Empty ride categories show **Retry Fare Estimate**.
- [ ] Categories with no available drivers show **Try Again** and no category
      can be confirmed.
- [ ] A successful fare shows the amount and usable **Confirm Ride**; tapping
      it enters the existing matching flow.
- [ ] Search, keyboard, cards, fare, primary action, and **Cancel Request**
      remain visible/scrollable with no clipped or overlapping content.

Automated widget coverage is supporting evidence only; it does not replace
this physical iPhone/iPad matrix.

## App Review Notes template — Client

Replace every placeholder before pasting:

> MyShop contains real booking-scoped VoIP between the two participants of an
> active booking. Reviewer account: `[CLIENT_REVIEWER_ACCOUNT]`; test ride:
> `[ACTIVE_RIDE_ID]`. Sign in, open the recovered active ride
> (`/ride/tracking`), find **Chat with [driver first name]**, and tap the
> adjacent green telephone icon (VoiceOver label **Call driver**). If a choice
> sheet appears, select **Call in app**; when no public phone number is present,
> the icon starts the in-app call directly. Incoming calls use PushKit and the
> native CallKit UI. Accepted calls carry audible two-way WebRTC audio and
> remain audible while temporarily backgrounded. Calling is restricted to the
> active booking and is never used for app keep-alive. The physical-device
> video shows Client→Provider and Provider→Client, answer, decline, remote end,
> microphone permission, Lock Screen/Home Screen delivery, and background
> audio: `[CLIENT_TWO_DIRECTION_VIDEO_HTTPS_URL]`.
>
> The ride-booking action issue is also corrected: after pickup and destination
> selection, **Plan Your Trip** always exposes a persistent state-specific
> action for exact-pin selection, calculating, retry, changing either
> location, no-driver retry, or **Confirm Ride**.

## App Review Notes template — Provider

Replace every placeholder before pasting:

> MyShop Provider contains real booking-scoped VoIP between the two
> participants of an active booking. Reviewer account:
> `[PROVIDER_REVIEWER_ACCOUNT]`; test ride: `[ACTIVE_RIDE_ID]`. Sign in and open
> the recovered active ride (`/active-ride`), then tap the green telephone icon
> in the passenger contact row (VoiceOver label **Call passenger**). If a
> choice sheet appears, select **Call in app**; when no public phone number is
> present, the icon starts the in-app call directly. Incoming calls use PushKit
> and native CallKit. Accepted calls carry audible two-way WebRTC audio; the
> `audio` background mode is used only to keep that accepted conversation
> audible while temporarily backgrounded, never for keep-alive or request
> alerts. The physical-device video shows Provider→Client and Client→Provider,
> answer, decline, remote end, microphone permission, Lock Screen/Home Screen
> delivery, and background audio:
> `[PROVIDER_TWO_DIRECTION_VIDEO_HTTPS_URL]`.

## App Store Connect actions that code cannot perform

Perform these actions independently for **both** app records:

1. In App Store Connect availability, remove **China mainland** from the
   available countries or regions for the Ghana pilot and save.
2. Wait for App Store Connect to finish processing. Apple notes that an
   availability change can take up to 24 hours; see
   [Manage availability for your app on the App Store](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store).
3. Reopen the saved availability and capture a timestamped screenshot showing
   China mainland absent for the correct app/version. Verify the public
   storefront result from a signed-out browser after propagation.
4. Put the matching signed-out video URL, reviewer account, test ride ID, and
   exact UI path into **App Review Information → Notes** for each submission.
5. Verify both video links and reviewer credentials from a clean, signed-out
   environment immediately before resubmission.

Do not implement locale/IP inference, disable CallKit by guessed region, or
claim CallKit is disabled in China. Territory availability is the approved
store-side control.

## Release evidence gate

- [ ] Candidate commit and both version/build identifiers recorded above.
- [ ] Client reviewer credentials work from a fresh install.
- [ ] Provider reviewer credentials work from a fresh install.
- [ ] Test ride is active, recoverable, and belongs to both reviewer accounts.
- [ ] Client video shows both directions, answer, decline, remote end,
      microphone permission, locked/background incoming CallKit, two-way
      speech, and Client background audio.
- [ ] Provider video independently shows both directions, answer, decline,
      remote end, microphone permission, locked/background incoming CallKit,
      two-way speech, and Provider background audio.
- [ ] Both HTTPS video links play to completion without authentication.
- [ ] Every fresh/upgrade iPhone/iPad matrix cell is checked with device and iOS
      evidence.
- [ ] Every Client ride-booking device-state item is checked.
- [ ] China mainland is absent from both saved app availabilities after
      propagation.
- [ ] Timestamped availability evidence is retained for both app records.
- [ ] Client Review Notes contain no placeholders and use **Call driver** /
      **Call in app** exactly.
- [ ] Provider Review Notes contain no placeholders and use **Call passenger**
      / **Call in app** exactly.
- [ ] A release owner has reviewed the final, combined build after all mobile,
      push-lifecycle, router, and call-service changes are integrated.
