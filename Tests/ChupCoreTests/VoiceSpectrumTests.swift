import XCTest
@testable import ChupCore

final class VoiceSpectrumTests: XCTestCase {
  func levels(frequency: Double, amplitude: Double, meter: inout VoiceSpectrumMeter) -> [Float] {
    let samples = (0..<4800).map { Int16(sin(Double($0) * frequency * 2 * .pi / 48000) * amplitude * 32767) }
    return samples.withUnsafeBufferPointer { meter.levels(pcm: $0, sampleRate: 48000) }
  }
  func testFrequencyChangesMoveDifferentBars() {
    var low = VoiceSpectrumMeter(), high = VoiceSpectrumMeter()
    let bass = levels(frequency: 100, amplitude: 0.1, meter: &low)
    let treble = levels(frequency: 6000, amplitude: 0.1, meter: &high)
    XCTAssertGreaterThan(bass[0], bass[4])
    XCTAssertGreaterThan(treble[4], treble[0])
    XCTAssertNotEqual(bass, treble)
  }
  func testOrdinaryLoudSpeechRetainsVisualHeadroomAndSilenceSettles() {
    var meter = VoiceSpectrumMeter()
    let medium = levels(frequency: 800, amplitude: 0.3, meter: &meter)
    let loud = levels(frequency: 800, amplitude: 0.8, meter: &meter)
    XCTAssertTrue(medium.allSatisfy { $0 < 1 })
    XCTAssertGreaterThan(loud.max()!, medium.max()!)
    _ = levels(frequency: 800, amplitude: 0, meter: &meter)
    XCTAssertEqual(levels(frequency: 800, amplitude: 0, meter: &meter), [0, 0, 0, 0, 0])
  }
}
