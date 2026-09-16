import CSQLite
import Darwin
import Foundation

/// Serialized, transaction-backed repository. No networking or audio callbacks execute here.
public final class WorkspaceStore {
  var db: OpaquePointer?
  private var lockFile: Int32 = -1
  public private(set) var encrypted = false
  public private(set) var migratedPlaintext = false
  let lock = NSRecursiveLock()
  private let encoder = JSONEncoder()
  let decoder = JSONDecoder()
  public init(url: URL, key: Data? = nil) throws {
    encoder.outputFormatting = [.sortedKeys]
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    if let key {
      lockFile = open(url.appendingPathExtension("lock").path, O_CREAT | O_RDWR, 0o600)
      guard lockFile >= 0, flock(lockFile, LOCK_EX | LOCK_NB) == 0 else {
        if lockFile >= 0 {
          close(lockFile)
          lockFile = -1
        }
        throw WorkspaceError.message("The encrypted workspace is already open in another process.")
      }
      do { migratedPlaintext = try DatabaseEncryption.migratePlaintext(at: url, key: key) } catch {
        close(lockFile)
        lockFile = -1
        throw error
      }
    }
    guard
      sqlite3_open_v2(
        url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        == SQLITE_OK
    else { throw WorkspaceError.message("Cannot open workspace database.") }
    if let key {
      do {
        try DatabaseEncryption.apply(key, to: db)
        guard !(try DatabaseEncryption.sql(db, "PRAGMA cipher_version")).isEmpty else {
          throw WorkspaceError.message(
            "SQLCipher is unavailable. The app will not store plaintext metadata.")
        }
        encrypted = true
      } catch {
        sqlite3_close(db)
        db = nil
        if lockFile >= 0 {
          close(lockFile)
          lockFile = -1
        }
        throw error
      }
    }
    try execute("PRAGMA temp_store=MEMORY;")
    try execute("PRAGMA secure_delete=ON;")
    try execute("PRAGMA journal_mode=WAL;")
    try execute("PRAGMA synchronous=FULL;")
    try execute("PRAGMA foreign_keys=ON;")
    sqlite3_busy_timeout(db, 3000)
    try execute(
      "CREATE TABLE IF NOT EXISTS objects(kind TEXT NOT NULL, id TEXT NOT NULL, parent TEXT NOT NULL DEFAULT '', json TEXT NOT NULL, PRIMARY KEY(kind,id));"
    )
    try execute(
      "CREATE VIRTUAL TABLE IF NOT EXISTS search USING fts5(kind UNINDEXED,id UNINDEXED,parent UNINDEXED,body);"
    )
    try execute(
      "CREATE TABLE IF NOT EXISTS notes(meeting TEXT PRIMARY KEY, text TEXT NOT NULL, version INTEGER NOT NULL);"
    )
    try execute(
      "CREATE TABLE IF NOT EXISTS mutations(id TEXT PRIMARY KEY, fingerprint TEXT NOT NULL, receipt TEXT NOT NULL);"
    )
    try execute("PRAGMA user_version=1;")
  }
  deinit {
    sqlite3_close(db)
    if lockFile >= 0 { close(lockFile) }
  }
  private func error() -> WorkspaceError { .message(String(cString: sqlite3_errmsg(db))) }
  func execute(_ sql: String, _ values: [String] = []) throws {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw error() }
    defer { sqlite3_finalize(statement) }
    for (i, value) in values.enumerated() {
      sqlite3_bind_text(
        statement, Int32(i + 1), value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { break }
      guard status == SQLITE_ROW else { throw error() }
    }
  }
  func rows(_ sql: String, _ values: [String] = []) throws -> [[String]] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw error() }
    defer { sqlite3_finalize(statement) }
    for (i, value) in values.enumerated() {
      sqlite3_bind_text(
        statement, Int32(i + 1), value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
    var result = [[String]]()
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { break }
      guard status == SQLITE_ROW else { throw error() }
      result.append(
        (0..<sqlite3_column_count(statement)).map { i in
          sqlite3_column_text(statement, i).map { String(cString: $0) } ?? ""
        })
    }
    return result
  }
  func transaction<T>(_ work: () throws -> T) throws -> T {
    lock.lock()
    defer { lock.unlock() }
    try execute("BEGIN IMMEDIATE")
    do {
      let result = try work()
      try execute("COMMIT")
      return result
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }
  func json<T: Encodable>(_ value: T) throws -> String {
    String(decoding: try encoder.encode(value), as: UTF8.self)
  }
  public func put<T: Encodable>(
    _ value: T, kind: String, id: String, parent: String = "", searchable: String = ""
  ) throws {
    try transaction {
      if kind == "meeting" { try requireExistingScope(id) }
      if !parent.isEmpty, kind != "deletion",
        !(try rows("SELECT id FROM objects WHERE kind='deletedMeeting' AND id=?", [parent])).isEmpty
      {
        throw WorkspaceError.message("This meeting has been deleted. Late work was discarded.")
      }
      try execute(
        "INSERT OR REPLACE INTO objects(kind,id,parent,json) VALUES(?,?,?,?)",
        [kind, id, parent, try json(value)])
      try execute("DELETE FROM search WHERE kind=? AND id=?", [kind, id])
      try execute(
        "INSERT INTO search(kind,id,parent,body) VALUES(?,?,?,?)", [kind, id, parent, searchable])
    }
  }
  public func list<T: Decodable>(_ type: T.Type, kind: String, parent: String? = nil) throws -> [T]
  {
    lock.lock()
    defer { lock.unlock() }
    let data = try rows(
      "SELECT json FROM objects WHERE kind=?" + (parent == nil ? "" : " AND parent=?")
        + " ORDER BY rowid", [kind] + (parent.map { [$0] } ?? []))
    return try data.map { try decoder.decode(type, from: Data($0[0].utf8)) }
  }
  public func remove(kind: String, id: String) throws {
    try transaction {
      try execute("DELETE FROM objects WHERE kind=? AND id=?", [kind, id])
      try execute("DELETE FROM search WHERE kind=? AND id=?", [kind, id])
    }
  }
  public func search(_ query: String, kind: String) throws -> Set<String> {
    lock.lock()
    defer { lock.unlock() }
    let terms = query.split(whereSeparator: { $0.isWhitespace }).map {
      "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*"
    }.joined(separator: " AND ")
    guard !terms.isEmpty else { return [] }
    return Set(
      try rows("SELECT id FROM search WHERE search MATCH ? AND kind=?", [terms, kind]).map { $0[0] }
    )
  }
  public func receipt(requestID: String) throws -> MutationReceipt? {
    lock.lock()
    defer { lock.unlock() }
    guard let row = try rows("SELECT receipt FROM mutations WHERE id=?", [requestID]).first else {
      return nil
    }
    return try decoder.decode(MutationReceipt.self, from: Data(row[0].utf8))
  }
  public func note(_ meetingID: String) throws -> Note {
    lock.lock()
    defer { lock.unlock() }
    guard let row = try rows("SELECT text,version FROM notes WHERE meeting=?", [meetingID]).first
    else { return Note() }
    return Note(text: row[0], version: Int(row[1]) ?? 0)
  }
  @discardableResult public func writeNote(
    meetingID: String, text: String, expectedVersion: Int, requestID: String
  ) throws -> MutationReceipt {
    try transaction {
      try requireExistingScope(meetingID)
      let fingerprint = try json([meetingID, text, String(expectedVersion)])
      if let row = try rows("SELECT fingerprint,receipt FROM mutations WHERE id=?", [requestID])
        .first
      {
        guard row[0] == fingerprint else { throw WorkspaceError.requestCollision }
        return try decoder.decode(MutationReceipt.self, from: Data(row[1].utf8))
      }
      let before = try note(meetingID)
      guard before.version == expectedVersion else { throw WorkspaceError.staleVersion }
      let after = Note(text: text, version: before.version + 1)
      let receipt = MutationReceipt(
        requestID: requestID, meetingID: meetingID, before: before, after: after)
      try execute(
        "INSERT OR REPLACE INTO notes(meeting,text,version) VALUES(?,?,?)",
        [meetingID, text, String(after.version)])
      try execute(
        "INSERT INTO mutations(id,fingerprint,receipt) VALUES(?,?,?)",
        [requestID, fingerprint, try json(receipt)])
      try execute(
        "INSERT INTO objects(kind,id,parent,json) VALUES('noteVersion',?,?,?)",
        [requestID, meetingID, try json(after)])
      try execute("DELETE FROM search WHERE kind='note' AND id=?", [meetingID])
      try execute(
        "INSERT INTO search(kind,id,parent,body) VALUES('note',?,?,?)",
        [meetingID, meetingID, text])
      return receipt
    }
  }
  public func undo(_ receipt: MutationReceipt, requestID: String = UUID().uuidString) throws
    -> MutationReceipt
  {
    try writeNote(
      meetingID: receipt.meetingID, text: receipt.before.text,
      expectedVersion: receipt.after.version, requestID: requestID)
  }
  public func saveSegments(_ incoming: [TranscriptSegment], meetingID: String, revisionID: String)
    throws
  {
    try requireExistingScope(meetingID)
    // One transaction protects the complete provider revision and the correction overlay.
    try transaction {
      let corrections = try list(TranscriptSegment.self, kind: "correction", parent: meetingID)
      let overlay = Dictionary(corrections.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
      try execute(
        "INSERT OR REPLACE INTO objects(kind,id,parent,json) VALUES('transcriptRevision',?,?,?)",
        [revisionID, meetingID, try json(incoming)])
      for item in incoming {
        let segment = overlay[item.id] ?? item
        try execute(
          "INSERT OR REPLACE INTO objects(kind,id,parent,json) VALUES('segment',?,?,?)",
          [segment.id, meetingID, try json(segment)])
        try execute("DELETE FROM search WHERE kind='segment' AND id=?", [segment.id])
        try execute(
          "INSERT INTO search(kind,id,parent,body) VALUES('segment',?,?,?)",
          [segment.id, meetingID, segment.text])
      }
    }
  }
  /// The window replacement, revision, review gate and resumable job advance share one commit.
  public func commitWindow(_ job: TranscriptionJob, acceptReview: Bool = false) throws -> Bool {
    try requireExistingScope(job.window.meetingID)
    return try transaction {
      let window = job.window
      let current = try list(TranscriptSegment.self, kind: "segment", parent: window.meetingID)
        .filter { !$0.provisional && window.owns($0) }
      let incoming = job.context.filter { window.owns($0) }
      guard Set(incoming.map(\.id)).count == incoming.count,
        incoming.allSatisfy({
          $0.meetingID == window.meetingID && $0.start.isFinite && $0.end.isFinite && $0.start >= 0
            && $0.end > $0.start
        })
      else {
        throw WorkspaceError.invalidEvidence
      }
      let corrections = try list(
        TranscriptSegment.self, kind: "correction", parent: window.meetingID
      )
      .filter { $0.track == window.track && $0.start < window.end && $0.end > window.start }
      let conflict = corrections.contains { correction in
        !incoming.contains {
          $0.id == correction.id && abs($0.start - correction.start) < 0.02
            && abs($0.end - correction.end) < 0.02
        }
      }
      try execute(
        "INSERT OR REPLACE INTO objects(kind,id,parent,json) VALUES('transcriptRevision',?,?,?)",
        [UUID().uuidString, window.meetingID, try json(job.context)])
      var finished = job
      finished.status = conflict && !acceptReview ? "review" : "completed"
      if finished.status == "review" {
        let review = TranscriptReview(window: window, incoming: incoming, current: current)
        try execute(
          "INSERT OR REPLACE INTO objects(kind,id,parent,json) VALUES('transcriptReview',?,?,?)",
          [review.id, window.meetingID, try json(review)])
      } else {
        let overlay = Dictionary(corrections.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        for old in current {
          try execute("DELETE FROM objects WHERE kind='segment' AND id=?", [old.id])
          try execute("DELETE FROM search WHERE kind='segment' AND id=?", [old.id])
        }
        for value in incoming {
          let item = acceptReview ? value : overlay[value.id] ?? value
          try execute(
            "INSERT OR REPLACE INTO objects(kind,id,parent,json) VALUES('segment',?,?,?)",
            [item.id, window.meetingID, try json(item)])
          try execute("DELETE FROM search WHERE kind='segment' AND id=?", [item.id])
          try execute(
            "INSERT INTO search(kind,id,parent,body) VALUES('segment',?,?,?)",
            [item.id, window.meetingID, item.text])
        }
        try execute("DELETE FROM objects WHERE kind='transcriptReview' AND id=?", [window.id])
      }
      try execute(
        "INSERT OR REPLACE INTO objects(kind,id,parent,json) VALUES('transcriptionJob',?,?,?)",
        [job.id, window.meetingID, try json(finished)])
      return finished.status == "completed"
    }
  }
  public func keepTranscriptReview(_ review: TranscriptReview) throws {
    try transaction {
      var job =
        try list(TranscriptionJob.self, kind: "transcriptionJob", parent: review.window.meetingID)
        .first { $0.id == review.id } ?? TranscriptionJob(window: review.window)
      job.status = "completed"
      job.context = try list(
        TranscriptSegment.self, kind: "segment", parent: review.window.meetingID
      )
      .filter { review.window.owns($0) }
      try execute(
        "INSERT OR REPLACE INTO objects(kind,id,parent,json) VALUES('transcriptionJob',?,?,?)",
        [job.id, review.window.meetingID, try json(job)])
      try execute("DELETE FROM objects WHERE kind='transcriptReview' AND id=?", [review.id])
    }
  }
  public func correct(_ segment: TranscriptSegment) throws {
    try transaction {
      for kind in ["correction", "segment"] {
        try execute(
          "INSERT OR REPLACE INTO objects(kind,id,parent,json) VALUES(?,?,?,?)",
          [kind, segment.id, segment.meetingID, try json(segment)])
      }
      try execute("DELETE FROM search WHERE kind='segment' AND id=?", [segment.id])
      try execute(
        "INSERT INTO search(kind,id,parent,body) VALUES('segment',?,?,?)",
        [segment.id, segment.meetingID, segment.text])
    }
  }
  public func writeAction(_ requested: ActionRecord, expectedVersion: Int, requestID: String) throws
    -> ActionReceipt
  {
    try transaction {
      guard !requested.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        ["open", "done", "unknown", "archived"].contains(requested.status)
      else { throw WorkspaceError.invalidEvidence }
      try requireExistingScope(requested.meetingID)
      let fingerprint = try json(requested) + "/" + String(expectedVersion)
      if let saved = try rows(
        "SELECT json FROM objects WHERE kind='actionMutation' AND id=?", [requestID]
      ).first {
        let pair = try decoder.decode([String].self, from: Data(saved[0].utf8))
        guard pair[0] == fingerprint else { throw WorkspaceError.requestCollision }
        return try decoder.decode(ActionReceipt.self, from: Data(pair[1].utf8))
      }
      if let existing = try rows(
        "SELECT parent FROM objects WHERE kind='action' AND id=?", [requested.id]
      ).first {
        guard existing[0] == requested.meetingID else { throw WorkspaceError.requestCollision }
      }
      let before = try list(ActionRecord.self, kind: "action", parent: requested.meetingID).first {
        $0.id == requested.id
      }
      guard (before?.version ?? 0) == expectedVersion else { throw WorkspaceError.staleVersion }
      if requested.origin == "transcript" {
        let item = SummaryItem(
          category: "action", text: requested.title, owner: requested.owner,
          dueDate: requested.dueDate, status: requested.status, sources: requested.sources)
        try EvidenceValidator.validate(
          MeetingSummary(items: [item]), meetingID: requested.meetingID,
          segments: list(TranscriptSegment.self, kind: "segment", parent: requested.meetingID))
      }
      var after = requested
      after.version = expectedVersion + 1
      let receipt = ActionReceipt(requestID: requestID, before: before, after: after)
      try execute(
        "INSERT OR REPLACE INTO objects(kind,id,parent,json) VALUES('action',?,?,?)",
        [after.id, after.meetingID, try json(after)])
      try execute(
        "INSERT INTO objects(kind,id,parent,json) VALUES('actionMutation',?,?,?)",
        [requestID, after.meetingID, try json([fingerprint, try json(receipt)])])
      try execute("DELETE FROM search WHERE kind='action' AND id=?", [after.id])
      try execute(
        "INSERT INTO search(kind,id,parent,body) VALUES('action',?,?,?)",
        [after.id, after.meetingID, after.title])
      return receipt
    }
  }
  public func saveSummaryRevision(_ revision: SummaryRevision, segments: [TranscriptSegment]) throws
  {
    try transaction {
      try requireExistingScope(revision.meetingID)
      guard !revision.provisional, revision.fingerprint == TranscriptScope.fingerprint(segments)
      else {
        throw WorkspaceError.staleVersion
      }
      try EvidenceValidator.validate(
        revision.summary, meetingID: revision.meetingID, segments: segments)
      try execute(
        "INSERT INTO objects(kind,id,parent,json) VALUES('summary',?,?,?)",
        [revision.id, revision.meetingID, try json(revision.summary)])
      try execute(
        "INSERT INTO objects(kind,id,parent,json) VALUES('summaryVersion',?,?,?)",
        [revision.id, revision.meetingID, try json(revision)])
    }
  }
  public func saveSummary(
    _ summary: MeetingSummary, meetingID: String, segments: [TranscriptSegment]
  ) throws {
    try EvidenceValidator.validate(summary, meetingID: meetingID, segments: segments)
    try put(summary, kind: "summary", id: UUID().uuidString, parent: meetingID)
  }
}
