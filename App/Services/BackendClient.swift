import Foundation
import ChupCore

struct FileTranscript: Decodable {
  struct Segment: Decodable {
    var start: Double
    var end: Double
    var text: String
    var speaker: String
  }
  var text: String
  var segments: [Segment]?
}
struct AssistantReply: Decodable {
  typealias ProposedWrite = ProposedNoteWrite
  var text: String
  var sources: [Evidence]
  var write: ProposedWrite?
}
@MainActor struct BackendClient {
  var baseURL: URL
  var token: String
  var store: WorkspaceStore?
  var scope = "workspace"
  var associationID: String?
  var onChange: (() -> Void)?
  var timeout: TimeInterval = 180
  func request<T: Decodable>(_ route: String, body: Data, contentType: String = "application/json")
    async throws -> T
  {
    guard
      baseURL.scheme == "https" || ["localhost", "127.0.0.1", "::1"].contains(baseURL.host ?? "")
    else { throw WorkspaceError.message("Use HTTPS for a remote backend.") }
    let job = DurableRequest(scope: scope, associationID: associationID, route: route, body: body)
    return try JSONDecoder().decode(T.self, from: await perform(job, contentType: contentType))
  }
  func perform(_ original: DurableRequest, contentType: String = "application/json") async throws
    -> Data
  {
    guard
      baseURL.scheme == "https" || ["localhost", "127.0.0.1", "::1"].contains(baseURL.host ?? "")
    else { throw WorkspaceError.message("Use HTTPS for a remote backend.") }
    var job = original
    if let cached = job.response, job.status == "completed" { return cached }
    job.status = "running"
    job.error = nil
    try store?.saveRequest(job)
    onChange?()
    do {
      var request = URLRequest(url: baseURL.appendingPathComponent(job.route))
      request.httpMethod = "POST"
      request.httpBody = job.body
      request.timeoutInterval = timeout
      request.setValue(contentType, forHTTPHeaderField: "Content-Type")
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      request.setValue(job.id, forHTTPHeaderField: "X-Chup-Request-ID")
      let (data, response) = try await URLSession.shared.data(for: request)
      struct Metadata: Decodable {
        var _chup: Values?
        struct Values: Decodable { var usage: [ProviderUsage] }
      }
      let usageDecoder = JSONDecoder()
      usageDecoder.dateDecodingStrategy = .millisecondsSince1970
      if let items = try? usageDecoder.decode(Metadata.self, from: data)._chup?.usage {
        for item in items { try store?.saveProviderUsage(item, scope: job.scope) }
      }
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        let message =
          (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
        throw WorkspaceError.message(
          message ?? "Backend request did not complete. Your recording is safe.")
      }
      job.status = "completed"
      job.response = data
      if ["transcribe", "dictation"].contains(job.route) { job.body = Data() }
      try store?.saveRequest(job)
      onChange?()
      return data
    } catch {
      job.status = Task.isCancelled ? "cancelled" : "interrupted"
      job.error = error.localizedDescription
      try store?.saveRequest(job)
      onChange?()
      throw error
    }
  }

  func transcribe(
    _ wave: Data, diarize: Bool, language: String, keywords: [String],
    references: [[String: String]] = []
  ) async throws
    -> FileTranscript
  {
    let body: [String: Any] = [
      "audio": wave.base64EncodedString(), "diarize": diarize,
      "languages": language == "auto" ? ["en", "nl"] : [language],
      "keywords": keywords, "references": references,
    ]
    return try await request("transcribe", body: JSONSerialization.data(withJSONObject: body))
  }
  func cleanup(
    _ text: String, mode: CleanupMode, selection: String, instruction: String,
    personalization: [Personalization], application: String
  ) async throws -> String {
    struct Result: Decodable { var text: String }
    let body: [String: Any] = [
      "text": text, "mode": mode.rawValue, "selection": selection, "instruction": instruction,
      "personalization": try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(personalization)), "application": application,
    ]
    let result: Result = try await request(
      "dictation", body: JSONSerialization.data(withJSONObject: body))
    return result.text
  }
  func outline(_ segments: [TranscriptSegment]) async throws -> MeetingSummary {
    try await request("outline", body: JSONEncoder().encode(segments))
  }
  func summarize(_ segments: [TranscriptSegment]) async throws -> MeetingSummary {
    try await request("summary", body: JSONEncoder().encode(segments))
  }
  func ask(
    _ question: String, segments: [TranscriptSegment], note: Note, history: [AssistantExchange] = []
  ) async throws
    -> AssistantReply
  {
    let body: [String: Any] = [
      "question": question,
      "segments": try JSONSerialization.jsonObject(with: JSONEncoder().encode(segments)),
      "note": note.text,
      "history": history.filter { $0.status == "completed" || $0.status == "committed" }.suffix(8)
        .map {
          ["question": String($0.question.prefix(2000)), "answer": String($0.answer.prefix(4000))]
        },
    ]
    return try await request("ask", body: JSONSerialization.data(withJSONObject: body))
  }
}
