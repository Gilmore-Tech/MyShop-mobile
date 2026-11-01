# In-app call connection verification

The reported symptom is roughly 45–60 seconds of Connecting after pickup on
both Android and iPhone, predominantly on mobile data. The production trigger
has not yet been identified from a correlated real call.

## Candidate changes

- Start the 30-second RTC deadline before ringback cleanup, microphone access,
  peer creation and signaling. Audio cleanup has its own three-second limit.
- Release startup waiters on failure/disposal. Reject late microphone/peer
  results and clean up their native resources; prevent late signaling from
  reviving a failed attempt.
- At the automatic recovery attempt, fetch the authenticated call session,
  apply returned TURN servers, then restart caller ICE. Preserve existing
  servers if refresh fails or returns STUN only. Credential refresh is bounded
  to six seconds and never extends the original startup deadline.
- In the API repository, reduce the failed-credential cooldown from 30 to five
  seconds so TURN can be retried before mobile setup times out. Successful
  credentials remain cached. No new endpoint or auth bypass is introduced.
- Prevent session polling from automatically recreating an RTC instance after
  a startup exception. The user explicitly selects Retry audio.
- Add elapsed milliseconds to RTC logs and include the setup phase on errors
  and timeout. SDP, relay credentials and candidate addresses are not added to
  these timing logs.

## Rollout and device checks

Deploy the API change together with candidate client and provider builds before
assessing TURN recovery. Local unit tests cannot establish real carrier latency.
Neither the API nor mobile builds have been deployed as part of this change.

Test both call directions for each pair:

| Pair | Primary test | Comparison |
| --- | --- | --- |
| Android / Android | Separate mobile-data networks | Wi-Fi / mobile data |
| iPhone / iPhone | Separate mobile-data networks | Wi-Fi / mobile data |
| Android / iPhone | Separate mobile-data networks | Wi-Fi / mobile data |

For each call record the call ID, both app/build versions, caller/callee role,
phone OS, network/carrier, pickup time, time until each screen says Connected,
and whether audio works in both directions. Run multiple calls per case; retain
individual timings rather than reporting an unmeasured average. Include fresh
microphone permission, already-granted permission, background/locked pickup,
and Retry audio after a failed attempt.

Inspect both phones' `[CALL-RTC][callId] elapsedMs=...` logs:

1. `start`: check `rtcProvider`, STUN and TURN URL counts.
2. `audio cleanup ready`, `microphone ready`, `peer ready`: isolate native delay.
3. `signal tx/rx` and `first remote signal`: isolate signaling delay.
4. Local/remote candidate counts: `relay` means a relay candidate was gathered
   or received, not proof that it was the selected media route.
5. `recovery TURN configuration applied`: confirms fresh relay configuration
   reached the existing peer before the recovery offer.
6. `terminal connection state=connected` or timeout with `phase=...`: determine
   time to connection or the exact stage that exhausted the budget.

A new attempt must show failure by its 30-second RTC deadline, or earlier for
failed audio cleanup, and remain failed until explicit retry. A connected call
must retain audio without a later startup timeout. Frequent 12-second recoveries
still indicate an unresolved network/signaling problem; a bounded failure alone
is not evidence of improved connection speed.
