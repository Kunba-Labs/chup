import Foundation

public struct MeetingSearchHit: Equatable, Identifiable {
  public var meetingID: String
  public var segmentID: String?
  public var excerpt: String
  public var id: String { meetingID }
  public init(meetingID: String, segmentID: String?, excerpt: String) {
    self.meetingID = meetingID
    self.segmentID = segmentID
    self.excerpt = excerpt
  }
}
extension WorkspaceStore {
  /// A shared-meeting search never includes private thoughts or assistant exchanges.
  public func searchMeetings(_ query: String) throws -> [MeetingSearchHit] {
    lock.lock(); defer { lock.unlock() }
    let terms = query.prefix(1000).split(whereSeparator: \.isWhitespace).prefix(32).map {
      "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*"
    }.joined(separator: " AND ")
    guard !terms.isEmpty else { return [] }
    let values = try rows("""
      SELECT m.id,search.kind,search.id,snippet(search,3,'','',' … ',24)
      FROM search JOIN objects AS m ON m.kind='meeting' AND m.id=CASE WHEN search.kind='meeting' THEN search.id ELSE search.parent END
      WHERE search MATCH ? AND search.kind IN ('meeting','segment','note')
        AND m.id NOT IN (SELECT id FROM objects WHERE kind='trash')
      ORDER BY bm25(search) LIMIT 500
      """, [terms])
    var seen = Set<String>()
    return values.compactMap { row in
      guard seen.insert(row[0]).inserted else { return nil }
      return MeetingSearchHit(meetingID: row[0], segmentID: row[1] == "segment" ? row[2] : nil, excerpt: row[3])
    }
  }
  /// Every matching transcript line (not one per meeting), best first; trashed meetings excluded.
  public func searchTranscriptLines(_ query: String, limit: Int = 30) throws -> [MeetingSearchHit] {
    lock.lock(); defer { lock.unlock() }
    let terms = query.prefix(1000).split(whereSeparator: \.isWhitespace).prefix(32).map {
      "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*"
    }.joined(separator: " AND ")
    guard !terms.isEmpty else { return [] }
    return try rows("""
      SELECT search.parent,search.id,snippet(search,3,'','',' … ',24)
      FROM search JOIN objects AS m ON m.kind='meeting' AND m.id=search.parent
      WHERE search MATCH ? AND search.kind='segment'
        AND m.id NOT IN (SELECT id FROM objects WHERE kind='trash')
      ORDER BY bm25(search) LIMIT ?
      """, [terms, String(limit)]).map { MeetingSearchHit(meetingID: $0[0], segmentID: $0[1], excerpt: $0[2]) }
  }
}
