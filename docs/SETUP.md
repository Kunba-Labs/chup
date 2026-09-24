# Set up Chup!

For the repeatable local install, run `python3 scripts/deploy-local.py`: it builds the commit-count version and installs a verified, locally signed copy in `/Applications` (Developer ID when available). Later releases update that copy through Sparkle.

For interactive debugging, open `Chup.xcodeproj`, choose the `Chup` scheme and My Mac, select a Development signing team, then run. For repeatable OS permission and startup tests, use a consistently signed copy of `Chup!.app` in `/Applications`. Replacing an unsigned development build may invalidate macOS permissions.

On first launch, choose the workflows you want. Nothing records automatically. “Set up later” keeps typed notes usable; Settings → General → Run setup again returns to onboarding. Command-comma opens Settings.

## macOS access

Settings → Permissions provides a button to open each relevant macOS pane and “Check access again.” Enable Chup! in the listed pane, then return to the app. If macOS requests a restart, finish recording first. Pane links are best effort; follow the printed breadcrumb if macOS opens the general Settings window instead.

| Feature | macOS setting | When needed |
| --- | --- | --- |
| Your voice | Privacy & Security → Microphone | Dictation, microphone recording, addressed voice questions |
| Insert dictated text | Privacy & Security → Accessibility | Writing into another app's selected field |
| Fn/mouse global gestures | Privacy & Security → Input Monitoring | Native modifier and mouse shortcut path |
| Meeting app audio | Privacy & Security → Screen & System Audio Recording | A selected app process tap requests audio-only access on first capture |
| Audio fallback | Privacy & Security → Screen & System Audio Recording | Optional ScreenCaptureKit route; broader screen permission, audio-only storage |

System-audio-only access has no general public preflight status used by this app. “Checked when capture starts” is intentional. First choose a source in the meeting capture sheet and start recording to invoke that system check. Browsers may include audio from other tabs. Ordinary recording needs no virtual driver. No camera, Full Disk Access or Automation access is requested by these workflows.

Chup! does not share your screen. The optional screen permission supports meeting audio capture. Conferencing software continues to control its own screen sharing and microphone mute.

## Multiple shortcuts and external keyboards

Settings → Shortcuts supports several simultaneous bindings for every action. Under Hold to dictate, keep **Fn**, then use **Add Control–Shift for dictation** or **Add shortcut**. Press Control and Shift together, then release both; no letter or Space is needed. Either binding now starts the same hold-to-dictate action. Changes are saved immediately and remain active after Settings closes and after relaunch.

Click a binding to edit only that binding. Its minus button removes only that binding. Each action also accepts ordinary modified keys and side mouse buttons. Duplicate gestures are rejected, including duplicates on the same action. A failed macOS registration disables that binding while its other bindings stay available. Presets replace the entire assignment list.

Fn, modifier-only gestures such as Control–Shift, and mouse gestures require Input Monitoring for global use. Enable access in Settings → Permissions, then use Enable / retry registration. These monitored gestures do not suppress their normal macOS behavior. Test shortcuts without performing actions verifies the presses/releases locally; it does not start a microphone. While rebinding, voice actions are suspended. Escape cancels capture except when assigning the Cancel voice action itself.

## Open at login

Settings → General → Launch Chup! at login uses Apple's main-app login service. If approval is pending, use “Open Login Items settings” and enable it under General → Login Items & Extensions. Disable the toggle to unregister it. Startup reveals controls; it never starts recording.

## Workspace window restore

The workspace window reopens at its last size and position, on the display it was closed on, after a normal quit or a crash. SwiftUI autosaves the frame as `NSWindow Frame workspace`; Chup! re-applies it at launch because SwiftUI would otherwise move the window to the display under the mouse. A saved frame on a disconnected display is ignored. The last page, open meeting and meeting tab are restored from `lastPage`, `lastMeetingID` and `lastMeetingTab`; a deleted meeting is not reopened. Check with `defaults read com.chup.mac | grep -E "NSWindow Frame|last"`.

## Cloud processing

Follow the backend instructions in the repository README. Save the app token in Settings → Advanced; keep the OpenAI project secret on the trusted backend. Settings → Privacy controls AI uploads. Local recording and typed notes remain usable when cloud processing is off or disconnected. Live captions have an additional Meetings toggle.

