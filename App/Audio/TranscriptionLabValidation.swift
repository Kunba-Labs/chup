import AVFoundation
import ChupCore

@MainActor enum TranscriptionLabValidation {
  static func run(directory: URL, install: Bool) async throws {
    let state = WorkspaceState(preview: true)
    defer { try? FileManager.default.removeItem(at: state.root) }
    guard let key = state.key else { throw WorkspaceError.message("Fixture key unavailable.") }
    let lab = state.transcriptionLab
    if install {
      print("Installing the pinned Parakeet comparison model; no user audio is accessed.")
      try await lab.parakeet.install(directory: lab.directory) { _ in }
    }
    _ = URLProtocol.registerClass(OfflineSpeechNetworkProbe.self)
    defer { URLProtocol.unregisterClass(OfflineSpeechNetworkProbe.self) }
    OfflineSpeechNetworkProbe.reset()
    for (name, language, expected) in [("english", "en", "microphones"), ("dutch", "nl", "microfoons")] {
      let source = try AVAudioFile(forReading: directory.appendingPathComponent(name + ".wav"))
      let buffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: AVAudioFrameCount(source.length))!
      try source.read(into: buffer)
      let samples = (0..<Int(buffer.frameLength)).map { Int16(max(-32767, min(32767, buffer.floatChannelData![0][$0] * 32767))) }
      let folder = state.root.appendingPathComponent(name)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let path = folder.appendingPathComponent("microphone-0.vwj")
      let journal = try AudioJournal(url: path, key: key)
      try journal.append(AudioPacket(hostTime: 0, sampleRate: buffer.format.sampleRate, pcm: samples.withUnsafeBytes { Data($0) }))
      try journal.close()
      var entry = DictationEntry(text: "Preserved original", original: "Preserved original", application: "Synthetic fixture", mode: "Verbatim", audioDirectory: folder.path)
      entry.language = language
      try state.db().put(entry, kind: "dictation", id: entry.id)
      lab.run(entry: entry, journals: [path], key: key)
      while lab.busy { try await Task.sleep(for: .milliseconds(100)) }
      guard lab.results.count == 2, lab.results.allSatisfy({ $0.error == nil && $0.text.lowercased().contains(expected) }),
        try state.db().list(DictationEntry.self, kind: "dictation").first(where: { $0.id == entry.id })?.text == "Preserved original" else {
        print(lab.results.map { ($0.model, $0.text, $0.error) })
        throw WorkspaceError.message("Local model comparison failed for synthetic \(language).")
      }
      for result in lab.results {
        print("PASS: synthetic \(language) / \(result.model): prepare=\(result.preparationSeconds)s transcribe=\(result.transcriptionSeconds)s; original preserved.")
      }
    }
    guard OfflineSpeechNetworkProbe.count == 0 else { throw WorkspaceError.message("Local comparison attempted a network request.") }
    print("PASS: both comparison models load and transcribe with URL loading blocked; no user audio or clipboard accessed.")
  }
}
