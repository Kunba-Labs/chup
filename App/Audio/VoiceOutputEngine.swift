import AVFoundation
import AudioToolbox
import ChupCore

/// Pinned output fed by a bounded render queue. The callback reports only consumed samples.
/// Used separately for local monitoring and the controlled outgoing device.
final class VoiceOutputEngine: @unchecked Sendable {
  private let engine = AVAudioEngine()
  let queue = VoiceRenderQueue()
  let microphoneQueue = VoiceRenderQueue()
  private let source: AVAudioSourceNode
  private var observer: NSObjectProtocol?
  private var expectedDevice: AudioDeviceID?
  private var expectedRate: Double = 0
  var onFailure: ((String) -> Void)?
  init(
    outgoing: Bool = false,
    rendered: @escaping (UnsafeBufferPointer<Float>, Int, Double, UUID) -> Void = { _, _, _, _ in }
  ) {
    let queue = self.queue
    let microphoneQueue = self.microphoneQueue
    let microphone = FloatStorage(pointer: .allocate(capacity: 32768))
    let scratch = UnsafeMutablePointer<Float>.allocate(capacity: 32768)
    // Owned by the source closure; release through a small lifetime owner.
    let storage = FloatStorage(pointer: scratch)
    source = AVAudioSourceNode(
      format: AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    ) {
      _, timestamp, frames, list in
      guard frames <= 32768 else { return kAudio_ParamError }
      let buffer = UnsafeMutableBufferPointer(start: storage.pointer, count: Int(frames))
      let (consumed, context) = queue.renderWithContext(into: buffer, gain: outgoing ? 0.8 : 1)
      do {
        rendered(
          UnsafeBufferPointer(buffer), consumed,
          AVAudioTime.seconds(forHostTime: timestamp.pointee.mHostTime), context)
      }
      if outgoing {
        _ = microphoneQueue.render(
          into: UnsafeMutableBufferPointer(start: microphone.pointer, count: Int(frames)))
        for i in 0..<Int(frames) {
          buffer[i] = MixMinus.outgoing(
            microphone: microphone.pointer[i], assistant: buffer[i] / 0.8, privateAddress: false)
        }
      }
      for channel in UnsafeMutableAudioBufferListPointer(list) {
        if let data = channel.mData {
          memcpy(data, storage.pointer,
            min(Int(channel.mDataByteSize), Int(frames) * MemoryLayout<Float>.size))
        }
      }
      return noErr
    }
    engine.attach(source)
    engine.connect(
      source, to: engine.mainMixerNode,
      format: AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!)
    observer = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
    ) { [weak self] _ in
      DispatchQueue.main.async {
      guard let self, let expected = self.expectedDevice else { return }
      var current: AudioDeviceID = 0
      var size: UInt32 = 4
      if let unit = self.engine.outputNode.audioUnit,
        AudioUnitGetProperty(
          unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &current, &size)
          == noErr,
        current == expected, self.engine.isRunning,
        self.engine.outputNode.outputFormat(forBus: 0).sampleRate == self.expectedRate
      {
        return
      }
      self.stop()
      self.onFailure?("Voice output device changed. Voice stopped; recheck the route.")
      }
    }
  }
  @MainActor func start(device: AudioDeviceID, context: UUID) throws {
    stop()
    guard let unit = engine.outputNode.audioUnit else { throw WorkspaceError.unsafeRoute }
    var device = device
    guard
      AudioUnitSetProperty(
        unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, 4)
        == noErr
    else {
      throw WorkspaceError.message("Could not pin voice output to the selected device.")
    }
    queue.reset(context: context, active: true)
    engine.prepare()
    try engine.start()
    expectedDevice = device
    expectedRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
  }
  @MainActor func renderOffline(assistant: Data, microphone: Data, context: UUID, frames: Int)
    throws -> [Float]
  {
    stop()
    try engine.enableManualRenderingMode(
      .offline, format: AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!,
      maximumFrameCount: 1024)
    queue.reset(context: context, active: true)
    microphoneQueue.reset(context: context, active: true)
    try queue.append(assistant, context: context)
    try microphoneQueue.append(microphone, context: context)
    try engine.start()
    defer {
      stop()
      engine.disableManualRenderingMode()
    }
    let output = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 1024)!
    var result: [Float] = []
    while result.count < frames {
      let count = min(1024, frames - result.count)
      guard try engine.renderOffline(UInt32(count), to: output) == .success else {
        throw WorkspaceError.message("Voice render stalled.")
      }
      result.append(
        contentsOf: UnsafeBufferPointer(start: output.floatChannelData![0], count: count))
    }
    return result
  }
  var isRunning: Bool { engine.isRunning }
  func stop() {
    expectedDevice = nil
    queue.reset(context: UUID(), active: false)
    microphoneQueue.reset(context: UUID(), active: false)
    engine.stop()
  }
}
private final class FloatStorage: @unchecked Sendable {
  let pointer: UnsafeMutablePointer<Float>
  init(pointer: UnsafeMutablePointer<Float>) { self.pointer = pointer }
  deinit { pointer.deallocate() }
}