## Storage and recovery

The data location is `~/Library/Application Support/Chup/`. SQLCipher encrypts notes/search/request data; separate AES-GCM journals encrypt audio. Keys use the `com.chup.mac` Keychain service. Do not remove keys while retaining the associated files. Prior plaintext preview databases migrate on opening; existing encrypted data with a missing key produces an error rather than creating a replacement key.

Settings → Privacy contains retention, cleanup, integrity check, JSON exports and encrypted backup/restore. Retention starts disabled and uses creation dates. Deleting a meeting also deletes its private thoughts, saved conversation and origin voice references. Private-question retention alone removes its recorded audio; saved text exchanges remain with their meeting.

Choose an external backup destination and a password of at least 12 characters. Keep that password separately. Use “Verify backup” before relying on an archive. “Restore for next launch” creates a separate verified workspace and switches on relaunch; it does not overwrite or merge the current one. It restores workspace content and audio keys, not OS permissions, API credentials, login registration or global UserDefaults preferences. A restored workspace can contain an old retention schedule; review it before restoring an archive you intend to preserve.

Readable JSON exports are unencrypted. The ordinary export omits private thoughts/history; the explicitly private export includes them. User-created exports and external backups are outside the app's deletion controls.

Settings → Recovery shows interrupted provider requests. Resume reuses their stable ID; unknown provider acceptance stops automatic retry. “New attempt” may incur another charge. Saved responses can be recovered with cloud processing off. Review note/action proposals before saving. Settings → Usage shows confirmed/partial provider units and optional estimates from rates you enter; it is not a bill.

## Recording export, search and diagnostics

Select a stopped meeting, then Settings → Privacy → Export selected meeting as aligned WAV tracks. Choose a new folder. Export runs off the UI thread and can be cancelled; all exported source tracks share a start and duration. Silence represents capture gaps/pauses. The manifest describes chunk intervals. WAV/JSON exports are readable and unencrypted. Private-question recordings are excluded.

Meeting search includes transcript text and My notes; a transcript hit opens its source. Private thoughts/history are excluded. Opening a stopped recording builds an encrypted waveform index next to its chunks; missing/corrupt caches rebuild without changing recordings.

Menu bar → Focus floating controls enables keyboard interaction with the rail. Fresh presets use Control–Option–R; existing shortcuts are preserved, so add a binding in Shortcuts if needed. Hover alone never requests keyboard focus.

Settings → Advanced → Export diagnostics writes versions, permission states and counts to a JSON file you choose. It omits content, device identifiers, backend endpoints and credentials. It does not send anything.

## Release packaging

Local iteration delivery remains `python3 scripts/deploy-local.py`. The separate release command builds optimized arm64 code, signs it with a specified Developer ID Application identity and creates a DMG/checksum manifest:

```sh
python3 scripts/package-release.py --identity 'Developer ID Application: YOUR NAME (TEAMID)'
```

Artifacts are under `.artifacts/Distribution`. The default command does not upload to Apple, install a driver, or claim Gatekeeper readiness. Once you have configured your own notarytool Keychain profile, pass `--notary-profile YOUR_PROFILE` to explicitly submit, await acceptance, staple and assess the DMG. Never put Apple credentials in this repository. An existing versioned DMG is protected from overwrite; archive it or use the next build number. `--build N` sets CFBundleVersion, which defaults to the commit count. Nested Sparkle code is signed with the Developer ID identity. CI runs this script on every push to `main`. See *Releases and updates* in the README. App Store sandbox/distribution design remains separate engineering.

## Chup! missing from the recording permission list

Opening a Privacy pane does not register capture access. In Settings → Permissions (or onboarding), **Set up meeting audio…** opens the app/source selection without recording. Choose a meeting app and press Start recording deliberately; this creates a new meeting and invokes missing audio capture permissions. Audio-only permission may appear in a separate section below screen recording. In-person/microphone-only recording does not request system-audio access.

Alternatively, use **+** below the relevant macOS recording list, choose `/Applications/Chup!.app`, and enable it. For the optional ScreenCaptureKit path, **Enable access** requests screen-recording permission explicitly. If macOS asks for a relaunch, finish any recording first.

