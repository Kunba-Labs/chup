import Foundation

/// GPT-Live events are deliberately separate from Realtime transcription events.
public enum LiveEvent: Equatable, Sendable {
  case started(String)
  case inputTranscript(String)
  case outputTranscript(String)
  case outputAudio(id: String, pcm: Data)
  case delegation(String)
  case closed(usageJSON: String?)
  case failure(String)
  case other(String)

  public static func decode(_ data: Data) throws -> LiveEvent {
    guard data.count <= 4_000_000,
      let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let type = event["type"] as? String
    else { throw WorkspaceError.message("Invalid Live event.") }
    switch type {
    case "session.started":
      guard let session = event["session"] as? [String: Any], let id = session["id"] as? String,
        !id.isEmpty
      else { throw WorkspaceError.message("Live session did not supply an ID.") }
      return .started(id)
    case "session.input_transcript.delta": return .inputTranscript(event["delta"] as? String ?? "")
    case "session.output_transcript.delta":
      return .outputTranscript(event["delta"] as? String ?? "")
    case "session.output_audio.delta":
      guard let text = event["delta"] as? String, let pcm = Data(base64Encoded: text),
        !pcm.isEmpty, pcm.count % 2 == 0, pcm.count <= 480000
      else { throw WorkspaceError.message("Invalid Live PCM16 audio delta.") }
      return .outputAudio(id: event["event_id"] as? String ?? UUID().uuidString, pcm: pcm)
    case "session.delegation.created":
      guard let delegation = event["delegation"] as? [String: Any],
        let id = delegation["id"] as? String, !id.isEmpty
      else { throw WorkspaceError.message("Live delegation metadata is missing its ID.") }
      return .delegation(id)
    case "session.closed":
      let usage = try event["usage"].map {
        try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys])
      }
      return .closed(usageJSON: usage.map { String(decoding: $0, as: UTF8.self) })
    case "error":
      return .failure(
        (event["error"] as? [String: Any])?["message"] as? String ?? "Live request failed.")
    default: return .other(type)
    }
  }
}

/// Binds queued speech to one context. Revocation rejects late deltas and late render callbacks.
public struct VoiceOutputQueue {
  public let context: UUID
  public let sessionID: String
  public let mode: AssistantMode
  public private(set) var revoked = false
  public private(set) var acceptedFrames = 0
  public private(set) var renderedFrames = 0
  public private(set) var ledger = PlaybackLedger()
  private var ids = Set<String>()
  public init(context: UUID, sessionID: String, mode: AssistantMode, policy: RoutingPolicy) throws {
    guard policy.allows(mode), mode != .privateText else { throw WorkspaceError.unsafeRoute }
    self.context = context
    self.sessionID = sessionID
    self.mode = mode
  }
  /// Returns false for a duplicate provider event. Keep at most four seconds ahead of output.
  public mutating func enqueue(id: String, pcm: Data, context: UUID) throws -> Bool {
    guard context == self.context, !revoked else { throw WorkspaceError.unsafeRoute }
    guard !ids.contains(id) else { return false }
    let frames = pcm.count / 2
    guard !pcm.isEmpty, pcm.count % 2 == 0, frames <= 96000,
      acceptedFrames - renderedFrames + frames <= 96000
    else { throw WorkspaceError.message("Voice output exceeded its bounded playback queue.") }
    ids.insert(id)
    acceptedFrames += frames
    ledger.enqueue(PlayedAudio(id: id, sessionID: sessionID, mode: mode, generatedFrames: frames))
    return true
  }
  public mutating func rendered(through frame: Int, context: UUID) {
    guard context == self.context, !revoked else { return }
    let target = max(renderedFrames, min(acceptedFrames, frame))
    var cursor = 0
    for item in ledger.entries {
      let count = max(0, min(item.generatedFrames, target - cursor))
      ledger.rendered(id: item.id, frames: count - item.playedFrames)
      cursor += item.generatedFrames
    }
    renderedFrames = target
  }
  public mutating func revoke(renderedThrough frame: Int) {
    rendered(through: frame, context: context)
    revoked = true
    ledger.interrupt()
  }
}
