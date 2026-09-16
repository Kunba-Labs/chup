import XCTest
@testable import ChupCore

final class VoiceWaveformTests: XCTestCase {
  func testQuietSpeechIsVisibleWithoutAnimatingSilence() {
    XCTAssertEqual(VoiceWaveformEnvelope.amplitude(0), 0)
    XCTAssertEqual(VoiceWaveformEnvelope.amplitude(0.001), 0)
    XCTAssertGreaterThan(VoiceWaveformEnvelope.amplitude(0.01), 0.3)
    XCTAssertGreaterThan(VoiceWaveformEnvelope.amplitude(0.1), VoiceWaveformEnvelope.amplitude(0.01))
    XCTAssertEqual(VoiceWaveformEnvelope.amplitude(10), 1)
  }
  func testNonFiniteOrNegativeMeterInputIsSilent() {
    for input: Float in [.nan, .infinity, -.infinity, -1] {
      XCTAssertEqual(VoiceWaveformEnvelope.amplitude(input), 0)
    }
  }
  func testHistoryFollowsPacketsAndSettlesWhenSpeechStops() {
    var meter = VoiceWaveformEnvelope()
    meter.receive(0.01)
    meter.receive(0.08)
    XCTAssertEqual(meter.bars[3], VoiceWaveformEnvelope.amplitude(0.01))
    XCTAssertEqual(meter.bars[4], VoiceWaveformEnvelope.amplitude(0.08))
    for _ in 0..<5 { meter.receive(0) }
    XCTAssertEqual(meter.bars, [0, 0, 0, 0, 0])
    meter.receive(0.1)
    meter.reset()
    XCTAssertEqual(meter.bars, [0, 0, 0, 0, 0])
  }
}
