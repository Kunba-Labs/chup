# Appearance and motion

The management window, sheets, meeting prompts and Settings use the light paper palette even when macOS uses Dark Mode. The independent hover rail and drawers use dark charcoal glass. The old System/Light/Dark setting is removed, so a previously saved preference cannot override this choice.

## Native implementation

`App/UI/HoverRail.swift` keeps one hosting view and one observable presentation alive through transitions. The nonactivating panel animates its actual frame; there is no oversized transparent overlay. Tracking areas and the 16-point geometric pointer corridor remain independent of the backdrop.

- Expanded navigation: a 56 × 238 pt icon strip (238 × 56 pt along the bottom). Dictate, Meeting, Assistant and Settings show labels inward from the edge. Native labels use a separate nonactivating, mouse-ignoring child panel, so the label never enlarges the rail’s click area. Recording/pause/error status stays visible as an accessible glyph.
- Hover intent: 160 ms before opening. Hover does not activate the app or microphone.
- Expansion and drawer change: 240 ms ease-out, with a content crossfade.
- Exit: 450 ms outside the interaction area, then 180 ms collapse.
- Buttons: 120 ms highlight and 100 ms press feedback; press scale is 0.98.
- Listening: 90 ms smoothing of the real microphone envelope. Bars are a level visualization, not a frequency spectrum or invented audio activity.
- Reduce Motion: immediate frame/content updates, no press scaling or interpolated meter movement. The current audio level is still represented.
- Reduce Transparency: opaque charcoal. Increase Contrast strengthens the surface border.

The background uses AppKit's HUD material with behind-window blending and an explicit dark appearance. It supports macOS 15 without depending on the newer Liquid Glass APIs. The blur depends on the desktop behind the panel. Static native design exports deliberately use the opaque fallback.

References checked against official Apple documentation on September 14, 2026: [NSVisualEffectView](https://developer.apple.com/documentation/appkit/nsvisualeffectview), [Reduce Motion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion).

## Interactive study

Open `Design/motion.html`. The page runs locally and requests neither audio nor network access. It includes the light workspace, dark glass rail, sample listening and speaking envelopes, processing, immediate interruption, and the ten-second meeting notification. Buttons let reviewers inspect each state, replay the walkthrough and enable Reduce Motion. Escape closes transient previews. Operating-system Reduce Motion disables autoplay. Hidden browser tabs stop the preview.

Speaking uses a synthesized sample envelope **only in this explicitly labeled design study**. There is no generated sound. The native full-duplex assistant remains incomplete; this study is not evidence of a working provider session or private audio route. The eventual native speaking envelope must come from frames actually played, and interruption must clear that playback queue. Recorded meeting state remains independent.

## Reproduce and validation

1. `npm install --prefix .tools --save-dev playwright` (development tooling only).
2. Install Google Chrome if absent; the script uses Playwright's `chrome` channel.
3. Ensure `ffmpeg` is on PATH.
4. `node scripts/render-motion.mjs` verifies the browser study and exports the speaking screenshot, MP4 and looping GIF to `Design/Previews`.
5. Run `./scripts/build.sh` and `./scripts/render-design.sh` for native builds and static views.

The browser checks cover light styling under a dark OS preference, hover open/close, changing speaking bars, immediate flatline on interruption, static Reduced Motion bars, ten-second expiry without recording, Escape focus recovery and narrow layout. These are browser preview checks, not native audio integration tests.

Native follow-up: run the built app interactively over both light and dark backgrounds, at each dock edge; drag and cross the pointer corridor during transitions; toggle accessibility display options; verify no focus change on hover, visible recording status, corner hit testing, multiple displays/Spaces, and full-screen behavior. This change compiles and renders, but those interactive native checks have not been certified by the automated browser run.
