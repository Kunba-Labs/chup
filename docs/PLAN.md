# Phased implementation and prioritized backlog

1. **Native spikes and durable foundation:** Xcode app/core package, permission-on-use mic and process tap capture, native shortcut arbitration, destination-safe insertion, SQLite revisions, encrypted recoverable tracks. Verify Live API and prototype privacy routing policy early.
2. **Dictation and shell:** complete record/transcribe/cleanup/recovery loop; Fn paths, custom chords/mouse, Settings capture; rail docking/drawer; dictionary/snippets/styles; local search. Qualify AX in native, Electron, browser and secure fields.
3. **Meeting workspace:** selected app + mic capture, pause/resume/playback; resumable diarization; speaker corrections; source-backed summaries; note tools and private text assistant. Live captions are a separate integration; long meeting chunk consolidation and stable acoustic identity need qualification.
4. **Participant audio:** controlled virtual mic prototype, mix-minus, headphones qualification, verified private input mute, Live playback/interruption ledger; then speakers/AEC. Do not unlock broadcast on an unverified route.
5. **Release hardening:** two-hour soak and crash injection, Bluetooth/USB/rate/drift matrix, signed TCC/accessibility/VoiceOver, full metadata encryption, retention/enrollment/sync controls, notarization and auto-update.

P0 release gates: no wrong-field insertion; no recording loss due to AI; truthful source-loss/sleep state; durable note idempotency; no private-to-broadcast leakage; no unsupported summary facts. P1: complete live captions/voice transport qualification, stable speaker linkage with enrolled references, long-recording boundary reconciliation, bounded callback allocations, driver route. P2: optional calendar, platform bots, sync, multilingual eval expansion, wake phrase and open conversation.

Implementation status is tracked separately in STATUS.md; roadmap entries are not claims of completed behavior.

Requested increments 1–3 are documented in [their implementation report](ITERATIONS-1-3.md). Requested increments 4–6 now have [native implementations and offline validation](ITERATIONS-4-6.md): meeting intelligence, addressed private voice, and the assistant outgoing graph/interruption. These product increments do not close the original release-hardening phase.

## Remaining product increments

7. **Privacy and storage — implemented:** SQLCipher encryption/migration, retention/deletion, JSON/backup recovery, durable provider jobs and usage estimates, onboarding/OS settings/login service, and Chup! branding. See [iteration 7](ITERATION-7.md). Real billing reconciliation and larger fault qualification carry into increment 8.
8. **Qualification and distribution:** real provider and signed permission sessions; licensed/signed virtual-driver lifecycle; private-route transition guarantees; actual headphones/USB/Bluetooth/process-helper matrix; speakers/AEC; long-call performance and drift; accessibility/VoiceOver; installation/update/notarization/App Store route assessment.

Priority within these increments:
- P0: close private-input routing races, preserve capture under voice faults, reject stale/unsupported evidence, finish recovery and retention semantics.
- P1: exact provider contract/access/accuracy/latency testing, driver distribution, source-render versus delivered-frame measurement, complete metering and speaker identity evaluation.
- P2: optional calendar/platform bot, cloud sync, wake phrases, open conversation and more language evaluation.

One planned increment remains, with genuine engineering and qualification work inside it; this is not a guarantee that one unattended session can certify every hardware or distribution gate.

## Iteration delivery requirement

After every implementation iteration, run the relevant checks, build a new numbered version and install the locally signed app at `/Applications/Chup!.app` with `python3 scripts/deploy-local.py`. This is authorized by the user for future iterations; no repeated confirmation is required. Report the installed version and path. A running recording must never be force-quit to replace the application. Local app installation does not install the separate virtual microphone driver or satisfy the release qualification gates.

Delivered follow-up: multiple global shortcuts per action, including Fn plus Control–Shift for external keyboards, with per-binding settings and native capture/persistence validation. This completes a dictation/settings refinement; the remaining release qualification scope is unchanged.

## Increment 8 progress

The independent implementation and automated qualification slice is delivered; see [PHASE-8.md](PHASE-8.md). Completed: full audio export/indexes, transcript search, rail keyboard entry, storage and metering guards, diagnostics, provider smoke tests and signed packaging. The remaining acceptance work is [MANUAL-TESTS.md](MANUAL-TESTS.md). Remaining engineering is explicitly separate: private-route atomicity, speakers/AEC, driver lifecycle/license, acoustic linkage/semantic overlap reconciliation, production accounting/backend operation, notarization/update/App Store distribution. This is not a claim that those gates are closed.
