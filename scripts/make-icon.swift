// Regenerates the app icon: the bar mark in membox's Bauhaus (2026-11-06) — square bars in the
// three primaries on the ink ground, matching the main window (was gradient pills, 2026-10-30).
// Usage: swift scripts/make-icon.swift   (from the repo root)
// Writes the Icon Composer layer and the legacy appiconset PNGs.
import AppKit

func rgb(_ hex: UInt32) -> CGColor {
  CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
    blue: CGFloat(hex & 255) / 255, alpha: 1)
}
/// Blue selects, red files, yellow marks — the same order as `WaveMark` in the app.
let bars = [rgb(0x2D51E0), rgb(0x2D51E0), rgb(0xD93B2B), rgb(0xF0B323), rgb(0xF2F1EE)]
let ink = rgb(0x0D0D10)

/// Five pill bars centred in `rect`, sized from the design board (220 pt tile).
func drawBars(_ ctx: CGContext, in rect: CGRect) {
  let scale = rect.width / 220
  let heights: [CGFloat] = [52, 96, 128, 84, 44], width = 22 * scale, gap = 10 * scale
  var x = rect.midX - (5 * width + 4 * gap) / 2
  for (index, h) in heights.enumerated() {
    let height = h * scale
    let bar = CGRect(x: x, y: rect.midY - height / 2, width: width, height: height)
    ctx.setFillColor(bars[index])
    ctx.fill(bar)  // Square, like everything Bauhaus.
    x += width + gap
  }
}

func png(_ size: Int, _ path: String, _ draw: (CGContext) -> Void) {
  let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  draw(ctx)
  let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

// Icon Composer layer: bars only on a transparent 1024 canvas; icon.json supplies the tile.
png(1024, "App/Resources/ChupIcon.icon/Assets/Waveform.png") { ctx in
  drawBars(ctx, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
}

// Legacy appiconset: the macOS grid (824 pt tile in 1024, ~185 pt radius) on the ink ground.
let master = "App/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"
png(1024, master) { ctx in
  let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
  let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(gray: 0, alpha: 0.28))
  ctx.addPath(shape)
  ctx.setFillColor(ink)
  ctx.fillPath()
  ctx.restoreGState()
  drawBars(ctx, in: tile)
}
for (name, size) in [
  ("16x16@1x", 16), ("16x16@2x", 32), ("32x32@1x", 32), ("32x32@2x", 64), ("128x128@1x", 128),
  ("128x128@2x", 256), ("256x256@1x", 256), ("256x256@2x", 512), ("512x512@1x", 512),
] {
  let out = "App/Resources/Assets.xcassets/AppIcon.appiconset/icon_\(name).png"
  let task = Process()
  task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
  task.arguments = ["-z", "\(size)", "\(size)", master, "--out", out]
  task.standardOutput = FileHandle.nullDevice
  try! task.run()
  task.waitUntilExit()
}
