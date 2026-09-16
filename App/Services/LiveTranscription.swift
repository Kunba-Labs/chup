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
    guard ready, let socket else { return }
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
      if let start, lastEnd - start >= 8 {
        awaitingWindows.append((start, lastEnd))
        self.start = nil
        try await socket.send(.string("{\"type\":\"input_audio_buffer.commit\"}"))
      }
    } catch {
      onFailure("Live captions unavailable: \(error.localizedDescription)")
      close()
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
        if type == "session.updated" { ready = true }
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
          onSegment(
            TranscriptSegment(
              id: "live:\(track.rawValue):\(id)", meetingID: meetingID, start: max(0, window.0),
              end: max(0, window.1), text: text, speakerID: "provisional-\(track.rawValue)",
              track: track, provisional: true))
        }
        if type == "error" {
          onFailure(
            "Live transcription rejected a request. Saved audio remains available for final transcription."
          )
        }
      }
    } catch {
      if !Task.isCancelled { onFailure("Live captions disconnected. Local recording continues.") }
      close()
    }
  }
  func close() {
    ready = false
    receiver?.cancel()
    socket?.cancel(with: .normalClosure, reason: nil)
    socket = nil
    awaitingWindows = []
    itemWindows = [:]
  }
}
