import Foundation

public enum WorkspaceError: LocalizedError, Equatable {
  case message(String)
  case staleVersion, requestCollision, invalidEvidence, unsafeRoute, corruptJournal
  public var errorDescription: String? {
    switch self {
    case .message(let s): return s
    case .staleVersion: return "This note changed. Reload it before applying this edit."
    case .requestCollision: return "This request ID was already used for a different change."
    case .invalidEvidence:
      return "The generated result contains an unsupported source. It was not saved."
    case .unsafeRoute:
      return "Voice is unavailable until the audio route provides verified privacy and isolation."
    case .corruptJournal:
      return "Audio authentication failed. The recording was not silently repaired."
    }
  }
}
public enum TrackKind: String, Codable, CaseIterable { case microphone, remote, assistant }
public enum CaptureStatus: String, Codable {
  case idle, listening, processing, recording, speaking, paused, error
}
public enum CleanupMode: String, Codable, CaseIterable {
  case verbatim = "Verbatim"
  case light = "Light cleanup"
  case polished = "Polished"
}
public struct Meeting: Identifiable, Codable, Equatable {
  public var id: String
  public var title: String
  public var created: Date
  public var status: String
  public var participants: String
  public var tags: String
  public init(
    id: String = UUID().uuidString, title: String, created: Date = Date(), status: String = "Ready",
    participants: String = "", tags: String = ""
  ) {
    self.id = id
    self.title = title
    self.created = created
    self.status = status
    self.participants = participants
    self.tags = tags
  }
}
public struct Note: Codable, Equatable {
  public var text: String
  public var version: Int
  public init(text: String = "", version: Int = 0) {
    self.text = text
    self.version = version
  }
}
public struct MutationReceipt: Codable, Equatable {
  public let requestID: String
  public let meetingID: String
  public let before: Note
  public let after: Note
}
public struct TranscriptSegment: Identifiable, Codable, Equatable {
  public var id: String
  public var meetingID: String
  public var start: Double
  public var end: Double
  public var text: String
  public var speakerID: String
  public var speakerName: String?
  public var track: TrackKind
  public var provisional: Bool
  public var attribution: String?
  public init(
    id: String = UUID().uuidString, meetingID: String, start: Double, end: Double, text: String,
    speakerID: String, speakerName: String? = nil, track: TrackKind, provisional: Bool = false
  ) {
    self.id = id
    self.meetingID = meetingID
    self.start = start
    self.end = end
    self.text = text
    self.speakerID = speakerID
    self.speakerName = speakerName
    self.track = track
    self.provisional = provisional
  }
}
public struct Evidence: Codable, Equatable {
  public var segmentID: String
  public var quote: String
  public init(segmentID: String, quote: String) {
    self.segmentID = segmentID
    self.quote = quote
  }
}
public struct SummaryItem: Identifiable, Codable, Equatable {
  public var id: String
  public var category: String
  public var text: String
  public var owner: String?
  public var dueDate: String?
  public var status: String
  public var sources: [Evidence]
  public init(
    id: String = UUID().uuidString, category: String, text: String, owner: String? = nil,
    dueDate: String? = nil, status: String = "open", sources: [Evidence]
  ) {
    self.id = id
    self.category = category
    self.text = text
    self.owner = owner
    self.dueDate = dueDate
    self.status = status
    self.sources = sources
  }
}
public struct MeetingSummary: Codable, Equatable {
  public var items: [SummaryItem]
  public init(items: [SummaryItem]) { self.items = items }
}
public struct DictationEntry: Identifiable, Codable, Equatable {
  public var id: String = UUID().uuidString
  public var created: Date = Date()
  public var text: String
  public var original: String
  public var application: String
  public var mode: String
  public var audioDirectory: String
  public var language: String?
  public var selection: String?
  public var preferences: [Personalization]?
  public var status: String?
  public var transcriptionProvider: String?
  public var processingNote: String?
  public var microphoneName: String?
  public init(
    text: String, original: String, application: String, mode: String, audioDirectory: String
  ) {
    self.text = text
    self.original = original
    self.application = application
    self.mode = mode
    self.audioDirectory = audioDirectory
  }
}
public struct Personalization: Identifiable, Codable, Equatable {
  public var id: String = UUID().uuidString
  public var kind: String
  public var trigger: String
  public var replacement: String
  public var language: String
  public var mode: String?
  public init(kind: String, trigger: String, replacement: String, language: String = "en") {
    self.kind = kind
    self.trigger = trigger
    self.replacement = replacement
    self.language = language
  }
}
public struct RecordingLeg: Identifiable, Codable, Equatable {
  public var id: String = UUID().uuidString
  public var meetingID: String
  public var directory: String
  public var offset: Double
  public var reason: String
  public var hostStart: Double?
  public var microphoneUID: String?
  public var processBundleID: String?
  public init(
    meetingID: String, directory: String, offset: Double, reason: String = "capture",
    hostStart: Double? = nil, microphoneUID: String? = nil, processBundleID: String? = nil
  ) {
    self.meetingID = meetingID
    self.directory = directory
    self.offset = offset
    self.reason = reason
    self.hostStart = hostStart
    self.microphoneUID = microphoneUID
    self.processBundleID = processBundleID
  }
}
public struct CaptureGap: Codable, Equatable {
  public var start: Double
  public var end: Double?
  public var reason: String
  public var track: TrackKind?
  public init(start: Double, end: Double?, reason: String, track: TrackKind? = nil) {
    self.start = start
    self.end = end
    self.reason = reason
    self.track = track
  }
}
public enum EvidenceValidator {
  public static func validate(
    _ summary: MeetingSummary, meetingID: String, segments: [TranscriptSegment]
  ) throws {
    let allowed = Dictionary(
      segments.filter { $0.meetingID == meetingID && !$0.provisional }.map { ($0.id, $0) },
      uniquingKeysWith: { a, _ in a })
    let categories = Set(["overview", "topic", "decision", "action", "question", "risk"])
    for item in summary.items {
      guard categories.contains(item.category), !item.text.isEmpty, !item.sources.isEmpty else {
        throw WorkspaceError.invalidEvidence
      }
      for source in item.sources {
        guard let segment = allowed[source.segmentID],
          !source.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          segment.text.contains(source.quote)
        else { throw WorkspaceError.invalidEvidence }
      }
    }
  }
}
public enum AssistantMode: String, Codable, CaseIterable {
  case privateText = "Private text"
  case privateVoice = "Private voice"
  case broadcast = "Speak in meeting"
}
public struct RoutingPolicy {
  public var meetingActive: Bool
  public var verifiedInputIsolation: Bool
  public var verifiedMixMinus: Bool
  public var headphones: Bool
  public init(
    meetingActive: Bool, verifiedInputIsolation: Bool = false, verifiedMixMinus: Bool = false,
    headphones: Bool = false
  ) {
    self.meetingActive = meetingActive
    self.verifiedInputIsolation = verifiedInputIsolation
    self.verifiedMixMinus = verifiedMixMinus
    self.headphones = headphones
  }
  public func allows(_ mode: AssistantMode) -> Bool {
    switch mode {
    case .privateText: return true
    case .privateVoice: return !meetingActive || (verifiedInputIsolation && headphones)
    case .broadcast: return meetingActive && verifiedMixMinus && headphones
    }
  }
  public static func requiresNewSession(from: AssistantMode, to: AssistantMode) -> Bool {
    from != to
  }
}
