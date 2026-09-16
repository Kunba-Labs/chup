import Foundation

public struct RouteEvidence: Equatable {
  public var microphoneUID: String
  public var outputUID: String
  public var virtualUID: String?
  public var headphones: Bool
  public var callUsesOnlyVirtualInput: Bool
  public init(
    microphoneUID: String, outputUID: String, virtualUID: String? = nil,
    headphones: Bool, callUsesOnlyVirtualInput: Bool = false
  ) {
    self.microphoneUID = microphoneUID
    self.outputUID = outputUID
    self.virtualUID = virtualUID
    self.headphones = headphones
    self.callUsesOnlyVirtualInput = callUsesOnlyVirtualInput
  }
  public func policy(meetingActive: Bool) -> RoutingPolicy {
    let isolated =
      virtualUID != nil && microphoneUID != virtualUID && outputUID != virtualUID
      && callUsesOnlyVirtualInput
    return RoutingPolicy(
      meetingActive: meetingActive, verifiedInputIsolation: isolated,
      verifiedMixMinus: isolated, headphones: headphones)
  }
}

/// A bounded source queue. Only render consumption advances the ledger; interrupted tails remain
/// unplayed. Each mode switch revokes every previous context, including queued microphone audio.
public final class VoiceRenderQueue: @unchecked Sendable {
  private let lock = NSLock()
  private var pcm = [Int16](repeating: 0, count: 96000)
  private var read = 0, write = 0, count = 0
  private var context = UUID()
  private var active = false
  private var consumedTotal = 0
  public init() {}
  public func reset(context: UUID, active: Bool) {
    lock.withLock {
      self.context = context
      self.active = active
      read = 0
      write = 0
      count = 0
      consumedTotal = 0
    }
  }
  public func consumed(context: UUID) -> Int {
    lock.withLock { self.context == context ? consumedTotal : 0 }
  }
  public func append(_ data: Data, context: UUID) throws {
    try lock.withLock {
      guard self.context == context, active else { throw WorkspaceError.unsafeRoute }
      guard data.count % 2 == 0, data.count / 2 <= pcm.count - count else {
        throw WorkspaceError.message("Voice output buffer is full.")
      }
      data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
        for i in stride(from: 0, to: bytes.count, by: 2) {
          pcm[write] = Int16(bitPattern: UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8)
          write = (write + 1) % pcm.count
          count += 1
        }
      }
    }
  }
  @discardableResult public func render(
    into destination: UnsafeMutableBufferPointer<Float>, gain: Float = 1
  ) -> Int {
    renderWithContext(into: destination, gain: gain).0
  }
  public func renderWithContext(
    into destination: UnsafeMutableBufferPointer<Float>, gain: Float = 1
  ) -> (Int, UUID) {
    lock.withLock {
      let consumed = active ? min(destination.count, count) : 0
      for i in 0..<destination.count {
        if i < consumed {
          destination[i] = max(-1, min(1, Float(pcm[read]) / 32768 * gain))
          read = (read + 1) % pcm.count
        } else {
          destination[i] = 0
        }
      }
      count -= consumed
      consumedTotal += consumed
      return (consumed, context)
    }
  }
}
public enum MixMinus {
  /// Remote participants are deliberately absent from this signature.
  public static func outgoing(microphone: Float, assistant: Float, privateAddress: Bool) -> Float {
    let mic = privateAddress ? 0 : (microphone.isFinite ? microphone : 0) * 0.8
    let voice = assistant.isFinite ? assistant : 0
    return max(-0.95, min(0.95, mic + voice * 0.8))
  }
}
public struct VoiceTurnScope: Equatable {
  public var id: UUID
  public var meetingID: String
  public var mode: AssistantMode
  public init(meetingID: String, mode: AssistantMode) {
    id = UUID()
    self.meetingID = meetingID
    self.mode = mode
  }
  public func backendContext(note: Note, history: [AssistantExchange]) -> (
    Note, [AssistantExchange]
  ) {
    mode == .broadcast ? (Note(), []) : (note, history)
  }
}
