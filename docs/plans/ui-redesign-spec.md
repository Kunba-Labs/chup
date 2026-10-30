# Build Spec: Chup! UI/UX redesign (increment 10)

> Contract for the build. Derived from ui-redesign.md on 2026-10-30, after the item-by-item walk with Waseem.
> Check items off ONLY when the acceptance criteria are verified working,
> not when the code is merely written.

## How to use this spec
Build against this file. When a feature lands and its criteria verify, flip
`[ ]` to `[x]` and commit the spec change with the feature. Run
`/product-planner check` to audit coverage. A design board is reviewed and
approved before any build work starts.

## F0. Design review gate
- [x] A design board shows every screen below in all three palettes, plus the app icon concepts, before any build work starts.
  - Accept: Waseem picks a palette and an icon mark in writing. The choice is recorded in PLAN.md. (Verified 2026-10-30: palette A voice, icon A pill bars.)

## F1. Visual system
- [x] The palette tokens live in `Theme.swift`, and the three candidate palettes can be switched for review renders.
  - Accept: one argument renders the same screen in each palette. The shipped build uses only the chosen one. (2026-10-30: the palette was picked from the HTML design board, so the in-app switch was dropped as unneeded. `Theme.swift` holds only the voice palette.)
- [x] Titles use a sans display face. Body and transcript text stay legible at 14 to 16 pt.
  - Accept: no 32 pt serif titles remain in the workspace.
- [ ] A gradient pill waveform component is used for every surface that hears audio.
  - Accept: the floating sidebar, island, indicator, rail and record pill all use it. With Reduce Motion on, the bars hold still and still show the level. (gap: island, indicator, rail, sidebar list and recording scrubber done; floating sidebar waveform lands with F4, record pill with F3.)
- [ ] Each speaker in a meeting gets a stable colour, used consistently across the transcript, the timeline and the chips.
  - Accept: the same speaker has the same colour in every place in one meeting. Colour is never the only cue, so the name or initial is always shown. (gap: `Palette.speaker` keyed by speaker ID, shown in the transcript; timeline and chips land with F3.)

## F2. App shell
- [ ] A glass icon rail switches between Today, Meetings, Dictation, Notebook, Personal, Search (⌘K) and Settings, with a Record button at the bottom.
  - Accept: every icon has a tooltip and a VoiceOver label, and the rail can be used from the keyboard. With Reduce Transparency on, the rail has a solid background. (gap: rail with ⌘1–⌘6, tooltips, labels and solid fallback shipped; the Search entry lands with the ⌘K palette in F6.)
- [x] A list column per module can be collapsed with ⌘\.
  - Accept: you can switch between meetings with one click while the detail stays open. The window stays usable at 900 pt wide. (Meetings has the column; Dictation, Notebook and Personal are lists themselves. Below 940 pt of panel the column steps aside automatically.)
- [x] Content sits in a floating rounded panel.
  - Accept: content does not clip at 900 pt or at 1600 pt wide.

## F3. Meeting page
- [ ] The header holds an inline-editable title, tag chips, the record pill, Export and Ask.
  - Accept: a title edit is saved and survives a relaunch.
- [ ] The left pane has a Notes | Summary toggle.
  - Notes is the merged document, with action items as a checklist at the top and private thoughts as a locked section at the end.
  - Summary keeps today's evidence cards, pins and versions.
  - Accept: pinned edits and summary versions from before the redesign still show. Private thoughts never appear in search or exports.
- [ ] The transcript sits in the right pane and can be resized or collapsed. It collapses automatically below 1100 pt.
  - Accept: segment correction and speaker rename still work from this pane.
- [ ] The transcript pane has a find field that highlights matches and steps through them.
  - Accept: ⌘F inside the meeting focuses it, and Enter moves to the next match.
- [ ] A timeline scrubber at the bottom shows speaker-coloured segments, with play, pause and skip.
  - Accept: clicking the timeline seeks the audio and scrolls the transcript to that point. A meeting with no audio shows a timeline-free state.
- [ ] Clicking a summary or notes citation seeks the audio and highlights the matching transcript line.
  - Accept: works for both AI notes lines and summary cards.
- [ ] A citation whose source was deleted shows an unavailable state.
  - If the audio was deleted, the citation still highlights the transcript line, and a "no audio" mark replaces the seek.
  - If the transcript was deleted, the citation shows "source deleted": it stays visible, is not clickable, and has a tooltip that names what was deleted.
  - The note text itself is never removed or rewritten.
  - Accept: delete the audio of a meeting and click a citation, then delete its transcript and click again. Each shows the matching state, and there are no crashes or dead seeks.
- [ ] Unknown speakers show a "who is this?" chip after Stop, and the chip opens the existing rename.
  - Accept: renaming applies to every place that speaker appears.
- [ ] Ask opens as a panel over the transcript side, and its history stays with each meeting.
  - Accept: leave the meeting, come back, and the earlier exchanges are still there.

## F4. Recording (floating live sidebar)
- [ ] The floating sidebar keeps its current behaviour and adds the gradient waveform with a playhead and a timer.
  - Accept: it is still excluded from screen sharing and is non-activating.
- [ ] Live text shows the current line large, older lines fade, and lines are labelled You or Them.
  - Accept: the current line meets 4.5:1 contrast. No speaker numbers are invented while recording.
- [ ] The sidebar has Pause, Stop and Discard.
  - Accept: Discard asks for confirmation, then deletes the audio and the meeting. Stop saves as it does today.
- [ ] If no audio arrives for 20 s, the sidebar shows a warning with "Restart input".
  - Accept: unplugging an input during a test recording shows the warning. Restart resumes capture without ending the meeting.

