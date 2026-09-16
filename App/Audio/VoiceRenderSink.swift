import AVFoundation
import ChupCore

/// Copies actual outgoing render samples into AudioOwner's bounded writer path before returning.
final class VoiceRenderSink: @unchecked Sendable {
  private let lock = NSLock()
  private var owner: AudioOwner?
  private var lease: CaptureLease?
  private var context = UUID()
  private let buffer = AVAudioPCMBuffer(
    pcmFormat: AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!,
    frameCapacity: 32768)!
  func bind(owner: AudioOwner?, lease: CaptureLease?, context: UUID) {
    lock.withLock {
      self.owner = owner
      self.lease = lease
      self.context = context
    }
  }
  func render(_ samples: UnsafeBufferPointer<Float>, count: Int, time: Double, context: UUID) {
    lock.withLock {
      guard self.context == context, let owner, let lease, count <= 32768 else { return }
      buffer.frameLength = UInt32(count)
      buffer.floatChannelData![0].update(from: samples.baseAddress!, count: count)
      owner.appendRenderedAssistant(buffer, hostTime: time, lease: lease)
    }
  }
}
