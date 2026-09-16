import AVFoundation
import CryptoKit
import SoundAnalysis
import ChupCore

/// Local analysis of silence at any length and noise in short clips. Never captures, uploads or deletes audio.
enum ShortDictationFilter {
  static func inspect(directory: URL, key: SymmetricKey) async -> String? {
    let task = Task.detached(priority: .userInitiated) { () -> String? in
      do {
        guard FileManager.default.fileExists(atPath: directory.path) else { return "Empty shortcut tap" }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
          .filter { $0.pathExtension == "vwj" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var packets: [AudioPacket] = [], duration = 0.0, peak: Float = 0
        enum LongerClip: Error { case keep }
        for file in files {
          let truncated = try AudioJournal.scan(url: file, key: key) { packet in
            try Task.checkCancellation()
            duration += packet.duration
            peak = max(peak, packet.pcm.withUnsafeBytes { raw in
              raw.bindMemory(to: Int16.self).reduce(Float(0)) { max($0, abs(Float(Int16(littleEndian: $1))) / 32768) }
            })
            if duration > 2 && peak > 0.0001 { throw LongerClip.keep }
            if duration <= 2 { packets.append(packet) }
          }
          if truncated { return nil }
        }
        if peak <= 0.0001 { return duration == 0 ? "No audio received" : "No microphone signal" }
        try Task.checkCancellation()
        var cursor = 0.0
        let positioned = packets.map { packet -> PositionedAudio in
          defer { cursor += packet.duration }
          return PositionedAudio(start: cursor, track: .microphone, packet: packet)
        }
        let samples = try AudioTimeline.mix(positioned, start: 0, frames: max(1, Int(ceil(duration * 24000))), rate: 24000, gains: [.microphone: 1])
        let prediction = try classify(samples)
        guard !Task.isCancelled else { return nil }
        return ShortDictationPolicy.ignore(duration: duration, peak: peak,
          speechConfidence: prediction?.speech, noiseConfidence: prediction?.noise) ? "Short background-noise recording" : nil
      } catch { return nil } // Keep speech on any malformed audio, unavailable model or uncertain analysis.
    }
    return await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
  }
  static func classify(_ samples: [Float]) throws -> (speech: Double, noise: Double)? {
    let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
    let labels = Set(request.knownClassifications.filter {
      $0.contains("speech") || $0.contains("whisper") || $0.contains("singing") || $0.contains("conversation")
    })
    guard labels.contains("speech") else { return nil }
    // Use the model's default temporal context; its shortest window is too ambiguous for noise.
    guard request.windowDuration.seconds.isFinite, request.windowDuration.seconds > 0,
      request.windowDuration.seconds <= 3 else { return nil }
    request.overlapFactor = 0.5
    let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    // Zero padding allows classification of a brief tap; it never enters the saved audio.
    let frames = max(samples.count, Int(ceil(request.windowDuration.seconds * 24000)))
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(frames)) else { return nil }
    buffer.frameLength = UInt32(frames)
    buffer.floatChannelData![0].initialize(repeating: 0, count: frames)
    samples.withUnsafeBufferPointer { source in
      if let base = source.baseAddress { buffer.floatChannelData![0].update(from: base, count: source.count) }
    }
    let observer = SoundObserver(speechLabels: labels)
    let analyzer = SNAudioStreamAnalyzer(format: format)
    try analyzer.add(request, withObserver: observer)
    analyzer.analyze(buffer, atAudioFramePosition: 0)
    analyzer.completeAnalysis()
    guard observer.finished.wait(timeout: .now() + 5) == .success else { analyzer.removeAllRequests(); return nil }
    return observer.result()
  }
}
private final class SoundObserver: NSObject, SNResultsObserving {
  let finished = DispatchSemaphore(value: 0)
  let speechLabels: Set<String>
  private let lock = NSLock()
  private var speech = 0.0, noise = 1.0, count = 0
  private var failed = false
  init(speechLabels: Set<String>) { self.speechLabels = speechLabels }
  func request(_ request: SNRequest, didProduce result: SNResult) {
    guard let result = result as? SNClassificationResult else { return }
    lock.lock(); defer { lock.unlock() }
    let voice = result.classifications.filter { speechLabels.contains($0.identifier) }.map(\.confidence).max() ?? 0
    let other = result.classifications.filter { !speechLabels.contains($0.identifier) }.map(\.confidence).max() ?? 0
    speech = max(speech, voice); noise = min(noise, other); count += 1
  }
  func request(_ request: SNRequest, didFailWithError error: Error) { lock.lock(); failed = true; lock.unlock(); finished.signal() }
  func requestDidComplete(_ request: SNRequest) { finished.signal() }
  func result() -> (speech: Double, noise: Double)? {
    lock.lock(); defer { lock.unlock() }
    return !failed && count > 0 ? (speech, noise) : nil
  }
}
