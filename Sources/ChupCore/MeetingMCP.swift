import Foundation

/// Read-only Model Context Protocol server over the meeting library (JSON-RPC 2.0, one message
/// per line). Exposes meetings, notes, summaries, actions and transcripts. Never private
/// thoughts, assistant exchanges or voice enrollments, and it has no write tools.
public struct MeetingMCP {
  public let store: WorkspaceStore
  public var version = "1.0"
  public init(store: WorkspaceStore) { self.store = store }

  static let tools: [[String: Any]] = [
    tool(
      "list_meetings", "List recent Chup! meetings (newest first) with IDs, titles and dates.",
      ["limit": ["type": "integer", "description": "Maximum meetings, default 20"]]),
    tool(
      "search_meetings", "Full-text search over meeting titles, notes and transcripts.",
      ["query": ["type": "string"]], required: ["query"]),
    tool(
      "get_meeting_notes",
      "A meeting's notes (the user's lines plus transcript-backed additions), summary and actions.",
      ["meeting_id": ["type": "string"]], required: ["meeting_id"]),
    tool(
      "get_transcript", "A meeting's transcript with timestamps and speaker names.",
      ["meeting_id": ["type": "string"]], required: ["meeting_id"]),
  ]
  static func tool(
    _ name: String, _ description: String, _ properties: [String: Any], required: [String] = []
  ) -> [String: Any] {
    [
      "name": name, "description": description,
      "inputSchema": ["type": "object", "properties": properties, "required": required],
      "annotations": ["readOnlyHint": true],
    ]
  }

  /// Returns the response line, or nil for notifications.
  public func handle(_ line: Data) -> Data? {
    guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
      return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
    }
    guard let id = message["id"] else { return nil }
    let params = message["params"] as? [String: Any] ?? [:]
    let result: [String: Any]
    switch message["method"] as? String {
    case "initialize":
      result = [
        "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
        "capabilities": ["tools": [:]], "serverInfo": ["name": "chup", "version": version],
        "instructions":
          "Read-only access to the user's Chup! meetings. Notes mark the user's own lines; other lines come from the transcript.",
      ]
    case "ping": result = [:]
    case "tools/list": result = ["tools": Self.tools]
    case "tools/call":
      let arguments = params["arguments"] as? [String: Any] ?? [:]
      do {
        result = ["content": [["type": "text", "text": try call(params["name"] as? String ?? "", arguments)]]]
      } catch {
        result = ["content": [["type": "text", "text": error.localizedDescription]], "isError": true]
      }
    default:
      return encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found"]])
    }
    return encode(["jsonrpc": "2.0", "id": id, "result": result])
  }

  func call(_ name: String, _ arguments: [String: Any]) throws -> String {
    let trashed = try store.trashedIDs()
    let meetings = try store.list(Meeting.self, kind: "meeting").filter { !trashed.contains($0.id) }
      .sorted { $0.created > $1.created }
    func meeting() throws -> Meeting {
      guard let id = arguments["meeting_id"] as? String, let found = meetings.first(where: { $0.id == id })
      else { throw WorkspaceError.message("No meeting with that meeting_id. Use list_meetings.") }
      return found
    }
    func header(_ m: Meeting) -> String {
      "\(m.title) · \(m.created.formatted(date: .abbreviated, time: .shortened))"
        + (m.participants.isEmpty ? "" : " · \(m.participants)") + " · id: \(m.id)"
    }
    switch name {
    case "list_meetings":
      let limit = min(200, max(1, arguments["limit"] as? Int ?? 20))
      return meetings.prefix(limit).map(header).joined(separator: "\n")
    case "search_meetings":
      guard let query = arguments["query"] as? String, !query.isEmpty else {
        throw WorkspaceError.message("query is required.")
      }
      let titles = Dictionary(meetings.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
      let hits = try store.searchMeetings(query).prefix(25)
      return hits.isEmpty
        ? "No matches."
        : hits.map { "\(titles[$0.meetingID] ?? "Meeting") (id: \($0.meetingID)): \($0.excerpt)" }
          .joined(separator: "\n")
    case "get_meeting_notes":
      let m = try meeting()
      var out = ["# " + header(m)]
      if let notes = try store.list(EnhancedNotes.self, kind: "enhancedNotes", parent: m.id).last {
        out.append("\n## Notes (lines marked [you] are the user's own)")
        out += notes.blocks.map {
          $0.isHeading ? "\n### " + $0.plainText : "- " + ($0.kind == "user" ? "[you] " : "") + $0.text
        }
      }
      // Always include the live note too: it may have changed after the notes were written.
      if !(try store.note(m.id).text.isEmpty) {
        out.append("\n## The user's current notes\n" + (try store.note(m.id).text))
      }
      if let summary = try store.list(MeetingSummary.self, kind: "summary", parent: m.id).last {
        out.append("\n## Summary")
        out += summary.items.map { "- [\($0.category)] \($0.text)" }
      }
      let actions = try store.list(ActionRecord.self, kind: "action", parent: m.id)
        .filter { $0.status != "archived" }
      if !actions.isEmpty {
        out.append("\n## Actions")
        out += actions.map {
          "- [\($0.status)] \($0.title)" + ($0.owner.map { " · owner: \($0)" } ?? "")
            + ($0.dueDate.map { " · due: \($0)" } ?? "")
        }
      }
      return out.joined(separator: "\n")
    case "get_transcript":
      let m = try meeting()
      let all = try store.list(TranscriptSegment.self, kind: "segment", parent: m.id)
        .sorted { $0.start < $1.start }
      guard !all.isEmpty else { return "No transcript yet for \(m.title)." }
      // Prefer the refined transcript; live captions are labelled as provisional.
      let final = all.filter { !$0.provisional }
      let segments = final.isEmpty ? all : final
      return (final.isEmpty ? "(Live captions, provisional until the transcript is refined)\n" : "")
        + segments.map {
        let t = Int($0.start)
        return String(format: "[%02d:%02d] ", t / 60, t % 60) + ($0.speakerName ?? $0.speakerID) + ": " + $0.text
      }.joined(separator: "\n")
    default:
      throw WorkspaceError.message("Unknown tool \(name).")
    }
  }

  private func encode(_ value: [String: Any]) -> Data {
    ((try? JSONSerialization.data(withJSONObject: value)) ?? Data()) + Data("\n".utf8)
  }
}
