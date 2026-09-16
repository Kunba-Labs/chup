import Foundation

public struct RetentionPolicy: Codable, Equatable {
  public var meetingDays = 0
  public var dictationDays = 0
  public var questionDays = 0
  public init() {}
  public func expired(_ created: Date, days: Int, now: Date = Date()) -> Bool {
    days > 0 && created < now.addingTimeInterval(-Double(days) * 86400)
  }
}
public struct VoiceQuestionRecord: Codable, Identifiable {
  public var id: String
  public var meetingID: String
  public var directory: String
  public var created: Date = Date()
  public init(id: String, meetingID: String, directory: String) {
    self.id = id
    self.meetingID = meetingID
    self.directory = directory
  }
}
public struct DeletionPlan: Codable, Identifiable {
  public var id: String
  public var meetingID: String?
  public var kind: String
  public var relativePaths: [String]
  public var created = Date()
  public var requestIDs: [String] = []
}
public enum SafeWorkspacePath {
  public static func relative(_ url: URL, root: URL) throws -> String {
    let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
    let actual = url.standardizedFileURL.resolvingSymlinksInPath().path
    guard actual.hasPrefix(rootPath) else {
      throw WorkspaceError.message("The file is outside this workspace.")
    }
    let relative = String(actual.dropFirst(rootPath.count))
    _ = try resolve(relative, root: root)
    return relative
  }
  public static func resolve(_ relative: String, root: URL) throws -> URL {
    let components = relative.split(separator: "/", omittingEmptySubsequences: false)
    guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
      !relative.contains("\\"), !relative.contains("\0")
    else {
      throw WorkspaceError.message("Invalid archive or deletion path.")
    }
    var result = root.standardizedFileURL.resolvingSymlinksInPath()
    for component in components {
      result.appendPathComponent(String(component))
      if let attributes = try? FileManager.default.attributesOfItem(atPath: result.path),
        attributes[.type] as? FileAttributeType == .typeSymbolicLink
      {
        throw WorkspaceError.message("Symbolic links are not allowed in archive or deletion paths.")
      }
    }
    return result
  }
}
public struct MeetingExport: Codable {
  public var format = "Chup meeting export v1"
  public var meeting: Meeting
  public var notes: Note
  public var records: [ExportRecord]
  public struct ExportRecord: Codable {
    public var kind: String
    public var id: String
    public var json: String
  }
}

