import SwiftUI

/// Live speech-band energy. Silence settles; no synthetic activity is added.
struct VoiceWaveform: View {
  let samples: [Float]
  var width: CGFloat = 27
  var height: CGFloat = 32
  var color: Color = RailPalette.red
  var barCount: Int = 5
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    let barWidth: CGFloat = width < 24 ? 2 : 3
    let count = max(2, barCount)
    HStack(spacing: max(1, (width - CGFloat(count) * barWidth) / CGFloat(count - 1))) {
      ForEach(0..<count, id: \.self) { index in
        let position = Float(index) / Float(count - 1) * Float(max(0, samples.count - 1))
        let lower = Int(position)
        let upper = min(lower + 1, samples.count - 1)
        let raw = samples.isEmpty ? 0 : samples[lower] + (samples[upper] - samples[lower]) * (position - Float(lower))
        let level = raw.isFinite ? min(1, max(0, raw)) : 0
        let scale = CGFloat(0.65 + 0.35 * sin(Double(index) / Double(count - 1) * .pi))
        Capsule().fill(color).frame(width: barWidth,
          height: max(3, height * CGFloat(level) * scale))
      }
    }.frame(width: width, height: height)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.07), value: samples)
      .accessibilityHidden(true)
  }
}
