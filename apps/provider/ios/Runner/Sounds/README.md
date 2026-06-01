# iOS notification sounds

## `incoming_request.caf`

Referenced by the backend's `buildApnsConfig` (in
`apps/api/src/modules/notification/push.service.ts`) — the FCM/APNs
payload sets `aps.sound = 'incoming_request.caf'` for `job_request`
and `ride_request` notifications. iOS looks the file up by name
inside the bundled app — it MUST be a "Copy Bundle Resources"
build-phase entry in the Runner target.

### Requirements

- Format: **`.caf`** (Core Audio Format) — Apple's preferred
  notification format. AAC inside CAF works well.
- Length: **maximum 30 seconds**. iOS truncates anything longer.
- Filename: exactly `incoming_request.caf` (the backend hardcodes
  this name).

### Convert an MP3 to CAF

If you have a 25–30 s MP3 ringtone (same file you drop into Android's
`res/raw/incoming_request.mp3`), convert it with macOS's `afconvert`:

```bash
afconvert -f caff -d aac incoming_request.mp3 incoming_request.caf
```

### Add to Xcode (one-time)

1. Drop `incoming_request.caf` into this folder
   (`apps/provider/ios/Runner/Sounds/`).
2. Open `apps/provider/ios/Runner.xcworkspace` in Xcode.
3. In the Project Navigator, right-click on the **Runner** target
   (the yellow folder icon) → **Add Files to "Runner"...**.
4. Select `Sounds/incoming_request.caf`.
5. In the dialog, ensure:
   - "**Copy items if needed**" — leave UNchecked (the file is
     already in the right place).
   - "**Create groups**" — selected.
   - "**Add to targets**" → tick **Runner**.
6. Click **Add**.
7. Verify under Runner target → Build Phases → **Copy Bundle
   Resources** that `incoming_request.caf` is listed.

### Behaviour if the file is missing

The APNs payload still sends `sound: 'incoming_request.caf'`. iOS
can't find the file → falls back to the **default** notification
sound. No crash, no error. **Add the file when you have one; no
code changes are needed.**

### Suggested CC0 / royalty-free sources

- <https://pixabay.com/sound-effects/search/ringtone/>
- <https://mixkit.co/free-sound-effects/notification/>
- <https://freesound.org/> (filter by Creative Commons 0)
