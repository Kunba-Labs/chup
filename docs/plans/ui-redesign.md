# Product Plan: Chup! UI/UX redesign (increment 10)

> A distinct, balanced meeting and dictation workspace: glass module rail, notes beside transcript, honest live states, and full control over your data. Generated 2026-10-30. Market researched live on 2026-10-30.

## The product

Chup! is a native macOS 15+ meeting note taker and dictation app. It captures audio locally, with no bot, and cloud AI is opt-in. This increment redesigns the interface only. Capture, storage, privacy and the evidence rules stay as they are.

### Owner's assumptions (2026-10-30)

1. The UI should look more distinctive. Today it is warm beige serif cards, which read as generic.
2. The meeting page should be balanced like the industry sidebar note takers: notes and transcript visible together, with a timeline (reference: the Nixtio "Kick-Off Meeting" shot).
3. Settings has too many pages. Simplify it and use real brand ("marketing") icons.
4. Users need to edit, delete, cancel, tag/untag and search their data.
5. Module rails use translucent glass, the way inbox2's top navbar does.
6. While recording: a live waveform with a playhead, fading transcript lines, and a "who is this?" chip per unknown speaker (reference: @michaels_ux). Big gradient pill waveform with large live text (reference: OllieVoice).
7. The home can work like an assistant landing: greeting, record action, cards (reference: Daily Nixtio).

## Current state (checked in code, 2026-10-30)

- **Shell:** a 218pt beige sidebar with 6 pages plus Settings (`App/UI/WorkspaceView.swift`). There is no list column. Meetings is a full-width list of large cards, and opening one replaces the list.
- **Meeting page:** six tabs: Notes, Summary, My notes, Transcript, Actions, Private thoughts (`MeetingDetailView`). The transcript is a separate tab of cards. A thin player sits at the bottom with no speaker segments.
- **Settings:** 14 pages (`App/UI/SettingsView.swift:7`), including Diagnostics, Recovery, Transcription Lab and Usage.
- **Delete:**
  - Meeting delete exists in a right-click menu (`WorkspacePrivacy.swift:72`). It is permanent, with no trash and no undo.
  - Dictation delete (`deleteDictation`) and personalization delete exist.
  - No bulk delete.
- **Cancel:** dictation, the assistant and transcription can be cancelled. There is no way to discard a recording in progress: `stopMeeting` always saves (`WorkspaceState.swift:951`). There is no way to cancel a summary job from the UI.
- **Tags:** a free-text `String` on `Meeting` (`Models.swift:35`), edited only through rename. There are no chips, no add/remove and no tag filter.
- **Search:** FTS over meetings, segments and notes (`MeetingSearch.swift`), plus a substring search over dictation history. Notebook, dictionary, snippets and styles have no search, and there is no global search.
- **Edit:** transcript segment correction (`correctSegment`), speaker rename everywhere (`renameSpeaker`), pinned summary edits, and note undo all exist.
- **Floating surfaces:** the dark glass hover rail, the dynamic island and the live notes sidebar exist (`HoverRail.swift`, `DynamicIsland.swift`, `MeetingSidebar.swift`).

## Market landscape

