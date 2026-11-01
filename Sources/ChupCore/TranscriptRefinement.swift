import Foundation

public struct TranscriptionWindow: Codable, Equatable, Identifiable {
  public var id: String
  public var meetingID: String
  public var track: TrackKind
  public var start: Double
  public var end: Double
  public var audioStart: Double { max(0, start - 3) }
  public var audioEnd: Double
  /// A provider interval (seconds into this window's audio) fitted inside the audio: zero-length
  /// words and ends a little past the clip are normal provider output, not a reason to drop the
  /// window. Only non-finite times are rejected. Text is never touched.
  public func fit(start: Double, end: Double) -> (start: Double, end: Double)? {
    let length = audioEnd - audioStart
    // Tolerate boundary drift and zero-length words only; reversed or out-of-clip times are
    // provider errors, not evidence to place text against.
    guard start.isFinite, end.isFinite, length > 0.05, end >= start, start < length + 0.5, end > -0.5,
      end < length + 0.5
    else { return nil }
    // Stored segments need end > start, so a zero-length word gets a 50 ms span.
    let start = min(max(0, start), length - 0.05)
    return (start, min(max(start + 0.05, end), length))
  }
  public init(meetingID: String, track: TrackKind, start: Double, end: Double, duration: Double) {
    self.meetingID = meetingID
    self.track = track
    self.start = start
    self.end = end
    self.audioEnd = min(duration, end + 3)
    self.id = "window-v1/\(meetingID)/\(track.rawValue)/\(Int(start))"
  }
  public func owns(_ segment: TranscriptSegment) -> Bool {
    let midpoint = (segment.start + segment.end) / 2
    return segment.track == track && midpoint >= start && midpoint < end
  }
  public static func plan(meetingID: String, track: TrackKind, duration: Double) -> [Self] {
    guard duration.isFinite, duration > 0, duration <= 86400 else { return [] }
    return stride(from: 0.0, to: duration, by: 90).map {
      Self(
        meetingID: meetingID, track: track, start: $0, end: min(duration, $0 + 90),
        duration: duration)
    }
  }
}
public struct TranscriptionJob: Codable, Equatable, Identifiable {
  public var window: TranscriptionWindow
  public var status: String
  public var error: String?
  public var context: [TranscriptSegment]
  public var id: String { window.id }
  public init(
    window: TranscriptionWindow, status: String = "pending", context: [TranscriptSegment] = [],
    error: String? = nil
  ) {
    self.window = window
    self.status = status
    self.context = context
    self.error = error
  }
}
public struct TranscriptReview: Codable, Equatable, Identifiable {
  public var id: String
  public var window: TranscriptionWindow
  public var incoming: [TranscriptSegment]
  public var current: [TranscriptSegment]
  public init(
    window: TranscriptionWindow, incoming: [TranscriptSegment], current: [TranscriptSegment]
  ) {
    self.id = window.id
    self.window = window
    self.incoming = incoming
    self.current = current
  }
}
/// The diarizing model labels speakers well but hears words worse than `gpt-transcribe`, which
/// has no speakers. This keeps the diarized turns and swaps in the accurate pass's words, aligned
/// by longest common word subsequence; words in an unmatched run are spread over the diarized
/// words in the same run. Too little agreement keeps the diarized text untouched.
public enum AccuracyPass {
  public static func merge(_ segments: [String], accurate: String) -> [String] {
    func norm(_ word: Substring) -> String {
      String(word.lowercased().filter { $0.isLetter || $0.isNumber })
    }
    var owner: [Int] = []
    var diar: [String] = []
    for (index, text) in segments.enumerated() {
      for word in text.split(whereSeparator: \.isWhitespace) {
        owner.append(index)
        diar.append(norm(word))
      }
    }
    let words = accurate.split(whereSeparator: \.isWhitespace)
    let acc = words.map(norm)
    let n = diar.count, m = acc.count
    guard n > 0, m > 0, n * m <= 4_000_000 else { return segments }
    // ponytail: O(n·m) LCS table; a 96 s window is a few hundred words a side.
    var table = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
    for i in stride(from: n - 1, through: 0, by: -1) {
      for j in stride(from: m - 1, through: 0, by: -1) {
        table[i][j] = diar[i] == acc[j] && !acc[j].isEmpty
          ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
      }
    }
    guard Double(table[0][0]) >= 0.6 * Double(min(n, m)) else { return segments }
    var pairs: [(Int, Int)] = []
    var i = 0, j = 0
    while i < n && j < m {
      if diar[i] == acc[j] && !acc[j].isEmpty && table[i][j] == table[i + 1][j + 1] + 1 {
        pairs.append((i, j)); i += 1; j += 1
      } else if table[i + 1][j] >= table[i][j + 1] { i += 1 } else { j += 1 }
    }
    var assigned = [Int](repeating: 0, count: m)
    var previous = (-1, -1)
    for pair in pairs + [(n, m)] {
      let gapDiar = (previous.0 + 1)..<pair.0, gapAcc = (previous.1 + 1)..<pair.1
      for (r, k) in gapAcc.enumerated() {
        assigned[k] = gapDiar.isEmpty
          ? owner[previous.0 >= 0 ? previous.0 : min(pair.0, n - 1)]
          : owner[gapDiar.lowerBound + r * gapDiar.count / gapAcc.count]
      }
      if pair.0 < n { assigned[pair.1] = owner[pair.0] }
      previous = pair
    }
    var merged = [[Substring]](repeating: [], count: segments.count)
    for (k, word) in words.enumerated() { merged[assigned[k]].append(word) }
    return segments.indices.map { merged[$0].isEmpty ? segments[$0] : merged[$0].joined(separator: " ") }
  }
}
public enum SpeakerContinuity {
  /// Each window is diarized on its own, so the provider's labels restart every 90 s. One clip
  /// per earlier acoustic group (its longest line, clipped to 2–10 s), most talk time first, is
  /// sent as a known-speaker reference so the next window can reuse that group.
  public static func carryReferences(_ seen: [TranscriptSegment], limit: Int)
    -> [(speakerID: String, start: Double, end: Double)]
  {
    guard limit > 0 else { return [] }
    let groups = Dictionary(grouping: seen.filter {
      !$0.provisional && !$0.speakerID.hasPrefix("enrolled:") && $0.speakerID != "assistant"
    }, by: \.speakerID)
    return groups.compactMap { id, lines -> (String, Double, Double, Double)? in
      guard let longest = lines.max(by: { $0.end - $0.start < $1.end - $1.start }),
        longest.end - longest.start >= 2.5
      else { return nil }
      return (id, longest.start, min(longest.end, longest.start + 10),
        lines.reduce(0) { $0 + $1.end - $1.start })
    }
    .sorted { $0.3 != $1.3 ? $0.3 > $1.3 : $0.0 < $1.0 }
    .prefix(limit).map { ($0.0, $0.1, $0.2) }
  }
  /// Matching content is only useful in shared audio, on the same track. Conflicting matches
  /// leave the request-local label unknown. Numeric speaker labels never establish identity.
  public static func reconcile(_ incoming: [TranscriptSegment], previous: [TranscriptSegment])
    -> [TranscriptSegment]
  {
    func words(_ text: String) -> [String] {
      text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
    var evidence: [String: [String: Int]] = [:]
    for next in incoming {
      let tokens = words(next.text)
      guard tokens.count >= 3 else { continue }
      for old in previous where old.track == next.track && old.meetingID == next.meetingID {
        let overlap = min(old.end, next.end) - max(old.start, next.start)
        guard overlap > 0.3, tokens == words(old.text) else { continue }
        evidence[next.speakerID, default: [:]][old.speakerID, default: 0] += tokens.count
      }
    }
    let proposed = evidence.compactMapValues { matches -> String? in
      guard matches.count == 1, let match = matches.first, match.value >= 6 else { return nil }
      return match.key
    }
    return incoming.map { segment in
      var item = segment
      // Shared utterances retain the first request's boundary, preventing jitter around the
      // midpoint ownership boundary from duplicating or dropping an otherwise identical phrase.
      let same = previous.filter {
        $0.track == item.track && $0.meetingID == item.meetingID
          && min($0.end, item.end) - max($0.start, item.start) > 0.3
          && words($0.text) == words(item.text) && words(item.text).count >= 3
      }
      if same.count == 1, let original = same.first {
        item.start = original.start
        item.end = original.end
        item.id = original.id
      }
      if let target = proposed[item.speakerID], proposed.values.filter({ $0 == target }).count == 1
      {
        item.speakerID = target
        item.speakerName = previous.first { $0.speakerID == target }?.speakerName
        item.attribution = "overlap-linked acoustic group"
      }
      return item
    }
  }
}
public struct VoiceEnrollment: Codable, Equatable, Identifiable {
  public var id: String
  public var name: String
  public var meetingID: String
  public var segmentID: String
  public var created: Date
  public var duration: Double
  public var referencePath: String
  public var cloudMatching: Bool
  public init(
    id: String = UUID().uuidString, name: String, meetingID: String, segmentID: String,
    duration: Double, referencePath: String, cloudMatching: Bool = false
  ) {
    self.id = id
    self.name = name
    self.meetingID = meetingID
    self.segmentID = segmentID
    self.duration = duration
    self.referencePath = referencePath
    self.cloudMatching = cloudMatching
    self.created = Date()
  }
}