Enabled permissions now use a larger filled olive **Access enabled** badge with a white checkmark. Unknown/unchecked states remain visibly distinct; audio-only status is still checked during actual capture and is not inferred from screen permission.

The expanded “Chup! not listed?” help block and Finder button were removed from onboarding and Settings at the user’s request. Permission actions and the larger status badges remain.

The arrow beside each permission title opens its macOS Privacy pane. The full pane path is available on hover; enabled cards no longer reserve a separate button/breadcrumb row.

The circular refresh control checks the displayed permissions. It briefly spins, then shows a green checkmark only when every displayed permission is confirmed enabled; missing or denied access shows an exclamation mark, while audio access awaiting capture shows a clock; details are available on hover/VoiceOver. Audio-only access marked Checked when capture starts remains unverified, so it never produces a false all-clear. Reduce Motion uses a static hourglass during the check.

Refresh uses an icon **and** the visible label “Check access again” (“Checking access…” while running). A pending capture-only check is distinct from denied access and never shows a failure icon by itself.

## Dictation audio recovery

In Dictation history, use **Play recording** even if transcription failed. Pause or seek with the playback controls. Playback stops before new capture or a voice session and is unavailable during an active meeting.

Accidental short clips with silence or very low speech evidence are skipped before cloud processing and hidden from the default history. **Show ignored clips** reveals them for playback, explicit Retry audio or deletion. Recordings are preserved under the normal retention policy; the filter does not remove existing recordings.

Holding a configured dictation shortcut shows an independent dark indicator on the right edge of the display under the pointer. It shows Starting mic, Listening with the actual input level, then Processing. The hover rail can remain disabled. Settings → Shortcuts calls the main preset **Default preset**.

Offline audio playback and local noise classification work without the backend. Offline transcription is not installed yet; [the local-model investigation](LOCAL-TRANSCRIPTION.md) describes the proposed English/Dutch fallback and readiness requirements.

Build 15 addresses the reported periodic shortcut-timer crash. Chup! does not currently have a separate crash-restart supervisor; reopen it from Applications if it exits unexpectedly. Recording recovery uses saved local journals and never claims continuous capture across a crash.

The Dictation page’s **test** button starts a dictation saved to history; it changes to **Finish** while listening. Use a global shortcut in another app to dictate into its focused field.

## Local dictation (implemented)

Settings → Dictation → Transcription selects **Cloud with local fallback**, **Local only**, or **Cloud only**. Auto goes directly local when cloud processing is off or the backend is unconfigured, and falls back when a cloud dictation request fails (20-second request timeout). Local only never uploads audio or calls cloud cleanup.

The Local speech model card downloads a pinned 630 MB Whisper Turbo model/tokenizer, verifies every file, then runs an inference readiness check. Setup progress, cancellation, retry and model/download removal are available there. Verified files survive interrupted downloads. On this development Mac the model was downloaded and qualified during this iteration; other installations need the one-time download. No download is attempted during offline inference.

Use **test** or the dictation shortcut for new audio. For older audio-only entries, click **Retry audio**. Results appear directly in history with **Local · Whisper large-v3-turbo** or **OpenAI cloud**. Retry never inserts into another app. Normal shortcut dictation keeps the existing destination validation.

Local output is a plain transcript with deterministic dictionary/snippet handling. AI cleanup and selected-text rewriting are not performed offline. A local voice editing command is saved as an instruction and never inserted as replacement text. Meeting speaker labeling, meeting summaries and conversational voice are separate cloud paths.

The model lives in `~/Library/Application Support/Chup/Models/whisper-turbo-626mb-v1`. Source audio remains encrypted; local inference resamples in bounded memory, without plaintext audio files.

## Dictation completion and clipboard recovery

After releasing the shortcut, the collapsed/expanded rail, floating indicator and Dictation sidebar item show circular processing feedback. The floating indicator says Thinking while transcription and insertion finish. Reduce Motion shows a static progress arc.

Chup! revalidates the original captured field and attempts insertion only while it remains the intended active destination. It never switches to an unrelated field or inserts into a secure field. It verifies the resulting text instead of treating a posted paste event as success.

