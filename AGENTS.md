# Chup! iteration delivery

The user requires a fresh build installed in their Applications folder after every implementation iteration. This is standing authorization to build, locally sign and replace `/Applications/Chup!.app`; do not ask again each iteration.

- Complete the change and relevant checks, then run `python3 scripts/deploy-local.py --launch`. It increments the build number, builds, signs with an available Apple Development identity, verifies the bundle, runs offline native checks, installs it, compares executable UUIDs and verifies the exact installed process stays running for 20 seconds. Follow the script's explicit error if signing or installation fails; do not report deployment success unless the installed bundle was verified.
- Report the installed version/build and path in the handoff. Keep setup and validation documentation current.
- Complete implementation, visual/automated validation and Codex's final code review before replacing or restarting the installed app. Installation and restart are the final delivery operation of the turn; do not restart mid-iteration and continue development afterward. Launch verification is part of that final operation.
- Never force-quit an app that could be recording. If Chup! is running, finish building the replacement and defer replacing it until the user closes it safely. Do not install the separate virtual audio driver as part of routine app deployment.
- If the user explicitly says “kill it and redeploy” (or equivalent), that is standing authorization for this delivery to terminate the running Chup! process before installation; perform it only as the final delivery operation and report the termination.
- Product name and executable: `Chup!`; Xcode project/scheme: `Chup`; module: `ChupCore`; bundle/Keychain identity: `com.chup.mac`. No legacy identity aliases are needed.

## Repository and implementation conventions

- Keep recording, transcription, notes, shortcuts, insertion, and assistant services behind explicit protocols so failures in one service cannot discard durable meeting data.
- Treat local audio chunks, transcript revisions, speaker corrections, note versions, and resumable jobs as user data. Write durable state before cloud processing and never fabricate transcript, speaker, summary, or action-item evidence.
- Use SwiftUI for management views and AppKit for global event monitoring, non-activating panels, text insertion, and audio integration. Preserve the shared `ChupCore` state model across the menu bar, hover rail, and management window.
- Request microphone, Accessibility, input monitoring, and screen/system-audio permissions only when the associated feature is enabled. Keep secrets out of the repository; use Keychain or a trusted backend for credentials.
- Keep the light editorial workspace and dark glass rail visually consistent, support VoiceOver and Reduce Motion, and prevent transient panels from intercepting unrelated clicks.
- Validate risky behavior with the native/offline checks in `scripts/` and document any macOS-only checks that cannot run in a non-macOS environment. Do not replace real integrations with simulated success.

## Git and local files

- Commit source, project configuration, documentation, scripts, and reproducible design assets. Do not commit local credentials, generated build products, crash artifacts, Xcode user state, or MCP/tool configuration.
- Before handoff, run `git status`, record the tested build/version, and keep `README.md` and `docs/` aligned with the implementation.
