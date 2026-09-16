# Native layout review — September 15, 2026

The redesign groups each decision or task on a warm reading surface, with an inset layer for status. Shared `WorkspaceCard`, `SettingSwitch`, `InlineStatus` and `DetailDisclosure` components live in `App/UI/Theme.swift`. Cards use 22-point padding, a restrained border and 16-point corners. Settings content has a bounded reading width, 20-point group spacing, a short page introduction and an icon navigation list. Technical explanations move into disclosures; permission, privacy and destructive-action information stays available at its relevant control.

## Screen review

| Area | Result |
| --- | --- |
| General | Separate floating-control, login and setup cards; installation details in a disclosure. |
| Audio | Microphone selection/current input, waveform test and meeting capture are separate cards. A working external input is not presented as a red lid-closed error. |
| Dictation settings | Transcription/local model separated from writing preferences; offline capability explanation expands on demand. |
| Shortcuts | Presets/setup, per-action bindings and testing have separate surfaces. Existing multiple bindings and rebind cancellation remain. |
| Meetings settings | Call suggestions, cloud transcription/summary options and enrolled voices have separate groups. |
| Assistant settings | Conversation boundaries and recent sessions separated; route requirements remain in contextual help and the actual voice controls. |
| Appearance | Light/dark surface samples separate from docking controls and accessibility explanation. |
| Privacy | Cloud access, encryption status, retention, export/recovery and deletion have distinct cards. Existing confirmations remain. |
| Permissions | Existing prominent status badges and title arrows retained, with shared card spacing/borders. |
| Usage | Model rates separate from provider activity; rate validation feedback is local to this view. |
| Recovery | Explanation, honest empty state and resumable jobs separated. |
| Diagnostics | Timing reports separate from export/clear controls. |
| Transcription Lab | Recording choice, model setup, comparison and results separated. |
| Dictation/history | Capture controls and microphone together; individual history entries are readable cards. |
| Meetings/notebook | Individual dated entries; notebook uses the same scroll/card construction after its native List failed to render rows in review. |
| Dictionary/snippets/styles | Always-visible field labels, room for multiline values, separate entries and empty states. |
| Meeting details | Notes/private-thought editors have paper surfaces; summary, transcript and action items have distinct surfaces. Summary source controls wrap into a grid. |
| Assistant conversation | Exchanges and proposed writes have separate reading surfaces. Voice route setup has an inset area. |
| Onboarding | Workflow, cloud/privacy and login choices have their own groups; all five steps reviewed. |
| Capture/backup/speaker correction | Scrollable setup with fixed action footers. Capture keeps microphone and call selection visible; the optional microphone waveform test stays in Audio settings. |
| Floating controls/notices | Existing dark glass design retained; window geometry and capture logic are outside this layout change. |

The unrelated global cleanup message was removed from Settings pages such as Audio. Storage results remain in Privacy and backup workflows; usage-rate validation now reports in Usage itself.

## Validation and code review

- Native arm64 Xcode build passed. Log: `.artifacts/layout-build.log`.
- Rendered and visually reviewed 37 layouts: all 14 Settings pages at 790 × 640, three taller Settings views, six library pages, five meeting tabs, five onboarding steps and four assistant/setup/editor dialogs. Images are generated from the actual SwiftUI/AppKit views. Data is illustrative; no user audio was captured or sent.
- The native offline regression suite passed, including microphone exception containment, shortcut delivery, clipboard/destination guards, encrypted recording and local voice-transport fixtures. Log: `.artifacts/layout-native.log`. No new implementation-mirroring UI unit tests were added for cosmetic changes.
- Codex reviewed card ownership, scroll containers/action footers, field labels, preserved bindings/action handlers, destructive confirmations, microphone test lifecycle, shortcut cleanup on navigation and message scoping. Findings from the first visual pass (blank notebook rows, overloaded capture setup, non-scrolling editor sheets and an incorrect preview-only microphone status) were corrected and rerendered.
- This is not a full VoiceOver or keyboard traversal certification. Physical capture/device switching and cloud integration were not retested for this visual iteration.

Reproduce the screenshots after building:

```sh
CHUP_LAYOUT_REVIEW=1 CHUP_DESIGN_OUTPUT="$PWD/.artifacts/layout-review" \
  '.artifacts/DerivedData/Build/Products/Debug/Chup!.app/Contents/MacOS/Chup!' --render-design
```

Gallery: `Design/Previews/layout-review/index.html`. Installation/restart is deferred until implementation, validation and this review are complete. The final deployment receipt and log record the installed build; no post-restart development is part of this iteration.
