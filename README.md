# Chup!

Dictation and meeting notes for the Mac. Hold a shortcut and talk, and the text lands in whatever app you're typing in. Start a meeting and Chup! records it locally, transcribes it and keeps a summary and a list of actions that point back to the moments they came from. Native SwiftUI and AppKit, macOS 15+ on Apple silicon.

![A meeting in Chup!: the summary tab with an overview, a decision and an action, each linked to its source in the transcript](docs/screenshots/meeting.jpg)

<details>
<summary>More screens: the meetings list, the Dynamic Island and the floating rail</summary>

![The meetings list with search across notes and transcripts](docs/screenshots/meetings.jpg)

![Dictation and recording controls in the Dynamic Island on a notched Mac](docs/screenshots/dynamic-island.jpg)

![The dark glass rail on displays without a notch](docs/screenshots/rail.jpg)
</details>

- **Recording stays on your Mac.** Audio, transcripts and notes are stored in an encrypted local library. Cloud transcription and summaries only run when you turn them on, through a backend you host.
- **Dictation anywhere.** Local Whisper models or the cloud. Chup! applies your personal dictionary and snippets, and you can review the text before it's pasted.
- **Summaries show their sources.** Every point in a summary links to the part of the transcript it came from. Your own edits are kept when the summary is regenerated.
- **Out of the way.** The controls sit in the notch or on a thin rail at the edge of the screen, and nothing takes focus from the app you're in.

**Status: development preview.** The app builds and ships, but it isn't production-complete. Private voice and assistant broadcast are route-gated prototypes, and physical audio routing and provider access haven't been qualified yet. Read [implementation status](docs/STATUS.md) before relying on capture.

## Install

