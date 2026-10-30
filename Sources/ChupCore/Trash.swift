import Foundation

/// A meeting or dictation moved to the Trash. The item itself is untouched until it is
/// purged through the verified deletion plan, so Restore brings it back intact.
public struct TrashEntry: Codable, Identifiable, Equatable {
  public var id: String
  public var kind: String
  public var title: String
  public var trashedAt: Date
  public init(id: String, kind: String, title: String, trashedAt: Date = Date()) {
    self.id = id
    self.kind = kind
    self.title = title
    self.trashedAt = trashedAt
  }
  public static let retentionDays = 30
  public func expired(now: Date = Date()) -> Bool {
    now.timeIntervalSince(trashedAt) > Double(Self.retentionDays) * 86_400
  }
}

/// A meeting whose audio or transcript was deleted on its own; citations show why a source is gone.
public struct PartialDeletion: Codable, Equatable {
  public var audio = false
  public var transcript = false
  public init(audio: Bool = false, transcript: Bool = false) {
    self.audio = audio
    self.transcript = transcript
  }
}

extension WorkspaceStore {
  public func trashEntries() throws -> [TrashEntry] {
    try list(TrashEntry.self, kind: "trash").sorted { $0.trashedAt > $1.trashedAt }
  }
  public func trashedIDs() throws -> Set<String> { Set(try trashEntries().map(\.id)) }
  public func moveToTrash(_ entries: [TrashEntry]) throws {
    try transaction {
      for entry in entries {
        try execute(
          "INSERT OR REPLACE INTO objects(kind,id,parent,json) VALUES('trash',?,'',?)",
          [entry.id, try json(entry)])
      }
    }
  }
  public func restoreFromTrash(_ ids: [String]) throws {
    try transaction {
      for id in ids { try execute("DELETE FROM objects WHERE kind='trash' AND id=?", [id]) }
    }
  }

  public func partialDeletion(_ meetingID: String) throws -> PartialDeletion {
    try list(PartialDeletion.self, kind: "partialDeletion", parent: meetingID).first ?? PartialDeletion()
  }
  /// Deletes the meeting's recorded audio; transcript, notes and summaries stay.
  public func deleteMeetingAudio(_ meetingID: String, root: URL) throws {
    let legs = try list(RecordingLeg.self, kind: "leg", parent: meetingID)
    let paths = try legs.map { try SafeWorkspacePath.relative(URL(fileURLWithPath: $0.directory), root: root) }
    var marker = try partialDeletion(meetingID)
    marker.audio = true
    // Files first: if this stops halfway the leg records still point at what is left,
    // so running it again (or a full meeting delete) removes the rest.
    for path in Set(paths) {
      let url = try SafeWorkspacePath.resolve(path, root: root)
      if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    try transaction {
      try execute("DELETE FROM objects WHERE kind='leg' AND parent=?", [meetingID])
      try execute("DELETE FROM search WHERE kind='leg' AND parent=?", [meetingID])
      try savePartialMarker(marker, meetingID)
    }
  }
  /// Deletes the transcript (and its search rows); notes, summaries and audio stay.
  public func deleteMeetingTranscript(_ meetingID: String) throws {
    var marker = try partialDeletion(meetingID)
    marker.transcript = true
    try transaction {
      try execute("DELETE FROM objects WHERE kind='segment' AND parent=?", [meetingID])
      try execute("DELETE FROM search WHERE kind='segment' AND parent=?", [meetingID])
      try savePartialMarker(marker, meetingID)
    }
  }
  /// Caller holds the transaction.
  private func savePartialMarker(_ marker: PartialDeletion, _ meetingID: String) throws {
    try execute(
      "INSERT OR REPLACE INTO objects(kind,id,parent,json) VALUES('partialDeletion',?,?,?)",
      [meetingID, meetingID, try json(marker)])
  }
}
