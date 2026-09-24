# Validation

## Dynamic Island absorbs the floating controls — 2026-09-16

With the island enabled on a notched display, the hover rail no longer appears at all; its controls moved under the notch. The island stays compact whenever it owns the rail's job — drawing nothing at rest, so the notch is always a hover target — and expands while dictating or once the pointer has rested still over it for three seconds, so dragging across the notch toward the menu bar never opens it. A display without a notch gets no compact state from DynamicNotchKit, so the rail keeps every case there.

- Native arm64 build passed: `.artifacts/island-controls-build.log`.
- Offline native suite passed, including the new island presentation-policy check: `.artifacts/island-controls-native.log`; no microphone opened.
- Design asset rendered from the shipping views: `Design/Previews/31-dynamic-island.png`.
- Installed **Chup! 1.0 (75)** at `/Applications/Chup!.app` after the user explicitly authorised terminating the running app; the running instance was quit gracefully, not force-killed. One stable process (PID 83990) verified for 20 seconds.
- Follow-up in the same delivery: the island drew nothing and hid itself at rest, leaving the moved controls unreachable, so compact now stays present as an invisible hover target, hover shows the control row in every state, and the expanded band is 560 × 64.
- Manual check after install: with the island on, confirm the rail never appears; hover the compact island during a recording and confirm pause and stop act on the meeting; toggle the setting off and confirm the rail returns immediately.

## Paste diagnostics and clearer recovery results — 2026-09-15

Paste recovery now distinguishes “Copied to clipboard” from an actual copy failure. The former means the destination was unavailable, changed focus, or could not be safely confirmed; the text is preserved for manual paste. “Paste not confirmed” means a paste command was dispatched but the target did not expose a verifiable change. Every delivery records its trigger, route and safety reason in the Dictation diagnostics Paste activity card, without storing transcript text.

- Native arm64 build passed: `.artifacts/paste-diagnostics-build.log`.
- Offline native suite passed: `.artifacts/paste-diagnostics-native.log`; no microphone opened.
- Code review checked modifier-release handling, destination revalidation, clipboard ownership and diagnostic coverage for accessibility, native Paste, Command-V, focus changes and clipboard changes.
- Manual check: open Dictation diagnostics after a successful paste, a field with no safe Accessibility target and a terminal paste; confirm the activity row explains the route and does not call recovery copying a failure.

## Edge hover target and queued dictation — 2026-09-15

The collapsed side rail now reaches the physical display edge (zero inset for the hover host) so moving the pointer all the way to the edge enters its tracking area. The visible glass remains inset through its own shape, while the transparent host does not add a separate click intercept region.

Dictation processing is now an ordered background queue. Audio is durably saved when capture ends, then transcription, cleanup and safe insertion run independently of the next recording. A new hold-to-dictate can begin while an earlier clip is processing; each queued job retains its captured destination and generation checks prevent stale work from changing the live waveform. Queue count is shown beside Dictation, and Escape cancels the active processing job without deleting saved clips.

- Native arm64 build passed: `.artifacts/queue-build.log`.
- Offline native suite passed: `.artifacts/queue-native.log`, including panel placement and existing capture, insertion, timing and Live transport checks. No microphone opened.
- Code review checked queue idempotency, durable-before-process ordering, destination retention, cancellation and no automatic send behavior. Manual validation remains: hold the shortcut during a long local/cloud transcription, start a second dictation, and verify both clips complete in order and insert only into their validated destinations.

## Physical screen-edge alignment and transient errors — 2026-09-15

The hover rail and compact dictation controls now share a 2-point physical screen-edge inset on left/right docks. A side Dock's reserved work area no longer pushes them inward. Vertical bounds still respect the usable screen area; bottom docking keeps clear of the Dock. Concurrent meeting status keeps its separate space.

Dictation errors, including rejected silence, return to idle after 1.5 seconds. Transient microphone and delivery messages also dismiss after 1.5 seconds. Cancellation and generation checks prevent an older timer from resetting a new dictation. Saved audio, history and persistent meeting/assistant status are untouched; active listening warnings still describe the current signal.

- Native arm64 Xcode build passed: `.artifacts/edge-rest-build.log`.
- 104 core tests passed, including physical-edge placement with reserved Dock space, negative secondary-display coordinates, dragged bounds and concurrent panel separation: `.artifacts/edge-rest-core.log`.
- Offline native suite passed, including error dismissal, newer-action protection and retained diagnostics: `.artifacts/edge-rest-native.log`. No microphone opened.
- 54 actual panel transitions passed across three docks on the one connected display. The actual error rail shrank from 26 × 64 to 10 × 36 after its timeout and retained the 2-point physical-edge inset: `.artifacts/edge-rest-panels.log`.
- Rendered listening, processing and alert windows reviewed; the right-edge warning wraps fully inside its card. Images: `.artifacts/edge-rest-panels/`. Multi-display hardware changes and VoiceOver were not requalified.
- Final code review checked shared geometry, timer cancellation, preserved recording status, action generations and absence of capture/storage changes.

Deployment is the final operation. If the installed app is running, AGENTS.md requires safe user closure before replacement. `.artifacts/edge-rest-deploy.log` records the deployment attempt; `.artifacts/last-install.json` identifies the last verified installed build and must not be mistaken for this update until deployment succeeds.

## Vertical screen-edge dictation controls — 2026-09-15

The compact listening/processing panel is now 36 × 148 points on the right and left edges. Cancel is above the live waveform and Finish below it. The waveform rotates within its own 24 × 68 point area; button symbols and text do not rotate. Processing replaces it with the existing animated circle. A confirmed-insertion check uses a 36-point circle on side docks; silent text dispatch still collapses immediately. Bottom docking retains 148 × 36 horizontal controls. The panel now follows the selected dock, including changes while visible; messages stay readable in wider horizontal cards.

Window geometry and the clipping shape update atomically. Waveform amplitude, spinner rotation and panel entrance opacity retain their own animations and Reduce Motion handling. Native review caught clipping during a processing-to-alert transition and an outgoing waveform retained over the spinner; removing the container transition fixes both without animating the alert's bounds.

- Native arm64 Xcode build passed: `.artifacts/vertical-indicator-build.log`.
- **54 real panel transitions passed on the one currently connected display**, across right, left and bottom docks. Checked exact compact dimensions, host/window agreement, visible-screen containment and non-key status. Log: `.artifacts/vertical-indicator-panels.log`. An initial assertion assumed a fixed 15-point inset while an auto-hiding Dock was changing visibleFrame; validation now checks actual containment while production positioning retains its 16-point inset.
- Native offline regression suite passed: `.artifacts/vertical-indicator-native.log`. No capture hardware opened.
- Actual window images reviewed for listening, processing, wide warnings and bottom controls. An 80-frame native animation preview uses explicitly illustrative microphone levels: `Design/Previews/vertical-dictation.gif`.
- Final code review checked layout snapshots, waveform-only rotation, upright controls, live dock changes, screen clamping, preserved action handlers and existing accessibility labels. This does not claim a full manual VoiceOver audit or renewed multi-display hardware qualification.

Reproduce panel checks with `CHUP_PANEL_FIXTURE=1 CHUP_PANEL_OUTPUT=<existing-directory> python3 scripts/test-live-transport.py`. Generate the animation frames with `CHUP_COMPACT_PREVIEW=1 CHUP_DESIGN_OUTPUT=<directory> <built-app-executable> --render-design`.

Installation/restart follows all review and artifact preparation as the final delivery operation. `.artifacts/vertical-indicator-deploy.log` and `.artifacts/last-install.json` record the result.


## Immediate collapse after text dispatch — 2026-09-15

Removed the user-facing “Text sent” completion. Both dictation and Paste Last clear previous feedback and return to idle without setting a popup, workspace banner or completion timer for dispatched text. Internal delivery diagnostics and clipboard recovery remain intact. Confirmed insertion and actual recovery/error messages retain their existing behavior. The obsolete completion is no longer emitted by the preview exporter.

Native arm64 build and offline regression suite passed (`.artifacts/quiet-collapse-build.log`, `.artifacts/quiet-collapse-native.log`). Code review verified both callers return to idle, so the shared floating-control visibility state collapses immediately. No capture hardware was opened or integration behavior changed for this presentation-only edit. Final reviewed installation/restart is recorded in `.artifacts/quiet-collapse-deploy.log` and `.artifacts/last-install.json`.


## Microphone startup and route identity — 2026-09-15

The installed build 32 logs show the C922 input engine stopping approximately 100 ms after startup when its delayed I/O configuration notification arrived. The periodic check interpreted a nil device ID from a stopped engine as a different microphone. See `.artifacts/microphone-route-system.log` around 18:16 local time. Startup now stays pending during a 250 ms settling interval, with at most two restarts of the existing graph. Recovery validates the original input, sample rate and channel count, and is cancelled when the last consumer releases the microphone. No automatic recovery is attempted once capture has been declared ready; later real interruptions remain visible and saved audio is preserved.

