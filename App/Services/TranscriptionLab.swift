import AppKit
import Combine
import CoreML
import CryptoKit
import FluidAudio
import ChupCore

actor ParakeetWorker {
  private var manager: AsrManager?
  private let files = LocalSpeechWorker()
  func install(directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
    try await files.install(manifest: LocalSpeechManifest.bundled("ParakeetModel"), directory: directory, progress: progress)
  }
  func prepare(directory: URL) async throws {
    if manager != nil { return }
    let manifest = try LocalSpeechManifest.bundled("ParakeetModel")
    for file in manifest.files {
      guard try await files.verify(file, in: directory) else {
        throw WorkspaceError.message("Download or repair Parakeet before running a comparison.")
      }
    }
    // Load verified files directly. SDK auto-download/recovery paths are never
    // used for inference, even when a model file is missing or damaged.
    func model(_ name: String, units: MLComputeUnits) throws -> MLModel {
      let config = MLModelConfiguration(); config.computeUnits = units
      return try MLModel(contentsOf: directory.appendingPathComponent(name + ".mlmodelc"), configuration: config)
    }
    let raw = try JSONDecoder().decode([String: String].self,
      from: Data(contentsOf: directory.appendingPathComponent("parakeet_vocab.json")))
    let vocabulary = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in Int(key).map { ($0, value) } })
    guard !vocabulary.isEmpty else { throw WorkspaceError.message("Parakeet vocabulary is empty.") }
    let config = MLModelConfiguration(); config.computeUnits = .cpuAndNeuralEngine
    let models = try AsrModels(encoder: model("Encoder", units: .cpuAndNeuralEngine),
      preprocessor: model("Preprocessor", units: .cpuOnly), decoder: model("Decoder", units: .cpuAndNeuralEngine),
      joint: model("JointDecision", units: .cpuAndNeuralEngine), configuration: config,
      vocabulary: vocabulary, version: .v3)
    try Task.checkCancellation()
    let loaded = AsrManager()
    try await loaded.loadModels(models)
    _ = try await loaded.transcribe([Float](repeating: 0, count: 16000), source: .microphone)
    try Task.checkCancellation()
    manager = loaded
  }
  func transcribe(journals: [URL], key: SymmetricKey) async throws -> String {
    guard let manager else { throw WorkspaceError.message("Parakeet is not ready.") }
    var texts: [String] = []
    for file in journals {
      try Task.checkCancellation()
      var packets: [PositionedAudio] = [], duration = 0.0
      let truncated = try AudioJournal.scan(url: file, key: key) { packet in
        guard duration + packet.duration <= 35 else { throw WorkspaceError.message("Choose a recording with regular audio chunks.") }
        packets.append(PositionedAudio(start: duration, track: .microphone, packet: packet))
        duration += packet.duration
      }
      guard !truncated else { throw WorkspaceError.corruptJournal }
      if duration == 0 { continue }
      let samples = try AudioTimeline.mix(packets, start: 0, frames: Int(ceil(duration * 16000)), rate: 16000, gains: [.microphone: 1])
      let result = try await manager.transcribe(samples, source: .microphone)
      try Task.checkCancellation()
      texts.append(result.text)
    }
    return texts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
  }
  func unload() async { await manager?.cleanup(); manager = nil }
}

