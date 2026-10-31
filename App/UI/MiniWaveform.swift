import CryptoKit
import SwiftUI
import ChupCore

/// Reads the encrypted per-leg waveform index (`RecordingIndex`, cached on disk next to the
/// audio) one recording at a time, so a long list can't start dozens of journal scans at once.
actor WaveformThumbnailLoader {
  static let shared = WaveformThumbnailLoader()
  static let barCount = 36
  private var cache: [String: [Float]] = [:]

  func peaks(id: String, legs: [RecordingLeg], key: SymmetricKey, cacheable: Bool) -> [Float] {
    if let hit = cache[id] { return hit }
    var points: [(Double, Float)] = []
    for leg in legs.sorted(by: { $0.offset < $1.offset }) {
      let directory = URL(fileURLWithPath: leg.directory)
      guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter({ $0.pathExtension == "vwj" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }),
        !files.isEmpty, let (index, _) = try? RecordingIndex.load(leg: leg, urls: files, key: key)
      else { continue }
      let origin = index.files.map(\.first).min() ?? 0
      for file in index.files { points += file.bins.map { (leg.offset + $0.time - origin, $0.peak) } }
    }
    let result = Self.downsample(points, count: Self.barCount)
    if cacheable { cache[id] = result }
    return result
  }

  /// Max peak per bar, scaled to the loudest bar so quiet recordings still show their shape.
  static func downsample(_ points: [(Double, Float)], count: Int) -> [Float] {
    guard let end = points.map(\.0).max(), end > 0 else { return [] }
    var bars = [Float](repeating: 0, count: count)
    for (time, peak) in points {
      let index = min(count - 1, max(0, Int(time / end * Double(count))))
      bars[index] = max(bars[index], peak)
    }
    let loudest = bars.max() ?? 0
    return loudest > 0 ? bars.map { sqrt($0 / loudest) } : bars
  }
}

extension WorkspaceState {
  func thumbnailPeaks(_ source: MiniWaveform.Source) async -> [Float] {
    guard let key else { return [] }
    switch source {
    case .meeting(let id):
      guard let legs = try? db().list(RecordingLeg.self, kind: "leg", parent: id), !legs.isEmpty else { return [] }
      // A meeting still recording keeps growing; don't pin its partial shape in the cache.
      let cacheable = activeMeetingID != id
      return await WaveformThumbnailLoader.shared.peaks(id: id, legs: legs, key: key, cacheable: cacheable)
    case .dictation(let id, let directory):
      var leg = RecordingLeg(meetingID: id, directory: directory, offset: 0)
      leg.id = id  // Stable id so the on-disk index cache is reused.
      let cacheable = recordingEntry?.id != id
      return await WaveformThumbnailLoader.shared.peaks(id: id, legs: [leg], key: key, cacheable: cacheable)
    }
  }
}

/// Small gradient waveform for a meeting or dictation row.
struct MiniWaveform: View {
  enum Source: Hashable {
    case meeting(String)
    case dictation(id: String, directory: String)
  }
  let source: Source
  var width: CGFloat = 72
  var height: CGFloat = 22
  @EnvironmentObject private var state: WorkspaceState
  @State private var peaks: [Float] = []
  var body: some View {
    Canvas { context, size in
      let count = WaveformThumbnailLoader.barCount
      let step = size.width / CGFloat(count)
      for index in 0..<count {
        let peak = peaks.isEmpty ? 0 : CGFloat(peaks[index])
        let barHeight = max(2, peak * size.height)
        let rect = CGRect(x: CGFloat(index) * step, y: (size.height - barHeight) / 2,
          width: max(1, step - 1), height: barHeight)
        let t = Double(index) / Double(count - 1)
        context.fill(Path(roundedRect: rect, cornerRadius: 1),
          with: .color(peaks.isEmpty ? Palette.border : Palette.gradient(at: t)))
      }
    }
    .frame(width: width, height: height)
    .task(id: source) { peaks = await state.thumbnailPeaks(source) }
    .accessibilityHidden(true)
  }
}
