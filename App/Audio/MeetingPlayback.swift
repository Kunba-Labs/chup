import AVFoundation
import CryptoKit
import ChupCore

/// Index and decrypt off the main actor; retain only journals intersecting the next playback window.
actor MeetingAudioArchive {
  struct Entry {
    let url: URL
    let start: Double
    let end: Double
    let origin: Double
    let offset: Double
    let track: TrackKind
  }
  private var entries: [Entry] = []
  private var cache: [URL: [AudioPacket]] = [:]
  private var waveform: [WaveformBin] = []
  private var reusedIndexes = 0
  private let key: SymmetricKey
  init(key: SymmetricKey) { self.key = key }
  func prepare(_ legs: [RecordingLeg]) throws -> (Double, Bool) {
    entries = []
    cache = [:]
    waveform = []
    reusedIndexes = 0
    var recoveredTail = false
    for leg in legs.sorted(by: { $0.offset < $1.offset }) {
      try Task.checkCancellation()
      let directory = URL(fileURLWithPath: leg.directory)
      let files = try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil
      )
      .filter { $0.pathExtension == "vwj" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
      // The same leg origin is used by final transcription; it is shared by all tracks.
      let origin =
        leg.hostStart ?? files.compactMap {
          Double($0.deletingPathExtension().lastPathComponent.split(separator: "-").last ?? "")
        }.min() ?? 0
      let (index, reused) = try RecordingIndex.load(leg: leg, urls: files, key: key)
      if reused { reusedIndexes += 1 }
      for file in index.files {
        recoveredTail = recoveredTail || file.truncated
        let url = try SafeWorkspacePath.resolve(file.name, root: directory)
        entries.append(Entry(url: url, start: leg.offset + file.first - origin,
          end: leg.offset + file.end - origin, origin: origin, offset: leg.offset, track: file.track))
        waveform += file.bins.map { WaveformBin(time: leg.offset + $0.time - origin, peak: $0.peak) }
      }
    }
    entries.sort { $0.start < $1.start }
    return (entries.map(\.end).max() ?? 0, recoveredTail)
  }
  func waveformBins() -> [WaveformBin] { waveform }
  func cachedLegs() -> Int { reusedIndexes }
  func exportTracks(to destination: URL, progress: @Sendable (Double) async -> Void) async throws {
    guard !FileManager.default.fileExists(atPath: destination.path),
      let duration = entries.map(\.end).max(), duration.isFinite, duration > 0,
      ceil(duration * 24000) <= Double((Int(UInt32.max) - 36) / 2) else {
      throw WorkspaceError.message("Choose a new audio export folder for a recorded meeting.")
    }
    let staging = destination.deletingLastPathComponent().appendingPathComponent(".chup-export-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: staging) }
    let total = Int(ceil(duration * 24000))
    let sources = tracks()
    for (index, track) in sources.enumerated() {
      let writer = try WaveFileWriter(destination: staging.appendingPathComponent(track.rawValue + ".wav"), frames: total)
      var position = 0
      while position < total {
        try Task.checkCancellation()
        let count = min(24000, total - position)
        try writer.append(render(start: Double(position) / 24000, frames: count, track: track, rate: 24000))
        position += count
        await progress((Double(index) + Double(position) / Double(total)) / Double(sources.count))
      }
      try Task.checkCancellation()
      try writer.finish()
    }
    let manifest: [String: Any] = ["format": "Chup audio export v1", "sampleRate": 24000, "channels": 1,
      "duration": Double(total) / 24000, "tracks": sources.map { $0.rawValue + ".wav" },
      "timing": "Tracks start at meeting time zero. Pauses and capture gaps are silence. Private question recordings are excluded.",
      "intervals": entries.map { ["track": $0.track.rawValue, "start": $0.start, "end": $0.end] as [String: Any] }]
    try DurableFile.write(JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]), to: staging.appendingPathComponent("manifest.json"))
    try Task.checkCancellation()
    try FileManager.default.moveItem(at: staging, to: destination)
    try DurableFile.syncDirectory(destination.deletingLastPathComponent())
  }
  func render(start: Double, frames: Int, track: TrackKind? = nil, rate: Double = 48000) throws
    -> [Float]
  {
    try Task.checkCancellation()
    let end = start + Double(frames) / rate
    let selected = entries.filter {
      $0.start < end && $0.end > start && (track == nil || $0.track == track)
    }
    let needed = Set(selected.map(\.url))
    cache = cache.filter { needed.contains($0.key) }
    var packets: [PositionedAudio] = []
    for entry in selected {
      try Task.checkCancellation()
      if cache[entry.url] == nil {
        cache[entry.url] = try AudioJournal.recover(url: entry.url, key: key).packets
      }
      for packet in cache[entry.url] ?? [] {
        let time = entry.offset + packet.hostTime - entry.origin
        if time < end && time + packet.duration > start {
          packets.append(PositionedAudio(start: time, track: entry.track, packet: packet))
        }
      }
    }
    return try AudioTimeline.mix(
      packets, start: start, frames: frames, rate: rate,
      gains: track == nil ? [.microphone: 0.5, .remote: 0.5, .assistant: 0.5] : [track!: 1])
  }
  func tracks() -> [TrackKind] {
    TrackKind.allCases.filter { track in entries.contains { $0.track == track } }
  }
  func wave(start: Double, end: Double, track: TrackKind) throws -> Data {
    guard start.isFinite, end.isFinite, end > start, end - start <= 100 else {
      throw WorkspaceError.message("Audio export must be between 0 and 100 seconds.")
    }
    var pcm = Data()
    var position = start
    while position < end {
      let frames = min(24000, Int(((end - position) * 24000).rounded()))
      if frames <= 0 { break }
      let samples = try render(start: position, frames: frames, track: track, rate: 24000)
        .map { Int16(max(-32767, min(32767, $0 * 32767))) }
      pcm.append(samples.withUnsafeBytes { Data($0) })
      position += Double(frames) / 24000
    }
    return try AudioJournal.wave(packets: [AudioPacket(hostTime: 0, sampleRate: 24000, pcm: pcm)])
  }

}

