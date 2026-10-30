import SwiftUI
import ChupCore

struct RecordingWaveform: View {
  let bins: [WaveformBin]
  let duration: Double
  let position: Double
  var onSeek: ((Double) -> Void)? = nil
  var body: some View {
    GeometryReader { geometry in
      canvas.contentShape(Rectangle()).onTapGesture { location in
        guard let onSeek, duration > 0, geometry.size.width > 0 else { return }
        onSeek(min(max(0, location.x / geometry.size.width), 1) * duration)
      }
    }
  }
  private var canvas: some View {
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
        context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(Palette.gradient(at: Double(index) / Double(count)).opacity(Double(index) / Double(count) <= position / duration ? 1 : 0.3)))
      }
    }
  }
}

/// One lane of speaker-coloured spans across the meeting; click to seek.
struct SpeakerTimeline: View {
  let segments: [TranscriptSegment]
  let duration: Double
  let position: Double
  var onSeek: (Double) -> Void
  var body: some View {
    GeometryReader { geometry in
      Canvas { context, size in
        guard duration > 0 else { return }
        context.fill(
          Path(roundedRect: CGRect(x: 0, y: size.height / 2 - 1, width: size.width, height: 2), cornerRadius: 1),
          with: .color(Palette.border))
        for segment in segments where !segment.provisional {
          let x = CGFloat(segment.start / duration) * size.width
          let width = max(3, CGFloat((segment.end - segment.start) / duration) * size.width)
          context.fill(
            Path(roundedRect: CGRect(x: x, y: 3, width: width, height: size.height - 6), cornerRadius: 3),
            with: .color(Palette.speaker(segment.speakerID)))
        }
        let playhead = CGFloat(min(1, position / duration)) * size.width
        context.fill(Path(CGRect(x: playhead - 1, y: 0, width: 2, height: size.height)), with: .color(Palette.ink))
      }
      .contentShape(Rectangle())
      .onTapGesture { location in
        guard duration > 0, geometry.size.width > 0 else { return }
        onSeek(min(max(0, location.x / geometry.size.width), 1) * duration)
      }
    }
    // The transport slider below is the accessible way to seek.
    .accessibilityHidden(true)
  }
}
