import AVFoundation
import ChupCore

/// Local Live PCM output. Outgoing meeting routing remains a separate, unimplemented audio graph.
/// A route-qualified coordinator must own this service; it never opens a microphone or runs tools.
@MainActor final class LiveAudioPlayback {
  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
  private var queue: VoiceOutputQueue?
  private var observer: NSObjectProtocol?
  private var started = false
  private var completedFrames = 0
  var onStop: (([PlayedAudio]) -> Void)?
  var onFailure: ((String) -> Void)?
  var onLevel: ((Float) -> Void)?
  init() {
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
    observer = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: engine, queue: nil
    ) { [weak self] _ in
      DispatchQueue.main.async {
        guard let self, self.queue != nil else { return }
        self.stop()
        self.onFailure?("Voice output changed. Revalidate the route before speaking again.")
      }
    }
  }
  func begin(context: UUID, sessionID: String, policy: RoutingPolicy) throws {
    stop()
    // A default-device local player cannot promise private output during a call.
    // No UI path can unlock it with a headphone checkbox or a fabricated route flag.
    guard !policy.meetingActive else { throw WorkspaceError.unsafeRoute }
    queue = try VoiceOutputQueue(
      context: context, sessionID: sessionID, mode: .privateVoice, policy: policy)
    completedFrames = 0
    started = false
  }
  func append(id: String, pcm: Data, context: UUID) throws {
    guard var queue, queue.context == context else { throw WorkspaceError.unsafeRoute }
    queue.rendered(through: renderedFrames(), context: context)
    guard try queue.enqueue(id: id, pcm: pcm, context: context) else { return }
    let count = pcm.count / 2
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(count)) else {
      stop()
      throw WorkspaceError.message("Voice output allocation failed.")
    }
    buffer.frameLength = UInt32(count)
    pcm.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
      for i in 0..<count {
        let bits = UInt16(bytes[i * 2]) | UInt16(bytes[i * 2 + 1]) << 8
        let value = Float(Int16(bitPattern: bits)) / 32768
        buffer.floatChannelData![0][i] = value
      }
    }
    self.queue = queue
    let end = queue.acceptedFrames
    player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.queue?.context == context else { return }
        self.completedFrames = max(self.completedFrames, end)
        self.queue?.rendered(through: self.completedFrames, context: context)
        if self.queue?.renderedFrames == self.queue?.acceptedFrames { self.onLevel?(0) }
      }
    }
    if !started {
      do {
        engine.prepare()
        try engine.start()
        player.play()
        started = true
      } catch {
        stop()
        throw error
      }
    }
    // Output envelopes must ultimately be sampled from the render tap; receipt is not speech.
    // This service intentionally does not publish the received packet's level as a speaking meter.
  }
  private func renderedFrames() -> Int {
    // The complete-buffer callback is conservative: queued/generated audio is never counted.
    // Partial buffers are not promoted to "heard" from a wall clock or transcript timestamp.
    completedFrames
  }
  func stop() {
    guard var queue else { return }
    queue.revoke(renderedThrough: renderedFrames())
    self.queue = nil  // Revoke before stopping; completion callbacks can run during stop().
    player.stop()
    engine.stop()
    started = false
    onLevel?(0)
    onStop?(queue.ledger.entries)
  }
}
