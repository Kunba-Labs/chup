import AVFoundation
import CryptoKit
import Foundation
import ChupCore
import CAudioSafety

@MainActor enum AudioValidation {
  static func run() async throws {
    if ProcessInfo.processInfo.environment["CHUP_HARDWARE_MIC_TEST"] == "1" {
      try await MicrophoneHealthValidation.checkHardware()
      return
    }
    if ProcessInfo.processInfo.environment["CHUP_PANEL_FIXTURE"] == "1" {
      try await DictationIndicatorController.validatePanelLayout()
      return
    }
    guard CHValidateInputExceptionBoundary() else { throw WorkspaceError.message("AVFAudio exception escaped its native boundary.") }
    print("PASS: injected AVFAudio exception becomes an ordinary startup error before returning to Swift; no hardware opened.")
    if let script = ProcessInfo.processInfo.environment["CHUP_PASTE_FIXTURE"] {
      try await PasteIntegrationValidation.run(script: URL(fileURLWithPath: script))
      return
    }
    if ProcessInfo.processInfo.environment["CHUP_INSPECT_MICROPHONE"] == "1" {
      let devices = AudioDevices()
      print("Lid closed:", devices.lidClosed as Any)
      print("System input:", devices.inputs.first(where: { $0.id == devices.defaultInputUID })?.name ?? "none")
      let selected = try devices.selection(UserDefaults.standard.string(forKey: "microphoneUID") ?? "")
      print("Chup input:", selected.name, "built-in:", selected.builtIn, "available:", selected.available)
      return
    }
    try await MicrophoneHealthValidation.run()
    try ShortcutRegistry.validateBindings()
    try await ShortcutRegistry.validateCallbackDelivery()
    try await TextInsertion.validateFocusObservation()
    try await DictationTraceValidation.run()
    if let directory = ProcessInfo.processInfo.environment["CHUP_LAB_FIXTURES"] {
      try await TranscriptionLabValidation.run(directory: URL(fileURLWithPath: directory), install: ProcessInfo.processInfo.environment["CHUP_LAB_INSTALL"] == "1")
    }
    try await MainActorTimer.validateDelivery()
    try await TextDeliveryValidation.run()
    if let directory = ProcessInfo.processInfo.environment["CHUP_LOCAL_SPEECH_FIXTURES"] {
      try await LocalSpeechValidation.run(directory: URL(fileURLWithPath: directory),
        install: ProcessInfo.processInfo.environment["CHUP_INSTALL_LOCAL_MODEL"] == "1")
    }
    if let port = ProcessInfo.processInfo.environment["CHUP_TEST_PORT"] {
      try await LiveValidation.run(port: port)
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "Chup-AudioValidation-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let key = SymmetricKey(size: .bits256)
    let first = root.appendingPathComponent("first")
    let second = root.appendingPathComponent("second")
    try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
    func write(_ directory: URL, name: String, time: Double, value: Int16, count: Int, rate: Double)
      throws
    {
      let journal = try AudioJournal(url: directory.appendingPathComponent(name + ".vwj"), key: key)
      let samples = [Int16](repeating: value, count: count)
      try journal.append(
        AudioPacket(hostTime: time, sampleRate: rate, pcm: samples.withUnsafeBytes { Data($0) }))
      try journal.close()
    }
    // First leg: independent mic and delayed call audio. Second leg: a real pause and rate change.
    try write(
      first, name: "microphone-100.000000", time: 100, value: 8192, count: 48000, rate: 48000)
    try write(first, name: "remote-100.500000", time: 100.5, value: 8192, count: 12000, rate: 24000)
    try write(
      second, name: "microphone-200.000000", time: 200, value: 16384, count: 220500, rate: 44100)
    let legs = [
      RecordingLeg(meetingID: "fixture", directory: first.path, offset: 0),
      RecordingLeg(meetingID: "fixture", directory: second.path, offset: 2),
    ]
    let playback = MeetingPlayback()
    let samples = try await playback.renderOfflineForValidation(legs: legs, key: key)
    guard samples.count == 336000 else {
      throw WorkspaceError.message("Unexpected rendered duration: \(samples.count)")
    }
    func expect(_ frame: Int, _ value: Float) throws {
      guard abs(samples[frame] - value) < 0.005 else {
        throw WorkspaceError.message(
          "Audio alignment check failed at \(frame): \(samples[frame]) != \(value)")
      }
    }
    try expect(12000, 0.125)
    try expect(36000, 0.25)
    try expect(72000, 0)
    try expect(120000, 0.25)
    try expect(310000, 0.25)  // Beyond the initial four-second lookahead.
    let owner = AudioOwner(key: key)
    try await owner.validateOfflineFanout(root: root)
    let archive = MeetingAudioArchive(key: key)
    let anchored = [
      RecordingLeg(meetingID: "fixture", directory: first.path, offset: 10, hostStart: 99)
    ]
    let prepared = try await archive.prepare(anchored)
    guard abs(prepared.0 - 12) < 0.001 else {
      throw WorkspaceError.message("Explicit leg clock anchor was lost.")
    }
    let silence = try await archive.render(start: 10, frames: 24000, track: .remote, rate: 24000)
    guard silence.allSatisfy({ $0 == 0 }) else {
      throw WorkspaceError.message("Delayed call audio moved into the gap.")
    }
    let wave = try await archive.wave(start: 11.5, end: 12, track: .remote)
    guard wave.count == 24044 else {
      throw WorkspaceError.message("Track export duration changed.")
    }
    let recovery = try await RecordingRecovery().inspect(
      meetingID: "fixture", legs: anchored, key: key)
    guard recovery.completePackets == 2, recovery.duration == 12 else {
      throw WorkspaceError.message("Recovery index disagrees with playback.")
    }
    _ = try await archive.prepare(anchored)
    guard await archive.cachedLegs() == 1, !(await archive.waveformBins()).isEmpty else {
      throw WorkspaceError.message("Encrypted waveform index was not reused.")
    }
    let indexURL = first.appendingPathComponent("waveform.chupindex")
    let sealedIndex = try Data(contentsOf: indexURL)
    guard sealedIndex.range(of: Data("microphone".utf8)) == nil else {
      throw WorkspaceError.message("Waveform index leaked clear metadata.")
    }
    try Data([0, 1, 2]).write(to: indexURL)
    _ = try await archive.prepare(anchored)
    guard await archive.cachedLegs() == 0 else {
      throw WorkspaceError.message("Tampered index was trusted.")
    }
    let exported = root.appendingPathComponent("aligned-tracks")
    try await archive.exportTracks(to: exported) { _ in }
    let micWAV = try Data(contentsOf: exported.appendingPathComponent("microphone.wav"))
    let remoteWAV = try Data(contentsOf: exported.appendingPathComponent("remote.wav"))
    guard micWAV.count == 576044, remoteWAV.count == micWAV.count else {
      throw WorkspaceError.message("Full recording exports do not share the same timeline.")
    }
    func sample(_ wave: Data, _ second: Double) -> Int16 {
      let byte = 44 + Int(second * 24000) * 2
      return Int16(bitPattern: UInt16(wave[byte]) | UInt16(wave[byte + 1]) << 8)
    }
    guard sample(micWAV, 10.5) == 0, sample(micWAV, 11.25) == 8191,
      sample(remoteWAV, 11.25) == 0, sample(remoteWAV, 11.75) == 8191 else {
      throw WorkspaceError.message("Aligned export moved or mixed independent tracks.")
    }
    let cancelled = root.appendingPathComponent("cancelled-export")
    let job = Task {
      try await archive.exportTracks(to: cancelled) { _ in
        withUnsafeCurrentTask { $0?.cancel() }
      }
    }
    do { try await job.value; throw WorkspaceError.message("Cancelled export succeeded.") }
    catch is CancellationError {}
    let lateJob = Task {
      try await archive.exportTracks(to: cancelled) { progress in
        if progress == 1 { withUnsafeCurrentTask { $0?.cancel() } }
      }
    }
    do { try await lateJob.value; throw WorkspaceError.message("Late cancelled export succeeded.") }
    catch is CancellationError {}
    guard !FileManager.default.fileExists(atPath: cancelled.path),
      !(try FileManager.default.contentsOfDirectory(atPath: root.path)).contains(where: { $0.hasPrefix(".chup-export-") }) else {
      throw WorkspaceError.message("Cancelled export left partial output.")
    }
    try write(first, name: "assistant-102.000000", time: 102, value: 4096, count: 24000, rate: 24000)
    _ = try await archive.prepare(anchored)
    guard await archive.cachedLegs() == 0, (await archive.tracks()).contains(.assistant) else {
      throw WorkspaceError.message("New audio did not invalidate the waveform index.")
    }
    let panel = NonactivatingPanel(contentRect: .zero, styleMask: [.nonactivatingPanel], backing: .buffered, defer: false)
    guard !panel.canBecomeKey, !panel.canBecomeMain else { throw WorkspaceError.unsafeRoute }
    panel.keyboardRequested = true
    guard panel.canBecomeKey, !panel.canBecomeMain else { throw WorkspaceError.unsafeRoute }
    panel.keyboardRequested = false
    if ProcessInfo.processInfo.environment["CHUP_LONG_EXPORT_TEST"] == "1" {
      let long = root.appendingPathComponent("long")
      try FileManager.default.createDirectory(at: long, withIntermediateDirectories: true)
      try write(long, name: "microphone-7299.000000", time: 7299, value: 8192, count: 24000, rate: 24000)
      let longArchive = MeetingAudioArchive(key: key)
      _ = try await longArchive.prepare([RecordingLeg(meetingID: "long", directory: long.path, offset: 0, hostStart: 100)])
      let destination = root.appendingPathComponent("two-hour-export")
      try await longArchive.exportTracks(to: destination) { _ in }
      let wav = destination.appendingPathComponent("microphone.wav")
      guard try wav.resourceValues(forKeys: [.fileSizeKey]).fileSize == 345600044 else {
        throw WorkspaceError.message("Two-hour WAV was truncated.")
      }
      let handle = try FileHandle(forReadingFrom: wav)
      try handle.seek(toOffset: 44 + 7199 * 48000)
      let end = try handle.read(upToCount: 2)
      try handle.close()
      guard end == Data([255, 31]) else { throw WorkspaceError.message("Two-hour export lost its final audio.") }
      print("PASS: accelerated two-hour sparse timeline exports 345,600,044-byte WAV with final audio at its absolute offset. This is not a capture soak.")
    }
    print("PASS: encrypted waveform reuse/tamper recovery/invalidation; aligned full WAV tracks; cancelled export cleanup; nonactivating panel keyboard eligibility.")
    try owner.validatePrivateFanout(root: root)
    try owner.validateMeterOnlyFanout(root: root)
    let silent = root.appendingPathComponent("silent-shortcut")
    try FileManager.default.createDirectory(at: silent, withIntermediateDirectories: true)
    try write(silent, name: "microphone-10.000000", time: 10, value: 0, count: 4800, rate: 24000)
    guard await ShortDictationFilter.inspect(directory: silent, key: key) != nil else {
      throw WorkspaceError.message("Empty shortcut noise guard failed.")
    }
    guard FileManager.default.fileExists(atPath: silent.appendingPathComponent("microphone-10.000000.vwj").path) else {
      throw WorkspaceError.message("Noise filtering deleted recoverable audio.")
    }
    let longSilent = root.appendingPathComponent("long-silent-shortcut")
    try FileManager.default.createDirectory(at: longSilent, withIntermediateDirectories: true)
    try write(longSilent, name: "microphone-20", time: 20, value: 0, count: 24000 * 12, rate: 24000)
    guard await ShortDictationFilter.inspect(directory: longSilent, key: key) != nil else {
      throw WorkspaceError.message("Long silent recording would reach transcription.")
    }
    try write(longSilent, name: "microphone-33", time: 33, value: 40, count: 2400, rate: 24000)
    guard await ShortDictationFilter.inspect(directory: longSilent, key: key) == nil else {
      throw WorkspaceError.message("Late quiet speech was incorrectly discarded.")
    }
    print("PASS: twelve-second silent recording skips transcription without deleting audio; a later quiet signal is preserved.")
    let dictationPlayer = MeetingPlayback(track: .microphone)
    let dictationAudio = try await dictationPlayer.renderOfflineForValidation(legs: [RecordingLeg(meetingID: "d", directory: first.path, offset: 0)], key: key)
    guard !dictationAudio.isEmpty else { throw WorkspaceError.message("Saved dictation cannot render without cloud processing.") }
    if let directory = ProcessInfo.processInfo.environment["CHUP_SHORT_SPEECH_FIXTURES"] {
      var seed: UInt32 = 42
      let noise: [Float] = (0..<36000).map { _ in
        seed = seed &* 1664525 &+ 1013904223
        return (Float(seed) / Float(UInt32.max) * 2 - 1) * 0.1
      }
      guard let prediction = try ShortDictationFilter.classify(noise) else { throw WorkspaceError.message("Noise classifier returned no result.") }
      print("Local classifier noise fixture: speech=\(prediction.speech), noise=\(prediction.noise)")
      guard ShortDictationPolicy.ignore(duration: 1.5, peak: 0.1, speechConfidence: prediction.speech, noiseConfidence: prediction.noise) else {
        throw WorkspaceError.message("Synthetic short noise was not identified confidently.")
      }
      for name in ["no", "nee"] {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: directory).appendingPathComponent(name + ".wav"))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: UInt32(file.length)) else { throw WorkspaceError.corruptJournal }
        try file.read(into: buffer)
        let signal = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        guard let prediction = try ShortDictationFilter.classify(signal) else {
          throw WorkspaceError.message("Local classifier did not return a result for synthetic speech.")
        }
        print("Local classifier fixture \(name): speech=\(prediction.speech), noise=\(prediction.noise)")
        let pcm = (0..<Int(buffer.frameLength)).map { Int16(max(-32767, min(32767, buffer.floatChannelData![0][$0] * 32767))) }
        let folder = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let journal = try AudioJournal(url: folder.appendingPathComponent("microphone-10.vwj"), key: key)
        try journal.append(AudioPacket(hostTime: 10, sampleRate: buffer.format.sampleRate, pcm: pcm.withUnsafeBytes { Data($0) }))
        try journal.close()
        guard await ShortDictationFilter.inspect(directory: folder, key: key) == nil else {
          throw WorkspaceError.message("Short spoken negation was incorrectly ignored: " + name)
        }
      }
      print("PASS: local short-clip classifier rejects synthetic noise and preserves English No and Dutch Nee. No capture, playback or cloud calls.")
    }
    print("PASS: short silent dictation ignored without deletion; saved dictation renders locally without transcription.")
    let context = UUID()
    let microphone = [Int16](repeating: 8192, count: 2400).withUnsafeBytes { Data($0) }
    let assistant = [Int16](repeating: 16384, count: 1200).withUnsafeBytes { Data($0) }
    let routed = VoiceOutputEngine(outgoing: true)
    let mixed = try routed.renderOffline(
      assistant: assistant, microphone: microphone, context: context, frames: 2400)
    guard abs(mixed[500] - 0.6) < 0.01, abs(mixed[1800] - 0.2) < 0.01 else {
      throw WorkspaceError.message("Mix-minus render disagreed with source gains.")
    }
    print(
      "PASS: private microphone fanout excludes meeting journal; production AVAudioSourceNode outgoing mix renders assistant + mic with remote absent."
    )
    print(
      "PASS: production audio-owner callback fencing and leg flush; explicit clock anchors; isolated track WAV export; recovery index. No capture devices opened."
    )
    print(
      "PASS: native offline audio render, encrypted journals, separate-track alignment, pause gap, 44.1/24/48 kHz conversion, seven-second continuous playback beyond initial lookahead. No hardware or microphone opened."
    )
  }
}
