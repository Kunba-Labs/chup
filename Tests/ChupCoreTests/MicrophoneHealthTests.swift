import XCTest
@testable import ChupCore

final class MicrophoneHealthTests: XCTestCase {
  let builtIn = MicrophoneCandidate(id: "built", builtIn: true, physicalExternal: false, available: true)
  let usb = MicrophoneCandidate(id: "usb", builtIn: false, physicalExternal: true, available: true)
  func testClosedLidUsesSingleExternalOnlyInAutomaticMode() throws {
    XCTAssertEqual(try MicrophoneSelectionPolicy.choose([builtIn, usb], preferred: "", systemDefault: "built", lidClosed: true), "usb")
    XCTAssertThrowsError(try MicrophoneSelectionPolicy.choose([builtIn, usb], preferred: "built", systemDefault: "built", lidClosed: true))
    XCTAssertEqual(try MicrophoneSelectionPolicy.choose([builtIn, usb], preferred: "usb", systemDefault: "built", lidClosed: true), "usb")
  }
  func testUnknownLidDoesNotGuessClosedAndExplicitMissingDoesNotSilentlySwitch() throws {
    XCTAssertEqual(try MicrophoneSelectionPolicy.choose([builtIn, usb], preferred: "", systemDefault: "built", lidClosed: nil), "built")
    XCTAssertThrowsError(try MicrophoneSelectionPolicy.choose([builtIn], preferred: "usb", systemDefault: "built", lidClosed: false))
  }
  func testAmbiguousVirtualAndUnavailableAlternativesAreNotChosen() {
    let bluetooth = MicrophoneCandidate(id: "bt", builtIn: false, physicalExternal: true, available: true)
    let virtual = MicrophoneCandidate(id: "loopback", builtIn: false, physicalExternal: false, available: true)
    let gone = MicrophoneCandidate(id: "gone", builtIn: false, physicalExternal: true, available: false)
    XCTAssertThrowsError(try MicrophoneSelectionPolicy.choose([builtIn, usb, bluetooth], preferred: "", systemDefault: "built", lidClosed: true))
    XCTAssertThrowsError(try MicrophoneSelectionPolicy.choose([builtIn, virtual, gone], preferred: "", systemDefault: "built", lidClosed: true))
  }
  func testQuietPacketsAndSourceLossAreDifferentAndSpeechClearsWarning() {
    var health = MicrophoneSignalHealth()
    health.start(at: 10)
    XCTAssertEqual(health.status(at: 12), .starting)
    health.receive(peak: 0, at: 13)
    XCTAssertEqual(health.status(at: 13), .quiet)
    health.receive(peak: 0.001, at: 13.1)
    XCTAssertEqual(health.status(at: 13.1), .receiving)
    XCTAssertEqual(health.status(at: 16), .missingPackets)
    health.start(at: 20)
    XCTAssertEqual(health.status(at: 21), .starting)
  }
}