If there is no safe target, the transcript is copied and a short **Couldn’t paste · Copied to clipboard** message appears at the screen edge. A paste whose result cannot be verified shows **Paste unconfirmed · Copied to clipboard**. Recovery text stays on the clipboard. Successful clipboard-based paste restores all previous formats if no newer clipboard action occurred. A newer user copy is preserved; in that case the message says the clipboard changed and the transcript remains in history. A failed clipboard write never claims success. Completion messages dismiss automatically or with the close button.

## Live listening waveform

While holding a dictation shortcut, the dark floating indicator, compact rail, expanded Dictate button and workspace show animated bars driven by recent microphone peaks. A logarithmic visual scale makes quieter speech visible without changing microphone gain or recording data. The bars settle after silence; missing meter packets clear the waveform rather than leaving it frozen high. Reduce Motion removes interpolated movement while retaining meter updates. Releasing the shortcut switches to the circular thinking state.

## Custom editor and terminal insertion

Insertion is chosen by Accessibility capabilities, without an application-name whitelist. Editable fields retain strict caret/selection/value validation and use Accessibility writes where supported. Focused text controls with read-only or incomplete caret metadata use a guarded Command-V path. This requires an active Input Monitoring event stream, the same focused control and window, no intervening typing/clicking/scrolling or event interruption, no highlighted selection, and no secure input. Changing focus cancels automatic delivery.

For these opaque inputs, multiline text and control characters are copied for deliberate manual paste because an unknown control can interpret them as commands. Ordinary editable fields still support paragraphs. The app never posts Return. Readback confirms only a provable insertion; controls that redraw or hide their text may report Paste unconfirmed even when text arrived. A second paste is attempted only when a dropped paste is provable (see below); otherwise the transcript remains available for recovery.

## Compact floating voice controls

The idle rail is 10 × 36 pt at a side edge (36 × 10 pt at the bottom). Hover still expands after 160 ms, with the existing 450 ms exit delay and icon label overlays. During dictation, a 148 × 36 pt nonactivating pill replaces the idle handle: Cancel, eleven microphone-driven cream bars, and Finish. Release the hold shortcut or use Finish to start processing; the waveform becomes a circular progress indicator. Successful insertion shows a short checkmark message. Recovery uses a 320 pt wide card that grows vertically to fit its message. The card stays inset from the screen edge. Meeting/assistant activity retains its separate rail indicator, with space between the two controls.

Appearance fades in over 140 ms; waveform levels interpolate over 120 ms and processing crossfades over 160 ms. Reduce Motion removes those interpolations and uses the existing static processing arc. Reduce Transparency retains an opaque surface. To keep the idle handle completely hidden, turn off Show the floating hover rail in General; the dictation pill still appears when a shortcut starts dictation.

## Unified floating surfaces, live EQ and native Paste

All custom floating controls now share the charcoal glass surface, cream text and compact rounded controls. The expanded hover rail is 44 × 188 pt, retains icon label overlays, and uses the same surface as its drawers and meeting notifications. Detection prompts retain the ten-second dismiss timer and explicit Record action; their panel sizes to content within the visible screen. Native macOS alerts remain system controls.

The dictation EQ now uses five overlapping frequency bands from captured PCM, interpolated into eleven visible bars. The worker computes bands after saving audio and publishes at up to roughly 20 Hz (buffer cadence can reduce this); SwiftUI interpolates over 70 ms. The visual scale keeps headroom up to 0 dBFS instead of flattening at -12 dBFS. Microphone gain, recorded samples, peak indicators and noise classification are unchanged. Silence settles, and Reduce Motion removes interpolation.

Clipboard insertion waits for shortcut modifiers to be released and prefers the app's enabled ordinary Paste menu action, regardless of its shortcut binding. Exact English/Dutch menu labels are supported initially; other labels use the existing Command-V fallback. Paste Selection, Paste and Go, Paste and Execute and similar commands are never selected by native-menu discovery. The destination and clipboard are revalidated immediately before delivery. If the paste does not confirm, Chup! waits 300 ms for a late render, then retries the same paste route once, but only when the field's readable contents are still exactly what they were before dispatch and the field, window, focus, input activity and clipboard are all unchanged. An unreadable or changed field is never pasted twice. Paste activity notes when a retry was used. Readback still determines whether success can be claimed; genuinely unconfirmed results retain clipboard recovery.