/// Continuous, bounded lookahead playback on a single sample clock for all recorded tracks.
@MainActor final class MeetingPlayback {
  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
  private let isolatedTrack: TrackKind?
  private var observer: NSObjectProtocol?
  private var archive: MeetingAudioArchive?
  private var task: Task<Void, Never>?
  private var generation = UUID()
  private var offset: Double = 0
  private var queuedFrames: Int64 = 0
  private(set) var duration: Double = 0
  private(set) var position: Double = 0
  private(set) var running = false
  private(set) var loading = false
  var onChange: ((Double, Double, Bool, Bool) -> Void)?
  var onFailure: ((String) -> Void)?
  var onWaveform: (([WaveformBin]) -> Void)?
  init(track: TrackKind? = nil) {
    isolatedTrack = track
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
    observer = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: engine, queue: nil
    ) { [weak self] _ in
      DispatchQueue.main.async {
        guard let self, self.running else { return }
        self.pause()
        self.onFailure?(
          "Audio output changed. Playback paused; check your output, then press Play.")
      }
    }
  }
  func prepare(legs: [RecordingLeg], key: SymmetricKey) {
    reset()
    let archive = MeetingAudioArchive(key: key)
    self.archive = archive
    loading = true
    changed()
    let scope = generation
    task = Task {
      do {
        let result = try await archive.prepare(legs)
        guard scope == generation, !Task.isCancelled else { return }
        let bins = await archive.waveformBins()
        guard scope == generation, !Task.isCancelled else { return }
        onWaveform?(bins)
        duration = result.0
        loading = false
        changed()
        if result.1 {
          onFailure?(
            "Recovered audio is playable up to its last complete packet. The incomplete tail is excluded."
          )
        }
      } catch {
        guard scope == generation, !Task.isCancelled else { return }
        loading = false
        changed()
        onFailure?("Audio could not be opened: \(error.localizedDescription)")
      }
    }
  }
  private func changed() { onChange?(position, duration, running, loading) }
  func reset() {
    pause()
    archive = nil
    onWaveform?([])
    duration = 0
    position = 0
    changed()
  }
  func play(at time: Double) {
    guard !loading, let archive, duration > 0 else { return }
    pause()
    offset = min(max(0, time), duration)
    if offset >= duration { offset = 0 }
    position = offset
    queuedFrames = 0
    loading = true
    changed()
    let scope = generation
    task = Task {
      do {
        try await fill(archive: archive, scope: scope)
        guard scope == generation, !Task.isCancelled else { return }
        engine.prepare()
        try engine.start()
        player.play()
        running = true
        loading = false
        changed()
      } catch {
        guard scope == generation, !Task.isCancelled else { return }
        fail(error)
      }
    }
  }
  func pause() {
    if running { updatePosition() }
    generation = UUID()
    task?.cancel()
    task = nil
    player.stop()
    engine.stop()
    running = false
    loading = false
    changed()
  }
  func seek(to time: Double) {
    let resume = running
    pause()
    position = min(duration, max(0, time))
    changed()
    if resume { play(at: position) }
  }
  private func updatePosition() {
    if let render = player.lastRenderTime, let time = player.playerTime(forNodeTime: render) {
      position = min(duration, offset + Double(max(0, time.sampleTime)) / time.sampleRate)
    }
  }
  func tick() {
    guard running, let archive else { return }
    updatePosition()
    changed()
    if position >= duration - 0.01 {
      pause()
      position = duration
      changed()
      return
    }
    let bufferedUntil = offset + Double(queuedFrames) / 48000
    if position >= bufferedUntil && bufferedUntil < duration - 0.01 {
      position = bufferedUntil
      pause()
      position = bufferedUntil
      changed()
      onFailure?("Playback paused while loading audio. Press Play to continue from this point.")
      return
    }
    guard !loading, bufferedUntil - position < 2, bufferedUntil < duration else { return }
    loading = true
    let scope = generation
    task = Task {
      do {
        try await fill(archive: archive, scope: scope)
        guard scope == generation, !Task.isCancelled else { return }
        loading = false
        changed()
      } catch {
        guard scope == generation, !Task.isCancelled else { return }
        fail(error)
      }
    }
  }
  private func fill(archive: MeetingAudioArchive, scope: UUID) async throws {
    while offset + Double(queuedFrames) / 48000 < min(duration, position + 4) {
      try Task.checkCancellation()
      let start = offset + Double(queuedFrames) / 48000
      let count = min(48000, Int(ceil((duration - start) * 48000)))
      guard count > 0 else { break }
      let samples = try await archive.render(start: start, frames: count, track: isolatedTrack)
      guard scope == generation, !Task.isCancelled else { return }
      guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(count)) else {
        throw WorkspaceError.message("Playback buffer allocation failed.")
      }
      buffer.frameLength = UInt32(count)
      samples.withUnsafeBufferPointer { pointer in
        buffer.floatChannelData![0].update(from: pointer.baseAddress!, count: count)
      }
      schedule(buffer, at: queuedFrames)
      queuedFrames += Int64(count)
    }
  }
  private func schedule(_ buffer: AVAudioPCMBuffer, at frame: Int64) {
    // Synchronous enqueue: awaiting the completion would wait for playback before starting it.
    player.scheduleBuffer(
      buffer, at: AVAudioTime(sampleTime: frame, atRate: 48000), options: [], completionHandler: nil
    )
  }
  /// Developer validation uses this same index, renderer and scheduler without any hardware I/O.
  func renderOfflineForValidation(legs: [RecordingLeg], key: SymmetricKey) async throws -> [Float] {
    reset()
    let archive = MeetingAudioArchive(key: key)
    self.archive = archive
    duration = try await archive.prepare(legs).0
    guard duration > 0, duration <= 10 else {
      throw WorkspaceError.message("Offline fixture must be at most ten seconds.")
    }
    offset = 0
    position = 0
    queuedFrames = 0
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
    defer {
      player.stop()
      engine.stop()
      engine.disableManualRenderingMode()
    }
    try await fill(archive: archive, scope: generation)
    try engine.start()
    player.play()
    let total = Int(ceil(duration * 48000))
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
    var result: [Float] = []
    var retries = 0
    while result.count < total {
      try Task.checkCancellation()
      if offset + Double(queuedFrames) / 48000 < min(duration, position + 2) {
        try await fill(archive: archive, scope: generation)
      }
      let frames = UInt32(min(4096, total - result.count))
      let status = try engine.renderOffline(frames, to: buffer)
      if status == .cannotDoInCurrentContext && retries < 20 {
        retries += 1
        await Task.yield()
        continue
      }
      guard status == .success, buffer.frameLength > 0 else {
        throw WorkspaceError.message("Offline audio render failed: \(status.rawValue)")
      }
      retries = 0
      result.append(
        contentsOf: UnsafeBufferPointer(
          start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
      position = Double(result.count) / 48000
    }
    return result
  }
  private func fail(_ error: Error) {
    pause()
    onFailure?("Playback stopped: \(error.localizedDescription)")
  }
}
