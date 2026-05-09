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

This is the **same audio file** you should also use for:

- Android channel ringtone — copy to
  `apps/provider/android/app/src/main/res/raw/incoming_request.mp3`.
- iOS push sound — convert to CAF and drop into
  `apps/provider/ios/Runner/Sounds/incoming_request.caf` (then add to
  Xcode "Copy Bundle Resources" — see the README in that directory).

One source file → three locations. Same ringtone heard whether the
artisan/driver is foreground, Android-backgrounded, or iOS-backgrounded.

### Requirements

- Length: **20–30 seconds** (the foreground modal also auto-dismisses
  at 40 s, so anything longer gets cut off).
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