extension WorkspaceStore {
  public func exportMeeting(_ id: String, includePrivate: Bool = false) throws -> Data {
    guard let meeting = try list(Meeting.self, kind: "meeting").first(where: { $0.id == id }) else {
      throw WorkspaceError.message("Meeting not found.")
    }
    let allowed =
      ["segment", "summary", "summaryVersion", "summaryEdit", "liveOutline", "action", "gap"]
      + (includePrivate ? ["assistantExchange"] : [])
    var records = try rows("SELECT kind,id,json FROM objects WHERE parent=?", [id]).filter {
      allowed.contains($0[0])
    }.map { MeetingExport.ExportRecord(kind: $0[0], id: $0[1], json: $0[2]) }
    if includePrivate {
      records.append(
        .init(kind: "privateThoughts", id: id, json: try json(note("private-thoughts/" + id))))
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(MeetingExport(meeting: meeting, notes: note(id), records: records))
  }
  public func planMeetingDeletion(_ id: String, root: URL) throws -> DeletionPlan {
    var paths = try list(RecordingLeg.self, kind: "leg", parent: id).map {
      try SafeWorkspacePath.relative(URL(fileURLWithPath: $0.directory), root: root)
    }
    let profiles = try list(VoiceEnrollment.self, kind: "enrollment").filter { $0.meetingID == id }
    paths += try profiles.map {
      try SafeWorkspacePath.relative(URL(fileURLWithPath: $0.referencePath), root: root)
    }
    paths += try list(VoiceQuestionRecord.self, kind: "voiceQuestion", parent: id).map {
      try SafeWorkspacePath.relative(URL(fileURLWithPath: $0.directory), root: root)
    }
    paths += try rows("SELECT id FROM objects WHERE kind='voicePlayback' AND parent=?", [id]).map {
      "VoiceQuestions/" + $0[0]
    }
    paths = Array(Set(paths)).sorted()
    for path in paths { _ = try SafeWorkspacePath.resolve(path, root: root) }
    var plan = DeletionPlan(id: id, meetingID: id, kind: "meeting", relativePaths: paths)
    plan.requestIDs = try list(DurableRequest.self, kind: "request", parent: id).map(\.id)
    plan.requestIDs = Array(Set(plan.requestIDs + (try requestsUsingReferences(Set(profiles.map(\.id)))))).sorted()
    try transaction {
      try execute(
        "INSERT OR REPLACE INTO objects(kind,id,parent,json) VALUES('deletion',?,?,?)",
        [id, id, try json(plan)])
      try execute(
        "INSERT OR REPLACE INTO objects(kind,id,json) VALUES('deletedMeeting',?,?)", [id, "{}"])
    }
    return plan
  }
  public func planItemDeletion(id: String, kind: String, directory: String, root: URL) throws
    -> DeletionPlan
  {
    guard ["dictation", "voiceQuestion", "enrollment"].contains(kind) else {
      throw WorkspaceError.message("Unsupported deletion type.")
    }
    let path = try SafeWorkspacePath.relative(URL(fileURLWithPath: directory), root: root)
    var plan = DeletionPlan(id: id, kind: kind, relativePaths: [path])
    plan.requestIDs = try list(DurableRequest.self, kind: "request", parent: kind + "/" + id).map(
      \.id)
    if kind == "enrollment" {
      plan.requestIDs = Array(Set(plan.requestIDs + (try requestsUsingReferences([id])))).sorted()
    }
    try put(plan, kind: "deletion", id: id)
    return plan
  }
  public func finishDeletion(_ plan: DeletionPlan, root: URL) throws {
    for path in plan.relativePaths {
      let url = try SafeWorkspacePath.resolve(path, root: root)
      if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
    }
    try transaction {
      if let id = plan.meetingID {
        for row in try rows("SELECT id,receipt FROM mutations") {
          let receipt = try decoder.decode(MutationReceipt.self, from: Data(row[1].utf8))
          if [id, "private-thoughts/" + id].contains(receipt.meetingID) {
            try execute("DELETE FROM mutations WHERE id=?", [row[0]])
          }
        }
        for profile in try list(VoiceEnrollment.self, kind: "enrollment")
        where profile.meetingID == id {
          try execute("DELETE FROM objects WHERE kind='enrollment' AND id=?", [profile.id])
          try execute("DELETE FROM search WHERE kind='enrollment' AND id=?", [profile.id])
        }
        try execute("DELETE FROM notes WHERE meeting IN (?,?)", [id, "private-thoughts/" + id])
        try execute(
          "DELETE FROM objects WHERE parent IN (?,?) OR (kind='meeting' AND id=?)",
          [id, "private-thoughts/" + id, id])
        try execute(
          "DELETE FROM search WHERE parent IN (?,?) OR (kind='meeting' AND id=?)",
          [id, "private-thoughts/" + id, id])
      } else {
        try execute("DELETE FROM objects WHERE parent=?", [plan.kind + "/" + plan.id])
        try execute("DELETE FROM search WHERE parent=?", [plan.kind + "/" + plan.id])
        try execute("DELETE FROM objects WHERE kind=? AND id=?", [plan.kind, plan.id])
        try execute("DELETE FROM search WHERE kind=? AND id=?", [plan.kind, plan.id])
      }
      if !plan.requestIDs.isEmpty {
        for requestID in plan.requestIDs {
          try execute("DELETE FROM objects WHERE kind='request' AND id=?", [requestID])
        }
        try execute(
          "INSERT OR REPLACE INTO objects(kind,id,json) VALUES('backendDeletion',?,?)",
          [plan.id, try json(plan.requestIDs)])
      }
      try execute("DELETE FROM objects WHERE kind='deletion' AND id=?", [plan.id])
    }
  }
  private func requestsUsingReferences(_ ids: Set<String>) throws -> [String] {
    guard !ids.isEmpty else { return [] }
    let names = Set(ids.map { "voice_" + $0 })
    return try list(DurableRequest.self, kind: "request").filter { job in
      guard let body = try? JSONSerialization.jsonObject(with: job.body) as? [String: Any],
        let references = body["references"] as? [[String: Any]] else { return false }
      return references.contains { ($0["name"] as? String).map(names.contains) ?? false }
    }.map(\.id)
  }
  public func maintenanceCheck() throws -> String {
    let integrity = try rows("PRAGMA integrity_check")
    guard integrity == [["ok"]] else {
      throw WorkspaceError.message("Workspace integrity check failed.")
    }
    if encrypted {
      guard try rows("PRAGMA cipher_integrity_check").isEmpty else {
        throw WorkspaceError.message("Database authentication failed.")
      }
    }
    return "Database integrity and encryption authentication passed."
  }
  public func checkpoint() throws { _ = try rows("PRAGMA wal_checkpoint(TRUNCATE)") }
  public func encryptedSnapshot(to url: URL, key: Data) throws {
    guard !FileManager.default.fileExists(atPath: url.path) else {
      throw WorkspaceError.message("Choose a new backup destination.")
    }
    try DatabaseEncryption.sql(
      db, "ATTACH DATABASE ? AS backup KEY ?", [url.path, DatabaseEncryption.keyText(key)])
    do {
      try DatabaseEncryption.sql(db, "SELECT sqlcipher_export('backup')")
      try DatabaseEncryption.sql(db, "DETACH DATABASE backup")
    } catch {
      _ = try? DatabaseEncryption.sql(db, "DETACH DATABASE backup")
      throw error
    }
  }
}

extension WorkspaceStore {
  public func rebaseRecordingPaths(from old: URL, to root: URL) throws {
    for var leg in try list(RecordingLeg.self, kind: "leg") {
      let relative = try SafeWorkspacePath.relative(URL(fileURLWithPath: leg.directory), root: old)
      leg.directory = try SafeWorkspacePath.resolve(relative, root: root).path
      try put(leg, kind: "leg", id: leg.id, parent: leg.meetingID)
    }
    for var entry in try list(DictationEntry.self, kind: "dictation") {
      entry.audioDirectory = try SafeWorkspacePath.resolve(
        SafeWorkspacePath.relative(URL(fileURLWithPath: entry.audioDirectory), root: old),
        root: root
      ).path
      try put(entry, kind: "dictation", id: entry.id, searchable: entry.text)
    }
    for var profile in try list(VoiceEnrollment.self, kind: "enrollment") {
      profile.referencePath = try SafeWorkspacePath.resolve(
        SafeWorkspacePath.relative(URL(fileURLWithPath: profile.referencePath), root: old),
        root: root
      ).path
      try put(profile, kind: "enrollment", id: profile.id)
    }
    for var question in try list(VoiceQuestionRecord.self, kind: "voiceQuestion") {
      question.directory = try SafeWorkspacePath.resolve(
        SafeWorkspacePath.relative(URL(fileURLWithPath: question.directory), root: old), root: root
      ).path
      try put(question, kind: "voiceQuestion", id: question.id, parent: question.meetingID)
    }
  }
  func requireExistingScope(_ id: String) throws {
    let meeting =
      id.hasPrefix("private-thoughts/") ? String(id.dropFirst("private-thoughts/".count)) : id
    guard try rows("SELECT id FROM objects WHERE kind='deletedMeeting' AND id=?", [meeting]).isEmpty
    else {
      throw WorkspaceError.message("This meeting was deleted. Late work was discarded.")
    }
  }
}

extension WorkspaceStore {
  public func pendingBackendDeletions() throws -> [(id: String, requests: [String])] {
    try rows("SELECT id,json FROM objects WHERE kind='backendDeletion'").map {
      ($0[0], try decoder.decode([String].self, from: Data($0[1].utf8)))
    }
  }
  public func queueBackendDeletion(id: String, requests: [String]) throws {
    try put(requests, kind: "backendDeletion", id: id)
  }
  public func indexLegacyQuestions(root: URL) throws {
    let directory = root.appendingPathComponent("VoiceQuestions")
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    let indexed = Set(try list(VoiceQuestionRecord.self, kind: "voiceQuestion").map(\.id))
    let scopes = Dictionary(
      try rows("SELECT id,parent FROM objects WHERE kind='voicePlayback'").map { ($0[0], $0[1]) },
      uniquingKeysWith: { a, _ in a })
    for file in try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey])
    where !indexed.contains(file.lastPathComponent) {
      let attributes = try file.resourceValues(forKeys: [.creationDateKey, .isDirectoryKey])
      guard attributes.isDirectory == true else { continue }
      _ = try SafeWorkspacePath.relative(file, root: root)
      let scope = scopes[file.lastPathComponent] ?? "unassigned-private-audio"
      var record = VoiceQuestionRecord(
        id: file.lastPathComponent, meetingID: scope, directory: file.path)
      record.created = attributes.creationDate ?? Date()
      try put(record, kind: "voiceQuestion", id: record.id, parent: scope)
    }
  }
}