Download the `.dmg` from the [latest release](../../releases/latest) and drag Chup! into Applications. Every push to `main` becomes a Developer ID signed, notarized release. The app checks for updates hourly and has **Check for Updates…** in its menu bar menu. See [Releases and updates](#releases-and-updates).

## Design gallery

Open [the design gallery](Design/index.html), or view [Meetings](Design/Previews/01-workspace.png), [meeting detail](Design/Previews/02-meeting.png), [notification panels](Design/Previews/03-panels.png), [dark glass rail](Design/Previews/04-dark-glass-rail.png), and [speaker controls](Design/Previews/09-speakers.png), [meeting actions](Design/Previews/10-actions.png), [private voice](Design/Previews/11-private-voice.png), [onboarding](Design/Previews/12-onboarding.png), [Permissions](Design/Previews/13-permissions.png), and [storage settings](Design/Previews/14-storage.png). Sample content is restricted to the explicit `--render-design` path and uses a temporary database. Normal startup is empty.

The original red scanner waveform is provided as a [1024 px master](Design/AppIcon-master.png), a [layered Icon Composer document](App/Resources/ChupIcon.icon), and legacy size variants. See [icon notes](Design/ICON.md).

## Build and run

Requirements: Xcode 27 (latest build validated here), Apple silicon, macOS 15+, XcodeGen, Node 22+ for the optional backend.

```sh
xcodegen generate
open Chup.xcodeproj
```

Choose the `Chup` scheme, My Mac, and a signing team for permission testing. Run with Command-R. The checked-in `.xcodeproj` is usable without regenerating it. ChupCore is a local Swift package with vendored SQLCipher using Apple CommonCrypto. The first app build resolves the pinned WhisperKit dependency through SwiftPM; the core package remains self-contained. See [dependency provenance](docs/DEPENDENCIES.md).

For a compile-only build without signing:

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/render-design.sh
open Design/index.html
```

XcodeBuildMCP 2.7.0 was installed and used through its CLI. To reproduce:

```sh
npm install --prefix .tools --no-audit --no-fund xcodebuildmcp@2.7.0
.tools/node_modules/.bin/xcodebuildmcp macos build \
  --project-path "$PWD/Chup.xcodeproj" --scheme Chup \
  --derived-data-path "$PWD/.artifacts/DerivedData" --extra-args CODE_SIGNING_ALLOWED=NO
```

A project-local `.codex/config.toml` registers the MCP for future trusted sessions. The current implementation did not require global Codex configuration changes.

## AI backend setup

Local recording, typed notes and installed-model dictation work without this service. Meeting transcription, summaries and AI editing use the cloud when enabled.

```sh
cd backend
npm ci
cp .env.example .env
# Edit .env locally: OpenAI project key + a separate randomly generated app token.
# Generate a token with: openssl rand -hex 32
npm start
```

In app Settings → Advanced, enter `http://127.0.0.1:8787` and the **app token**, then Save token in Keychain. Do not enter your OpenAI project secret in the app. Enable cloud processing in Privacy. Live captions have a separate Meetings toggle. Production deployment needs HTTPS, real per-user authentication, quotas and monitoring; the included service binds loopback only and is a development relay.

Models: `gpt-live-1` for the Live transport spike; `gpt-live-transcribe` for live captions; `gpt-4o-transcribe-diarize` for final file segments; `gpt-transcribe` for dictation; configurable `gpt-5.6-luna` for cleanup, summaries and questions. These names/contracts were checked against current official documentation, but no account-level requests were performed here. See [API research](docs/API-RESEARCH.md).

## Try the workflows

- Create a meeting note. Type notes; writes commit immediately. Record opens an explicit mic-only/application picker. Inform participants. Pause does not mute the conference app.
- Stop and choose Transcribe saved audio. Completed chunk jobs survive a retry. Rename/correct speakers in Transcript; generate a source-backed summary afterward.
- Settings → Shortcuts supports multiple bindings per action: keep Fn and add Control–Shift for an external keyboard. Edit or remove each binding independently; changes persist immediately. Configure Input Monitoring and Accessibility through Settings. Use the default or no-Fn shortcut preset. Fn OS behavior must be configured appropriately. Dictation records into the original field only if its identity, focus epoch, content and selection still match.
- Meeting detection reads Core Audio activity metadata for known apps. Its nonactivating prompt dismisses after ten seconds, deduplicates and supports two-minute snooze. Accepting starts recording. Browser detection is heuristic, not tab isolation.
- Ask a meeting question in private text. Proposed note writes are visible; Save commits with a request ID and expected version. Undo will not overwrite newer edits.

## Local data

`~/Library/Application Support/Chup/` stores **Chup!** data. The app and Keychain service use `com.chup.mac`; no legacy identity or data-directory fallback is retained. SQLCipher encrypts metadata, FTS, notes and request journals; a separate Keychain key encrypts audio/reference files. Previous plaintext databases migrate on opening. Settings provides opt-in retention, deletion, readable JSON export and password-protected backup/restore. See [setup and recovery](docs/SETUP.md).

The backend caches encrypted provider results for durable retries, with separate retention/deletion; it logs neither meeting text nor audio. No login item, voice enrollment, virtual driver, bot or cloud sync is silently enabled.

[Product specification](docs/PRODUCT.md) · [Architecture](docs/ARCHITECTURE.md) · [Phased backlog](docs/PLAN.md) · [Actual validation and manual steps](docs/VALIDATION.md)

## Motion preview

Open [Design/motion.html](Design/motion.html) for the light workspace and animated dark glass rail. Try Listening, Speaking, Interrupt and the ten-second meeting prompt. [The MP4](Design/Previews/06-motion.mp4) and [GIF](Design/Previews/06-motion.gif) show the walkthrough without requiring the app. These are labeled design demonstrations, with no audio connection. See [motion and validation notes](docs/MOTION.md).

## Latest build-out

[Iteration 7](docs/ITERATION-7.md) adds encrypted metadata/migration, retention/deletion, backups, durable request recovery, provider usage, feature-scoped onboarding, Privacy settings links and launch at login. It also applies the **Chup!** name throughout the product. Native build, **50 Swift tests + 20 backend tests**, offline audio and localhost Live fixtures pass. One planned increment remains: qualification and distribution. Real provider, signed permissions/login registration and physical privacy/audio routing remain untested.

[Iterations 4–6](docs/ITERATIONS-4-6.md) cover meeting intelligence, private voice and assistant outgoing routing.

```sh
python3 scripts/test-live-transport.py  # after building; no OpenAI or audio hardware
python3 scripts/build-virtual-mic.py   # builds a separate driver; never installs it
```

See [driver setup and qualification](DriverPrototype/README.md) for the separate license and explicit development installation steps. Ordinary meeting recording does not need it. See [iterations 1–3](docs/ITERATIONS-1-3.md) for capture recovery, dictation and transcript/speaker work.

## Install each iteration

Run `python3 scripts/deploy-local.py` after completing an iteration and its relevant checks. It builds `Chup!.app` with the commit count as its build number, signs it with Developer ID (falling back to Apple Development), validates the app with offline native fixtures and installs it at `/Applications/Chup!.app`. The installed copy is checked again. Previous app versions are retained under `.artifacts/InstalledBackups`; the latest successful installation is recorded in `.artifacts/last-install.json`.

The command does not force-quit Chup!, start a microphone, enable login items or install the virtual audio driver. Close Chup! safely before replacing a running version. `--applications-dir "$HOME/Applications"` selects the per-user Applications folder if desired. `--signing-identity` can select another configured local identity. This is a development install, separate from notarization or App Store distribution.


## Releases and updates

Every push to `main` on [Kunba-Labs/chup](https://github.com/Kunba-Labs/chup) runs `.github/workflows/release.yml` on a GitHub macOS runner. It builds arm64 Release as **1.0.<commit count>**, signs it with Developer ID, notarizes and staples the DMG, and publishes it as a GitHub release with `appcast.xml`. Any copy installed in an Applications folder checks that appcast hourly through Sparkle, including `deploy-local.py` installs, which carry the same Developer ID signature and commit-count build number, and has **Check for Updates…** in the menu bar. It offers no update while you're recording or dictating. Xcode runs from DerivedData never update themselves. `scripts/release-secrets` puts the signing, notarizing and Sparkle secrets on the repo. The Sparkle private key lives in `~/Desktop/chup-updater-key`: back it up, because losing it strands every installed release.

Increment 8 independent work is implemented and locally installed as **1.0 (5)**: [implementation and test evidence](docs/PHASE-8.md), [manual acceptance checklist](docs/MANUAL-TESTS.md). Real-provider synthetic checks pass; physical recording, privacy routing and public distribution are not yet qualified. Release DMGs and their explicit notarization status are in `.artifacts/Distribution`.

Latest dictation update: **1.0 (14)** adds saved-audio playback, recoverable accidental-clip filtering and an independent listening indicator. See [validation](docs/VALIDATION.md) and [the 2026 local-transcription investigation](docs/LOCAL-TRANSCRIPTION.md). Local dictation ASR is now implemented; see Dictation settings for model readiness and VALIDATION.md for qualification.