| Product | Meeting page shape | Library | Data ops | Take |
|---|---|---|---|---|
| Granola | Note first; transcript hidden behind a waveform pill; Cmd+J chat | Spaces and folders, multi-folder | Delete transcript parts, trash with restore, no transcript edit | Best authorship model; transcript "stuck in a small box", no audio playback |
| Notion AI Meeting Notes | Block in a page; citations hover and jump | Database list: filter, sort, group | Separate delete for transcript and audio | Strong citations, no speaker rename |
| Fireflies | Two panels (notes left, transcript right), each expandable, plus a left tool rail | Channels; filters by host, participant, date, duration, source; bulk bar | Find/replace, edit mode with undo, speaker rename "this or all"; delete without trash | Closest to the balanced layout the owner wants |
| Fathom | Player top, Summary/Transcript/Ask tabs, right highlight rail | Grid, playlists, folders, AI search | Click line to seek | Player-centric |
| Wispr Flow Notetaker | Tabs My thoughts / Summary / Transcript / Docs; pop-out window | Notes list | Discard recording; speaker reassign "update everywhere"; read-only transcript | Most honest states: "isn't getting any audio", too short, failed |
| Otter | Right AI sidebar, 0.5 to 3x playback, word seek | Folders | Global speaker rename; edits do not refresh summary | Incumbent |
| Char (formerly Hyprnote) | Left sidebar, chat panel, Listen button | Sidebar list | Undo-delete toast, regenerate transcript | Closest local-first peer |
| Wispr Flow, Superwhisper (dictation) | n/a | Dictionary, Snippets, Style live in the main app, not Settings | History retention options | Settings stays thin |

Sources are listed at the end.

## Table stakes and conventions

- A floating capture indicator while you work elsewhere; clicking it returns to the note.
- Pause/Resume separate from Stop.
- The notes or summary come first, with the transcript one click away or in a side pane.
- Summary items link to the transcript or audio moment.
- An Ask chat scoped to the meeting.
- Speaker rename, with an "all occurrences" option.
- A chronological list with folders or tags and filters by person and date.
- Delete for a meeting.
- Settings stays small. Content-like settings (dictionary, snippets, styles, history, usage) live in the main window. Integrations show as logo rows with Connect/Disconnect.

## Assumption check

