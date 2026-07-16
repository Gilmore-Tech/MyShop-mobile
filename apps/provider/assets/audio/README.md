# Audio assets

## `incoming_request.mp3`

Foreground ringtone for new job/ride requests. Looped from
`LocalNotificationService.startIncomingRingtone()` via the
`audioplayers` package while the modal/screen is on screen, and
stopped on dispose.

### Drop the file here

```
apps/provider/assets/audio/incoming_request.mp3
```

This file is the canonical source. Keep byte-identical MP3 copies at:

- `apps/provider/android/app/src/main/res/raw/incoming_request.mp3` for the
  fallback notification channel.
- `packages/incoming_request_overlay/android/src/main/res/raw/incoming_request.mp3`
  for the native overlay service.
- `apps/provider/ios/Runner/Sounds/incoming_request.mp3` as the checked-in iOS
  conversion source.

Convert the same MP3 to
`apps/provider/ios/Runner/Sounds/incoming_request.caf` for APNs; iOS system
notification sounds cannot use MP3 directly.

One source file → all packaged variants. The same ringtone is heard whether the
artisan/driver is foreground, Android-backgrounded, or iOS-backgrounded.

### Requirements

- Length: **under 30 seconds** for iOS compatibility. Foreground and Android
  overlay playback loop until the authoritative offer deadline.
- Format: MP3 is the easiest cross-platform choice. WAV / OGG also
  work for the Dart asset but the Android channel is happier with
  MP3 and iOS needs CAF separately.
- Filename: exactly `incoming_request.mp3`. The Dart code
  hardcodes this name.

### Suggested CC0 / royalty-free sources

- <https://pixabay.com/sound-effects/search/ringtone/>
- <https://mixkit.co/free-sound-effects/notification/>
- <https://freesound.org/> (filter by Creative Commons 0)

### Behaviour if the file is missing

`LocalNotificationService.startIncomingRingtone()` catches the
`FlutterError: Unable to load asset` and silently falls back to
**haptic-only** (heavy-impact pulses every 1.5 s). No crash, no
broken modal — just no sound until you drop the MP3.
