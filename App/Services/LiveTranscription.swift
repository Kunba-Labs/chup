@preconcurrency import AVFoundation
import Foundation
import ChupCore

/// One ordered stream per physical source. Capture-window timings remain explicitly provisional.
actor LiveTranscription {
  private var socket: URLSessionWebSocketTask?
  private var receiver: Task<Void, Never>?
  private var ready = false
  private var start: Double?
  private var lastEnd: Double = 0
  private var awaitingWindows: [(Double, Double)] = []
  private var itemWindows: [String: (Double, Double)] = [:]
  private var transcript: [String: String] = [:]
  private var converter: AVAudioConverter?
  private var sourceRate: Double = 0
  // Speech captured while the socket opens is sent once the session is ready, not dropped.
  private var pending: [AudioPacket] = []
  private var endpoint: (URL, String)?
  private var closed = false
  private var reconnects = 0
  private let meetingID: String
  private let track: TrackKind
  private let origin: Double
  private let onSegment: (TranscriptSegment) -> Void
  private let onUsage: (String, String) -> Void
  private let onFailure: (String) -> Void
  init(
    meetingID: String, track: TrackKind, origin: Double,
    onSegment: @escaping (TranscriptSegment) -> Void, onFailure: @escaping (String) -> Void,
    onUsage: @escaping (String, String) -> Void = { _, _ in }
  ) {
    self.meetingID = meetingID
    self.track = track
    self.origin = origin
    self.onSegment = onSegment
    self.onFailure = onFailure
    self.onUsage = onUsage
  }
  func connect(backend: URL, token: String) {
    endpoint = (backend, token)
    closed = false
    var components = URLComponents(
      url: backend.appendingPathComponent("live-transcribe"), resolvingAgainstBaseURL: false)!
    components.scheme = backend.scheme == "https" ? "wss" : "ws"
    var request = URLRequest(url: components.url!)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let socket = URLSession.shared.webSocketTask(with: request)
    self.socket = socket
    socket.resume()
    receiver = Task { [weak self] in await self?.receive() }
  }
  func append(_ packet: AudioPacket) async {
    guard !closed else { return }
    guard ready else {
      pending.append(packet)
      // ponytail: ~20 s of 4096-frame packets; older audio still reaches the final transcript.
      if pending.count > 240 { pending.removeFirst() }
      return
    }
    // A failed packet waits for the reconnect, and later packets queue behind it.
    if !(await send(packet)), !closed { pending.append(packet) }
  }
  private func send(_ packet: AudioPacket) async -> Bool {
    guard let socket else { return false }
    do {
      let data = try resample(packet)
      if start == nil { start = packet.hostTime - origin }
      lastEnd = packet.hostTime - origin + packet.duration
      try await socket.send(
        .string(
          String(
            decoding: JSONSerialization.data(withJSONObject: [
              "type": "input_audio_buffer.append", "audio": data.base64EncodedString(),
            ]), as: UTF8.self)))
      // Commit at a pause after 3 s so captions arrive per phrase; never hold more than 8 s.
      if let start, lastEnd - start >= 8 || (lastEnd - start >= 3 && Self.quiet(packet)) {
        awaitingWindows.append((start, lastEnd))
        self.start = nil
        try await socket.send(.string("{\"type\":\"input_audio_buffer.commit\"}"))
      }
    } catch {
      // Buffer from now on; dropping the socket makes receive() fail and reconnect.
      ready = false
      socket.cancel(with: .goingAway, reason: nil)
      return false
    }
    return true
  }
  static func quiet(_ packet: AudioPacket) -> Bool {
    packet.pcm.withUnsafeBytes { raw in
      let samples = raw.bindMemory(to: Int16.self)
      guard !samples.isEmpty else { return true }
      let power = samples.reduce(0.0) { $0 + pow(Double(Int16(littleEndian: $1)) / 32768, 2) }
      return (power / Double(samples.count)).squareRoot() < 0.008
    }
  }
  private func resample(_ packet: AudioPacket) throws -> Data {
    let source = AVAudioFormat(
      commonFormat: .pcmFormatInt16, sampleRate: packet.sampleRate, channels: 1, interleaved: true)!
    let destination = AVAudioFormat(
      commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true)!
    if converter == nil || sourceRate != packet.sampleRate {
      converter = AVAudioConverter(from: source, to: destination)
      sourceRate = packet.sampleRate
    }
    guard let converter,
      let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: UInt32(packet.pcm.count / 2)),
      let output = AVAudioPCMBuffer(
        pcmFormat: destination,
        frameCapacity: UInt32(ceil(Double(packet.pcm.count / 2) * 24000 / packet.sampleRate)) + 32)
    else { throw WorkspaceError.message("Cannot convert microphone audio.") }
    input.frameLength = input.frameCapacity
    packet.pcm.withUnsafeBytes {
      if let base = $0.baseAddress { memcpy(input.int16ChannelData![0], base, packet.pcm.count) }
    }
    var supplied = false
    var error: NSError?
    converter.convert(to: output, error: &error) { _, status in
      if supplied {
        status.pointee = .noDataNow
        return nil
      }
      supplied = true
      status.pointee = .haveData
      return input
    }
    if let error { throw error }
    return Data(bytes: output.int16ChannelData![0], count: Int(output.frameLength) * 2)
  }
  private func receive() async {
    do {
      while let socket, !Task.isCancelled {
        let message = try await socket.receive()
        let data: Data
        switch message {
        case .string(let value): data = Data(value.utf8)
        case .data(let value): data = value
        @unknown default: continue
        }
        guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let type = event["type"] as? String
        else { continue }
        if type == "session.updated" {
          reconnects = 0
          // Packets arriving during the flush queue behind it, keeping audio in order.
          // On a send failure, keep the rest for the next connection.
          // Take each packet before awaiting: append may evict and close() may clear meanwhile.
          var flushed = true
          while !pending.isEmpty {
            let packet = pending.removeFirst()
            guard await send(packet) else {
              if !closed { pending.insert(packet, at: 0) }
              flushed = false
              break
            }
          }
          ready = flushed
        }
        if type == "input_audio_buffer.committed", let id = event["item_id"] as? String,
          !awaitingWindows.isEmpty
        {
          itemWindows[id] = awaitingWindows.removeFirst()
        }
        if type == "conversation.item.input_audio_transcription.completed",
          let id = event["item_id"] as? String, let text = event["transcript"] as? String,
          let window = itemWindows.removeValue(forKey: id)
        {
          let usage =
            (try? JSONSerialization.data(withJSONObject: event["usage"] ?? [:])) ?? Data("{}".utf8)
          onUsage(id, String(decoding: usage, as: UTF8.self))
          // A pause-only commit is billed but has no words to show.
          if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { onSegment(
            TranscriptSegment(
              id: "live:\(track.rawValue):\(id)", meetingID: meetingID, start: max(0, window.0),
              end: max(0, window.1), text: text, speakerID: "provisional-\(track.rawValue)",
              track: track, provisional: true)) }
        }
        if type == "error" {
          onFailure(
            "Live transcription rejected a request. Saved audio remains available for final transcription."
          )
        }
      }
    } catch {
      guard !Task.isCancelled, !closed else { return }
      // Sessions end (provider limits, network blips); reopen so captions cover the whole meeting.
      receiver = nil  // This task; reset() must not cancel it before the backoff.
      reset()
      reconnects += 1
      guard reconnects <= 5, let (backend, token) = endpoint else {
        onFailure("Live captions disconnected. Local recording continues.")
        close()
        return
      }
      try? await Task.sleep(for: .seconds(min(reconnects, 3)))
      if !closed { connect(backend: backend, token: token) }
    }
  }
  func close() {
    closed = true
    pending = []
    reset()
  }
  private func reset() {
    ready = false
    start = nil
    receiver?.cancel()
    socket?.cancel(with: .normalClosure, reason: nil)
    socket = nil
    awaitingWindows = []
    itemWindows = [:]
  }
}