@MainActor final class TranscriptionLab: ObservableObject {
  struct Result: Identifiable {
    let id = UUID()
    let model: String
    let text: String
    let preparationSeconds: Double
    let transcriptionSeconds: Double
    let error: String?
  }
  @Published var selectedEntryID = ""
  @Published private(set) var busy = false
  @Published private(set) var progress: Double?
  @Published private(set) var status = "Compare the same saved audio locally. Results stay here until cleared."
  @Published private(set) var results: [Result] = []
  @Published private(set) var baseline = ""
  @Published private(set) var parakeetInstalled = false
  let directory: URL
  let parakeet = ParakeetWorker()
  private let whisper = LocalSpeechService()
  private var task: Task<Void, Never>?
  private var generation = UUID()
  init() {
    directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Chup/Models/parakeet-v3-7dd20fe-v1")
    parakeetInstalled = FileManager.default.fileExists(atPath: directory.path)
  }
  var downloadSize: String {
    let bytes = (try? LocalSpeechManifest.bundled("ParakeetModel").size) ?? 0
    return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
  func install() {
    guard !busy else { return }
    busy = true; progress = 0; status = "Downloading verified Parakeet files…"
    task = Task {
      defer { busy = false; progress = nil; parakeetInstalled = FileManager.default.fileExists(atPath: directory.path) }
      do {
        try await parakeet.install(directory: directory) { value in
          Task { @MainActor in if self.progress != nil { self.progress = value } }
        }
        progress = nil; status = "Checking Parakeet locally…"
        try await parakeet.prepare(directory: directory)
        status = "Parakeet ready for offline comparison."
      } catch { status = Task.isCancelled ? "Download cancelled. Verified files can be resumed." : error.localizedDescription }
      await parakeet.unload()
    }
  }
  func removeModel() {
    guard !busy else { return }
    busy = true
    task = Task {
      defer { busy = false }
      await parakeet.unload()
      do {
        for path in [directory, directory.appendingPathExtension("download")] where FileManager.default.fileExists(atPath: path.path) {
          try FileManager.default.removeItem(at: path)
        }
        parakeetInstalled = false; status = "Parakeet removed."
      } catch { status = error.localizedDescription }
    }
  }
  func cancel() { task?.cancel(); generation = UUID() }
  func clear() {
    guard !busy else { return }
    results = []; baseline = ""
    status = "Choose a recording and compare both models locally."
  }
  func run(entry: DictationEntry, journals: [URL], key: SymmetricKey) {
    guard !busy else { return }
    busy = true; results = []; baseline = entry.original
    let run = UUID(); generation = run
    task = Task {
      defer { busy = false }
      do {
        if let reason = await ShortDictationFilter.inspect(directory: URL(fileURLWithPath: entry.audioDirectory), key: key) {
          throw WorkspaceError.message(reason + ". Choose a recording with speech.")
        }
        for model in ["Whisper large-v3-turbo", "Parakeet TDT 0.6B v3"] {
          try Task.checkCancellation()
          let preparing = ProcessInfo.processInfo.systemUptime
          var prepared: Double?
          status = "Preparing \(model)…"
          do {
            if model.hasPrefix("Whisper") { try await whisper.prepare() }
            else { try await parakeet.prepare(directory: directory) }
            prepared = ProcessInfo.processInfo.systemUptime
            status = "Transcribing with \(model)…"
            let text: String
            if model.hasPrefix("Whisper") { text = try await whisper.transcribe(files: journals, key: key, language: entry.language ?? "en") }
            else { text = try await parakeet.transcribe(journals: journals, key: key) }
            try Task.checkCancellation()
            guard generation == run else { throw CancellationError() }
            results.append(Result(model: model, text: text, preparationSeconds: prepared! - preparing,
              transcriptionSeconds: ProcessInfo.processInfo.systemUptime - prepared!, error: text.isEmpty ? "No text returned" : nil))
          } catch {
            try Task.checkCancellation()
            guard generation == run else { throw CancellationError() }
            results.append(Result(model: model, text: "", preparationSeconds: (prepared ?? ProcessInfo.processInfo.systemUptime) - preparing,
              transcriptionSeconds: prepared.map { ProcessInfo.processInfo.systemUptime - $0 } ?? 0, error: error.localizedDescription))
          }
          // Release one model before loading the next; every run includes fresh loading.
          await whisper.unload()
          await parakeet.unload()
        }
        status = "Comparison complete. Review names, numbers and negation before copying a result."
      } catch { status = Task.isCancelled ? "Comparison cancelled." : error.localizedDescription }
      await whisper.unload()
      await parakeet.unload()
    }
  }
}
