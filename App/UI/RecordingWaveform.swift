import SwiftUI
import ChupCore

struct RecordingWaveform: View {
  let bins: [WaveformBin]
  let duration: Double
  let position: Double
  var body: some View {
    Canvas { context, size in
      guard duration > 0, !bins.isEmpty else { return }
      let count = max(1, Int(size.width / 3))
      var peaks = [Float](repeating: -1, count: count)
      for bin in bins where bin.time >= 0 && bin.time <= duration {
        let index = min(count - 1, Int(bin.time / duration * Double(count)))
        peaks[index] = max(peaks[index], bin.peak)
      }
      for index in peaks.indices where peaks[index] >= 0 {
        let height = max(2, CGFloat(peaks[index]) * size.height)
        let x = CGFloat(index) * size.width / CGFloat(count)
        let rect = CGRect(x: x, y: (size.height - height) / 2, width: 2, height: height)
        context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(Palette.olive.opacity(Double(index) / Double(count) <= position / duration ? 1 : 0.35)))
      }
    }
  }
}
