import AVFoundation
import Foundation
import ChupCore

/// Native transport for the documented Live protocol, separate from Realtime transcription.
/// Playback remains gated until an output route has been qualified. No production key is accepted.
actor LiveSession {
  private var socket: URLSessionWebSocketTask?
  private var receiveTask: Task<Void, Never>?
  private var ready = false
  private var closing = false
  private var muted = true
  private var muteRevision = UUID()
  private var heartbeat: Task<Void, Never>?
  private var acknowledgments: [String: CheckedContinuation<Void, Error>] = [:]
  private var sessionID: String?
  private var inputTranscript = ""
  private var outputTranscript = ""
  private var mode: AssistantMode = .privateText
  private var generation = UUID()
  private let onEvent: @Sendable (LiveEvent) async -> Void
  private let onUsage: @Sendable (String, Bool) async -> Void
  init(
    onUsage: @escaping @Sendable (String, Bool) async -> Void = { _, _ in },
    onEvent: @escaping @Sendable (LiveEvent) async -> Void = { _ in }
  ) {
    self.onEvent = onEvent
    self.onUsage = onUsage
  }
  func connect(backend: URL, token: String, mode: AssistantMode, policy: RoutingPolicy) throws {
    guard policy.allows(mode), mode != .privateText else { throw WorkspaceError.unsafeRoute }
    guard socket == nil else {
      throw WorkspaceError.message("Close the old voice session before changing context.")
    }
    guard backend.scheme == "https" || ["127.0.0.1", "localhost"].contains(backend.host ?? "")
    else { throw WorkspaceError.message("Voice relay must use TLS outside localhost.") }
    var url = URLComponents(
      url: backend.appendingPathComponent("live"), resolvingAgainstBaseURL: false)!
    url.scheme = backend.scheme == "https" ? "wss" : "ws"
    var request = URLRequest(url: url.url!)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    self.mode = mode
    inputTranscript = ""
    outputTranscript = ""
    ready = false
    closing = false
    generation = UUID()
    let socket = URLSession.shared.webSocketTask(with: request)
    self.socket = socket
    socket.resume()
    let scope = generation
    receiveTask = Task { [weak self] in await self?.receive(scope: scope) }
  }
  private func receive(scope: UUID) async {
    do {
      while !Task.isCancelled, scope == generation, let socket {
        let message = try await socket.receive()
        let data: Data
        switch message {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: continue
        }
        guard scope == generation, !Task.isCancelled else { return }
        if let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          ["session.input_audio.muted", "session.input_audio.unmuted"].contains(
            raw["type"] as? String ?? ""),
          let id = raw["client_event_id"] as? String
        {
          acknowledgments.removeValue(forKey: id)?.resume()
        }
        if let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let type = raw["type"] as? String,
          ["session.usage.updated", "session.closed"].contains(type),
          let usage = raw["usage"], let bytes = try? JSONSerialization.data(withJSONObject: usage)
        {
          await onUsage(String(decoding: bytes, as: UTF8.self), type == "session.closed")
        }
        let event = try LiveEvent.decode(data)
        switch event {
        case .started(let id):
          if closing {
            try await send(["type": "session.close"])
            continue
          }
          ready = true
          sessionID = id
          heartbeat = Task { [weak self] in
            while !Task.isCancelled {
              try? await Task.sleep(for: .milliseconds(20))
              guard !Task.isCancelled else { break }
              await self?.silence(scope: scope)
            }
          }
        case .inputTranscript(let text): inputTranscript += text
        case .outputTranscript(let text): outputTranscript += text
        case .closed:
          heartbeat?.cancel()
          ready = false
          self.socket?.cancel(with: .normalClosure, reason: nil)
          self.socket = nil
        default: break
        }
        await onEvent(event)
      }
    } catch {
      // An old receive task must never close a replacement connection.
      guard scope == generation, !Task.isCancelled else { return }
      heartbeat?.cancel()
      ready = false
      socket?.cancel(with: .goingAway, reason: nil)
      socket = nil
      await onEvent(.failure(error.localizedDescription))
    }
  }

  func appendPCM24k(_ data: Data) async throws {
    guard ready, !closing, data.count % 2 == 0 else {
      throw WorkspaceError.message("Live session is not ready for PCM16 audio.")
    }
    try await send(["type": "session.input_audio.append", "audio": data.base64EncodedString()])
  }
  private func silence(scope: UUID) async {
    guard generation == scope, ready, !closing, muted else { return }
    try? await appendPCM24k(Data(repeating: 0, count: 960))
  }
  func muteInput(_ muted: Bool) async throws {
    guard ready else { throw WorkspaceError.message("Voice session is not ready.") }
    let revision = UUID()
    muteRevision = revision
    if muted { self.muted = true }
    let id = UUID().uuidString
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      acknowledgments[id] = continuation
      Task {
        do {
          try await send([
            "type": muted ? "session.input_audio.mute" : "session.input_audio.unmute",
            "event_id": id,
          ])
        } catch { acknowledgments.removeValue(forKey: id)?.resume(throwing: error) }
      }
      Task {
        try? await Task.sleep(for: .seconds(5))
        acknowledgments.removeValue(forKey: id)?.resume(
          throwing: WorkspaceError.message("Microphone control was not acknowledged."))
      }
    }
    if muteRevision == revision { self.muted = muted }
  }
  /// A delegation event contains only metadata; the caller owns the task text and committed tool results.
  func returnDelegation(id: String?, committedResult: String) async throws {
    guard ready, !closing, !committedResult.isEmpty, committedResult.utf8.count <= 500 else {
      throw WorkspaceError.message(
        "Voice updates must be short; return a concise committed result.")
    }
    try await send([
      "type": "session.commentary.append", "event_id": UUID().uuidString,
      "delegation_id": id as Any? ?? NSNull(),
      "content": committedResult,
    ])
  }
  /// Immediate transport revocation for scope changes. Call the local output stop first.
  /// This does not cancel or roll back already committed note tools.
  func disconnect() {
    generation = UUID()
    closing = true
    ready = false
    heartbeat?.cancel()
    acknowledgments.values.forEach { $0.resume(throwing: WorkspaceError.unsafeRoute) }
    acknowledgments = [:]
    receiveTask?.cancel()
    receiveTask = nil
    socket?.cancel(with: .goingAway, reason: nil)
    socket = nil
    inputTranscript = ""
    outputTranscript = ""
    sessionID = nil
  }
  func close() async {
    let current = generation
    closing = true
    heartbeat?.cancel()
    if ready { try? await send(["type": "session.close"]) }
    Task {
      try? await Task.sleep(for: .seconds(15))
      await self.forceClose(scope: current)
    }
  }
  private func forceClose(scope: UUID) async {
    guard scope == generation else { return }
    let incomplete = socket != nil
    receiveTask?.cancel()
    socket?.cancel(with: .goingAway, reason: nil)
    socket = nil
    ready = false
    if incomplete { await onEvent(.failure("Session closed without final usage confirmation.")) }
  }

  private func send(_ event: [String: Any]) async throws {
    guard let socket else { throw WorkspaceError.message("Voice connection unavailable.") }
    let data = try JSONSerialization.data(withJSONObject: event)
    try await socket.send(.string(String(decoding: data, as: UTF8.self)))
  }
}
