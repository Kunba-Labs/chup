import SwiftUI

/// Today's backdrop: Mount Fuji with a snow cap, low hills, drifting mist and snow-dusted pines,
/// drawn in faint brand tints. Snow falls slowly; Reduce Motion holds a still frame.
struct FujiLandscape: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var scheme
  var body: some View {
    // ponytail: 20 fps Canvas redraw, only while Today is on screen; cheap at this size.
    TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { context in
      let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
      Canvas { g, size in draw(&g, size, t) }
    }.allowsHitTesting(false).accessibilityHidden(true)
  }

  private func draw(_ g: inout GraphicsContext, _ size: CGSize, _ t: Double) {
    let w = size.width, h = size.height
    let dark = scheme == .dark
    let snow = Color.white.opacity(dark ? 0.35 : 0.9)
    func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * w, y: y * h) }

    // The mountain is sized from the height, so wide windows keep Fuji's shape instead of
    // stretching the summit into a flat shelf. dx is in heights from the centre.
    func m(_ dx: Double, _ y: Double) -> CGPoint { CGPoint(x: w / 2 + dx * h, y: y * h) }

    // Sun, low and warm beside the summit.
    g.fill(
      Path(ellipseIn: CGRect(origin: m(0.42, 0.08), size: CGSize(width: 0.14 * h, height: 0.14 * h))),
      with: .color(Palette.red.opacity(dark ? 0.10 : 0.13)))

    // Fuji: concave slopes up to a narrow flat summit.
    var fuji = Path()
    fuji.move(to: m(-1.15, 0.86))
    fuji.addQuadCurve(to: m(-0.09, 0.20), control: m(-0.42, 0.62))
    fuji.addLine(to: m(0.09, 0.20))
    fuji.addQuadCurve(to: m(1.15, 0.86), control: m(0.42, 0.62))
    fuji.closeSubpath()
    g.fill(fuji, with: .linearGradient(
      Gradient(colors: [Palette.accent.opacity(dark ? 0.22 : 0.16), Palette.accent.opacity(0.04)]),
      startPoint: m(0, 0.2), endPoint: m(0, 0.86)))

    // Snow cap inside the slopes, with a ragged lower edge.
    var cap = Path()
    cap.move(to: m(-0.09, 0.20))
    cap.addLine(to: m(0.09, 0.20))
    cap.addQuadCurve(to: m(0.22, 0.36), control: m(0.15, 0.27))
    for (x, y) in [(0.18, 0.33), (0.14, 0.39), (0.10, 0.335), (0.05, 0.40), (0.0, 0.34),
                   (-0.05, 0.395), (-0.10, 0.335), (-0.14, 0.38), (-0.18, 0.33)] {
      cap.addLine(to: m(x, y))
    }
    cap.addLine(to: m(-0.22, 0.36))
    cap.addQuadCurve(to: m(-0.09, 0.20), control: m(-0.15, 0.27))
    cap.closeSubpath()
    g.fill(cap, with: .color(snow))

    // Mist drifting slowly across the mountain's waist.
    let drift = sin(t / 9) * 0.12
    g.drawLayer { mist in
      mist.addFilter(.blur(radius: 14))
      for (i, y) in [0.58, 0.67].enumerated() {
        let left = m(-0.7 + drift * Double(i == 0 ? 1 : -1), y)
        let rect = CGRect(x: left.x, y: left.y, width: 1.4 * h, height: 0.05 * h)
        mist.fill(Path(ellipseIn: rect), with: .color(Palette.workspace.opacity(0.8)))
      }
    }

    // Low hills in two layers.
    for (base, tint) in [(0.74, 0.07), (0.82, 0.10)] {
      var hills = Path()
      hills.move(to: p(0, 1))
      hills.addLine(to: p(0, base + 0.04))
      hills.addCurve(to: p(0.5, base + 0.02), control1: p(0.15, base - 0.06), control2: p(0.32, base + 0.08))
      hills.addCurve(to: p(1, base), control1: p(0.68, base - 0.05), control2: p(0.85, base + 0.06))
      hills.addLine(to: p(1, 1))
      hills.closeSubpath()
      g.fill(hills, with: .color(Palette.accent.opacity(dark ? tint * 1.6 : tint)))
    }

    // Snow-dusted pines on either side of the foreground.
    // Each tree is one flat layer, so overlapping tiers don't darken.
    let pine = Palette.ink
    for (x, height) in [(0.04, 0.40), (0.10, 0.30), (0.155, 0.22), (0.86, 0.26), (0.93, 0.36)] {
      var faded = g  // Opacity on the outer context fades the finished tree as one.
      faded.opacity = dark ? 0.30 : 0.16
      faded.drawLayer { g in
      let width = height * h * 0.55
      let baseY = h
      for tier in 0..<4 {
        let top = baseY - height * h * (1 - Double(tier) * 0.2) - 0.06 * h
        let bottom = top + height * h * 0.38
        let half = width / 2 * (1 - Double(tier) * 0.18)
        var tri = Path()
        tri.move(to: CGPoint(x: x * w, y: top))
        tri.addLine(to: CGPoint(x: x * w + half, y: bottom))
        tri.addLine(to: CGPoint(x: x * w - half, y: bottom))
        tri.closeSubpath()
        g.fill(tri, with: .color(pine))
        // A little snow on each tier's shoulders.
        var dusting = Path()
        dusting.move(to: CGPoint(x: x * w, y: top))
        dusting.addLine(to: CGPoint(x: x * w + half * 0.45, y: top + (bottom - top) * 0.45))
        dusting.addQuadCurve(
          to: CGPoint(x: x * w - half * 0.45, y: top + (bottom - top) * 0.45),
          control: CGPoint(x: x * w, y: top + (bottom - top) * 0.28))
        dusting.closeSubpath()
        g.fill(dusting, with: .color(.white))
      }
      g.fill(
        Path(CGRect(x: x * w - 2, y: baseY - 0.06 * h, width: 4, height: 0.06 * h)), with: .color(pine))
      }
    }

    // Snowfall: fixed flakes, each with its own speed and sway; loops top to bottom.
    for i in 0..<42 {
      let seed = Double(i)
      let speed = 0.012 + (seed * 0.618).truncatingRemainder(dividingBy: 1) * 0.02
      let y = ((seed * 0.371).truncatingRemainder(dividingBy: 1) + t * speed).truncatingRemainder(dividingBy: 1)
      let x = (seed * 0.137).truncatingRemainder(dividingBy: 1) + sin(t * 0.4 + seed) * 0.01
      let r = 1.0 + (seed * 0.29).truncatingRemainder(dividingBy: 1) * 1.6
      g.fill(
        Path(ellipseIn: CGRect(x: x * w - r, y: y * h - r, width: r * 2, height: r * 2)),
        with: .color(snow.opacity(0.4 + 0.5 * (1 - y))))
    }
  }
}
