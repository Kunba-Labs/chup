import CryptoKit
import Foundation

public struct SummaryRevision: Codable, Identifiable, Equatable {
  public var id: String = UUID().uuidString
  public var meetingID: String
  public var created: Date = Date()
  public var provisional: Bool
  public var fingerprint: String
  public var summary: MeetingSummary
  public init(
    meetingID: String, provisional: Bool, segments: [TranscriptSegment], summary: MeetingSummary
  ) {
    self.meetingID = meetingID
    self.provisional = provisional
    self.fingerprint = TranscriptScope.fingerprint(segments)
    self.summary = summary
  }
}
public enum TranscriptScope {
  public static func fingerprint(_ segments: [TranscriptSegment]) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = (try? encoder.encode(segments.sorted { $0.id < $1.id })) ?? Data()
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
  public static func recent(_ segments: [TranscriptSegment], seconds: Double) -> [TranscriptSegment]
  {
    let end = segments.map(\.end).max() ?? 0
    return segments.filter { $0.end > max(0, end - seconds) }.sorted { $0.start < $1.start }
  }
  /// A completed live transcript is provisional evidence, never final diarization. This copy is
  /// used only to validate/store a separately labeled live outline; canonical segments stay intact.
  public static func outlineEvidence(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
    segments.map {
      var copy = $0
      copy.provisional = false
      return copy
    }
  }
}
public struct ActionRecord: Codable, Identifiable, Equatable {
  public var id: String
  public var meetingID: String
  public var title: String
  public var owner: String?
  public var dueDate: String?
  public var status: String
  public var sources: [Evidence]
  public var version: Int
  public var origin: String
  public init(
    id: String = UUID().uuidString, meetingID: String, title: String, owner: String? = nil,
    dueDate: String? = nil, status: String = "open", sources: [Evidence] = [], version: Int = 0,
    origin: String = "user"
  ) {
    self.id = id
    self.meetingID = meetingID
    self.title = title
    self.owner = owner
    self.dueDate = dueDate
    self.status = status
    self.sources = sources
    self.version = version
    self.origin = origin
  }
}
public struct ActionReceipt: Codable, Equatable {
  public var requestID: String
  public var before: ActionRecord?
  public var after: ActionRecord
}
public struct UsageRecord: Codable, Identifiable {
  public var id: String
  public var meetingID: String
  public var category: String
  public var started: Date
  public var ended: Date?
  public var providerUsage: String?
  public var status: String
  public init(id: String = UUID().uuidString, meetingID: String, category: String) {
    self.id = id
    self.meetingID = meetingID
    self.category = category
    self.started = Date()
    self.status = "running"
  }
}
