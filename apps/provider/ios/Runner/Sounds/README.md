# iOS notification sounds

## `incoming_request.caf`

The Notification Service Extension selects this sound for mutable
`ride_request` and `job_request` pushes. iOS looks the file up by name inside
the bundled app, and `Runner.xcodeproj` includes it in Runner's **Copy Bundle
Resources** phase.

### Requirements

- Format: **`.caf`** (Core Audio Format). The checked-in file is 48 kHz,
  stereo, signed 16-bit linear PCM.
- Length: **maximum 30 seconds**. iOS truncates anything longer.
- Filename: exactly `incoming_request.caf` (the backend hardcodes
  this name).
- Source: exactly the same audio as
  `apps/provider/assets/audio/incoming_request.mp3`. A synchronized MP3 copy is
  kept beside the CAF to make provenance easy to verify.

### Convert an MP3 to CAF

Export the canonical MP3 to PCM WAV in an audio editor, then convert it with
macOS's `afconvert`:

```bash
afconvert -f caff -d LEI16 incoming_request.wav incoming_request.caf
afinfo incoming_request.caf
```

### Xcode wiring

No manual Xcode step is required. Keep the filename and the Copy Bundle
Resources entry unchanged if the sound is replaced later.

### Behaviour if the file is missing

iOS falls back to the default notification sound if the named resource is
missing. There is no crash, so always verify the built Runner.app contains the
CAF during release QA.

### Suggested CC0 / royalty-free sources

- <https://pixabay.com/sound-effects/search/ringtone/>
- <https://mixkit.co/free-sound-effects/notification/>
- <https://freesound.org/> (filter by Creative Commons 0)
