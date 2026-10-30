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

After every implementation iteration, run the relevant checks, build the commit-count version and install the locally signed app at `/Applications/Chup!.app` with `python3 scripts/deploy-local.py`. This is authorized by the user for future iterations; no repeated confirmation is required. Report the installed version and path. A running recording must never be force-quit to replace the application. Local app installation does not install the separate virtual microphone driver or satisfy the release qualification gates.

Delivered follow-up: multiple global shortcuts per action, including Fn plus Control–Shift for external keyboards, with per-binding settings and native capture/persistence validation. This completes a dictation/settings refinement; the remaining release qualification scope is unchanged.

## Increment 8 progress

The independent implementation and automated qualification slice is delivered; see [PHASE-8.md](PHASE-8.md). Completed: full audio export/indexes, transcript search, rail keyboard entry, storage and metering guards, diagnostics, provider smoke tests and signed packaging. The remaining acceptance work is [MANUAL-TESTS.md](MANUAL-TESTS.md). Remaining engineering is explicitly separate: private-route atomicity, speakers/AEC, driver lifecycle/license, acoustic linkage/semantic overlap reconciliation, production accounting/backend operation, notarization/update/App Store distribution. This is not a claim that those gates are closed.

## Increment 9 — meeting notes parity (decided 2026-10-29)

Benchmarked against Granola, Hyprnote/anarlog, Notion AI Meeting Notes, Fireflies, Otter, Fathom and Wispr Flow Notetaker (launched 2026-08-05). Already at par: speaker transcript, source-linked summary items, action owners/dates, pinned edits and summary versions, per-meeting "Ask this meeting" (includes notes), keyword search across meetings. Decisions, walked item by item with Waseem:

1. **Auto-summary on stop — build, no switch.** Stop & save starts refined transcription and then the summary whenever cloud processing is enabled. Turning cloud off is the only local-only path. A "Writing your notes…" state covers the minutes a long refine takes.
2. **Enhanced notes (Granola merge) — build in full.** A merged notes document after the meeting: the user's lines kept verbatim (ink), AI additions in grey with transcript sources, structured by the user's headings. User lines carry no transcript citation and are not passed to the evidence checker as claims; AI lines still must be source-backed. Private thoughts stay excluded. The evidence cards remain.
3. **Live notes sidebar — notepad + live AI notes.** A floating, collapsible, non-activating side panel during recording: the user's notepad above the live outline. It's excluded from screen sharing (`sharingType = .none`). Live captions and the outline are on by default while recording, so every meeting costs more in the cloud.
4. **Templates — built-in set only.** General, 1:1, Sales/customer, Standup and Interview set the merge's section headings; regenerate with another template. A custom template editor is deferred, so there's no support yet for "use my own template".
5. **Export — copy, follow-up draft and MCP.** (2026-10-29: MCP built as read-only, served by the running app over a 0600 socket and switched on in Keychain; see README.) Copy merged notes as Markdown, and "Draft follow-up email" to the clipboard (never sent). Read-only MCP access to meetings needs its own security review before it ships. Slack, Notion and CRM pushes are split off and still to be decided, so there's no support yet for "send to my tools".

## Increment 10 — UI/UX redesign (decided 2026-10-30)

Plan: [plans/ui-redesign.md](plans/ui-redesign.md). Spec: [plans/ui-redesign-spec.md](plans/ui-redesign-spec.md). Benchmarked live against Granola, Notion AI Meeting Notes, Fireflies, Fathom, Wispr Flow Notetaker, Otter, Char, Superwhisper and Raycast. Walked item by item with Waseem:

1. **Palette:** render three directions (voice gradient, warm evolved, reference lavender) and pick from renders. Structure from the references (floating panel, glass rail, big sans type, gradient waveform) either way.
2. **Shell:** glass icon rail, collapsible list column, floating content panel.
3. **Meeting page:** Notes | Summary toggle on the left (pins/versions untouched), transcript pane on the right, speaker-colored timeline at the bottom, Ask as a panel with per-meeting history. Six tabs become two views plus a pane.
4. **Recording:** no in-window live view. The existing floating sidebar gains the gradient waveform, fading You/Them live text, Pause/Stop/Discard and a no-audio warning with Restart input. "Who is this?" chips appear only after Stop, because live captions know just mic vs remote.
5. **Data operations:** all of it: trash + undo, partial delete, job cancel, tag chips, bulk select, inline title edit.
6. **Search:** ⌘K across all data types (keyword), list filters, find-in-transcript. Cross-meeting AI Ask parked, so "ask across my meetings" stays unsupported.
7. **Settings:** 14 pages to 6, colored section tiles, real installed-app icons in pickers. No bundled third-party logos and no integrations gallery, since Chup has no such integrations and brand permission is required.
8. **Today home:** without an Ask box, so no cross-meeting chat from the home.
9. **Floating surfaces:** restyle and resize the island for larger live text; click-through regions re-verified.
10. **App icon:** explore 3–4 marks before committing.

Waseem asked to see every screen as a design board before any build work.

**Design board decision (2026-10-30):** Waseem picked palette **A, voice gradient** (backdrop #E6E4F0→#F5ECE6, ink #16151A, muted #615E6D, accent #6A4CF5→#E8735A) and icon **A, pill bars** (five gradient pill bars on a light tile, dark variant for dark appearance). Warm and reference palettes are dropped from the shipped build.

**Wispr Flow realignment (decided 2026-10-30, evening).** Waseem rejected the two-pane meeting page and the window glass ("unusable"), and asked to base the note taker on Wispr Flow Notetaker. Researched from Wispr's help centre (meeting notes and editor, hub, live transcript, recording, Flow Summaries). Decisions:

1. **Meeting page: Wispr tabs.** One column: back, date pill, editable title, tags, ⋯ menu; tabs **My thoughts / Summary / Transcript**; an **Ask anything** bar docked at the bottom. Replaces the two panes, the side Ask panel and the bottom timeline; the audio player moves into the Transcript tab. Supersedes item 3 above.
2. **Summary: Wispr structure.** TL;DR, themed sections, **Decisions Made**, **Next Steps** grouped by owner (ticking one updates its action item), sources kept. The Granola-style merged grey-line notes are dropped; My thoughts stays the user's own text. Supersedes increment 9 item 2 (enhanced notes).
3. **Meeting list: day groups, no calendar.** Today / Yesterday / date headers, ⋯ per row (Share as Markdown, Delete), New note, search. Calendar "Upcoming" stays parked.
4. **Live view: Wispr notepad.** Light notepad with **Transcript** (speaker bubbles You/Others, grey in-progress words, Jump to bottom) and **My thoughts** tabs; Stop in its footer; "isn't getting any audio" card and "Started by mistake?" Keep/Discard card. The island or rail is the recording pill. Supersedes item 4 above.
5. **Window glass dropped** after two attempts made the window unreadable over busy desktops.
