import XCTest
@testable import ChupCore

final class DictationTranscriptionModeTests: XCTestCase {
  func testLocalModeNeverAttemptsCloud() {
    for enabled in [true, false] {
      for configured in [true, false] {
        XCTAssertFalse(DictationTranscriptionMode.local.attemptsCloud(cloudEnabled: enabled, configured: configured))
      }
    }
    XCTAssertTrue(DictationTranscriptionMode.local.allowsLocal)
  }
  func testAutomaticHonorsCloudPermissionAndConfiguration() {
    XCTAssertTrue(DictationTranscriptionMode.automatic.attemptsCloud(cloudEnabled: true, configured: true))
    XCTAssertFalse(DictationTranscriptionMode.automatic.attemptsCloud(cloudEnabled: false, configured: true))
    XCTAssertFalse(DictationTranscriptionMode.automatic.attemptsCloud(cloudEnabled: true, configured: false))
    XCTAssertTrue(DictationTranscriptionMode.automatic.allowsLocal)
    XCTAssertFalse(DictationTranscriptionMode.cloud.allowsLocal)
  }
  func testLegacyDictationDecodesAndProviderPersists() throws {
    var entry = DictationEntry(text: "Nee", original: "Nee", application: "Notes", mode: "Verbatim", audioDirectory: "/fixture")
    let old = try JSONEncoder().encode(entry)
    XCTAssertNil(try JSONDecoder().decode(DictationEntry.self, from: old).transcriptionProvider)
    entry.transcriptionProvider = "Local · Whisper large-v3-turbo"
    entry.processingNote = "Plain local transcript"
    XCTAssertEqual(entry, try JSONDecoder().decode(DictationEntry.self, from: JSONEncoder().encode(entry)))
  }
}
