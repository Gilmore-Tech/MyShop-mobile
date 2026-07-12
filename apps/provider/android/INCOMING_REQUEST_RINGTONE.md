# Android incoming-request ringtone

The `incoming_requests_v2` notification channel
(`lib/src/core/services/local_notification_service.dart` →
`_incomingRequestChannel`) plays a ringtone for new job/ride requests.

## Drop the audio file

Place a single audio file at:

```
apps/provider/android/app/src/main/res/raw/incoming_request.mp3
```

(`.ogg` or `.wav` also work — keep the basename `incoming_request`.)

> **Do NOT put a README or `.gitkeep` inside `res/raw/`** — Android's
> resource compiler rejects any filename in there that isn't all
> lowercase a–z, 0–9, or underscore. That's why this file lives one
> directory up.

## Requirements

- Length: **20–30 seconds** (longer ringtone = more chance the
  artisan/driver hears it across the room before the 40 s window
  closes).
- Format: MP3, OGG, or WAV. MP3 is fine.
- Filename: lowercase + underscores only, no spaces or dashes
  (Android resource naming rule). The extension is dropped when
  referencing — Dart code says `'incoming_request'`, no `.mp3`.

## Suggested CC0 / royalty-free sources

- <https://pixabay.com/sound-effects/search/ringtone/>
- <https://mixkit.co/free-sound-effects/notification/>
- <https://freesound.org/> (filter by Creative Commons 0)

## Behaviour if the file is missing

The notification channel falls back to the system's default
notification sound — the alert still rings, just not with the custom
ringtone. **No crash, no error log.** Add the file when you have
one; no other code changes needed.

## Why a separate channel?

Android locks a channel's sound at creation time — once a user has
the app installed, the channel's sound URI is permanent until they
clear app data. A new ringtone needs a new channel id.

The incoming-request channel uses a versioned id for this reason; the
existing `job_alerts` channel keeps its default sound for
`bid_accepted` / reminder pings so we don't accidentally retune
notifications users have already tuned in their settings.
