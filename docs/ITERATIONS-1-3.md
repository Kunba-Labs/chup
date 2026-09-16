# Iterations 1–3: implementation checklist

Requested scope: finish capture reliability, dictation, and transcript/speaker handling in one implementation pass. This is separate from the original five-phase roadmap.

## 1 — Capture reliability
- Fence old source callbacks and consumer lifetimes; bounded capture buffers.
- Persist explicit recording-leg clock anchors; detect packet gaps/rate discontinuities and measure drift.
- Select/pin microphone by device UID; react to device changes and offer explicit same-source recovery.
- Independent remote-source failure/gaps; no replacement app capture or automatic microphone start after wake/crash.
- Recover complete encrypted journal packets, index recording duration and expose recovery results.
- Run accelerated long-recording/fault tests and native offline audio validation. Physical two-hour capture, USB/Bluetooth and signed TCC qualification require actual hardware sessions.

## 2 — Dictation
- Register ordinary global chords with macOS; retain native Fn/modifier/mouse path and one resolver.
- Immediate rebinding, conflicts, permissions, missed releases and no duplicate dispatch.
- Strengthen destination and clipboard checks; retain results if insertion cannot be confirmed.
- Deterministic snippets, dictionary/pronunciation aliases, per-app language/style and cleanup settings.
- Durable recording/history and consistent retry/cancel behavior, including crash recovery.

## 3 — Transcripts and speakers
- Bounded overlapping file-transcription windows with absolute offsets and durable retry jobs.
- Reconcile overlap duplicates and speaker continuity conservatively; never equate independent numeric speaker labels.
- Stage conflicting reprocessing results instead of losing manual corrections.
- Explicit encrypted voice-reference enrollment, opt-in cloud matching, attribution provenance, rename and deletion controls.
- Validate provider request contracts using official documentation; actual account access and acoustic accuracy remain external qualification.

Implementation results, tests and any remaining engineering will be recorded below before handoff.

## Implementation result — September 14, 2026

This pass implements the three requested development increments in the native app and backend. It does **not** certify a production release or physical audio/provider behavior. The original full product scope remains in PLAN.md.

### Capture reliability

- AudioOwner fences each source and each consumer lifetime. Closing a consumer flushes accepted packets before closing journals. A late callback from an old remote source cannot enter a new recording leg, even when a consumer name is reused.
- PCM conversion uses 64 preallocated slots of at most 32,768 frames. Encryption, JSON and Data creation execute on the serial writer. Saturation pauses capture explicitly. Remote adapters still allocate AVAudioPCMBuffer objects and dispatch work; this is not an allocation-free hard-realtime graph.
- The microphone picker resolves a device UID, pins it for the session, and rejects a disconnected device rather than selecting a different microphone. Concurrent meeting/dictation consumers share the pinned input. Stop the meeting before changing its device selection.
- Recording legs now store host-clock anchors, microphone UID and selected process bundle ID. Playback and transcript exports use the same anchor. Existing recordings without anchors retain their legacy timestamp fallback.
- A ContinuousClock measures elapsed time without wall-clock changes. Resuming creates an anchored leg; another recording in the same meeting appends after saved audio. Sleep during initialization cancels startup; sleep during capture pauses it. Wake never starts capture.
- Packet discontinuities and rate changes create track-specific gaps. The source clock tracker measures drift; rendering positions each packet by its timestamp instead of accumulating nominal durations. This is not a claim of qualified adaptive cross-device drift correction.
- Remote source failure stops only remote capture, leaving microphone recording running. Reconnect validates the selected process. A remote gap remains open until packets arrive. Process-tap format changes require explicit reconnect.
- Interrupted meetings are scanned at startup without starting audio. The recovery inspector reports authenticated packet counts, last complete audio time, truncated tails and corrupt/missing files. It records an unknown interruption interval rather than inventing the crash duration.

### Dictation and shortcuts