The AirPods hardware check exposed a second distinction: AVAudioEngine can report its internal aggregate as CurrentDevice while retaining the same physical microphone. Input validation now resolves active subdevice UIDs to actual AudioDevices and accepts the wrapper only if exactly one subdevice supplies input and it is the requested microphone. Unknown membership, additional inputs and changed formats remain invalid. An unavailable property read is no longer labelled as proof of a route switch; packet health still detects lost input.

The first hardware test also exposed a teardown deadlock. Its process sample showed main waiting in AVAudioEngine deallocation while the engine notification queue waited for a main-queue NSOperation. Configuration observers now register on the posting queue and asynchronously dispatch state work to main, instead of synchronously waiting for main notification delivery. All four app-owned input/playback/voice configuration observers use this pattern. Evidence: `.artifacts/microphone-route-sample.txt`; the first hardware attempt timed out and was not a pass.

Apple documents that an I/O configuration change can stop/uninitialize the engine and cautions against synchronous engine teardown from the notification handler: [AVAudioEngineConfigurationChange](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/avaudioengineconfigurationchange). Aggregate subdevice enumeration, UID translation and CF ownership were checked against the installed Apple SDK's AudioHardware.h and AudioHardwareBase.h. AudioSubDevice objects do not themselves have I/O streams, so the code translates their UIDs before checking the physical input streams.

Validation before final installation:

- Native arm64 Xcode build passed: `.artifacts/microphone-route-build.log`.
- **101 core tests passed**, including late startup stop, healthy startup, changed route rejection, bounded retries and cancellation: `.artifacts/microphone-route-core.log`.
- Native offline suite passed: `.artifacts/microphone-route-native.log`.
- Signed, separate validation bundle passed three real meter-only C922 cycles at **16 kHz**, each with **17 meter updates**. It also passed an injected same-device engine stop during startup, simultaneous consumer readiness, last-consumer teardown, cancellation without microphone resurrection, and refusal to recover a different device/rate: `.artifacts/microphone-route-hardware-final.log`. No audio was saved or uploaded.
- An earlier AirPods run passed one cycle then failed on changed reported identity. After the aggregate fix, the requested AirPods were no longer available; the targeted follow-up opened no input and is **not a Bluetooth pass**: `.artifacts/microphone-route-airpods.log`. Reconnect AirPods and check repeated starts/profile transitions manually. USB unplug/replug and long meeting capture remain separate qualification.
- Code review checked startup task sharing, generation/cancellation cleanup, native exception boundaries, aggregate identity ambiguity, notification delivery and unchanged recording/clipboard behavior. The installed app was not restarted during implementation or review.

The hardware fixture accepts `CHUP_TEST_INPUT_NAME` for an exact connected device name without modifying the app's microphone preference. Run it with `CHUP_HARDWARE_MIC_TEST=1 python3 scripts/test-live-transport.py --app-path <signed-app> --timeout 60`. It requires pre-existing microphone permission and does not open a permission prompt. Final deployment and launch verification are recorded in `.artifacts/microphone-route-deploy.log` and `.artifacts/last-install.json`.


## Quiet paste completion and scrolling check — 2026-09-15

Paste dispatch and final-value confirmation now have separate presentation. An Accessibility action that returns success, or a posted Command-V pair, gets a compact “Text sent” completion when final-value readback cannot confirm insertion. This is generic for custom text controls; no Ghostty identity check is involved. Exact readback still yields “Inserted.” An uncertain failed AX call retains recovery feedback. Clipboard changes, copy failures and missing/changed destinations keep their existing recovery paths. Unverified delivery remains unconfirmed in diagnostics; the text remains on the clipboard unless the user copies something newer. No second paste is attempted.

- Native arm64 build passed: `.artifacts/scroll-build.log`.
- All **96 core tests passed**, including dispatched-without-readback, failed dispatch and clipboard/cancellation outcome cases: `.artifacts/scroll-core-tests.log`.
- Native offline regressions passed: `.artifacts/scroll-native.log`. This did not paste into the user's terminal or open capture hardware. The user's interactive Ghostty/TUI workflow was not independently retested.
- Rendered and inspected the compact completion: `Design/Previews/text-sent.png`.
- Scroll inspection covered Settings at 741, 790 and 1021 points and the layout preview suite. Native scroll documents matched their viewport widths and reported no horizontal scroller: `.artifacts/scroll-review.log`. The user subsequently reported the scrolling had disappeared. No production layout changes were made for this report. `CHUP_SCROLL_REVIEW=1` enables the preview-only sizing audit.
- Final code review checked destination revalidation, single dispatch, cancellation, clipboard revision ownership and the distinction between dispatch and verified contents. Installation/restart follows review as the final delivery operation. `.artifacts/paste-feedback-deploy.log` and `.artifacts/last-install.json` record its outcome.
 report

## Card hierarchy and screen review — 2026-09-15

Native Xcode build and the native offline regression suite passed for the layout update. Codex reviewed 37 native screen renders, covering every Settings section, library pages, meeting tabs, onboarding and key dialogs, then corrected and rerendered the visual findings before final delivery. See [UI-LAYOUT-REVIEW.md](UI-LAYOUT-REVIEW.md) for the inventory, scope and validation limits. Logs: `.artifacts/layout-build.log`, `.artifacts/layout-native.log`, `.artifacts/layout-render.log`. Gallery: `Design/Previews/layout-review/index.html` (illustrative data). Final installation is deliberately the last operation; `.artifacts/last-install.json` and `.artifacts/layout-deploy.log` record its result.

## Hardware-format exception and real alert placement — 2026-09-15

Build 29 crashed at 17:35:52 (`Chup!-2026-09-15-173552.ips`). The final SwiftUI button/executor stack was a delayed symptom: the unified log at 17:35:47.518 records AVFAudio throwing **“Failed to create tap due to format mismatch”**, with hardware input **16,000 Hz / two channels** and a cached client format of **48,000 Hz / one channel**. The exception originated in `AudioOwner.startMicrophone`, crossed a Swift async call, and was swallowed by AppKit. The report includes `SOME_OTHER_THREAD_SWALLOWED_AT_LEAST_ONE_EXCEPTION`. Removing individual executor checks in prior builds did not address this original audio exception. Local evidence: `.artifacts/alert-crash-system.log` (device metadata, no audio/transcript).

Each microphone restart now creates a fresh engine and binds its tap to the hardware input format. A narrow Objective-C boundary contains AVFAudio startup exceptions and returns an NSError before they can unwind through Swift. Failed starts revoke capture leases. Configuration notifications verify the current device, rate, channel count and running state; valid startup notifications no longer pause capture. Actual changes still pause rather than silently switching inputs. Apple's [input-node documentation](https://developer.apple.com/documentation/avfaudio/avaudioinputnode) specifies that hardware input cannot perform format conversion; the [configuration notification documentation](https://developer.apple.com/documentation/avfaudio/avaudioengineconfigurationchangenotification) explains that stopped engines retain prior connection formats. Engine replacement happens outside the notification callback.

The real panel regression initially failed: a 320-point alert kept the compact pill's x coordinate (2396), putting its right edge at 2716 on a display ending at 2560. Explicit window width and a layout snapshot prevent delayed host expansion; removing frame animation prevents an earlier compact animation from overwriting the new position. Opacity, waveform and spinner animation remain. Native measurements are coalesced outside property/view updates.

Checks completed before installation:

- **94 core tests passed**; full native offline suite passed, including an injected AVFAudio exception converted to an ordinary startup error without opening hardware. Logs: `.artifacts/mic-format-core.log`, `.artifacts/mic-format-native.log`.
- **36 real floating-window transitions on the two attached displays passed**, checking window/content bounds, screen containment and non-key status across listening, processing, short/long microphone alerts, clipboard recovery and success. The original test failed before the geometry fix. Logs: `.artifacts/panel-before.log`, `.artifacts/panel-after.log`.
- Actual alert-window content rendered to `Design/Previews/30-microphone-alert.png` and visually checked: message and both buttons are fully visible. This uses the production controller/hosting view with fixture text, not a separate mockup.

Reproduce panel checks with `CHUP_PANEL_FIXTURE=1 python3 scripts/test-live-transport.py`. The optional deployment flag `--check-microphone` runs three two-second meter-only startup/stop cycles on the selected physical input after installation and before launch; it saves/uploads no audio and validates actual binding, packet delivery and configuration stability. Physical USB unplug/replug, Bluetooth profile transitions and sustained meeting capture remain manual qualification.

**Installed Chup! 1.0 (30)** at `/Applications/Chup!.app` using `python3 scripts/deploy-local.py --launch --check-microphone`. Native offline checks passed for built, staged and installed bundles. The installed hardware check passed all three startup/stop cycles on **C922 Pro Stream Webcam, 16,000 Hz**, receiving 15 / 15 / 16 meter updates with the expected actual device and valid running configuration. No recording directory was created and no audio uploaded. Code signatures and executable UUIDs matched; the normal installed app then remained running as PID 86200 for the deployment's twenty-second check. Logs: `.artifacts/mic-format-deploy.log`, `.artifacts/last-install.json`. This is a real repeated-start check, not an acoustic accuracy test or long recording soak.