## F5. Data operations
- [ ] Deleted meetings, dictations and notebook entries go to a Trash with Restore.
  - Accept: a trashed item disappears from lists, search and MCP immediately. Restore brings it back intact, audio included.
- [ ] Every delete shows an Undo toast.
  - Accept: Undo within 8 s fully restores the item.
- [ ] The Trash purges items after 30 days, and "Delete forever" uses the existing verified deletion plan.
  - Accept: the purge removes the encrypted audio and the FTS rows.
- [ ] A meeting's audio only, transcript only, or the whole meeting can be deleted separately.
  - Accept: deleting the audio keeps the notes and transcript, and the timeline shows "audio deleted". Deleting the transcript keeps the notes.
- [ ] Running summary and refine jobs can be cancelled from the meeting page.
  - Accept: after Cancel, no partial summary is saved and the job can be restarted.
- [ ] Tags are chips that can be added, removed and autocompleted.
  - Accept: existing free-text tags migrate into separate chips, split on `·` and `,`.
- [ ] A tag can be renamed or deleted across all meetings.
  - Accept: the change shows on every meeting that had the tag.
- [ ] Bulk select in the list column (⌘-click, ⇧-click) offers Delete and Tag.
  - Accept: bulk delete of 3 meetings puts all 3 in the Trash, and one Undo restores all 3.
- [ ] Deleting is blocked while capture or AI work is active, as it is today.
  - Accept: the existing guard message shows.

## F6. Search
- [ ] A ⌘K palette searches meetings, notes, transcripts, dictations, notebook and Personal entries.
  - Accept: results are grouped by type. Choosing a transcript hit opens the meeting at that line with the audio seeked there. Private thoughts, assistant exchanges and trashed items are never shown.
- [ ] The list column has a search field and filters for tag, person and date range.
  - Accept: the filters combine, the result count updates, and clearing them restores the full list.
- [ ] Every module list has its own search, including Notebook and Personal.
  - Accept: a typed query narrows the list as you type.

## F7. Settings
- [ ] Settings has six sections: General, Dictation, Meetings, AI & Assistant, Privacy & Data, and Advanced (collapsed).
  - Accept: every control that exists today can be reached in the new structure, checked against the old list of 14 pages.
- [ ] Usage, Recovery, Diagnostics and Transcription Lab live under Advanced.
  - Accept: each opens and works as it does today.
- [ ] Permissions show as one checklist in General.
  - Accept: each permission row shows its real status and an action.
- [ ] Each section has a coloured, filled icon tile.
  - Accept: the tiles meet contrast, and VoiceOver reads the section name.
- [ ] The capture-source picker and meeting rows show the real app icon read from the installed app.
  - Accept: Zoom, Teams, FaceTime and browsers show their own icons. Apps that aren't installed show a generic symbol. No third-party logos are bundled.
- [ ] Dictionary, Snippets and Styles live in a Personal module in the rail.
  - Accept: create, edit, delete and search work for each. (gap: Personal module with a Dictionary | Snippets | Styles switch shipped; per-list search lands with F6.)

## F8. Today home
- [x] Today shows a greeting with Record meeting and Dictate actions.
  - Accept: both start the same flows as the rail and menu.
- [x] Today shows the 3 most recent meetings and the open action items across all meetings.
  - Accept: checking off an item updates the item inside its meeting. Trashed meetings are excluded.
- [x] On first run, an empty Today works as the first-run guide.
  - Accept: a fresh install with no data shows guidance, not sample data presented as real.

## F9. Floating surfaces
- [ ] The hover rail, dictation island and indicator use the new waveform, type and gradient.
  - Accept: the existing island and compact render boards show the new style. The 160/450 ms timings are unchanged.
- [ ] The island grows to fit up to 2 lines of large live dictation text, then fades.
  - Accept: the click-through regions are re-verified, so the island never blocks clicks outside its visible shape. Placement holds on left, right and bottom docks.

## F10. App icon
- [x] 3 to 4 icon concepts (pill bars, a monogram, and others) are rendered on the design board.
  - Accept: Waseem picks one. (Picked A, pill bars.)
- [ ] The chosen icon ships in `ChupIcon.icon` and the appiconset with a light default.
  - Accept: the installed app shows the new icon in the Dock and Finder at every size.

## Non-functional
- [ ] VoiceOver labels and a keyboard path exist for the rail, list, panes, timeline and ⌘K.
  - Accept: a manual VoiceOver pass over these surfaces is noted in MANUAL-TESTS.md.
- [ ] Reduce Motion and Reduce Transparency fallbacks exist on every new surface.
  - Accept: renders with both flags on look correct.
- [ ] Every list has an empty state, and every job has a failure state with a recovery action.
  - Accept: empty Trash, empty search and a failed summary each show a clear message and a next step.
- [ ] The existing native offline checks still pass, and the layout review renders every new screen.
  - Accept: `scripts/test.sh` and the `--render-design` layout review pass.

## Out of scope (Parked)
- **Calendar and upcoming meetings:** unpark when the P2 calendar integration is scheduled.
- **Slack, Notion and CRM pushes and logos:** unpark when an integration exists and brand permission is granted.
- **Cross-meeting AI Ask:** unpark after the per-meeting Ask history ships and the evidence checker covers multiple meetings.
- **Folders and spaces:** unpark if a user has more than about 30 tags or asks for nesting.
- **Custom template editor:** already deferred in increment 9.
- **Dark-mode workspace:** PRODUCT.md requires the light workspace.
- **An in-window live recording view:** decided 2026-10-30. The floating sidebar carries the live experience instead.