1. **Distinctive look: confirmed as a gap, with a direction challenge.** The references share a cool lavender/blue to peach gradient with white surfaces. Copying that makes Chup look like every 2026 Dribbble shot. Recommendation: keep a warm, Chup-owned base, and take the structure from the references (floating rounded panels, glass rail, big type, gradient waveform) rather than their palette. Untested until you see renders.
2. **Balanced meeting page: confirmed.** Fireflies ships notes left and transcript right with resizable panes ([source](https://guide.fireflies.ai/articles/6653885315-learn-about-the-fireflies-notepad?lang=en)). Granola's hidden transcript is its top complaint ([source](https://tldv.io/blog/granola-review/)). No source confirmed any competitor with a speaker-colored timeline, so the reference timeline is an opening.
3. **Simplify settings: confirmed.**
   - Superwhisper keeps a small top level and puts the rest behind Advanced ([source](https://superwhisper.com/docs/get-started/settings-advanced)).
   - Wispr moves dictionary, snippets and styles into the main app ([source](https://docs.wisprflow.ai/ml/collections/7303194563-using_wispr_flow)).
   - 14 pages become 6.
4. **"Real marketing icons": challenged in part.**
   - Zoom requires written permission for its marks ([source](https://explore.zoom.us/brandguidelines)). Slack restricts logo use ([source](https://slack.com/terms-of-service/slack-brand)). Google product icons are "ask first" ([source](https://about.google/brand-resource-center/guidance/)). Microsoft requires a license.
   - Chup has no Slack, Notion or Calendar integrations today, so a logo gallery would advertise features that don't exist.
   - Recommendation: show the real app icon of installed apps, read at runtime with `NSWorkspace.icon(forFile:)`, in the capture-source picker and meeting rows ("Recorded from Zoom"). That is accurate, needs no bundled assets, and is not a decorative trademark use. Give settings sections colored, filled icon tiles like System Settings.
5. **Edit, delete, cancel, tag, search: confirmed.** The gaps listed above are real.
   - Trash plus undo beats Fireflies' permanent delete ([source](https://guide.fireflies.ai/articles/1311785862-how-to-delete-a-meeting-from-fireflies)).
   - Granola added a trash with restore in Dec 2025 ([source](https://www.granola.ai/docs/changelog)).
   - Wispr lets you discard a recording ([source](https://docs.wisprflow.ai/articles/3665250541-getting-started-with-notetaker-beta)).
6. **Glass rails: confirmed, with a constraint.** PRODUCT.md requires the light workspace and support for Reduce Transparency. The glass rail falls back to a solid surface when Reduce Transparency is on.
7. **Live recording view: confirmed** as a differentiator. The fading transcript must still meet contrast for the current line, and Reduce Motion stops the scrolling waveform.
8. **Assistant-style home: untested.** No competitor leads with a chat home for meetings. Granola and Jamie lead with upcoming or recent meetings. Recommendation: a Today home with Record, the recent meetings, open action items, without a mascot. (Decided 2026-10-30: no Ask box.)

## Gaps and opportunities

**Missing table stakes, ranked:**
1. The transcript beside the notes.
2. Trash with undo.
3. Tag chips and filters.
4. Discarding a recording.
5. Search beyond meetings.
6. Bulk select.

**Openings competitors leave:**
- A speaker-colored timeline with click-to-seek.
- Editable transcript text (Granola and Wispr don't allow it).
- Chat history that persists per meeting (Granola loses it).
- Separate deletes for audio, transcript and meeting, with a trash.
- Voice memory across meetings, which Chup already has.

**Not building now:**
- A folders/spaces hierarchy. Tags cover it for a single user.
- Team channels, soundbites/clips, video.
- Slack, Notion and CRM pushes. Already "still to be decided" in PLAN.md increment 9.

## Production completeness

- **Auth:** not needed. Single local user, no account.
- **Unhappy paths:**
  - Empty states for every list.
  - "No audio for N seconds" with a Restart action. This matches the known stale-input bug.
  - Too short, no audio, failed summary with Retry.
  - Discard confirmation.
  - Deleting during capture is blocked, as today.
- **Admin:** not needed.
- **Money:** not needed. Usage moves under Advanced as a read-only meter.
- **Notifications:** no change. Existing NotificationCard.
- **Data:**
  - Trash with a 30-day auto-purge.
  - Separate delete of audio, transcript or the whole meeting.
  - Bulk delete and tag.
  - Export already exists and stays reachable from Privacy and Data.
- **Legal:** no bundled third-party logos; installed app icons only.
- **Analytics:** not needed. Local diagnostics stay.
- **Onboarding:**
  - Restyle the existing 5 steps.
  - The empty Today home doubles as the first-run guide.
- **i18n:** no change. English and Dutch strings stay hardcoded, as today.
- **Accessibility:**
  - VoiceOver labels on all new controls.
  - A keyboard path for the rail, split panes and timeline.
  - Reduce Motion and Reduce Transparency fallbacks.
- **Responsive:** the window shrinks to 900pt wide. Below 1100pt the transcript pane collapses to a toggle.
- **SEO:** not applicable.

## Build plan

1. **Visual system.** New tokens in `Theme.swift`:
   - A palette direction (decided per item below).
   - A sans display face for titles instead of the 32pt serif.
   - Floating rounded content panel, glass material tokens, a speaker color set.
   - A gradient pill waveform component.
2. **App shell.**
   - A thin glass module rail (icons: Today, Meetings, Dictation, Notebook, Personal, Search, Settings) with the record button at its foot.
   - A collapsible list column for the active module (LetFlow style).
   - The content panel.
3. **Meeting page.**
   - Header: title, record pill, tags, search, Share/Export, Ask.
   - Split body: Notes (enhanced notes with My notes and AI authorship, actions inline, private thoughts as a locked section) on the left, Transcript on the right, resizable and collapsible.
   - A speaker-colored timeline scrubber with transport, docked at the bottom.
   - Ask opens as a panel over the transcript pane, with history kept per meeting.
4. **Recording (floating live sidebar, decided 2026-10-30; no in-window live view).**
   - The existing floating sidebar gains the gradient pill waveform with a playhead, the current line in large type, earlier lines fading. Live lines are labelled You or Them only, because live captions know just mic and remote.
   - Controls: Pause, Stop, Discard.
   - An honest no-audio state with Restart input.
   - After Stop, unknown speakers get a "who is this?" chip on the meeting page transcript (item 3), which opens the existing rename.
5. **Data operations.**
   - Trash with Restore and Empty, plus an undo toast.
   - Delete audio only, transcript only, or the whole meeting.
   - Discard a recording.
   - Cancel the summary or refine job.
   - Tag chips with add, remove, autocomplete and rename across meetings; tags stored as a set.
   - Bulk select with delete and tag.
   - Inline title edit.
6. **Search.**
   - A ⌘K palette across meetings, notes, transcripts, dictations, notebook and personal entries.
   - Filters by tag, person and date range.
   - Inline search in every list.
7. **Settings.**
   - Six sections: General, Dictation, Meetings, AI & Assistant, Privacy & Data, Advanced.
   - Advanced holds Usage, Recovery, Diagnostics and Transcription Lab.
   - Section icons as colored filled tiles.
   - Dictionary, Snippets and Styles move into a Personal module.
   - Installed app icons in capture pickers.
8. **Today home.** Greeting, Record and Dictate actions, recent meetings and open actions. No Ask box (decided 2026-10-30; cross-meeting Ask is parked).
9. **Floating surfaces.** The hover rail, island and live notes sidebar adopt the new waveform and type. Their behaviour does not change.

### Parked

- **Calendar "upcoming meetings":** unpark when the optional calendar integration in PLAN.md P2 is scheduled.
- **Slack, Notion and CRM logos and pushes:** unpark when an integration exists, plus brand permission from Zoom and Slack.
- **Folders/spaces:** unpark if tags exceed about 30 per user or the user asks for nesting.
- **Custom template editor:** already deferred in increment 9.
- **Dark-mode workspace:** PRODUCT.md mandates light; unpark only by changing that rule.

## Risks and open questions

- **Palette direction:** the owner decides from renders.
- **Fading transcript contrast:** text below 4.5:1 is decorative only. The current line and every interactive element must pass.
- **Tag migration:** the free-text field holds separators like "Product  ·  Launch", so the migration splits on `·` and `,`.
- **Trash and the privacy contract:** a trashed meeting stays encrypted and is excluded from search and MCP. "Delete forever" uses the existing deletion plan.
- **Scope:** this touches most views in `App/UI` (about 5k lines). Visual review uses the existing `--render-design` exporter.

## Sources

- https://docs.granola.ai/help-center/taking-notes/transcription
- https://docs.granola.ai/help-center/sharing/folders/spaces-and-folders.md
- https://www.granola.ai/docs/changelog
- https://tldv.io/blog/granola-review/
- https://www.notion.com/help/ai-meeting-notes
- https://guide.fireflies.ai/articles/6653885315-learn-about-the-fireflies-notepad?lang=en
- https://guide.fireflies.ai/articles/4827382971-find-and-manage-your-meetings-in-fireflies
- https://guide.fireflies.ai/articles/1311785862-how-to-delete-a-meeting-from-fireflies
- https://max-productive.ai/ai-tools/fathom/
- https://docs.wisprflow.ai/articles/9406970664-meeting-notes-and-the-editor-in-notetaker-beta
- https://docs.wisprflow.ai/articles/3665250541-getting-started-with-notetaker-beta
- https://docs.meetjamie.ai/getting-started/menu-bar
- https://anarlog.so/changelog/1.0.14/
- https://manual.raycast.com/settings
- https://superwhisper.com/docs/get-started/settings-overview
- https://superwhisper.com/docs/get-started/settings-advanced
- https://docs.wisprflow.ai/ml/collections/7303194563-using_wispr_flow
- https://docs.wisprflow.ai/articles/2368263928-how-to-setup-flow-styles
- https://explore.zoom.us/brandguidelines
- https://slack.com/terms-of-service/slack-brand
- https://about.google/brand-resource-center/guidance/
- https://github.com/simple-icons/simple-icons/blob/develop/DISCLAIMER.md
