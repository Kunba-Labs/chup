import Foundation

public struct TranscriptionWindow: Codable, Equatable, Identifiable {
  public var id: String
  public var meetingID: String
  public var track: TrackKind
  public var start: Double
  public var end: Double
  public var audioStart: Double { max(0, start - 3) }
  public var audioEnd: Double
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
public enum SpeakerContinuity {
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
