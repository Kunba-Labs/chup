import Foundation
import Combine
import CryptoKit
import WhisperKit
import ArgmaxCore
import ChupCore

struct LocalSpeechManifest: Decodable {
  struct File: Decodable {
    let path: String
    let url: URL
    let size: Int64
    let sha256: String
  }
  let id: String
  let name: String
  let files: [File]
  var size: Int64 { files.reduce(0) { $0 + $1.size } }
  static func bundled(_ resource: String = "LocalSpeechModel") throws -> Self {
    guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else {
      throw WorkspaceError.message("Local model manifest is missing. Reinstall Chup!.")
    }
    return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
  }
}

/// Never lets the SDK's tokenizer recovery path reach the network during inference.
private final class OfflineWhisperKit: WhisperKit {
  override func loadTokenizerIfNeeded() async throws {
    guard tokenizer == nil else { return }
    guard let tokenizerFolder else { throw WorkspaceError.message("Local tokenizer is missing.") }
    tokenizer = try await LocalWhisperTokenizer(
      base: AutoTokenizerWrapper.from(modelFolder: tokenizerFolder))
  }
}

private final class ModelDownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  let report: @Sendable (Int64) -> Void
  init(report: @escaping @Sendable (Int64) -> Void) { self.report = report }
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    report(totalBytesWritten)
  }
}

/// One inference at a time, away from UI and capture callbacks. Journals stay encrypted on disk.
actor LocalSpeechWorker {
  private var pipe: OfflineWhisperKit?
  private var busy = false

  func verify(_ file: LocalSpeechManifest.File, in directory: URL) throws -> Bool {
    let url = directory.appendingPathComponent(file.path)
    guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
      Int64(size) == file.size else { return false }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hash = SHA256()
    while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
      try Task.checkCancellation()
      hash.update(data: data)
    }
    return hash.finalize().map { String(format: "%02x", $0) }.joined() == file.sha256
  }

  func install(manifest: LocalSpeechManifest, directory: URL,
    progress: @escaping @Sendable (Double) -> Void) async throws {
    guard !busy else { throw WorkspaceError.message("Local speech is busy. Try again shortly.") }
    busy = true
    defer { busy = false }
    let staging = directory.appendingPathExtension("download")
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 60
    config.timeoutIntervalForResource = 900
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    var completed: Int64 = 0
    for file in manifest.files {
      try Task.checkCancellation()
      if try !verify(file, in: staging) {
        let base = completed
        let delegate = ModelDownloadProgress { bytes in
          progress(min(1, Double(base + min(bytes, file.size)) / Double(manifest.size)))
        }
        let (temporary, response) = try await session.download(from: file.url, delegate: delegate)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
          throw WorkspaceError.message("Model download failed. Retry to resume verified files.")
        }
        let target = staging.appendingPathComponent(file.path)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.moveItem(at: temporary, to: target)
        guard try verify(file, in: staging) else {
          try? FileManager.default.removeItem(at: target)
          throw WorkspaceError.message("Local model checksum failed. Retry the download.")
        }
      }
      completed += file.size
      progress(Double(completed) / Double(manifest.size))
    }
    try Task.checkCancellation()
    if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    try FileManager.default.moveItem(at: staging, to: directory)
  }

  func prepare(manifest: LocalSpeechManifest, directory: URL) async throws {
    guard !busy else { throw WorkspaceError.message("Local speech is busy.") }
    if pipe != nil { return }
    busy = true
    defer { busy = false }
    for file in manifest.files {
      guard try verify(file, in: directory) else {
        throw WorkspaceError.message("Local model is missing or damaged. Download it in Settings → Dictation.")
      }
    }
    let loaded = try await OfflineWhisperKit(WhisperKitConfig(
      modelFolder: directory.path, tokenizerFolder: directory,
      verbose: false, prewarm: true, load: true, download: false))
    try Task.checkCancellation()
    // Only advertise readiness once a real local inference has completed.
    _ = try await loaded.transcribe(audioArray: [Float](repeating: 0, count: 16000),
      decodeOptions: options(language: "en"))
    try Task.checkCancellation()
    pipe = loaded
  }

  private func options(language: String) -> DecodingOptions {
    let automatic = language == "auto"
    return DecodingOptions(task: .transcribe, language: automatic ? nil : language,
      temperatureFallbackCount: 2, detectLanguage: automatic,
      skipSpecialTokens: true, withoutTimestamps: true, suppressBlank: true,
      concurrentWorkerCount: 1, chunkingStrategy: .vad)
  }

  func transcribe(files: [URL], key: SymmetricKey, language: String) async throws -> String {
    guard !busy, let pipe else { throw WorkspaceError.message("Local model is not ready. Open Settings → Dictation.") }
    busy = true
    defer { busy = false }
    var text = [String]()
    for file in files {
      try Task.checkCancellation()
      // AudioOwner rotates each journal at 30 seconds. Reject oversized imported journals.
      var packets = [PositionedAudio](), duration = 0.0
      let truncated = try AudioJournal.scan(url: file, key: key) { packet in
        guard duration + packet.duration <= 35 else {
          throw WorkspaceError.message("This audio chunk is too large for local dictation recovery.")
        }
        packets.append(PositionedAudio(start: duration, track: .microphone, packet: packet))
        duration += packet.duration
      }
      guard !truncated else { throw WorkspaceError.corruptJournal }
      var samples = [Float](), start = 0.0
      while start < duration {
        let frames = min(160000, Int(ceil((duration - start) * 16000)))
        guard frames > 0 else { break }
        samples += try AudioTimeline.mix(packets, start: start, frames: frames, rate: 16000, gains: [.microphone: 1])
        start += Double(frames) / 16000
      }
      guard !samples.isEmpty else { continue }
      let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options(language: language))
      try Task.checkCancellation()
      text.append(results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return text.filter { !$0.isEmpty }.joined(separator: " ")
  }

  func transcribeLive(packets: [AudioPacket], language: String) async throws -> String {
    guard !packets.isEmpty else { return "" }
    guard !busy, let pipe else { throw WorkspaceError.message("Local model is still warming up.") }
    busy = true
    defer { busy = false }
    var positioned: [PositionedAudio] = []
    var offset = 0.0
    for packet in packets {
      positioned.append(PositionedAudio(start: offset, track: .microphone, packet: packet))
      offset += packet.duration
    }
    let frames = min(160000, Int(ceil(offset * 16000)))
    let samples = try AudioTimeline.mix(positioned, start: 0, frames: frames, rate: 16000, gains: [.microphone: 1])
    guard samples.count >= 8000 else { return "" }
    let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options(language: language))
    return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func unload() async {
    guard !busy else { return }
    await pipe?.unloadModels()
    pipe = nil
  }
}