- Ordinary chords register exclusively with macOS through Carbon. Fn, modifier-only and mouse gestures retain the native event tap; all paths use one resolver. Settings capture unregisters chords while rebinding, persists changes and re-registers immediately. Registration/handler failures are visible; other apps’ shortcuts cannot be exhaustively enumerated.
- Hardware reconciliation covers keys, modifiers and side mouse buttons. Reset requires release before another action can start. Input Monitoring remains required for global Fn/mouse/Escape monitoring; registered ordinary chords can work without that permission. The local Settings capture path supports ordinary chords without a global event tap.
- AX destination capture subscribes to focused-element changes, including movement within an app. Automatic insertion requires that focus monitoring was established. App/element/selection/value/epoch and secure-field checks still apply. Clipboard snapshotting detects concurrent changes and conditional restoration preserves newer clipboard writes. Clipboard paste remains a best-effort operation without an app acknowledgment; history is the recovery path.
- A durable history row is created before microphone startup. Cancellation and interruption preserve recoverable audio. Language, cleanup mode, application style, selected editing text and preferences are saved with each dictation and reused on retry. Retry never automatically pastes.
- Exact spoken snippets bypass cleanup and retain formatting. Pronunciation aliases/preferred spellings match whole words, with longer aliases preferred and no cascading replacement. Personalization supports editing/upsert and deletion. Application styles set language and cleanup mode.
- Non-verbatim cleanup and selected-text commands use a separate schema-constrained fidelity review; rejected changes leave the raw transcript saved. This additional model check is fallible and still requires English/Dutch accuracy evaluation.

### Transcript refinement and speakers

- Final uploads use 90-second core windows with up to three seconds of overlap on each side. Separate tracks are rendered to mono 24 kHz WAV using absolute packet positions, preserving silence/gaps. Requests stay under 96 seconds (roughly 4.7 MB), below the relay’s 24 MB cap.
- Window jobs store pending/running/failed/completed/review state. Segment replacement, revision preservation and job completion share one SQLite transaction. Retry skips committed windows with unchanged bounds; reprocess explicitly reruns them. Cancellation leaves audio intact and a resumable window.
- Shared utterances can reconcile request-local groups when the same track, overlapping absolute interval and sufficient identical normalized words agree without ambiguous mappings. The first boundary is retained for matching phrases to avoid midpoint jitter. This links an acoustic group, not a person. Different wording, insufficient overlap or conflicting labels stay separate; semantic boundary reconciliation for substantially different transcriptions still needs further work.
- Provider segmentation changes overlapping manual corrections stage a review instead of replacing corrected text. The UI displays current/proposed text and offers Keep my corrections or explicit interval replacement. Accept checks that the displayed current revision has not changed. Earlier corrections and provider revisions remain in the audit history.
- Renaming/splitting/merging remain available. Explicit enrollment extracts a clean 2–10 second interval, rejects overlapping transcript intervals, encrypts the reference, and defaults cloud matching off. Users must confirm the speaker and can rename/delete the profile. Up to four profiles may be enabled for future requests. Matches are visibly labeled “voice match” rather than treated as confirmed identity.
- Backend reference validation accepts only bounded mono 24 kHz PCM16 WAV data, opaque unique names and the documented multipart arrays. Deleting a reference removes the local file/profile and stops future matching; it does not retract data previously sent to a provider or erase historical manual transcript assignments.

### Validation performed

- XcodeBuildMCP 2.7.0: native macOS/arm64 development build passed, `CODE_SIGNING_ALLOWED=NO`, no source warnings in the final build.
- **32 Swift tests passed**, including an accelerated two-hour journal exercise (240 rotated chunks / 7,200 one-second packets), two-hour clock simulation with 100 ppm drift, rate/reset/gap faults, overlap/track boundaries, transaction rollback, correction review across SQLite reopen, snippet/alias fidelity and old-model decoding.
- **12 backend tests passed**, including an actual loopback HTTP adapter test with a stub provider verifying diarization multipart references and rejection of an unfaithful cleanup result. No request reached OpenAI.
- Native `--validate-audio` passed against the production audio-owner fanout and writer, AVAudioEngine offline playback beyond its initial lookahead, explicit leg clocks, isolated WAV export, and recovery index. No microphone or physical output was opened.
- Native design rendering regenerated the light workspace, panels, dark glass rail and speaker/reference controls. `Design/Previews/09-speakers.png` uses labeled sample identities only.

### Required external checks and remaining engineering

Hardware/account checks: signed TCC grants/denials/revocation; real two-hour capture; USB disconnect and Bluetooth profile changes; Zoom/Teams/browser process selection; clock alignment across actual devices; AX and clipboard insertion in native/Electron/browser apps; held shortcut event ordering on real keyboards; English/Dutch model accuracy, enrolled-reference accuracy and provider account access. The accelerated tests are **not** a two-hour hardware soak.

Remaining engineering in these areas: fully allocation-free remote callback adapters; adaptive drift correction if device qualification exposes a need; semantic reconciliation for materially different overlap wording; automatic microphone replacement within an existing recording (currently requires stop/change/start); finer transcript text splitting than the existing per-segment speaker split; broader secure-field/AX compatibility. These are not represented as simulated successes.

Exact manual checks are in VALIDATION.md. Increments 4–8 from the eight-increment estimate remain: meeting intelligence, private voice, assistant broadcast, storage/privacy, release qualification.
