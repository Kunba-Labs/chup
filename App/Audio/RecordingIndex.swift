import Foundation
import CryptoKit
import ChupCore

struct RecordingIndex: Codable {
  struct File: Codable {
    var name: String
    var first: Double
    var end: Double
    var track: TrackKind
    var bins: [WaveformBin]
    var truncated: Bool
  }
  var version = 1
  var files: [File]
  static func load(leg: RecordingLeg, urls: [URL], key: SymmetricKey) throws -> (RecordingIndex, Bool) {
    let root = URL(fileURLWithPath: leg.directory)
    let cache = root.appendingPathComponent("waveform.chupindex")
    let fingerprint = try urls.map { url -> String in
      let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey])
      guard values.isSymbolicLink != true else { throw WorkspaceError.corruptJournal }
      return "\(url.lastPathComponent):\(values.fileSize ?? -1):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
    }.joined(separator: "\n")
    let aad = Data(("Chup-index-v1/" + leg.id + "/" + fingerprint).utf8)
    if let size = try? cache.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 20_000_000,
      let data = try? Data(contentsOf: cache),
      let clear = try? AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key, authenticating: aad),
      let saved = try? JSONDecoder().decode(Self.self, from: clear), saved.version == 1,
      Set(saved.files.map(\.name)).isSubset(of: Set(urls.map(\.lastPathComponent))),
      saved.files.allSatisfy({ $0.first.isFinite && $0.end.isFinite && $0.end >= $0.first && $0.bins.allSatisfy { $0.time.isFinite && $0.peak.isFinite && $0.peak >= 0 && $0.peak <= 1 } }) {
      return (saved, true)
    }
    var indexed: [File] = []
    for url in urls {
      guard let track = TrackKind.allCases.first(where: { url.lastPathComponent.hasPrefix($0.rawValue + "-") }) else { continue }
      var first: Double?
      var end: Double = 0
      var previous: Double?
      var bins: [Int: Float] = [:]
      let truncated = try AudioJournal.scan(url: url, key: key) { packet in
        if let previous, packet.hostTime < previous { throw WorkspaceError.corruptJournal }
        previous = packet.hostTime
        first = first ?? packet.hostTime
        end = max(end, packet.hostTime + packet.duration)
        let relative = packet.hostTime - first!
        guard relative >= 0, end - first! <= 108000 else { throw WorkspaceError.corruptJournal }
        let peak: Float = packet.pcm.withUnsafeBytes { raw in
          raw.bindMemory(to: Int16.self).reduce(Float(0)) { max($0, abs(Float(Int16(littleEndian: $1))) / 32768) }
        }
        let begin = Int(floor(relative * 4))
        let finish = max(begin, Int(ceil((relative + packet.duration) * 4)) - 1)
        for bin in begin...finish { bins[bin] = max(bins[bin] ?? 0, peak) }
      }
      if let first {
        indexed.append(.init(name: url.lastPathComponent, first: first, end: end, track: track,
          bins: bins.keys.sorted().map { WaveformBin(time: first + Double($0) / 4, peak: bins[$0]!) }, truncated: truncated))
      }
    }
    let index = Self(files: indexed)
    // This is a disposable derived cache. Failure to cache never prevents audio playback.
    if let clear = try? JSONEncoder().encode(index), let sealed = try? AES.GCM.seal(clear, using: key, authenticating: aad).combined {
      try? DurableFile.write(sealed, to: cache)
    }
    return (index, false)
  }
}
