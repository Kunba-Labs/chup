# Iterations 4–6 — implementation and validation

14 September 2026. This increment implements meeting intelligence, addressed private voice, and the assistant outgoing route in the native development preview. It is **not production qualification of OpenAI access, conference routing, privacy, or echo cancellation**.

## 4. Meeting intelligence

- Optional live outlines run from completed live transcript segments after a 20-second coalescing delay, over the most recent ten minutes. `/outline` is implemented on the backend. Canonical provisional text remains provisional; the outline is separately labeled and versioned.
- Final transcription can automatically generate a final summary. The app fingerprints the transcript, rejects a response if it changed, and atomically commits the summary and its version. Saved versions can be selected. User-pinned edits stay separate across regeneration.
- Summary extraction, long-transcript retrieval, source-ID/quote validation and an independent semantic review run through the trusted backend. The full transcript end anchors time-relative questions before retrieval. A model-based evidence reviewer is an additional check, not a proof of factual accuracy.
- Structured actions have owner/date-or-null, status, evidence, versions, idempotent writes and guarded Undo. Ambiguous dates remain strings. Source-derived actions can be saved from summaries; explicit user actions can be added without inventing meeting evidence. IDs are scoped to the meeting and the store rejects cross-meeting collisions.
- My notes, generated summaries, pinned interpretations and Private thoughts have separate storage. Private thoughts never enter AI requests. Source navigation opens the transcript and seeks its audio when recording is finished.
- Assistant requests propose note/action changes for visible review. Success is acknowledged only after the local write commits. Passive meeting audio cannot invoke tools or send external messages.

## 5. Private voice

- Actual `GPT-Live-1` transport and client delegation are wired to native controls. Live uses `/v1/live/sessions` and its own event protocol, not Realtime voice events. The backend owns the provider key.
- Connect prepares a session; the Ask button or hold gesture controls addressed physical-microphone input from the shared AudioOwner. PCM is converted to mono 24 kHz. The app waits for correlated mute/unmute acknowledgments; silent PCM maintains the Live input clock while muted.
- Delegation metadata waits for transcript text and the acknowledged end of addressed input. Scoped retrieval/validation and durable proposed writes belong to the app/backend. Backend completion precedes playback permission. New addressed turns use new contexts so late private results cannot reenter a later conversation.
- Output is pinned to verified headphone hardware. During a recorded call, the controlled outgoing route and exclusive selected-process input are required. Other active input readers and unknown process properties reject voice, including when Chup! itself is not recording. The route is checked periodically during voice.
- Private mic samples are omitted from meeting audio and live captions; the omission is visible as a gap. Addressed questions have separate encrypted local journals. The outgoing call mic stays muted after interruption/failure until explicitly resumed. Headphones alone are never treated as proof of private input.
- Text remains available when voice fails. Session/delegation/summary duration and status records are saved locally. Voice sessions currently have a two-minute maximum; the relay also caps lifetime at ten minutes. These are duration caps, not true inactivity detection. Full token/cost and transcription usage reconciliation remains engineering work.

## 6. Broadcast and interruption

- A separate AVAudioSourceNode graph mixes physical microphone and assistant PCM to **Chup! Mic**. Remote audio is not an input to that mixer. Local assistant monitoring uses a separate pinned headphone engine.
- Mode changes revoke queues and recreate Live context. Broadcast retrieval excludes private history, My notes and Private thoughts; only the shared transcript and newly addressed question are supplied. The render queue rejects stale contexts and is bounded to four seconds of 24 kHz samples.
- The output callback records the consumed assistant branch through AudioOwner on a separately labeled track. The ledger advances only for consumed PCM, including an interrupted prefix. Generated text is explicitly labeled as potentially unplayed. This is render accounting, not proof of remote receipt.
- Escape/Stop flushes voice output and closes the transport. Backend retrieval/proposals can still finish durably; interruption does not roll back committed writes. Recording/notes have independent lifetimes.
- The separate BlackHole-based driver prototype builds for arm64/macOS 15. It is **not installed or bundled**, and no closed-source distribution license was obtained. See [driver setup, licensing and qualification](../DriverPrototype/README.md).
- Native controls, source highlighting, action editing and private/broadcast status are integrated with the shared state, menu bar and animated dark rail. The light workspace remains unchanged in visual direction. [Design gallery](../Design/index.html) includes new actual native action and idle voice renders, labeled as design samples.

## Automated evidence

- Native XcodeBuildMCP application build passes, including audio routing, Live orchestration and native UI.
- 40 Swift tests: prior capture/dictation/transcript coverage plus action version/idempotency/scope guards, atomic summary revisions, private context exclusion, provisional evidence copies, mix-minus bounds and partial rendering/revocation.
- 16 backend tests: prior HTTP/contract tests plus live-outline route/authentication, provisional copy isolation, evidence-review rejection and chunked retrieval rejecting foreign IDs. Provider responses are fixtures where needed.
- Native `--validate-audio` exercises the production AVAudioSourceNode mix and AudioOwner private fanout, plus existing encrypted recording, alignment, conversion, recovery and continuous playback checks. No hardware opened.
- `scripts/test-live-transport.py` runs the real native URLSession WebSocket client and LiveConversation against a localhost fixture. It checks startup, PCM, correlated mute/unmute, early delegation ordering, addressed-input completion, commentary/audio and close. It makes no OpenAI request.
- The separate driver build succeeds. Native design export runs; new actions and private voice screens are visually inspected. Design-only samples do not simulate successful hardware routing or AI sessions.

## Genuine remaining engineering and external qualification

**Before shipping these voice modes:** licensed/signed driver installation lifecycle; actual headphone/conference loopback qualification; robust process/helper attribution and route-change privacy guarantees; acoustic echo cancellation and speakers; long-running drift/backpressure tuning; provider tests for exact Live timing, narration/fact fidelity and interruption; full durable backend job/usage recovery. Playback is gated on a validated delegation result, but model-generated spoken wording still requires evaluation.

The HAL check polls at 100 ms and is not atomic against another app independently switching inputs. Private voice must remain a development prototype until that race and the supported hardware matrix are qualified. Unclassified headphone devices are rejected. Source-render consumption does not prove the driver delivered audio to the meeting or that another participant heard it.

No OpenAI credentials were supplied. No signed TCC/AX capture run, real mic/Zoom/Teams/browser session, physical privacy/broadcast test, speaker AEC test, two-hour real-call soak, notarization or App Store submission was performed. Ordinary recording still requires no virtual driver. A named bot participant remains a separate optional integration.

Iterations 7–8 retain privacy/storage controls and release hardening. Earlier capture/transcript limitations remain in [iterations 1–3](ITERATIONS-1-3.md); those are not erased by this increment.
