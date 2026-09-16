import Foundation

/// Five inexpensive, overlapping speech bands for visual feedback only. Runs on
/// the serial audio worker after durable storage, never on the audio render thread.
public struct VoiceSpectrumMeter {
  private var low = [Double](repeating: 0, count: 4)
  private var rate = 0.0
  public init() {}
  public mutating func levels(pcm: UnsafeBufferPointer<Int16>, sampleRate: Double) -> [Float] {
    guard sampleRate.isFinite, sampleRate >= 8000, !pcm.isEmpty else { return Array(repeating: 0, count: 5) }
    if rate != sampleRate { low = Array(repeating: 0, count: 4); rate = sampleRate }
    let coefficients = [250.0, 600, 1400, 3200].map { 1 - exp(-2 * Double.pi * $0 / sampleRate) }
    var energy = [Double](repeating: 0, count: 5)
    for raw in pcm {
      let sample = Double(raw) / 32768
      for band in 0..<4 { low[band] += coefficients[band] * (sample - low[band]) }
      energy[0] += low[0] * low[0]
      for band in 1..<4 {
        let value = low[band] - low[band - 1]
        energy[band] += value * value
      }
      let high = sample - low[3]
      energy[4] += high * high
    }
    return energy.map {
      let rms = sqrt($0 / Double(pcm.count))
      guard rms > 0.0005 else { return 0 }
      // Full headroom to 0 dBFS; normal speech no longer pins every bar at one.
      return Float(min(1, max(0, (20 * log10(rms) + 66) / 66)))
    }
  }
}
