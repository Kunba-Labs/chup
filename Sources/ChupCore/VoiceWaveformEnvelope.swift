import Foundation

/// Recent microphone peaks mapped to a useful visual range. This affects only
/// the meter: it never changes recorded audio, gain or speech classification.
public struct VoiceWaveformEnvelope {
  public private(set) var bars: [Float] = Array(repeating: 0, count: 5)
  public init() {}
  public static func amplitude(_ peak: Float) -> Float {
    guard peak.isFinite, peak > 0.002 else { return 0 }
    return min(1, max(0, (20 * log10(min(1, peak)) + 54) / 42))
  }
  public mutating func receive(_ peak: Float) {
    bars.removeFirst()
    bars.append(Self.amplitude(peak))
  }
  public mutating func reset() { bars = Array(repeating: 0, count: 5) }
}
