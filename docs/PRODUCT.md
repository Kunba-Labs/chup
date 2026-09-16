# Chup! — product specification

Native macOS 15+, Apple silicon. Temporary original brand: a quiet, warm place for spoken work. No account or cloud connection is needed to record or take notes. Cloud processing is opt-in and clearly distinct from local capture. Empty state is real; sample content is never presented as a recording.

## Workflows and acceptance criteria

- **Dictation:** capture the frontmost app, AX element, selected range and original value before audio starts. Hold Fn, toggle Fn+Space, or use the rail/menu. Verbatim, light cleanup, polished; English/Dutch and extensible language hints. Restore a result to history before attempting insertion. Never press Return. If focus, selection, value or secure-field status changed, retain text and offer Copy. Fn+Control edits selected text using a spoken instruction. Dictionary aliases, snippets and per-app styles are user-owned settings.
- **Meetings:** explicitly choose microphone-only or an app audio process. Explain browser-wide capture before starting. Record separate encrypted microphone and remote tracks against a host clock. Pause affects recording, never the conference microphone. Independent source meters and actual capture gaps. Notes commit as edited. Live text is provisional; final segments are speaker-labeled. Sources link summary → segment → recorded interval. Speakers remain request-scoped unknowns until a human assigns identities. Rename, split, merge and correction overlays survive reprocessing.
- **Assistant:** private text first; explicitly addressed interactions only. Private voice requires verified isolation from any active conference input. Headphones are output privacy, not input privacy. Broadcast requires a controlled outgoing mix-minus route. New private-to-shared session, no private context reuse. Backend failures cannot affect capture. Tool writes use request IDs and version checks; success follows commit and Undo is available.
- **Rail:** independent nonactivating NSPanel, 160 ms hover open / 450 ms close, pointer corridor, left/right/bottom placement persisted per display, Spaces/full-screen support. Hover never captures or activates. Rail and management sidebar are separate. All actions also appear in menu/shortcuts.
- **Shortcuts:** central lifetime registry; editable bindings apply immediately. Native Fn/modifier/mouse path, ordinary chords, hold/release, repeat suppression, prefix arbitration, reset on sleep and tap disable. Rebinding suspends dispatch. Internal and known system conflicts are actionable; cross-app conflict detection is explicitly incomplete.
- **Library:** searchable dated meetings with participants/tags; summary, My notes, transcript; Notebook, dictation history, dictionary, snippets, styles. Settings: General, Shortcuts, Audio, Dictation, Meetings, Assistant, Appearance, Privacy, Advanced.

## Design

Workspace #F7F3EB; paper #FFFCF6; sidebar #EEE7DC; ink #29251F; muted #70675D; olive #626C4C; recording #9C4437. The workspace, Settings and normal notifications always use light appearance. The floating rail and drawers use dark charcoal glass, independent of system appearance. New York/system serif 32 pt titles and 22 pt note headings; sans 16 pt transcript, native controls, quiet dividers, broad whitespace. No metric dashboard. Recording always has text/icon alongside color. VoiceOver labels, keyboard access, Reduce Motion and Reduce Transparency are required. See MOTION.md for transition timings and the interactive study.

## Assumptions

Direct distribution (Developer ID/notarization), initially unsandboxed because cross-app AX and process capture require qualification. No calendar/bot dependency. User explicitly starts each recording and informs participants. No background always-listening wake phrase initially. Production provider credentials live on a trusted backend. Local metadata/FTS is SQLite plaintext with owner-only file access; audio journals are AES-GCM encrypted using a Keychain key. Full database encryption is a release gate, not implied by encrypted audio. Sync and voice enrollment remain independent optional capabilities.

## Delivery standard

All integration states must be truthful. A compiled adapter is not a qualified capture route. Cloud account/model access, hardware routing, two-hour soak, signed TCC behavior and distribution require explicit validation. See STATUS.md and VALIDATION.md for actual evidence and remaining scope.
