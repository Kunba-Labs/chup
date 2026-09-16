# Chup! Mic — development driver prototype

This is a **separate, uninstalled development component**. Ordinary meeting recording uses a Core Audio process tap (or explicit ScreenCaptureKit fallback) and does not need this driver. The driver supplies an outgoing microphone to a conference application; it does not create a separately named meeting participant.

## Source, license and build

The prototype customizes [Existential Audio BlackHole](https://github.com/ExistentialAudio/BlackHole) at commit `ffcb74433fbcf8c8ca5c736677c1a4864384dc09`. Its authors publish the source under GPL-3.0 and describe separate licensing for non-GPL projects in their README. No license for distributing it in a closed-source product has been obtained. Keep the upstream license and corresponding modified source with any distribution, and settle the distribution model before bundling. The app does not bundle a driver binary.

```sh
python3 scripts/build-virtual-mic.py
```

The script builds an unsigned arm64 / macOS 15 development artifact at `.artifacts/Driver/ChupMic.driver`. Source remains in `.artifacts/BlackHole`; the exact modifications are in the script. The upstream license is copied to `.artifacts/Driver/LICENSE-BlackHole.txt`. The script never installs software, restarts Core Audio, changes the conference input, or changes the system default devices.

Public device: **Chup! Mic**. Expected UID: `ChupMic2ch_UID`. Bundle identifier: `com.chup.mic.prototype`. The app only recognizes this named prototype, not an arbitrary virtual device or the unrelated Parrot plug-in present on this development Mac.

## Manual installation on a development Mac

These steps have **not** been performed here. Finish calls and close audio applications first. Inspect the artifact and the license. For deliberate local qualification, from the repository root:

```sh
sudo ditto .artifacts/Driver/ChupMic.driver '/Library/Audio/Plug-Ins/HAL/ChupMic.driver'
sudo chown -R root:wheel '/Library/Audio/Plug-Ins/HAL/ChupMic.driver'
```

Restart the Mac to reload HAL plug-ins. This avoids forcibly restarting Core Audio during another app's session. Verify the device in Audio MIDI Setup. A signed installer, upgrade/uninstall helper and distribution qualification remain required; this unsigned artifact is not a shipping installer.

To remove this specifically named prototype after closing audio apps:

```sh
sudo rm -rf '/Library/Audio/Plug-Ins/HAL/ChupMic.driver'
```

Restart and restore the physical microphone selection in each conference app.

## Headphones qualification sequence

1. Start Chup! recording using a physical microphone and the exact call process. Select an output that macOS identifies as headphones. Unclassified USB/Bluetooth outputs are deliberately rejected in this prototype.
2. In the assistant's Meeting audio route controls, start the outgoing microphone. Select **Chup! Mic** as the call application's microphone. Keep the call output on headphones. Core Audio must report that the selected process reads only this virtual input; unknown/helper-process routing fails closed.
3. Verify ordinary speech reaches the call once. Verify remote participant audio reaches the recorder and headphones, but never the outgoing mixer. Gain is 0.8 per branch with a final ±0.95 clamp; production loudness/limiting still needs calibration.
4. Connect private voice. The outgoing physical-mic branch is cleared and silenced; private microphone packets are omitted from the meeting journal and live captions. Addressed questions are separately stored in encrypted local VoiceQuestions journals and sent to the configured AI backend. Observe the persistent mute banner. Finishing or losing voice never automatically resumes the call mic; use the explicit resume action.
5. Switch to broadcast. A fresh Live context discards private conversation/history/notes. Only the selected meeting transcript and the newly addressed question go to the backend. Test that old queued output and delayed private results cannot play. Confirm assistant output is audible locally and remotely and appears on its own labeled recording track.
6. Interrupt midway through speech. Compare the isolated recorded branch and render-frame ledger with measured outgoing audio. Delayed model text is not proof of played speech. Stop/reconnect devices, change input selection, disconnect network, pause recording, sleep, and force-quit. Verify local meeting audio/notes survive, voice stops and device state remains truthful.

Core Audio routing is sampled every 100 ms. It cannot atomically prevent a conference app from independently switching to the physical microphone between samples. The prototype is not a certified privacy boundary. Production needs platform mute coordination or a qualified route/device-change mechanism, measured loopback testing, and explicit failure semantics. Do not promise private spoken input on unqualified hardware or routes.

The recorded assistant branch is captured at the output source render callback before hardware delivery and before the final combined limiter. It records consumed assistant PCM, including partial responses; it does not prove remote receipt or reproduce final mixed clipping. Remote audio is absent from the outgoing API by construction. No speaker-mode echo canceller is implemented; speakers stay blocked.

## Dedicated AudioServerPlugIn alternative

Apple's [AudioServerPlugIn sample](https://developer.apple.com/documentation/coreaudio/creating-an-audio-server-driver-plug-in) is a suitable API starting point if a dedicated driver is chosen. That alternative still needs a bounded shared ring buffer, a stable device clock, client start/stop and underrun semantics, installation/signing/update support, access/lifetime control, and a hardware matrix. It is a separate engineering effort, not implemented by renaming the prototype. A platform bot is another independent integration for a named participant.
