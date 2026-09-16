# Scanner waveform app icon

Original generated artwork: seven red waveform bars, charcoal background, restrained 1990s cyborg scanner inspiration. No franchise logos, character portrait, lettering, or copied competitor assets.

## Deliverables

- `AppIcon-generated-source.png`: original built-in generation (1254 px).
- `AppIcon-master.png`: normalized 1024 × 1024 opaque PNG master.
- `AppIcon-foreground.png`: separate generated alpha foreground.
- `../App/Resources/ChupIcon.icon`: editable Icon Composer document, independent charcoal background and waveform foreground.
- `AppIcon-composer.png`: 1024 × 1024 rendered macOS icon from Apple's `ictool`.
- `../App/Resources/Assets.xcassets/AppIcon.appiconset`: legacy 16, 32, 128, 256, 512 pt assets at 1×/2×. The current build selects ChupIcon from Icon Composer.

Apple's current guidance uses a 1024-square canvas, separate layers, and platform masking performed by the system. Icon Composer generates renditions for older deployment targets. The document was successfully exported with `ictool` and compiled by Xcode's asset pipeline. App Store Connect upload/review has not been performed. [Apple Icon Composer guidance](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer), [asset catalog requirements](https://developer.apple.com/documentation/xcode/configuring-your-app-icon), [App Icon HIG](https://developer.apple.com/design/human-interface-guidelines/app-icons).

## Generation provenance

Built-in imagegen was used (not an API-key CLI). Master prompt:

> Minimal original emblem: seven thick rounded vertical waveform bars, symmetrical, shortest at outer edges and tallest in the center, reading as a sound wave and a single horizontal red cyborg scanner eye. Restrained 1990s sci-fi electronics mood. Luminous vermilion on near-black charcoal. Centered, strong geometry, readable small. Square opaque artwork; no text, character face, franchise insignia, perspective, outer rounded corners, external shadow, or watermark.

Foreground edit prompt:

> Preserve the seven red rounded waveform bars; remove the black background and external bloom. Keep a genuinely transparent square canvas, with no text, shadow, or outer mask, for a separate Icon Composer foreground layer.

Only asset resizing and Apple platform rendering followed generation. The original generated files remain available. To export the Composer preview:

```sh
'/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool' \
  App/Resources/ChupIcon.icon --export-image --output-file Design/AppIcon-composer.png \
  --platform macOS --rendition Default --width 1024 --height 1024 --scale 1
```
