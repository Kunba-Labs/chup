# Playback and assistant implementation increment

## Meeting playback

`MeetingPlayback` replaces the old selected-chunk AVAudioPlayer array. It indexes encrypted recording journals on a separate actor, caches only the files intersecting the next window, and schedules a maximum four seconds of mixed audio ahead on a 48 kHz AVAudioPlayerNode clock. The timeline preserves packet timing, relative microphone/call positions, capture pauses and recording-leg offsets. A missing interval is silence rather than a reason to shift subsequent audio forward.

The management window now has continuous play/pause, duration and a seek slider. Dragging the slider pauses once and resumes at the chosen position when released. Transcript sources continue to seek to their absolute offsets. Switching meetings, sleeping, or changing the output route stops playback. The active recording cannot be played back into itself. Capture engine configuration events are filtered to the input owner; configuring the separate playback engine no longer counts as an input-device failure.

Each track has fixed -6 dB review gain before summation, with a final full-scale limiter. The original track files are untouched. The speech-review renderer uses linear sample-rate interpolation; high-quality resampling, per-track volume controls, persistent waveform/index caching and physical-device drift measurements remain further work. Opening a long meeting currently scans its bounded journals off the main actor instead of using an on-disk playback index.

## Saved assistant conversation

An `AssistantExchange` persists the addressed question before the request starts, then the answer, evidence, proposed write, captured note version and completion state. Reopening a meeting restores its conversation. Pending requests found after a crash are marked interrupted, never claimed completed.

Up to eight completed exchanges are supplied as bounded context for follow-ups. History is treated as data, not new permission or factual evidence. Answers still require transcript sources; only the current explicitly addressed request can propose a note write. Proposed edits can be reviewed from history, retain their original expected note version, and use a stable request ID for the note mutation. Saving acknowledges the durable note commit. Subsequent note edits can make an old proposal stale; it is rejected rather than overwriting those edits.

Cancel closes the active URLSession request. The backend propagates disconnects and the request deadline through the provider calls using AbortSignal. Leaving or switching meetings cancels its pending request, and request identity plus meeting scope reject late results. Cancellation does not undo an already committed note edit. Conversation metadata is stored in the same currently plaintext SQLite database as notes; database encryption remains a release gate.

## GPT-Live output foundation

Official Live WebSocket and delegation documentation was checked again. `LiveEvent` parses Live's PCM16 deltas, transcripts, session closure/usage and opaque client-delegation IDs. It deliberately does not interpret Realtime response audio events as Live audio. Live has no output-audio-done event; receipt and transcript timestamps are not playback completion.

`LiveConversation` now joins the transport to a bounded local PCM player, revokes output before disconnecting on interruption, rejects late events from an old context, and exposes a scoped client-delegation callback. The output queue deduplicates event IDs, enforces a four-second bound and tracks completed-buffer playback independently from generated frames. A close received while connecting cannot restart output. The conservative native ledger counts only `.dataPlayedBack` callbacks; a partially played final buffer is deliberately not counted as fully heard.

**This is not yet an enabled full-duplex assistant feature.** There is still no route-qualified UI/capture coordinator, automatic delegated backend orchestration, actual partial-frame output recording, persistent usage accounting or virtual microphone. `LiveAudioPlayback` rejects an active-meeting route instead of trusting a checkbox to make default-device output private. Voice/broadcast controls remain unavailable in the shipping UI. Model/account access and physical audio routes have not been exercised. Meeting capture and note storage use none of these voice services and continue independently.

References: [OpenAI Live WebSockets](https://developers.openai.com/api/docs/guides/voice-websockets?api=live), [Live client delegation](https://developers.openai.com/api/docs/guides/live-delegation), [Apple AVAudioPlayerNode](https://developer.apple.com/documentation/avfaudio/avaudioplayernode).

## Validation

- XcodeBuildMCP app build on Apple silicon, Xcode 26.6, without signing.
- 25 Swift tests and 9 backend tests. Added timeline alignment/gap/seek/rate/long-offset/bounds tests, Live decoding/revocation/backpressure tests and conversation context validation.
- A child-process backend test replaces provider fetch with a test fixture and verifies that disconnecting the app request aborts that provider request. No request reaches OpenAI.
- `--validate-audio` runs the native AVAudioEngine in offline rendering mode using newly generated, encrypted fixtures: microphone plus delayed call track, a pause, multiple journals/legs, 24/44.1/48 kHz input, and seven seconds of continuous output beyond the initial four-second lookahead. Sample assertions passed. No microphone or speaker hardware opens.
- Icon-rail browser checks include 56 px width, hover/focus labels and click-through overlay behavior, in addition to existing motion/interruption/timeout/Reduce Motion checks. Browser checks do not certify native full-screen/VoiceOver/pointer behavior.

Reproduce after building:

```sh
swift test
npm test --prefix backend
'.artifacts/DerivedData/Build/Products/Debug/Chup!.app/Contents/MacOS/Chup!' --validate-audio
node scripts/render-motion.mjs
./scripts/render-design.sh
```

The two-hour timestamp test is not a two-hour recording soak. No physical capture, conference routing, signed TCC or provider accuracy/latency test was performed in this increment.
