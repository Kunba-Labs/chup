import AVFoundation
import ChupCore

@MainActor enum MicrophoneHealthValidation {
  static func checkHardware() async throws {
    guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
      throw WorkspaceError.message("Hardware validation needs existing microphone access; no permission prompt was opened.")
    }
    let state = WorkspaceState(preview: true)
    defer { try? FileManager.default.removeItem(at: state.root) }
    guard let audio = state.audio else { throw WorkspaceError.message("Audio owner unavailable.") }
    let device: InputDevice
    if let name = ProcessInfo.processInfo.environment["CHUP_TEST_INPUT_NAME"] {
      let matches = state.devices.inputs.filter { $0.name == name && $0.available }
      guard matches.count == 1, let input = matches.first else {
        throw WorkspaceError.message("Requested test microphone is not uniquely available; no input opened.")
      }
      device = input
    } else {
      device = try state.devices.resolve(UserDefaults.standard.string(forKey: "microphoneUID") ?? "")
    }
    var configFailures = 0
    var captureActive = false
    let observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
      object: nil, queue: nil) { notification in
      let engine = notification.object
      DispatchQueue.main.async {
        if captureActive, audio.ownsEngine(engine), !audio.microphoneConfigurationValid { configFailures += 1 }
      }
    }
    defer { NotificationCenter.default.removeObserver(observer) }
    for cycle in 0..<3 {
      var packets = 0
      audio.onLevel = { _, _, _ in DispatchQueue.main.async { packets += 1 } }
      let id = "hardware-preview-\(cycle)"
      let directory = state.root.appendingPathComponent(id)
      try await audio.addConsumer(id: id, directory: directory, tracks: [], device: device, meterOnly: true)
      captureActive = true
      do {
        try await Task.sleep(for: .seconds(2))
        guard packets > 0, audio.actualMicrophoneID == device.objectID, audio.microphoneConfigurationValid else {
          throw WorkspaceError.message("Hardware microphone startup did not stay bound, running and delivering packets: \(packets) updates; \(audio.microphoneRouteDiagnostic)")
        }
        captureActive = false
        try audio.removeConsumer(id: id)
      } catch { captureActive = false; try? audio.removeConsumer(id: id); throw error }
      audio.onLevel = nil
      guard !FileManager.default.fileExists(atPath: directory.path) else {
        throw WorkspaceError.message("Hardware meter-only test wrote audio.")
      }
      print("PASS: hardware microphone cycle \(cycle + 1), \(packets) meter updates, input \(device.name), nominal \(device.sampleRate) Hz; no audio saved or uploaded.")
    }
    guard configFailures == 0 else { throw WorkspaceError.message("Hardware graph stopped or changed during microphone checks.") }
    try await audio.validateInterruptedMicrophoneStartup(device: device,
      directory: state.root.appendingPathComponent("startup-recovery-meter-only"))
  }
  static func run() async throws {
    let state = WorkspaceState(preview: true)
    defer { try? FileManager.default.removeItem(at: state.root) }
    guard let key = state.key else { throw WorkspaceError.message("Fixture key unavailable.") }
    let folder = state.root.appendingPathComponent("silent-input")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let journal = try AudioJournal(url: folder.appendingPathComponent("microphone-0.vwj"), key: key)
    try journal.append(AudioPacket(hostTime: 0, sampleRate: 24000, pcm: Data(count: 24000 * 12 * 2)))
    try journal.close()
    state.cloudEnabled = true
    state.backendURL = "http://127.0.0.1:9"
    state.backendToken = "synthetic-test-token"
    for mode in [DictationTranscriptionMode.cloud, .local] {
      state.transcriptionMode = mode
      let entry = DictationEntry(text: "", original: "", application: "Synthetic fixture", mode: CleanupMode.light.rawValue, audioDirectory: folder.path)
      do {
        _ = try await state.processDictation(entry)
        throw WorkspaceError.message("Silent dictation reached transcription.")
      } catch is DictationSignalError {}
      guard let stored = try state.db().list(DictationEntry.self, kind: "dictation").first(where: { $0.id == entry.id }),
        stored.status == "ignored", stored.text.isEmpty, stored.transcriptionProvider == nil else {
        throw WorkspaceError.message("Silent dictation was not committed as recoverable ignored audio.")
      }
    }
    print("PASS: production cloud/local dictation rejects a twelve-second silent journal before provider selection; audio and ignored records remain recoverable.")
  }
}
