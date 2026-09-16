import Foundation

public struct MeetingSearchHit: Equatable, Identifiable {
  public var meetingID: String
  public var segmentID: String?
  public var excerpt: String
  public var id: String { meetingID }
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
      ORDER BY bm25(search) LIMIT 500
      """, [terms])
    var seen = Set<String>()
    return values.compactMap { row in
      guard seen.insert(row[0]).inserted else { return nil }
      return MeetingSearchHit(meetingID: row[0], segmentID: row[1] == "segment" ? row[2] : nil, excerpt: row[3])
    }
  }
}