## Focus callback hardening, stage traces and comparison lab — 2026-09-15

Build 28 crashed at 17:03 local time in `MainActor.assumeIsolated` inside `TextInsertion.init`'s app-activation notification handler (`Chup!-2026-09-15-170302.ips`). The shortcut fix addressed its reported call site but did not remove the same pattern from other callbacks. All remaining app-owned native callback uses are now removed. Focus callbacks advance a locked generation counter synchronously, so they do not create an asynchronous wrong-field insertion window. Audio/sleep/display callbacks dispatch UI work explicitly to the main queue.

Automated checks for this increment:

- **94 core tests passed**, including concurrent focus-generation invalidation and trace stage/terminal-state validation. Log: `.artifacts/lab-core.log`.
- The production app-focus observer handled 1,000 notifications posted from a native background queue through a private notification center. The existing actual Quartz callback fixture also passed 1,000 ordered events. Neither test posted keystrokes or changed actual application focus.
- Production trace storage retained the latest 50 attempts, committed outcomes, and rejected late stage marks after completion. Traces contain no text/audio/name/field values. Trace writes are independent of recording durability; a diagnostic storage failure is reported without failing capture.
- The lab downloaded/verified the exact 21-file Parakeet manifest, then ran both models against synthetic English/Dutch audio. The originals in the encrypted history were unchanged; inference attempted zero URL-loading requests while the network probe blocked them. These runs read no user audio and never wrote the clipboard. Full native offline recording/clipboard/local-preview/localhost Live fixtures also passed. Log: `.artifacts/lab-model-validation.log`.
- The new Settings panels were rendered with native SwiftUI/AppKit and visually inspected: `Design/Previews/29-diagnostics.png` and `29-transcription-lab.png`. These are labeled UI previews, with synthetic timing data and no user recording. The Settings sidebar now scrolls so the additional sections remain accessible in a smaller window.
- **Chup! 1.0 (29)** was built, locally signed and installed at `/Applications/Chup!.app`. Deployment verified executable UUIDs, reran native checks on built/staged/installed bundles and verified PID 70155 for twenty seconds. A subsequent real focus test successfully alternated Finder and the installed Chup! process **12/12 times** without a crash, then restored the original foreground app. It posted no keyboard input, changed no clipboard content and requested no recording. Logs: `.artifacts/lab-deploy.log`, `.artifacts/lab-focus-check.log`; receipt: `.artifacts/last-install.json`.

The same installed process remained running for another 60.5 seconds after the focus test. The latest crash report remained the earlier build 28 report at 17:03. Log: `.artifacts/lab-running.log`. This exercises the reported activation trigger but does not certify long-term or hardware-capture stability.

Observed timings from the synthetic qualification on this M5 Max, in seconds:

| Sample | Model | Preparation | Transcription |
| --- | --- | ---: | ---: |
| English | Whisper Turbo | 47.92 | 0.76 |
| English | Parakeet v3 | 12.54 | 0.10 |
| Dutch | Whisper Turbo | 1.85 | 0.78 |
| Dutch | Parakeet v3 | 0.33 | 0.09 |

Preparation includes verified loading and a readiness inference. Models unload between runs but Core ML caches persist, explaining some variation. These are short synthetic smoke checks, not WER measurements, a hardware-independent speed claim, a peak-memory benchmark or a reason to replace the default model. Representative Dutch/English names, negation, code switching, quiet/noisy input and 16 GB Macs remain to be qualified.

Manual follow-up: switch between apps repeatedly, dictate with the configured holds and inspect Diagnostics; confirm missing-input attempts show no completed microphone-start measurement. In Transcription Lab, choose a speech recording, compare both models, cancel/retry, remove/repair Parakeet, then verify the original history remains intact. Starting capture should cancel lab work; in-flight Core ML calls may take time to unwind. Test sleep/device changes and verify new focus callbacks still prevent automatic insertion after switching fields/apps. Local diarization/VAD, offline generative cleanup and correction learning remain separate implementation work.

## Alert clipping adjustment — 2026-09-15

Floating clipboard/microphone alerts no longer impose one-/three-line truncation or fixed 48/76 pt heights. The native hosting controller measures their wrapped content, and the panel uses that size with an explicit screen-edge inset. Host-generated window sizing constraints are disabled so they cannot compete with the panel's placement. Message size changes apply immediately; fade-in, position movement and the live waveform retain their motion. Main-window notices also wrap vertically.

The native Xcode build passed (`.artifacts/alert-layout-build.log`). Actual SwiftUI/AppKit views rendered successfully and were visually inspected: `Design/Previews/28-clipboard-alert.png` and `28-microphone-alert.png`. Both sample messages and their buttons are fully visible. Reproduce with `CHUP_ALERT_PREVIEW=1 CHUP_DESIGN_OUTPUT="$PWD/Design/Previews" '.artifacts/DerivedData/Build/Products/Debug/Chup!.app/Contents/MacOS/Chup!' --render-design`. Preview messages are labeled samples and do not record audio or alter the clipboard. Multi-display placement still requires a physical check on the user's display arrangement.

## Native shortcut callback crash — 2026-09-15

The installed build 26 crashed at 15:34:59 and 16:46:32 local time. Both reports show `EXC_BAD_ACCESS` in Swift's main-executor identity check, called by `MainActor.assumeIsolated` at `ShortcutRegistry.swift:176` from the Quartz event-tap callback. Build 25 has the same crash site. This was a real event-driven crash after launch verification, not an old installed executable. Reports remain in `~/Library/Logs/DiagnosticReports/Chup!-2026-09-15-153500.ips` and `Chup!-2026-09-15-164635.ips`.

