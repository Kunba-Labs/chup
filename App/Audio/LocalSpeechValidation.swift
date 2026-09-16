import AVFoundation
import Foundation
import CryptoKit
import ChupCore

/// Explicit opt-in only: downloads public weights when requested, then tests generated speech.
@MainActor enum LocalSpeechValidation {
  static func run(directory: URL, install: Bool) async throws {
    let state = WorkspaceState(preview: true)
    defer { try? FileManager.default.removeItem(at: state.root) }
    guard let key = state.key else { throw WorkspaceError.message("Fixture key unavailable.") }
    if install {
      print("Installing verified local model (630 MB); no user audio is accessed.")
      try await state.localSpeech.installAndPrepare()
    }
    _ = URLProtocol.registerClass(OfflineSpeechNetworkProbe.self)
    defer { URLProtocol.unregisterClass(OfflineSpeechNetworkProbe.self) }
    OfflineSpeechNetworkProbe.reset()
    // A fresh load must also work with every URL loading request blocked.
    await state.localSpeech.worker.unload()
    let offline = LocalSpeechService()
    offline.checkInstalled()
    offline.checkInstalled()
    try await offline.prepare()
    await offline.worker.unload()
    // state service retains readiness but its worker was deliberately unloaded above.
    try await state.localSpeech.worker.prepare(manifest: LocalSpeechManifest.bundled(), directory: state.localSpeech.directory)
    state.cloudEnabled = true
    state.backendToken = "synthetic-test-token"
    state.backendURL = "https://local-speech-fixture.invalid"
    state.transcriptionMode = .local
    var last: DictationEntry?
    for (name, language, expected) in [("english", "en", "microphones"), ("dutch", "nl", "microfoons")] {
      let input = try AVAudioFile(forReading: directory.appendingPathComponent(name + ".wav"))
      guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: AVAudioFrameCount(input.length)) else {
        throw WorkspaceError.message("Cannot allocate synthetic speech fixture.")
      }
      try input.read(into: buffer)
      guard let floats = buffer.floatChannelData?[0] else { throw WorkspaceError.message("Expected float speech fixture.") }
      let samples = (0..<Int(buffer.frameLength)).map { Int16(max(-32768, min(32767, Float(floats[$0]) * 32767))) }
      let folder = state.root.appendingPathComponent(name)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let journal = try AudioJournal(url: folder.appendingPathComponent("microphone-0.vwj"), key: key)
      try journal.append(AudioPacket(hostTime: 0, sampleRate: buffer.format.sampleRate, pcm: samples.withUnsafeBytes { Data($0) }))
      try journal.close()
      var entry = DictationEntry(text: "", original: "", application: "Synthetic fixture", mode: CleanupMode.light.rawValue, audioDirectory: folder.path)
      entry.language = language
      let output = try await state.processDictation(entry)
      print("Local synthetic \(language): \(output.text)")
      guard output.text.lowercased().contains(expected), output.status == "ready",
        output.transcriptionProvider?.hasPrefix("Local") == true,
        try state.db().list(DictationEntry.self, kind: "dictation").contains(where: { $0.id == output.id && $0.text == output.text }) else {
        throw WorkspaceError.message("Local speech fixture failed to transcribe and commit \(language).")
      }
      last = entry
    }
    guard OfflineSpeechNetworkProbe.count == 0 else { throw WorkspaceError.message("Local inference attempted network access.") }
    guard let entry = last else { return }
    state.transcriptionMode = .automatic
    let fallback = try await state.processDictation(entry)
    guard OfflineSpeechNetworkProbe.count == 1, fallback.transcriptionProvider?.hasPrefix("Local") == true else {
      throw WorkspaceError.message("Cloud failure did not fall back exactly once.")
    }
    state.cloudEnabled = false
    _ = try await state.processDictation(entry)
    guard OfflineSpeechNetworkProbe.count == 1 else { throw WorkspaceError.message("Cloud-disabled dictation attempted an upload.") }
    var command = entry
    command.id = UUID().uuidString
    command.selection = "Selected text must stay unchanged"
    do {
      _ = try await state.processDictation(command)
      throw WorkspaceError.message("Local editing instruction was incorrectly returned as a replacement.")
    } catch {
      guard let saved = try state.db().list(DictationEntry.self, kind: "dictation").first(where: { $0.id == command.id }),
        saved.status == "transcribed", !saved.original.isEmpty else { throw error }
    }
    let cancelled = Task { @MainActor in try await state.processDictation(entry) }
    cancelled.cancel()
    do { _ = try await cancelled.value; throw WorkspaceError.message("Cancelled local work completed.") }
    catch is CancellationError {} // Other failures must escape the fixture.
    print("PASS: real local English/Dutch ASR commits from encrypted journals; fresh load and local mode make zero network requests; cloud failure falls back once; cloud-off stays local; editing and cancellation do not return insertion text.")
  }
}

final class OfflineSpeechNetworkProbe: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  private static var requests = 0
  static var count: Int { lock.lock(); defer { lock.unlock() }; return requests }
  static func reset() { lock.lock(); requests = 0; lock.unlock() }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.lock.lock(); Self.requests += 1; Self.lock.unlock()
    client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
  }
  override func stopLoading() {}
}