## Verify the running build

Settings → General now shows the version/build and the running app's bundle path. The menu-bar menu also shows the version/build. These values are captured when the app state starts. Advanced settings and exported diagnostics use the same captured version.

The shortcut event tap and Carbon hotkey handler copy native callback data and enqueue ordered main-queue delivery. Invalidated tap registrations discard pending work. This avoids calling `MainActor.assumeIsolated` inside the native shortcut callbacks; no keyboard binding changes are needed.

Settings → Diagnostics now shows the latest dictation attempts, their outcomes and timings for microphone start, recording, cloud/local transcription, cleanup and text delivery. A dash means no completed measurement for that stage. Up to 50 traces are stored in the encrypted workspace and can be cleared or included in an explicit diagnostics export. Trace data contains timestamps, stage identifiers and outcomes; it excludes dictated text, audio, application/field contents and device names. Interrupted traces stay marked interrupted after a restart.

Settings → Transcription Lab compares Whisper Turbo and Parakeet v3 using one selected saved dictation. Download Whisper in Dictation settings and Parakeet in the lab. The models run sequentially; preparation and transcription times are separate. Each model unloads after use, although macOS may retain compiled caches. No generative cleanup or speaker identification is applied in this comparison. Parakeet detects language automatically; Whisper uses the recording's saved language. First-use model compilation can take several minutes.

Lab results stay in memory until cleared or the app exits. They never replace a history entry or automatically paste. Copy result is an explicit clipboard action. Leaving the panel or starting dictation, a meeting or assistant voice cancels the comparison; in-flight Core ML work may take time to return before cancellation completes. Audio remains encrypted on disk and neither comparison model uploads it. Confirmed silent recordings are rejected before running models. Failures appear per model so one unavailable candidate does not hide the other's result.

`python3 scripts/deploy-local.py --launch` compares the installed executable UUIDs with the build output, performs the existing signature/native checks, launches the exact installed path, and checks that exactly one process from that path remains stable for 20 seconds. `.artifacts/last-install.json` records those UUIDs and the verified PID. Installation and launch verification are distinct: a launch failure is reported even when the bundle was successfully installed.

## Microphone selection and preview

Open Settings → Audio and click **Test microphone**. Speak and watch the live frequency waveform beside the button. The panel shows the resolved input name and feedback for signal, quiet input or a disconnected source. This is a local meter-only preview through the shared audio owner: no audio file, transcription request or outgoing voice packet. Stop test, leave the panel, start a voice action, or wait 30 seconds to release the microphone. Stop the test before selecting a different input. Testing is unavailable during active capture.

Automatic follows the system input. If that input is unavailable or the lid disconnects the built-in mic, Chup! uses exactly one available physical external input; if several are available, select one. An explicitly selected microphone is never silently replaced. Closed-lid detection uses Apple's public IOKit clamshell property; an unknown lid state is not assumed closed. Apple documents the hardware disconnection [here](https://support.apple.com/guide/security/hardware-microphone-disconnect-secbbd20b00b/web).

Chup! observes the device list and system default and reconciles alive/rate/lid state once a second. It checks the device actually bound to the audio engine. A changed source pauses meeting capture or preserves/stops dictation instead of silently switching tracks. Select another input while paused and resume into a new recording leg. Dictation warns after three seconds without detectable signal and stops if packets cease. Quiet input alone does not stop a natural pause.

Near-digital silence of any length skips both cloud and local transcription, including Retry audio. Short noise still uses the conservative local classifier. Ignored recordings remain recoverable and playable in history, with the reason shown. Uncertain or malformed audio is retained for processing rather than classified as silence; this is not a general speech-recognition guarantee. New history entries include the microphone name.
# Microphone and floating-panel regression checks

For a local deployment that also checks the selected physical input, run `python3 scripts/deploy-local.py --launch --check-microphone`. This opens the selected microphone for three two-second meter-only cycles before launching the installed app. It does not save or upload audio. Ordinary deployments do not open the microphone.

To exercise the real floating window across attached screens without capture, run `CHUP_PANEL_FIXTURE=1 python3 scripts/test-live-transport.py`. It briefly shows synthetic listening/processing/alert states without taking keyboard focus.