@MainActor final class LocalSpeechService: ObservableObject {
  @Published private(set) var status = "Model not installed"
  @Published private(set) var progress: Double?
  @Published private(set) var ready = false
  @Published private(set) var working = false
  private var task: Task<Void, Never>?
  let worker = LocalSpeechWorker()
  let directory: URL
  var installed: Bool { FileManager.default.fileExists(atPath: directory.path) }
  var partialDownload: Bool { FileManager.default.fileExists(atPath: directory.appendingPathExtension("download").path) }
  init() {
    directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Chup/Models/whisper-turbo-626mb-v1")
  }
  func checkInstalled() {
    guard installed, !working, !ready else { return }
    // Reserve setup before enqueuing: a second window must not enqueue a task
    // that waits on itself while another caller is starting preparation.
    working = true
    task = Task { try? await prepareModel() }
  }
  func install() {
    guard !working else { return }
    working = true
    task = Task {
      do { try await downloadModel() }
      catch { /* Status is set by installAndPrepare. */ }
    }
  }
  func cancel() { task?.cancel() }
  func installAndPrepare() async throws {
    guard !working else { throw WorkspaceError.message("Local model setup is already running.") }
    working = true
    try await downloadModel()
  }
  private func downloadModel() async throws {
    ready = false
    status = "Downloading local model…"
    progress = 0
    defer { working = false; progress = nil }
    do {
      let manifest = try LocalSpeechManifest.bundled()
      try await worker.install(manifest: manifest, directory: directory) { [weak self] value in
        Task { @MainActor in if self?.progress != nil { self?.progress = value } }
      }
      progress = nil
      status = "Preparing local model…"
      try await worker.prepare(manifest: manifest, directory: directory)
      ready = true
      status = "Offline ready"
    } catch {
      status = Task.isCancelled ? "Setup cancelled · retry to resume" : error.localizedDescription
      throw error
    }
  }
  func prepare() async throws {
    if ready { return }
    if working, let task {
      await task.value
      try Task.checkCancellation()
      guard ready else { throw WorkspaceError.message(status) }
      return
    }
    working = true
    try await prepareModel()
  }
  private func prepareModel() async throws {
    status = "Preparing local model…"
    defer { working = false }
    do {
      try await worker.prepare(manifest: LocalSpeechManifest.bundled(), directory: directory)
      ready = true
      status = "Offline ready"
    } catch {
      status = error.localizedDescription
      throw error
    }
  }
  func transcribe(files: [URL], key: SymmetricKey, language: String) async throws -> String {
    try await prepare()
    try Task.checkCancellation()
    guard !working else { throw WorkspaceError.message("Local speech is already working.") }
    working = true
    status = "Transcribing locally…"
    defer { working = false; status = ready ? "Offline ready" : "Model not installed" }
    return try await worker.transcribe(files: files, key: key, language: language)
  }

  func transcribeLive(packets: [AudioPacket], language: String) async throws -> String {
    try await prepare()
    return try await worker.transcribeLive(packets: packets, language: language)
  }
  func unload() async {
    guard !working else { return }
    ready = false
    await worker.unload()
    status = installed ? "Model installed" : "Model not installed"
  }
  func remove() {
    guard !working else { return }
    working = true
    ready = false
    task = Task {
      defer { working = false }
      await worker.unload()
      do {
        for url in [directory, directory.appendingPathExtension("download")] where FileManager.default.fileExists(atPath: url.path) {
          try FileManager.default.removeItem(at: url)
        }
        status = "Model not installed"
      } catch { status = error.localizedDescription }
    }
  }
}
