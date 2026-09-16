import AVFoundation
import AudioToolbox
import CoreAudio
import CryptoKit
import ChupCore
import CAudioSafety

/// Serial writer owns all disk state. An input source fans out to independently owned consumers.
final class AudioOwner: @unchecked Sendable {
  private var engine = AVAudioEngine()
  private var expectedInputDevice: AudioDeviceID = 0
  private var expectedInputRate: Double = 0
  private var expectedInputChannels: AVAudioChannelCount = 0
  @MainActor private var microphoneStartTask: Task<Void, Error>?
  @MainActor private var microphoneStartGeneration = UUID()
  @MainActor var microphoneStarting: Bool { microphoneStartTask != nil }
  @MainActor var microphoneRunning: Bool { engine.isRunning }
  private let queue = DispatchQueue(label: "com.chup.audio.writer", qos: .userInitiated)
  private let key: SymmetricKey
  private var consumers: [String: Consumer] = [:]
  private var remote: RemoteAudioCapture?
  private var remoteGeneration = UUID()
  private let backlogLock = NSLock()
  private var backlog = 0
  private let pcmSlots = (0..<64).map { _ in UnsafeMutablePointer<Int16>.allocate(capacity: 32768) }
  private var freeSlots = Array(0..<64)
  private var microphoneTapInstalled = false
  private var failureDelivered = false
  private var leases: [TrackKind: CaptureLease] = [:]
  private var consumerLeases: [String: UUID] = [:]
  private var clocks: [TrackKind: CaptureClockTracker] = [:]
  private(set) var microphoneUID: String?
  var onGap: ((String, TrackKind, AudioDiscontinuity) -> Void)?
  var onRemoteFailure: ((String) -> Void)?
  var onFailure: ((String) -> Void)?
  var onWaveform: (([Float], Double) -> Void)?
  private var spectrum = VoiceSpectrumMeter()
  private var lastSpectrumTime = -Double.infinity
  var onLevel: ((TrackKind, Float, Double) -> Void)?
  private var packetHandlers: [String: (TrackKind, AudioPacket) -> Void] = [:]
  private var privateAddress = false
  func setPacketHandler(_ handler: ((TrackKind, AudioPacket) -> Void)?, id: String = "captions") {
    queue.async { self.packetHandlers[id] = handler }
  }
  private var lastMeter: [TrackKind: Double] = [:]
  private struct Consumer {
    var directory: URL
    var tracks: Set<TrackKind>
    var meterOnly = false
    var needsMicrophone: Bool { meterOnly || tracks.contains(.microphone) }
    var journals: [TrackKind: AudioJournal] = [:]
    var starts: [TrackKind: Double] = [:]
    var formats: [TrackKind: Double] = [:]
  }
  init(key: SymmetricKey) { self.key = key }
  deinit { pcmSlots.forEach { $0.deallocate() } }
  func ownsEngine(_ object: Any?) -> Bool { (object as? AVAudioEngine) === engine }
  @MainActor func addConsumer(
    id: String, directory: URL, tracks: Set<TrackKind>, device: InputDevice? = nil, meterOnly: Bool = false
  ) async throws {
    precondition(!meterOnly || tracks.isEmpty)
    if tracks.contains(.microphone) || meterOnly {
      guard await AVCaptureDevice.requestAccess(for: .audio) else {
        throw WorkspaceError.message(
          "Microphone access is off. Enable it in System Settings → Privacy & Security → Microphone."
        )
      }
    }
    try Task.checkCancellation()
    if !meterOnly {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    if (engine.isRunning || microphoneStarting), let device, microphoneUID != device.id {
      throw WorkspaceError.message(
        "Another voice action owns a different microphone. Finish it before changing input.")
    }
    queue.sync { consumers[id] = Consumer(directory: directory, tracks: tracks, meterOnly: meterOnly) }
    backlogLock.withLock {
      consumerLeases[id] = UUID()
      failureDelivered = false
    }
    do {
      if tracks.contains(.microphone) || meterOnly {
        try await ensureMicrophoneStarted(device: device)
        try Task.checkCancellation()
      }
    } catch {
      try? removeConsumer(id: id)
      throw error
    }
  }
  @MainActor private func ensureMicrophoneStarted(device: InputDevice?) async throws {
    if let task = microphoneStartTask { try await task.value; return }
    if engine.isRunning { return }
    let generation = UUID()
    microphoneStartGeneration = generation
    microphoneUID = device?.id
    let task = Task { @MainActor in
      try Task.checkCancellation()
      try startMicrophone(device: device)
      // Core Audio may deliver the device-binding format notification after
      // start() returns. Keep callers in Starting until the graph settles.
      try await MicrophoneStartup.settle(isReady: { self.microphoneConfigurationValid }) {
        var error: NSError?
        guard CHResumeMatchingInput(engine, expectedInputDevice, expectedInputRate,
          expectedInputChannels, &error) else {
          throw error ?? WorkspaceError.message("Microphone startup was interrupted. Check Audio settings and try again.")
        }
      }
    }
    microphoneStartTask = task
    defer { if microphoneStartGeneration == generation { microphoneStartTask = nil } }
    do { try await task.value }
    catch MicrophoneStartup.Failure.didNotSettle {
      throw WorkspaceError.message("Microphone startup did not settle. Audio is preserved; try again or choose another input.")
    }
  }
  @MainActor private func startMicrophone(device: InputDevice?) throws {
    // A stopped engine retains the previous graph format. A new leg gets a
    // fresh engine so USB/Bluetooth/default-device changes cannot reuse it.
    CHStopInput(engine, microphoneTapInstalled)
    microphoneTapInstalled = false
    engine = AVAudioEngine()
    microphoneUID = nil
    expectedInputDevice = device?.objectID ?? 0
    let lease = CaptureLease()
    backlogLock.withLock { leases[.microphone] = lease }
    queue.sync { clocks[.microphone] = CaptureClockTracker() }
    var installed: ObjCBool = false
    var error: NSError?
    let started = CHStartInput(engine, expectedInputDevice, { [weak self] buffer, time in
      self?.accept(buffer: buffer, track: .microphone,
        hostTime: AVAudioTime.seconds(forHostTime: time.hostTime), lease: lease)
    }, &installed, &expectedInputRate, &expectedInputChannels, &error)
    microphoneTapInstalled = installed.boolValue
    guard started else {
      backlogLock.withLock { leases[.microphone] = nil }
      throw error ?? WorkspaceError.message("The microphone could not start. Check Audio settings.")
    }
    if expectedInputDevice == 0 { expectedInputDevice = CHInputDevice(engine) }
    microphoneUID = device?.id
  }
  @MainActor var microphoneConfigurationValid: Bool {
    microphoneTapInstalled && CHInputMatchesConfiguration(engine, expectedInputDevice,
      expectedInputRate, expectedInputChannels)
  }
  @MainActor var actualMicrophoneID: AudioDeviceID? {
    guard microphoneTapInstalled else { return nil }
    if CHInputUsesDevice(engine, expectedInputDevice) { return expectedInputDevice }
    let id = CHInputDevice(engine)
    return id == 0 ? nil : id
  }
  @MainActor var microphoneRouteDiagnostic: String {
    "expected=\(expectedInputDevice) raw=\(CHInputDevice(engine)) input=\(actualMicrophoneID ?? 0) running=\(microphoneRunning) matches=\(microphoneConfigurationValid) rate=\(expectedInputRate) channels=\(expectedInputChannels)"
  }
  /// Opt-in meter-only hardware regression. No recording or provider consumers.
  @MainActor func validateInterruptedMicrophoneStartup(device: InputDevice, directory: URL) async throws {
    let firstID = "startup-fixture:" + UUID().uuidString
    let secondID = "startup-fixture:" + UUID().uuidString
    defer { try? removeConsumer(id: firstID); try? removeConsumer(id: secondID) }
    let first = Task { try await addConsumer(id: firstID, directory: directory, tracks: [], device: device, meterOnly: true) }
    for _ in 0..<200 {
      if microphoneStarting && microphoneTapInstalled { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    guard microphoneStarting && microphoneTapInstalled else {
      first.cancel(); _ = try? await first.value
      throw WorkspaceError.message("Fixture could not interrupt the startup settling window.")
    }
    // Reproduce the logged delayed stop without changing the physical route.
    CHStopInput(engine, false)
    guard actualMicrophoneID == device.objectID else {
      first.cancel(); _ = try? await first.value
      throw WorkspaceError.message("Stopped graph lost its original input identity.")
    }
    let second = Task { try await addConsumer(id: secondID, directory: directory, tracks: [], device: device, meterOnly: true) }
    try await first.value
    try await second.value
    guard microphoneConfigurationValid && !microphoneStarting else {
      throw WorkspaceError.message("Same-input startup recovery did not settle for both consumers.")
    }
    var mismatch: NSError?
    guard !CHResumeMatchingInput(engine, AudioDeviceID.max, expectedInputRate, expectedInputChannels, &mismatch),
      !CHResumeMatchingInput(engine, expectedInputDevice, expectedInputRate + 1, expectedInputChannels, &mismatch),
      microphoneConfigurationValid else {
      throw WorkspaceError.message("Startup recovery accepted a different input or format.")
    }
    try removeConsumer(id: firstID)
    guard microphoneRunning else { throw WorkspaceError.message("Removing one consumer stopped the shared input.") }
    try removeConsumer(id: secondID)
    guard !microphoneRunning else { throw WorkspaceError.message("Final consumer did not release input.") }
    print("PASS: delayed hardware startup stop preserves input identity, resumes the matching graph, and shares readiness across two meter-only consumers.")

    let cancelled = Task { try await addConsumer(id: firstID, directory: directory, tracks: [], device: device, meterOnly: true) }
    for _ in 0..<200 {
      if microphoneStarting && microphoneTapInstalled { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    try removeConsumer(id: firstID)
    do { try await cancelled.value; throw WorkspaceError.message("Cancelled startup reported ready.") }
    catch is CancellationError {}
    try await Task.sleep(for: .milliseconds(300))
    guard !microphoneRunning && !microphoneStarting && microphoneUID == nil,
      !FileManager.default.fileExists(atPath: directory.path) else {
      throw WorkspaceError.message("Cancelled startup resumed capture or wrote audio.")
    }
    print("PASS: releasing the final consumer during startup cancels recovery and never reopens the microphone; no audio saved or uploaded.")
  }
  @MainActor func startRemote(pid: pid_t, fallback: Bool) async throws {
    guard remote == nil else { return }
    let generation = UUID()
    remoteGeneration = generation
    let lease = CaptureLease()
    backlogLock.withLock { leases[.remote] = lease }
    queue.sync { clocks[.remote] = CaptureClockTracker() }
    let source: RemoteAudioCapture = fallback ? ScreenAudioCapture() : ProcessAudioCapture()
    do {
      try await source.start(
        pid: pid,
        receive: { [weak self] buffer, time in
          self?.accept(buffer: buffer, track: .remote, hostTime: time, lease: lease)
        },
        failure: { [weak self] error in
          guard let self else { return }
          self.backlogLock.lock()
          let current = self.leases[.remote] == lease
          self.backlogLock.unlock()
          if current { self.onRemoteFailure?(error) }
        })
    } catch {
      source.stop()
      backlogLock.withLock { if leases[.remote] == lease { leases[.remote] = nil } }
      throw error
    }
    guard generation == remoteGeneration else {
      source.stop()
      return
    }
    remote = source
  }
  @MainActor func stopRemote() {
    remoteGeneration = UUID()
    backlogLock.lock()
    leases[.remote] = nil
    backlogLock.unlock()
    remote?.stop()
    remote = nil
  }
  @MainActor func removeConsumer(id: String) throws {
    defer {
      let needsMic = queue.sync { consumers.values.contains { $0.needsMicrophone } }
      if !needsMic {
        microphoneStartTask?.cancel()
        microphoneStartTask = nil
        microphoneStartGeneration = UUID()
        backlogLock.lock()
        leases[.microphone] = nil
        backlogLock.unlock()
        if microphoneTapInstalled { CHStopInput(engine, true) }
        microphoneUID = nil
        microphoneTapInstalled = false
      }
    }
    try queue.sync {
      backlogLock.lock()
      consumerLeases[id] = nil
      backlogLock.unlock()
      guard let consumer = consumers.removeValue(forKey: id) else { return }
      var failure: Error?
      for journal in consumer.journals.values {
        do { try journal.close() } catch { failure = error }
      }
      if let failure { throw failure }
    }
  }
  private func accept(
    buffer: AVAudioPCMBuffer, track: TrackKind, hostTime: Double, lease: CaptureLease
  ) {
    // Copies callback-owned memory before returning. Bounded backlog prevents memory growth.
    guard buffer.frameLength > 0 else { return }
    guard buffer.frameLength <= 32768 else {
      onFailure?("Capture buffer exceeded its safe limit; recording paused.")
      return
    }
    guard let channels = buffer.floatChannelData else {
      onFailure?("Unsupported capture PCM format.")
      return
    }
    backlogLock.lock()
    guard leases[track] == lease else {
      backlogLock.unlock()
      return
    }
    let recipients = consumerLeases
    let privatePacket = privateAddress
    if freeSlots.isEmpty {
      let report = !failureDelivered
      failureDelivered = true
      backlogLock.unlock()
      if report {
        onFailure?(
          "Audio writer fell behind; capture paused to preserve the recording. A gap was marked.")
      }
      return
    }
    backlog += 1
    let slot = freeSlots.removeLast()
    backlogLock.unlock()
    let count = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    let samples = pcmSlots[slot]
    let sampleRate = buffer.format.sampleRate
    var peak: Float = 0
    let interleaved = buffer.format.isInterleaved
    for i in 0..<count {
      var sample: Float = 0
      for ch in 0..<channelCount {
        sample += interleaved ? channels[0][i * channelCount + ch] : channels[ch][i]
      }
      sample /= Float(channelCount)
      if !sample.isFinite { sample = 0 }
      peak = max(peak, abs(sample))
      samples[i] = Int16(max(-32767, min(32767, sample * 32767)))
    }
    queue.async { [weak self] in
      guard let self else { return }
      defer {
        self.backlogLock.lock()
        self.backlog -= 1
        self.freeSlots.append(slot)
        self.backlogLock.unlock()
      }
      do {
        let packet = AudioPacket(
          hostTime: hostTime, sampleRate: sampleRate, pcm: Data(bytes: samples, count: count * 2))
        self.backlogLock.lock()
        let current = self.leases[track] == lease
        let eligible = recipients.filter { self.consumerLeases[$0.key] == $0.value }.map(\.key)
        self.backlogLock.unlock()
        guard current, !eligible.isEmpty else { return }
        var clock = self.clocks[track] ?? CaptureClockTracker()
        let gap = try clock.observe(
          hostTime: hostTime, frames: count, sampleRate: packet.sampleRate)
        self.clocks[track] = clock
        for id in eligible {
          guard var consumer = self.consumers[id], consumer.tracks.contains(track) else { continue }
          if privatePacket && track == .microphone && id.hasPrefix("meeting:") { continue }
          if consumer.journals[track] == nil || hostTime - (consumer.starts[track] ?? 0) >= 30
            || consumer.formats[track] != packet.sampleRate
          {
            try consumer.journals[track]?.close()
            let path = consumer.directory.appendingPathComponent(
              "\(track.rawValue)-\(String(format: "%.6f",hostTime)).vwj")
            consumer.journals[track] = try AudioJournal(url: path, key: self.key)
            consumer.starts[track] = hostTime
            consumer.formats[track] = packet.sampleRate
          }
          if let gap, track != .assistant { self.onGap?(id, track, gap) }
          try consumer.journals[track]?.append(packet)
          self.consumers[id] = consumer
        }
        if hostTime - (self.lastMeter[track] ?? 0) > 0.1 {
          self.lastMeter[track] = hostTime
          self.onLevel?(track, peak, hostTime)
        }
        if track == .microphone {
          let bands = self.spectrum.levels(pcm: UnsafeBufferPointer(start: samples, count: count), sampleRate: sampleRate)
          if hostTime - self.lastSpectrumTime >= 0.045 || hostTime < self.lastSpectrumTime {
            self.lastSpectrumTime = hostTime
            self.onWaveform?(bands, hostTime)
          }
        }
        // Meter-only preview never reaches transcription or outgoing audio consumers.
        guard eligible.contains(where: { self.consumers[$0]?.tracks.contains(track) == true }) else { return }
        for (id, handler) in self.packetHandlers {
          if privatePacket && track == .microphone && id == "captions" { continue }
          handler(track, packet)
        }
      } catch { self.onFailure?("Audio could not be saved: \(error.localizedDescription)") }
    }
  }
  func setPrivateAddress(_ value: Bool) { backlogLock.withLock { privateAddress = value } }
  func beginAssistantSource() -> CaptureLease {
    let lease = CaptureLease()
    backlogLock.withLock { leases[.assistant] = lease }
    queue.sync { clocks[.assistant] = CaptureClockTracker() }
    return lease
  }
  func endAssistantSource() { queue.sync { backlogLock.withLock { leases[.assistant] = nil } } }
  func appendRenderedAssistant(_ buffer: AVAudioPCMBuffer, hostTime: Double, lease: CaptureLease) {
    accept(buffer: buffer, track: .assistant, hostTime: hostTime, lease: lease)
  }
  @MainActor func validatePrivateFanout(root: URL) throws {
    let meeting = root.appendingPathComponent("private-meeting")
    let voice = root.appendingPathComponent("private-question")
    for directory in [meeting, voice] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let source = CaptureLease()
    queue.sync {
      consumers["meeting:privacy"] = Consumer(directory: meeting, tracks: [.microphone])
      consumers["voice:privacy"] = Consumer(directory: voice, tracks: [.microphone])
      clocks[.microphone] = CaptureClockTracker()
    }
    backlogLock.withLock {
      consumerLeases["meeting:privacy"] = UUID()
      consumerLeases["voice:privacy"] = UUID()
      leases[.microphone] = source
    }
    let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 240)!
    buffer.frameLength = 240
    buffer.floatChannelData![0].initialize(repeating: 0.25, count: 240)
    var observedBands: [Float] = []
    onWaveform = { bands, _ in observedBands = bands }
    defer { onWaveform = nil }
    setPrivateAddress(true)
    accept(buffer: buffer, track: .microphone, hostTime: 400, lease: source)
    setPrivateAddress(false)  // Writer must use privacy at capture, not the later UI state.
    try removeConsumer(id: "meeting:privacy")
    try removeConsumer(id: "voice:privacy")
    guard observedBands.count == 5, observedBands.contains(where: { $0 > 0 }),
      observedBands.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }) else {
      throw WorkspaceError.message("Microphone PCM did not publish the live EQ bands.")
    }
    print("PASS: production microphone fanout publishes bounded live frequency bands after saving audio; no hardware opened.")
    let shared = try FileManager.default.contentsOfDirectory(
      at: meeting, includingPropertiesForKeys: nil)
    let privateFiles = try FileManager.default.contentsOfDirectory(
      at: voice, includingPropertiesForKeys: nil)
    guard shared.isEmpty, privateFiles.count == 1,
      try AudioJournal.recover(url: privateFiles[0], key: key).packets.count == 1
    else { throw WorkspaceError.unsafeRoute }
  }
  @MainActor func validateMeterOnlyFanout(root: URL) throws {
    let directory = root.appendingPathComponent("meter-only-must-not-exist")
    let source = CaptureLease()
    queue.sync {
      consumers["preview:fixture"] = Consumer(directory: directory, tracks: [], meterOnly: true)
      clocks[.microphone] = CaptureClockTracker()
    }
    backlogLock.withLock {
      consumerLeases["preview:fixture"] = UUID()
      leases[.microphone] = source
    }
    var bands: [Float] = []
    var publishedPackets = 0
    onWaveform = { value, _ in bands = value }
    setPacketHandler({ _, _ in publishedPackets += 1 }, id: "preview-privacy-fixture")
    defer {
      onWaveform = nil
      setPacketHandler(nil, id: "preview-privacy-fixture")
      backlogLock.withLock { leases[.microphone] = nil }
    }
    let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2048)!
    buffer.frameLength = 2048
    for i in 0..<2048 { buffer.floatChannelData![0][i] = Float(sin(Double(i) * 0.15)) * 0.1 }
    accept(buffer: buffer, track: .microphone, hostTime: 500, lease: source)
    queue.sync {}
    guard bands.contains(where: { $0 > 0 }), publishedPackets == 0,
      !FileManager.default.fileExists(atPath: directory.path),
      queue.sync(execute: { consumers["preview:fixture"]?.needsMicrophone == true }) else {
      throw WorkspaceError.message("Meter preview failed its signal, storage or provider privacy check.")
    }
    try removeConsumer(id: "preview:fixture")
    bands = []
    accept(buffer: buffer, track: .microphone, hostTime: 501, lease: source)
    queue.sync {}
    guard bands.isEmpty, publishedPackets == 0,
      queue.sync(execute: { !consumers.values.contains(where: { $0.needsMicrophone }) }) else {
      throw WorkspaceError.message("Stopped preview retained microphone ownership or published a late packet.")
    }
    print("PASS: meter-only preview publishes real PCM bands, saves no files, sends no provider packets and fences stopped consumers; no hardware opened.")
  }
  /// Exercises the production fanout, lifetime fence and writer without opening an audio device.
  @MainActor func validateOfflineFanout(root: URL) async throws {
    let first = root.appendingPathComponent("lease-first")
    let second = root.appendingPathComponent("lease-second")
    let old = CaptureLease()
    let next = CaptureLease()
    let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 240)!
    buffer.frameLength = 240
    buffer.floatChannelData![0].initialize(repeating: 0.25, count: 240)
    try await addConsumer(id: "fixture", directory: first, tracks: [.remote])
    backlogLock.withLock { leases[.remote] = old }
    accept(buffer: buffer, track: .remote, hostTime: 100, lease: old)
    try removeConsumer(id: "fixture")  // Flush accepted packets before closing the leg.
    try await addConsumer(id: "fixture", directory: second, tracks: [.remote])
    backlogLock.withLock { leases[.remote] = next }
    accept(buffer: buffer, track: .remote, hostTime: 101, lease: old)  // Late callback must be fenced.
    accept(buffer: buffer, track: .remote, hostTime: 102, lease: next)
    try removeConsumer(id: "fixture")
    for directory in [first, second] {
      let files = try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)
      let packets = try files.flatMap { try AudioJournal.recover(url: $0, key: key).packets }
      guard packets.count == 1, packets.first?.hostTime == (directory == first ? 100 : 102) else {
        throw WorkspaceError.message("A stopped source published into another recording leg.")
      }
    }
  }

}

protocol RemoteAudioCapture: AnyObject {
  @MainActor func start(
    pid: pid_t, receive: @escaping (AVAudioPCMBuffer, Double) -> Void,
    failure: @escaping (String) -> Void) async throws
  @MainActor func stop()
}
