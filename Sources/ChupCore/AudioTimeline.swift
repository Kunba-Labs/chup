import Foundation

/// A packet's position is relative to the meeting, including pauses and source gaps.
public struct PositionedAudio {
  public var start: Double
  public var track: TrackKind
  public var packet: AudioPacket
  public init(start: Double, track: TrackKind, packet: AudioPacket) {
    self.start = start
    self.track = track
    self.packet = packet
  }
}

public enum AudioTimeline {
  /// Bounded offline rendering; never call on an audio I/O callback. Uncaptured time stays silent.
  /// Linear resampling is intended for speech review. Source journals remain unchanged.
  public static func mix(
    _ packets: [PositionedAudio], start: Double, frames: Int, rate: Double = 48000,
    gains: [TrackKind: Float] = [.microphone: 0.5, .remote: 0.5, .assistant: 0.5]
  ) throws -> [Float] {
    guard start.isFinite, start >= 0, rate.isFinite, rate >= 8000, rate <= 192000,
      frames >= 0, frames <= Int(rate * 10),
      gains.values.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 })
    else { throw WorkspaceError.message("Invalid playback window.") }
    var result = [Float](repeating: 0, count: frames)
    let end = start + Double(frames) / rate
    for positioned in packets {
      let packet = positioned.packet
      guard positioned.start.isFinite, packet.sampleRate.isFinite,
        (8000...192000).contains(packet.sampleRate), (1...8).contains(packet.channels),
        packet.pcm.count % (packet.channels * 2) == 0
      else { throw WorkspaceError.corruptJournal }
      guard positioned.start < end, positioned.start + packet.duration > start else { continue }
      let gain = gains[positioned.track] ?? 0
      if gain == 0 { continue }
      let first = max(0, Int(ceil((positioned.start - start) * rate - 0.000001)))
      let last = min(
        frames, Int(ceil((positioned.start + packet.duration - start) * rate - 0.000001)))
      guard first < last else { continue }
      let sampleCount = packet.pcm.count / (2 * packet.channels)
      packet.pcm.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
        func sample(_ frame: Int) -> Float {
          var value: Float = 0
          for channel in 0..<packet.channels {
            let offset = (frame * packet.channels + channel) * 2
            let bits = UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
            value += Float(Int16(bitPattern: bits)) / 32768
          }
          return value / Float(packet.channels)
        }
        for frame in first..<last {
          let position = max(
            0, (start + Double(frame) / rate - positioned.start) * packet.sampleRate)
          let a = min(sampleCount - 1, Int(position))
          let b = min(sampleCount - 1, a + 1)
          let fraction = Float(position - Double(a))
          result[frame] += (sample(a) * (1 - fraction) + sample(b) * fraction) * gain
        }
      }
    }
    return result.map { min(1, max(-1, $0)) }
  }
}
