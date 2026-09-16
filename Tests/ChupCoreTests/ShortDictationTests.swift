import XCTest
@testable import ChupCore
final class ShortDictationTests: XCTestCase {
  func testShortSilenceAndConfidentNoiseAreIgnored() {
    XCTAssertTrue(ShortDictationPolicy.ignore(duration: 0, peak: 0, speechConfidence: nil, noiseConfidence: nil))
    XCTAssertTrue(ShortDictationPolicy.ignore(duration: 1, peak: 0.00001, speechConfidence: nil, noiseConfidence: nil))
    XCTAssertTrue(ShortDictationPolicy.ignore(duration: 1.5, peak: 0.3, speechConfidence: 0.001, noiseConfidence: 0.96))
  }
  func testQuietShortWordsAndUnknownClassificationAreKept() {
    XCTAssertFalse(ShortDictationPolicy.ignore(duration: 0.3, peak: 0.001, speechConfidence: 0.8, noiseConfidence: 0.9))
    XCTAssertFalse(ShortDictationPolicy.ignore(duration: 0.3, peak: 0.001, speechConfidence: nil, noiseConfidence: nil))
    XCTAssertFalse(ShortDictationPolicy.ignore(duration: 0.8, peak: 0.5, speechConfidence: 0.02, noiseConfidence: 0.5))
  }
  func testLongOrInvalidClipsAreNeverHidden() {
    for duration in [2.01, .nan, .infinity, -1] {
      XCTAssertFalse(ShortDictationPolicy.ignore(duration: duration, peak: 0, speechConfidence: 0, noiseConfidence: 1))
    }
    XCTAssertFalse(ShortDictationPolicy.ignore(duration: 1, peak: .nan, speechConfidence: 0, noiseConfidence: 1))
    XCTAssertFalse(ShortDictationPolicy.ignore(duration: 1, peak: 0.5, speechConfidence: -.infinity, noiseConfidence: 1))
  }
}