The shortcut callbacks now copy the required flags/key/button/repeat values and enqueue them on the main dispatch queue. Carbon copies the hotkey ID and press/release state. Native callbacks no longer assert Swift executor identity or access actor-isolated registry state. Invalidated tap deliveries discard queued events. Apple documents [run-loop delivery for event taps](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)) and the [executor precondition of assumeIsolated](https://developer.apple.com/documentation/swift/mainactor/assumeisolated(_:file:line:)); the reports identify the concrete failing call on this Mac.

Checks passed:

- Native arm64 Debug build and **92 core tests**. Logs: `.artifacts/shortcut-crash-build.log`, `.artifacts/shortcut-crash-core.log`.
- The actual production Quartz callback receives 1,000 in-memory keyboard events from a background queue. Each source event is mutated immediately after the callback; delivered snapshots retain their original values and order. Hotkey press/release delivery and invalidated pending work are also checked. No tap is installed and no keystroke is posted into another app by this regression test.
- Full native offline audio/local microphone-preview/clipboard/localhost Live fixture suite passed. Log: `.artifacts/shortcut-crash-native.log`. Deployment reruns the same suite on built, staged and installed bundles.

Manual follow-up: exercise Command–Shift/Fn holds repeatedly, release to process, use the Audio microphone preview, and check shortcut rebinding and sleep/wake. Automated callback delivery is meaningful regression coverage but does not qualify every hardware event sequence or prove the absence of other crashes. See `.artifacts/shortcut-crash-deploy.log` and `.artifacts/last-install.json` for installation and launch evidence.

Build 27 was installed and launched from `/Applications/Chup!.app`, PID 45903. It remained stable for the normal twenty-second deployment check plus a further sixty seconds; `.artifacts/shortcut-crash-running.log` records the additional observation. The latest crash report at that point was still the earlier build 26 report. This observation did not inject global input or certify long-term stability.

## Microphone health and local preview — 2026-09-15

- Native arm64 Debug build passed with the currently selected Xcode 27 / macOS 27 SDK, retaining the macOS 15 deployment target. Core tests: **92 passed**, including four new selection/signal-health cases. Logs: `.artifacts/microphone-health-build.log`, `.artifacts/microphone-health-core.log`.
- Production native offline fixtures passed: a twelve-second silent encrypted journal is rejected before either cloud or local provider selection, with an ignored history entry and audio retained; a later quiet signal is kept. Existing short-noise handling remains conservative.
- Meter-only preview fixture exercises the real audio-owner callback: nonzero synthetic PCM publishes bounded frequency bands, creates no file/directory, reaches no registered packet handlers and stops publishing after its consumer is removed. It also verifies microphone ownership is released at the consumer level. No microphone or output hardware is opened by this test.
- Existing native encrypted audio, alignment, sample-rate conversion, stopped-callback fencing, private fanout, playback and localhost Live fixtures passed. Log: `.artifacts/microphone-health-native.log`. The deployment script repeats these checks on built, signed staged and installed bundles.
- Read-only inspection on this Mac reported lid closed, system default **MacBook Pro Microphone**, and automatic Chup! resolution **C922 Pro Stream Webcam**. This verifies selection metadata, not the camera microphone's acoustic quality. Log: `.artifacts/microphone-selection-inspect.log`.

Manual checks remaining for this change:

1. Settings → Audio → Test microphone: speak with the lid closed. Verify the resolved device name, varying waveform and Input detected text. Stop, change device and repeat. This is a waveform/signal test, not live transcription or speaker playback.
2. Verify stopping, leaving Audio settings, waiting 30 seconds and starting dictation each release the preview microphone. Deny/cancel the first microphone request and verify no delayed recording begins; retry after granting permission.
3. Start a test and unplug the USB input; check the disconnect message. Reconnect and explicitly restart. During dictation/meeting capture, unplug or change the default/rate and verify audio is preserved and capture pauses; resume a meeting with the new input into a separate leg. Qualify Bluetooth profile changes and sleep/wake on hardware.
4. In automatic mode, close/open the lid and verify selection at the next start. With multiple external inputs and a blocked default, verify Chup! asks for a selection. An explicit unavailable input must not silently become another microphone.
5. Dictate after choosing the working external microphone. Check the real EQ, transcript and original-field paste. Compare quiet speech, natural pauses, mute/digital silence and a short noise tap; speech must remain recoverable, and confirmed silence must not reach cloud or local transcription. History should show the chosen microphone and allow playback.

Physical capture, acoustic quality, UI navigation and these hardware transitions have not been certified by the offline fixtures. Deployment receipt: `.artifacts/last-install.json`; installation/launch log: `.artifacts/microphone-health-deploy.log`.

Environment: Apple silicon macOS, Xcode 26.6 (17F113), Swift 6.3.3. Target: macOS 15+, arm64. Build validation used XcodeBuildMCP 2.7.0 CLI with `CODE_SIGNING_ALLOWED=NO`.

## Checks performed

- Native Xcode application build, including Core Audio process-tap APIs, ScreenCaptureKit, AX, Settings, SwiftUI views, local core package and asset compilation.
- Core package automated tests: note persistence across database reopen; duplicate/colliding request IDs; stale version rejection; Undo preserving newer edits; speaker/text corrections surviving provider retry; FTS query; unsupported/foreign summary sources; encrypted journal truncation recovery and tamper rejection; routing privacy; held shortcut arbitration, repeat suppression, release/reset, longer-prefix cancellation; wrong-field and clipboard-generation predicates; played-frame interruption accounting; meeting prompt expiry/snooze/deduplication; scoped note tools.
- Backend contract tests: fabricated/foreign citations, empty evidence, provisional filtering, invalid timing/duplicate identities, chunk ordering, and separation of Live and Realtime startup contracts.
- Native app launched in `--render-design` mode. Actual SwiftUI/AppKit views rendered to PNG. Native text fields and scroll content were inspected; the initial ImageRenderer limitation was fixed with an NSHostingView bitmap path for app screens.
- Icon Composer document exported by `ictool`; Xcode compiled the icon. Normal/retina macOS asset sizes also provided. No submission claim.
- Backend JavaScript syntax and local test suite. No production key or real meeting data used.

Final automated result: **16 Swift tests + 7 backend tests passed (23 total)**. The backend suite includes an actual loopback server test of authentication and malformed-input rejection without calling OpenAI. Reproduce with `./scripts/test.sh`.

## Not performed — required before release

No physical mic/call recording, live OpenAI API call, real meeting detection, two-hour audio soak, full-screen/display hardware matrix, AX insertion into third-party apps, VoiceOver audit, Bluetooth/USB switching, speaker recognition accuracy evaluation, AEC/mix-minus test, signed TCC test, notarization or App Store upload has been claimed.

## Exact interactive Xcode validation

1. Open `Chup.xcodeproj`, choose Chup → My Mac. Set a Development signing team and run. Verify no recording starts at launch or hover. Grant each permission only from its related action. Repeat denial/revocation; verify an actionable state rather than false recording.
2. Open TextEdit with a selected phrase. Invoke hold dictation. Release; verify insertion only when app/element/value/selection stayed unchanged. Repeat with another field, another app, change then return to original app, secure password fields, and typing during transcription. Verify history recovery and no Return is ever sent. During clipboard fallback, copy rich content in another app; the newer clipboard must survive.
3. Rebind all shortcuts. Close Settings and restart. Test Fn, Fn+Space, Fn+Control, no-Fn preset, mouse side button, autorepeat and overlapping presses. Test delayed release, permission revocation, sleep, and session interruption. Verify longer chords never finish/inject a shorter dictation. Report unsuppressed-key behavior in target apps.
4. Enable meeting detection. Join Zoom/Teams and browser calls. Verify a single prompt after sustained input activity, 10-second dismissal with no mic start, two-minute snooze, and no repeat during the same call. Test muted startup, helper-process audio, multiple simultaneous apps and an ordinary browser mic use false positive. Accept only after reviewing capture scope.
5. Start a microphone-only session, then selected-app call capture. Check independent track files/meters, no remote loopback, pause vs conference mute, resume legs, stop/save. Kill the process during a journal append. Relaunch, verify recovered status, preserved notes and recoverable chunks. A corrupt authenticated frame must error instead of silently passing.
6. Configure the loopback backend from `.env.example`; verify actual access to each named model independently. Enable cloud processing. Disconnect the network while recording. Audio/notes must continue. Retry final transcription and verify completed chunks are not uploaded again. Compare live capture-window labels with final timing.
7. Run a two-hour real call and inspect alignment at 0/30/60/90/120 minutes. Disconnect USB, switch Bluetooth profiles, change rate/default device, revoke app audio, sleep and wake. Confirm gaps and no recording claim during sleep. Test browser audio outside the meeting tab to verify scope disclosure.
8. Rename/merge/split speakers, edit transcript and notes, then retry transcription and regenerate summaries. Manual edits must survive. Challenge summary extraction with negation, proposals versus decisions, ambiguous dates, missing owners and injected instructions. Verify citations actually support claims, not merely that JSON parses.
9. Private/broadcast now have native route-gated prototype controls. Before production qualification, test physical mic + assistant outgoing mix, remote exclusion, local assistant monitoring, headphone/speaker AEC, interruption and rendered-frame ledger, private context reset and independent backend write cancellation. No success acknowledgment before durable write.
10. Audit VoiceOver, keyboard-only access, Reduce Motion, light/dark contrast, scaling, multi-display placement, full-screen Spaces and transparent hit regions. Archive, sign/notarize or submit only after the release gates pass.

## Appearance and motion update — September 14, 2026

XcodeBuildMCP native build passed after the fixed light appearance, persistent rail host, dark material and animation changes. Regenerated and visually inspected the native panel and rail PNGs. `node scripts/render-motion.mjs` passed the browser motion checks documented in MOTION.md and exported a 15.23-second MP4 plus looping GIF. Inspected the speaking screenshot and video frames. No native audio playback or physical routing claim follows from these preview checks. The existing core/backend suites were not rerun for this UI-only update.

## Build-out increment — September 14, 2026

Native Xcode build passed with the icon rail, continuous meeting playback, saved assistant conversations and Live output foundation. **25 Swift + 9 backend tests passed (34 total)**. The native `--validate-audio` check also passed, rendering encrypted fixtures through AVAudioEngine offline across track/leg boundaries and beyond initial lookahead. A real local HTTP disconnect aborted a stubbed provider call. See PLAYBACK-AND-ASSISTANT.md for exact checks and limitations. Earlier test counts above describe previous increments.

## Iterations 1–3 — September 14, 2026

Final native build passed through XcodeBuildMCP 2.7.0, with no source warnings. **32 Swift tests + 12 backend tests passed (44 total).** The native `--validate-audio` check passed again after the final changes. Exact implementation and remaining engineering are in [ITERATIONS-1-3.md](ITERATIONS-1-3.md); earlier counts in this file are historical.

New automated coverage includes accelerated two-hour encrypted journal rotation (240 chunks, 7,200 full one-second packets), two-hour clock drift simulation, discontinuities/rate changes/backwards clocks, old-file model decoding, window bounds, duplicate segment rejection, transaction rollback, changed-segmentation correction review across reopen, boundary identity/track isolation, and literal snippet/noncascading alias behavior. Native offline tests use the production AudioOwner to check flush-on-close and stale-source fencing; shared playback/export validates explicit clock anchors and the recovery index. Backend tests run real loopback HTTP requests against a stubbed provider to inspect multipart diarization references and reject failed fidelity checks. They do not establish actual model accuracy.

Additional signed Xcode checks for this build:

1. Settings → Audio: choose a USB microphone by name. Start a mic-only meeting, then dictate concurrently. Verify a single input source, two durable consumers and no unexpected default-device switch. Disconnect USB, change Bluetooth profile and change tap format. Expect a paused mic or remote-only gap, and explicit recovery. Stop/change/start is required to select a different microphone.
2. Stop and record again in the same meeting. Verify the new leg appears after old audio, and earlier transcript windows remain unchanged. Stop while the microphone permission prompt or call capture startup is pending; then immediately start another meeting. Late callbacks must not appear in its tracks. Sleep during startup and while recording; waking must not restart capture.
3. Force-close the app during a recording. Relaunch and use Transcript → Inspect recovery. Verify packet count, incomplete-tail/corrupt-file reporting, unknown crash gap, and no microphone activation. Compare recovery end time with playback end time.
4. Register ordinary chords with Input Monitoring denied. Test the no-Fn preset; global Fn/mouse/Escape still require monitoring permission. Rebind in Settings, close it, restart, exercise overlapping chords and held keys across sleep. Test actual key suppression/registration collisions in a second app. Automated resolver tests do not qualify real keyboard event ordering.
5. Dictate in TextEdit and a browser, change focus within the same app and return before transcription finishes, then change clipboard formats during fallback. Verify saved text with no unintended insertion. Retry a selected-text command after changing global language/style; it must use its saved context. Exact snippets retain their line breaks. Negation/number changes rejected by the cleanup reviewer leave the original in history.
6. Transcribe a multi-window recording. Disconnect the backend, Cancel and Retry. Confirm already committed identical windows are skipped. Correct text and speaker, then choose Reprocess and review corrections. Changed boundaries must show current/proposed text, with explicit replacement required and stale review rejection after another edit.
7. Select a finalized, clean speaker interval of at least two seconds. Listen, confirm enrollment and save. Check Settings → Meetings: matching starts off. Enable up to four references, transcribe with real provider access, and assess the displayed “voice match” against known ground truth. Rename, disable and delete profiles; deletion removes their local encrypted reference files and prevents future uploads. Previously sent references and historical transcript assignments have separate retention semantics.
8. Conduct a real two-hour Zoom, Teams and browser capture with alignment measurements and a USB/Bluetooth/network fault schedule. This remains unperformed. So do actual provider accuracy, biometric match quality, signed TCC/AX cross-app validation and broadcast/private routing qualification.

Reproduce offline validation after building:

```sh
swift test
npm test --prefix backend
'.artifacts/DerivedData/Build/Products/Debug/Chup!.app/Contents/MacOS/Chup!' --validate-audio
./scripts/render-design.sh
```

Native UI snapshots were regenerated and the new speaker/reference screen inspected. They use labeled design samples, not real biometric enrollment. No new voice connection or microphone recording was opened to render them.

## Iterations 4–6 — September 14, 2026

Native XcodeBuildMCP build passes with no source warnings. **40 Swift + 16 backend tests pass (56 total).** Native offline audio, real localhost WebSocket transport and LiveConversation orchestration tests pass. The separate arm64/macOS 15 driver prototype builds but is not installed. Native actions/private-voice screens were exported and visually inspected; sample content and disconnected state are labeled. Full details: [ITERATIONS-4-6.md](ITERATIONS-4-6.md).

New tests reject cross-meeting action-ID collisions, duplicate/stale action writes, changed summary evidence, unsupported semantic claims, foreign retrieval sources, and early delegation before the addressed question ends. They verify preserved pinned edits, independent provisional-outline copies, private-context exclusion, revoked queues, partial rendered-frame counts, remote-free outgoing mixing, and omission of private mic packets from the meeting journal even if privacy changes before the writer consumes them. A test caught nested SQLite transactions in summary-version storage; the final implementation uses one transaction with direct inserts, and the regression passes.

```sh
swift test
npm test --prefix backend
python3 scripts/test-live-transport.py
python3 scripts/build-virtual-mic.py
./scripts/render-design.sh
```

Additional interactive Xcode validation for these features:

1. In Settings → Meetings, opt into live outlines; record and live-transcribe. Verify provisional labeling, no unrequested writes, and local notes/audio surviving an outline network failure. Stop/refine, then verify the atomic final summary/version. Edit the transcript while a summary request is pending; its stale result must be rejected. Pin an interpretation and regenerate; the pinned text must survive.
2. Save an action from a source-backed summary. Leave owner/date empty; use an ambiguous date, change status, and Undo. Retry the same proposed assistant write; only one action or note change may exist. Switch meetings and verify Undo never targets the previous meeting. Click a source; verify transcript navigation and recorded interval playback after capture stops.
3. Write Private thoughts. Inspect backend test traffic using synthetic data: these thoughts never appear. Ask follow-ups privately, then change to broadcast and verify previous private notes/questions/history are absent from the new session and backend scope. Test injected commands inside transcript quotes; only the explicit current request can propose a write.
4. Follow [driver installation/qualification](../DriverPrototype/README.md) on a development Mac. Verify correct physical mic, pinned headphones, exclusive selected-process virtual input, and rejection of unrelated input readers and unclassified outputs. These checks are not claimed to eliminate the 100 ms device-switch race; resolve that before production privacy promises.
5. Connect voice without addressing it; no physical mic samples may be uploaded. Hold/Ask, finish, inspect correlated mute/unmute acknowledgments and delegation ordering. Interrupt before/during/after backend completion. Old audio must remain revoked, while completed proposals remain reviewable and committed writes remain committed.
6. During private voice, verify outgoing mic silence with a measured conference loopback, private sample omission in meeting/caption tracks, and a separate encrypted question journal. Disconnect the voice network or headphone device; recording/notes continue and outgoing mic never automatically resumes. Explicitly resume, then switch to broadcast and check a fresh context and labeled assistant track.
7. Measure the outgoing physical-mic/assistant mix and local monitor, verify remote exclusion, compare partially rendered audio against the ledger, and assess driver latency/clipping/underruns. Test app input changes, helper processes, USB/Bluetooth rate changes, source loss, sleep/wake and concurrent dictation. Speakers remain blocked until AEC exists and passes tests.

None of the provider/hardware/conference procedures above were performed in this environment. Local fixtures do not establish OpenAI account access, actual model accuracy, physical private-input protection, remote receipt, signing or distribution readiness.

## Iteration 7 — September 14, 2026

Current results: **50 Swift + 20 backend tests passed (70 total)**, native XcodeBuildMCP arm64 build passed, native offline audio/localhost Live fixture passed, and the separate Chup! Mic driver built without installation. Native onboarding, Permissions and Privacy views were rendered and inspected. Earlier counts in this document are historical. Detailed scope, test coverage and limits: [ITERATION-7.md](ITERATION-7.md).

Additional signed Xcode and fault checks still required:

1. Run a consistently signed Chup!.app. Complete onboarding once with each workflow selection, then reopen it from General. Skip permissions and confirm typed notes work. Request Microphone/Accessibility/Input Monitoring individually; deny, grant and revoke them in System Settings, return to Chup!, and verify status/shortcut refresh. Never infer audio-only permission from screen capture preflight.
2. Start selected-app capture to trigger process-tap audio permission. Separately opt into ScreenCaptureKit fallback. Verify permission explanations, audio-only storage, source selection and browser-tab limitation. Exercise any macOS quit/reopen requirement while preserving the current recording first.
3. In General enable launch at login. Check the actual service status and Login Items pane; log out/in and confirm the app opens without capturing. Disable the service, log out/in, and confirm no launch. Test OS-disabled/pending-approval state and app relocation/update. This registration was not performed by the automated validation.
4. Use a disposable copy of a prior preview workspace with realistic audio and its own copied test keys. Verify plaintext migration preserves notes, receipts, FTS and revisions. Interrupt at export, verify, replace and first encrypted open; repeat with disk full and missing/wrong keys. Inspect main/WAL/temp files for plaintext markers. The unit test covers committed WAL recovery and an orphan staging file; it is not a full power-loss/disk fault matrix.
5. On fixture meetings, exercise each retention age and confirm the deletion count before saving. Delete a meeting with private thoughts, question audio and voice enrollment reused by another meeting. Interrupt deletion, relaunch and run cleanup; verify files, metadata, FTS and related upload requests are removed and late callbacks fail. Disconnect the backend, then reconnect and confirm queued cache deletion. Confirm exported copies and provider data are not claimed as deleted.
6. Export ordinary and private JSON; compare fields. Create a password backup, verify it, restore for next launch, relaunch and compare recording paths/playback, notes, revisions and receipts. Wrong password, missing/tampered chunks and existing destinations must fail without changing the current workspace. Test large files, low disk space and interrupted restore. Keep a known-good external backup and review any restored retention policy.
7. Interrupt real provider calls before/after backend step completion and app result commit. Resume the same ID; inspect provider accounting to confirm cached steps do not call twice. For unknown acceptance expect a stopped retry and an explicit new-attempt choice. Change transcript evidence before recovering a summary and expect stale-scope rejection. Recover assistant proposals without an automatic note write, paste or voice session.
8. Compare actual file/live/voice/response usage against the provider account. Check partial and final snapshots, missing final events, interruption and model-specific text/audio/cached token pricing. Current UI costs are user-rate estimates, not invoiced charges. The tests validate local ledger reconciliation only.

Reproduce current local checks:

```sh
./scripts/build.sh
swift test
npm test --prefix backend
python3 scripts/test-live-transport.py
./scripts/render-design.sh
python3 scripts/build-virtual-mic.py
```

No OS permission was granted, login service registered, production data deleted, real provider call made or driver installed by these checks.

The renamed interactive motion preview also passed its browser checks and regenerated the Chup! MP4/GIF (`node scripts/render-motion.mjs`, `.artifacts/iteration7-motion.log`). The speaking frame was visually inspected. This is illustrative motion, not an actual assistant audio session.

## Complete Chup! identity rename — September 15, 2026

There are no existing recordings, so the app now uses a fresh Chup identity throughout: `Chup.xcodeproj` / `Chup` scheme, `ChupCore` module/tests, `ChupApp`, `ChupIcon`, `com.chup.mac` bundle and Keychain service, `Application Support/Chup`, `CHUP_TOKEN` backend configuration and `ChupMic2ch_UID` / `com.chup.mic.prototype` driver identity. The displayed app and executable retain the requested exclamation mark: **Chup!**. XcodeGen's explicit product name also makes the launch scheme point to `Chup!.app`.

Native app and separate uninstalled driver builds passed. All **50 Swift + 20 backend tests** passed after renaming imports, paths and environment variables. Native offline audio and localhost Live checks passed using `CHUP_TEST_PORT`. A source/configuration/documentation and filename audit found no old product names or legacy identity aliases. Generated caches and historical build logs are excluded from that audit. Existing recording directories and Keychain entries outside the repository were not accessed or deleted.

Logs: `.artifacts/chup-rename-{build,core,backend,driver,live}.log`. This rename does not change the previously documented hardware/provider/distribution qualification limits.

## Versioned local deployment — September 15, 2026

Installed **Chup! 1.0 (3)** at `/Applications/Chup!.app`, signed with the available Apple Development identity. `codesign --verify --deep --strict` passed on the installed bundle. The installed executable passed the production offline audio and localhost Live fixtures without opening a microphone or reaching OpenAI. XcodeGen now binds bundle versions to MARKETING_VERSION/CURRENT_PROJECT_VERSION, and `scripts/deploy-local.py` increments the build number before each build/install.

The first signed build exposed a Team ID mismatch between the app launcher and Xcode's separate Debug dylib. The failed installation was removed. Signing embedded libraries before the containing bundle fixed the launch failure; both the signed staging app and final installed app then passed native validation. No library-validation exemption was added. Logs: `.artifacts/deploy-current.log`, `.artifacts/deploy-build-3.log`; installation receipt: `.artifacts/last-install.json`.

Previous installations are staged for rollback and archived after successful replacement. A running Chup! blocks replacement without force-quitting; that running-recording case has not been exercised. This is local development delivery, not notarization, App Store release or hardware/TCC qualification.

## Multiple global shortcuts — September 15, 2026

Settings now permits several simultaneous bindings for each action. Each binding has its own persisted ID; older saved settings acquire IDs without replacing their gestures. The native recorder retains the full modifier combination through staggered release, so pressing Control–Shift and releasing one modifier first still saves Control–Shift. Add/Edit/Remove operates on a single binding. Exact gesture collisions are rejected; registration failures disable only the affected binding. Carbon registrations use fresh IDs to reject queued events from obsolete registrations.

The resolver tracks suppression and repeat latches per binding, with one active hold lifecycle per action. Overlapping alternative holds hand off without a second start/finish. Longer conflicting chords cancel their shorter active hold; unrelated aliases cannot clear prefix suppression. Test mode and rebinding reset transient shortcut state. Permission loss resets the native monitor. Fn/modifier-only/mouse monitoring still requires Input Monitoring and does not suppress normal system behavior.

**58 Swift tests passed**, including eight new tests for legacy settings round trips, separate alias hold/release, partial modifier/key release, repeat latches, overlapping hold handoff, promoted prefix suppression, duplicate conflicts and mouse/reset behavior. Native app validation exercises actual ShortcutRegistry capture, persistence/reopen, per-binding edit/remove and conflict rejection using isolated preferences and in-memory events. It registers no global hooks and posts no input. Existing native offline audio/localhost Live fixtures also passed. The native Shortcuts screen was rendered with labeled sample Fn + Control–Shift bindings and visually inspected (`Design/Previews/15-shortcuts.png`). Backend code was unchanged; its suite was not rerun for this change.

Still required interactively: enable Input Monitoring; add Control–Shift under Hold to dictate; close Settings and try Fn on the Mac keyboard and Control–Shift on an external keyboard; release modifiers in both orders; relaunch and verify both remain. Exercise two ordinary chords for one action, conflicting registrations, sleep/wake and permission revocation. These physical keyboard/event-ordering checks were not performed by the fixture.

Logs: `.artifacts/multi-shortcuts-{core,build,native,design,deploy}.log`. The deployment receipt identifies the installed version after signature verification and native checks on the installed copy.

Deployment completed: **Chup! 1.0 (4)** at `/Applications/Chup!.app`. The signed staging and installed copies both passed native shortcut capture/persistence and existing audio/Live fixtures. Strict signature verification passed. Build 3 was retained under `.artifacts/InstalledBackups/20260915T065410856089Z/Chup!.app`; this also exercised replacement of an existing installed version.

## Increment 8 independent qualification — September 15, 2026

**Chup! 1.0 (5)** is installed at `/Applications/Chup!.app`. The installed bundle passed strict signature verification and the native shortcut/audio/localhost Live fixtures. **65 Swift tests and 22 backend tests passed.** Seven real-provider synthetic smoke checks passed, including GPT-Live-1 itself. The initial unsupported summary was rejected; action metadata generation/validation was corrected before the passing run. See [PHASE-8.md](PHASE-8.md) for evidence and exact limits.

New native cases cover encrypted waveform cache reuse, tamper recovery and invalidation; aligned full-track WAV publication; cancellation both during rendering and immediately before publication; and explicit panel keyboard eligibility. A separately enabled accelerated two-hour sparse export produced a 345,600,044-byte WAV with audio at the final absolute offset. No hardware capture or VoiceOver session was run.

Developer ID packaging builds optimized Release code with hardened runtime and a secure signing timestamp, runs native fixtures on the signed app, and signs the DMG. The manifest reports `notarized: false`; no Apple upload, driver installation or public release occurred. Local deployment retains build 4 for rollback. Exact current artifacts are listed in `.artifacts/last-install.json` and `.artifacts/Distribution`.

Run the [manual acceptance checklist](MANUAL-TESTS.md) on the installed app. Its engineering-gaps section is intentionally distinct from physical tests.

## Permission discovery and status clarity

Updated onboarding/Settings permission cards with a 15 pt semibold, padded olive **Access enabled** badge and explicit icon/text. Added missing-app instructions for macOS's + button, exact running-bundle reveal in Finder, and a source-selection sheet for first meeting-audio capture. Opening that sheet does not record or create a note; Start recording explicitly creates the new meeting. A meeting app is required on this permission-setup path, and active meetings block starting another.

Native build and existing offline checks passed. No permission grants or capture sessions were triggered by automation. `Design/Previews/16-permission-status.png` uses explicitly labeled sample permission states solely for visual review. System Settings interaction and OS permission dialogs still require manual verification.

Delivery status: build **1.0 (6)** was built and passed native fixtures. Installation was deferred because `/Applications/Chup!.app` was running; it was not force-quit. The installed copy remains **1.0 (5)** until the user closes it safely and deployment resumes. The updated badge preview was rendered and visually inspected.

Permission UI delivery completed: **Chup! 1.0 (7)** installed at `/Applications/Chup!.app`. The user explicitly authorized force-quitting the running app for this replacement. Strict signature verification and installed native fixtures passed; the updated app was reopened. Log: `.artifacts/permissions-deploy-final.log`. This supersedes the earlier build 6 deployment deferral.

Permission UI cleanup: removed the expanded missing-app help and Finder button. **Chup! 1.0 (8)** built, signed, installed at `/Applications/Chup!.app`, and restarted. Installed native checks and strict signature verification passed. Log: `.artifacts/permission-cleanup-deploy.log`.

Permission title links: replaced the text Privacy button and breadcrumb with an arrow next to the title, including a VoiceOver label and pane-path tooltip. Removed empty action rows for enabled permissions. Build 9 was blocked before compilation because xcodebuild reported an unaccepted Xcode/SDK license (exit 69). The installed build 8 was reopened; no replacement or successful build is claimed. Log: `.artifacts/permission-arrow-deploy.log`.

Compact permission links delivered: **Chup! 1.0 (10)** installed and restarted at `/Applications/Chup!.app` after the user accepted the Xcode license. Each permission title now has a small arrow to its Privacy pane; the text button, breadcrumb and empty action row are removed. Native build, installed fixtures and strict signature verification passed. Log: `.artifacts/permission-arrow-deploy-final.log`.

Permission refresh control: replaced Check access again text with a 40 pt circular button, native activity animation and a confirmed-success checkmark. Unresolved permissions use a distinct icon and accessible description; permission changes invalidate success immediately. Checks cancel when the view disappears and cannot overlap. **Chup! 1.0 (11)** installed and restarted. Native build, installed offline checks and strict signature verification passed. Actual permission and Reduce Motion interaction remain manual checks. Log: `.artifacts/permission-refresh-deploy.log`.

Permission refresh correction: restored the visible Check access again label beside the animated icon. Explicit result states distinguish enabled (checkmark), missing/denied access (exclamation), capture-only verification pending (clock) and no selection (refresh). Unknown capture access no longer looks like a failure; it is not falsely claimed as granted. **69 Swift tests passed**, including four new result-state tests; installed native checks and signature verification passed. **Chup! 1.0 (13)** installed and restarted. Logs: `.artifacts/permission-refresh-core.log`, `.artifacts/permission-refresh-result-deploy.log`.

## Build 14 — dictation recovery, noise filter and status indicator

September 15, 2026: native Xcode build passed with Xcode 27. **72 core tests passed**. Deployment signed and strictly verified `/Applications/Chup!.app` version **1.0 (14)** and passed native fixtures against the installed copy; the installed app was restarted. Logs: `.artifacts/dictation-recovery-build.log`, `.artifacts/dictation-recovery-core.log`, `.artifacts/dictation-recovery-native.log`, `.artifacts/dictation-recovery-deploy.log`.

New coverage: saved dictation microphone track renders without transcription; a short silent encrypted clip is ignored without deleting its journal; pure policy tests retain uncertain/long/invalid clips and short speech. Optional `CHUP_SHORT_SPEECH_FIXTURES` checks use deterministic synthetic noise and macOS-generated English “No” and Dutch “Nee.” The noise was rejected and both words retained by the production local SoundAnalysis path. These checks did not capture user audio, play sound through hardware or call a cloud provider. They do not establish representative classifier accuracy.

Native design renders `17-dictation-indicator.png` and `18-dictation-recovery.png` use explicitly labeled sample state. A read-only SpeechTranscriber availability query found English assets but no supported Dutch locale on this host; no ASR weights were downloaded. Local transcription remains research, not a shipping fallback.

Manual acceptance:

1. Play an existing failed-transcription recording, pause and seek; verify audible output and that another clip stops the previous one.
2. Hold Command–Shift in a text field; verify the right-edge indicator appears without focus changing. Release to process. Repeat with the rail disabled, on another display, in a full-screen app and across Spaces.
3. Make an accidental brief silent/noise-only tap. Verify it is recoverable under Show ignored clips and does not insert text. Then dictate short “No” and “Nee,” softly and normally, and confirm neither is lost.
4. Start dictation while playing saved audio and confirm playback stops before capture. Check output-device switching and cancellation.
5. Confirm the shortcuts preset reads Default preset.

## Shortcut timer crash follow-up — September 15

The build 14 crash report at 11:53:12 identifies `ShortcutRegistry.enable(request:)` line 142, inside `MainActor.assumeIsolated` from a Foundation timer, with EXC_BAD_ACCESS/SIGBUS in executor identity comparison. This locates the failing path; it does not establish an upstream runtime root cause. The three periodic app timers now explicitly enqueue MainActor work and discard queued work after invalidation. Synchronous input/focus callbacks retain their existing ordering.

The native Xcode build and offline/localhost fixture suite passed. A new native regression check exercises repeated Foundation timer delivery and invalidation before queued actor work runs. No user audio, cloud service or global input posting is involved. Logs: `.artifacts/timer-crash-build.log`, `.artifacts/timer-crash-native.log`, `.artifacts/timer-crash-deploy.log`. Long-running hardware/shortcut qualification remains manual.

Reference: [Swift actor-isolation diagnostics](https://docs.swift.org/compiler/documentation/diagnostics/actor-isolated-call/) documents using an explicitly actor-isolated task to enter an actor from a nonisolated context.

Delivery verified: **1.0 (15)** installed and restarted. The same installed process remained alive throughout a 45-second observation with no new crash report. This is a launch smoke check, not evidence of long-session stability.

Button label update: dictation's idle button now reads **test**. Chup! 1.0 (16) installed at `/Applications/Chup!.app` and reopened. Native build, strict code-signature verification and installed fixtures passed. Log: `.artifacts/test-button-deploy.log`.

## Local dictation integration — September 15

Native Xcode build and **75 core tests passed**. Real Whisper large-v3-turbo inference was run on this M5 Max with generated English and Dutch speech, passing through encrypted journals, the production dictation pipeline and database commits. The synthetic phrases retained the USB microphone terms and negation. These are smoke checks, not representative WER/latency qualification or a model benchmark. No user recordings were inspected, uploaded or played.

The initial opt-in test downloaded 629,711,418 bytes of public model/tokenizer artifacts and verified the pinned SHA-256 hashes. A subsequent run reused installed assets with no model download. A URL loading probe rejected all network requests during fresh model initialization and local inference: zero attempts occurred in local-only mode despite configured cloud settings. A forced cloud failure caused exactly one cloud attempt followed by local transcription. Cloud-disabled Auto made no additional attempts. Local selected-text editing saved the instruction and returned an error rather than insertion text; cancellation returned no result. Repeated startup model checks shared preparation successfully.

Commands:

```sh
swift test
# Generated WAV fixtures, no microphone or playback:
say -v Samantha -o .artifacts/local-speech-fixtures/english.wav --data-format=LEI16@24000 'We need to test the USB microphones tomorrow. Do not change the launch date.'
say -v Xander -o .artifacts/local-speech-fixtures/dutch.wav --data-format=LEI16@24000 'We moeten morgen de USB microfoons testen. Verander de datum niet.'
CHUP_LOCAL_SPEECH_FIXTURES="$PWD/.artifacts/local-speech-fixtures" python3 scripts/test-live-transport.py --timeout 300
# Add CHUP_INSTALL_LOCAL_MODEL=1 only to explicitly install/repair the model first.
```

Logs: `.artifacts/local-speech-build.log`, `.artifacts/local-speech-core.log`, `.artifacts/local-speech-native.log`, `.artifacts/local-speech-native-offline.log`, `.artifacts/local-speech-deploy.log`. Default deployment fixtures do not download or run the model; the ASR check is explicit and separate.

Manual checks remaining: real microphone dictation, recovery of your existing entries with Retry audio, permission/focus behavior, disconnected internet on physical networking, download interruption under poor connectivity, long dictation boundaries, model memory pressure and lower-memory Macs. Local meeting diarization and offline AI editing/summaries are not implemented by this dictation fallback.

Installed delivery: **Chup! 1.0 (17)** was signed, verified and installed. The real English/Dutch local ASR/network-blocking suite also passed against the signed installed bundle (`.artifacts/local-speech-installed.log`), without another model download. The app was then reopened normally.

## Circular processing and automatic clipboard recovery

**78 Swift tests passed**. Coverage includes original/current destination fingerprints, selection replacement in UTF-16, invalid ranges and split-surrogate rejection, and truthful recovery messages. A regression test caught Foundation accepting a range inside an emoji surrogate pair; expected insertion text now rejects those boundaries explicitly.

Native fixtures passed for missing-field recovery through the actual TextInsertion method, all-format clipboard restoration, preserving a newer user copy and cancellation before delivery. These used an isolated named pasteboard: no general clipboard mutation, global input posting or capture. Native UI renders were inspected for the thinking state and copied-text message. Existing native audio/shortcut/localhost Live fixtures passed.

Logs: `.artifacts/dictation-delivery-core.log`, `.artifacts/dictation-delivery-native.log`, `.artifacts/dictation-delivery-build.log`, `.artifacts/dictation-delivery-final-deploy.log`. Previews: `Design/Previews/19-dictation-processing.png` and `20-dictation-copied.png`.

Physical acceptance still needed:

1. Dictate in a TextEdit text field. Verify listening → circular thinking → inserted text, with no Return/Send.
2. Dictate without a text field or change focus while processing. Verify the brief copied message and manual Command-V recovery.
3. Test a browser/chat editor; if AX insertion is unavailable, verify paste confirmation and clipboard restoration.
4. During a delayed paste, copy something else. Verify the new clipboard content survives and Chup! does not claim its transcript was copied.
5. Start another dictation while an old completion message is showing. Verify it disappears without hiding the new listening/processing state.

The app conservatively reports unconfirmed paste when an editor transforms the inserted text or does not expose a readable AX value. No second insertion is attempted after an uncertain AX write. Actual cross-application paste behavior and VoiceOver announcements are not certified by offline fixtures.

Dictation delivery update: **Chup! 1.0 (19)** installed at `/Applications/Chup!.app` and reopened. Circular processing is visible in the compact rail, expanded rail, floating indicator and workspace sidebar. Completion verifies the original destination; missing/failed insertion copies the transcript and shows brief nonactivating recovery feedback. Newer clipboard actions remain protected. 78 core tests and installed native fixtures passed; real cross-application paste remains a manual acceptance check.

## Live waveform update

**81 core tests passed**. Added coverage verifies visible quiet-speech scaling, silent/invalid input, bounded clipping, rolling microphone history and reset after silence. Native audio, shortcut, clipboard and localhost Live fixtures passed. The native indicator preview uses explicitly labeled sample meter values; no microphone capture or user speech was used for automated validation.

The audio owner already publishes microphone peaks at approximately 10 Hz. WorkspaceState now maintains five recent normalized levels shared by the listening views. SwiftUI interpolates bar changes over 80 ms; zero packets drain the history, and the workspace timer clears it after meter packets go stale. The recording signal and speech/noise classifier are unchanged.

Logs: `.artifacts/voice-waveform-core.log`, `.artifacts/voice-waveform-build.log`, `.artifacts/voice-waveform-native.log`, `.artifacts/voice-waveform-deploy.log`. Manual check: hold the configured shortcut, speak softly and normally, pause, then release. Verify visible voice-driven movement, quiet settling and the thinking transition. Repeat in the collapsed rail and expanded Dictate button, and with Reduce Motion enabled. Physical microphone-to-screen animation remains a manual acceptance check.

Live waveform delivery: **Chup! 1.0 (20)** installed at `/Applications/Chup!.app`, signed and verified, with installed native fixtures passing. The app was reopened. Live microphone history now animates all dictation listening surfaces; 81 core tests passed. Physical speech-to-screen behavior remains a manual check.

## Capability-based custom editor paste

85 core tests passed, including capability routing without application identifiers, control/newline rejection, all destination guards and rendered-text confirmation. Native checks passed for unrelated typing/clicking/scrolling and interrupted event streams invalidating the destination while the configured dictation chord does not. The synthetic fixture initially used an untyped CGEvent that could not carry a keyboard code; it was corrected to construct a keyboard event and rerun successfully. No global input was posted by these checks. Existing clipboard preservation and offline native fixtures also passed.

Read-only inspection of installed Ghostty 1.3.1 showed AXTextArea, a non-settable selected-text attribute, a zero-length selection at zero, and a rendered screen value. Only metadata and the character count were inspected in tool output. Its [official source](https://github.com/ghostty-org/ghostty/blob/v1.3.1/macos/Sources/Ghostty/Surface%20View/SurfaceView_AppKit.swift) confirms the screen buffer and cached readback semantics. This prompted a generic capability-based path; application names and bundle IDs are absent from the insertion policy.

Build and tests: `.artifacts/focused-paste-build.log`, `.artifacts/focused-paste-core.log`, `.artifacts/focused-paste-native.log`. Deployment: `.artifacts/focused-paste-deploy.log`.

Manual acceptance remains: single-line dictation in a terminal and a custom browser editor, ordinary TextEdit paragraphs, moving between split panes/windows during transcription, typing before completion, password/secure input, multiline recovery without execution, and clipboard changes during confirmation. Rendered controls that redraw or hide text can still report Paste unconfirmed after actual delivery; that status deliberately does not imply verified success. No live cross-application paste was performed in this validation.

## Compact voice pill and quieter idle rail

Native build and offline checks passed before local deployment. The existing keyboard-panel eligibility, shortcut, audio, clipboard and transport fixtures were run; no new UI-mirroring tests were added. `Design/Previews/22-compact-motion.gif` renders the actual native controls with explicitly illustrative microphone levels, including a silence interval, processing and inserted feedback. It is a design preview, not evidence of physical microphone capture or cross-application insertion. Logs: `.artifacts/compact-pill-build.log`, `.artifacts/compact-pill-native.log`, `.artifacts/compact-pill-deploy.log`.

Manual acceptance: verify the 10 × 36 pt handle at a side edge, hover expansion, keyboard access, and 148 × 36 pt dictation pill appearing without focus activation. Speak, pause, release, and check waveform → thinking → result. Test Cancel and Finish in hands-free mode; failure feedback should remain readable. Check left/bottom docking, full-screen Spaces, display changes, Reduce Motion, Reduce Transparency, VoiceOver, and concurrent meeting status staying visible beside the pill. Physical desktop transitions and accessibility behavior remain manual qualification.

Recreate the focused native preview after building:

```sh
CHUP_COMPACT_PREVIEW=1 CHUP_DESIGN_OUTPUT="$PWD/Design/Previews" '.artifacts/DerivedData/Build/Products/Debug/Chup!.app/Contents/MacOS/Chup!' --render-design
ffmpeg -y -framerate 10 -i Design/Previews/compact-frames/%03d.png -vf 'scale=640:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse' -loop 0 Design/Previews/22-compact-motion.gif
```

## Unified popups, frequency EQ and native Paste — September 15

**88 core tests passed.** New coverage verifies frequency-dependent bar movement, visual headroom, settling after silence, and rejecting nonordinary Paste commands. Native offline fixtures passed, including production microphone fanout publishing bounded frequency bands after durable audio writes. No physical microphone was opened for those checks. Native popup renders were inspected in `Design/Previews/23-unified-popups.png`.

Read-only Accessibility inspection of the running terminal found an enabled ordinary Paste menu item without a Command-V equivalent, plus a separate disabled Paste Selection item. This made a generic shortcut-independent native Paste route preferable. Discovery uses exact ordinary English/Dutch Paste labels and supported [AXPress](https://developer.apple.com/documentation/applicationservices/kaxpressaction), with app/field/clipboard revalidation. It does not open a menu, activate a different destination or select execution/navigation variants. The [Apple menu modifier documentation](https://developer.apple.com/documentation/applicationservices/axmenuitemmodifiers) and installed SDK headers were checked when inspecting the keyboard equivalent.

An opt-in real desktop integration test launched a new Ghostty process running only `scripts/fixtures/paste-target.py`, a raw input receiver with no shell execution. It verified process ancestry and foreground identity, then exercised production TextInsertion, native Paste, actual clipboard handling and readback. The receiver obtained exactly one synthetic line, with no Return. Chup! returned Inserted. Existing terminal windows were not targeted. Both the earlier keyboard route and the final Native Paste command route passed in this isolated setup; this does not certify every TUI/editor or reproduce the user's complete dictation workflow.

Logs: `.artifacts/popup-spectrum-core.log`, `.artifacts/popup-paste-build.log`, `.artifacts/popup-paste-native.log`, `.artifacts/paste-desktop-native-command.log`, `.artifacts/popup-paste-deploy.log`.

To repeat the optional desktop test (opens a new isolated terminal and temporarily uses the clipboard):

```sh
CHUP_PASTE_FIXTURE="$PWD/scripts/fixtures/paste-target.py" '/Applications/Chup!.app/Contents/MacOS/Chup!' --validate-audio
```

It requires installed Ghostty and existing Accessibility/Input Monitoring access. Ordinary deployment fixtures do not run this desktop test. Manual acceptance: dictate into the actual target editor, verify animated EQ during speech and settling in pauses, release all shortcut modifiers, verify one insertion with no Send/Return, and repeat with focus changes and clipboard changes. Check hover labels/drawers, ten-second detection dismissal, Reduce Motion/Transparency and VoiceOver.

Final delivery: **1.0 (24)** installed and restarted. The real desktop Paste test also passed against the signed installed bundle (`.artifacts/paste-desktop-installed.log`). Earlier fixture attempts correctly refused to paste into an execution dialog: passing extra file paths through the terminal launcher caused those prompts. The receiver now starts as one executable with its receipt path in a scoped environment variable. Readiness additionally requires its unique marker in the focused text control, and any unrelated prompt is rejected. The fixture may acknowledge only the exact execution prompt for its explicitly requested receiver script. No production permission flow was changed.

## Deployment identity investigation

At the start of this check, no Chup! process was running. `/Applications/Chup!.app` and the build output both reported **1.0 (24)** and had identical app-code UUID `A1C5265C-1A46-375B-BBF8-03AB8CC8FC45`. Spotlight and Launch Services identified `/Applications/Chup!.app`; no alternate running copy was found. The available local crash reports were older (build 24 had no new report). This does not establish why the prior process stopped.

Launching the exact installed path produced one stable process over 20 seconds. Read-only inspection of its live windows showed the expected **10 × 36 pt** idle rail, plus the management window. There was no evidence that stale deployment explained the reported UI behavior at this check.

The app now exposes captured process version/build/path in Settings → General and version/build in the menu-bar menu. Deployment verifies executable UUIDs and optionally verifies the exact launched process for 20 seconds with `--launch`. Python syntax validation and the native build passed; the final deployment runs signature and installed native checks. A twenty-second launch check is not long-term crash qualification and does not validate physical dictation/paste.

Final identity check: **1.0 (25)** passed deployment UUID comparison, strict signature checks and installed native fixtures. The exact installed process remained stable for 20 seconds and was rechecked afterward. A pointer-only desktop check (no clicks, keyboard shortcuts, microphone or clipboard actions) observed the actual hover rail at **44 × 181 pt**, up from its **10 × 36 pt** idle handle. Native content fitting makes the height 181 pt despite the controller's 188 pt request; the earlier exact-height probe reported false for this size difference. The live width and contents are the compact implementation, not the old 56 × 238 pt rail. The pointer was restored only if the user had not moved it meanwhile.
