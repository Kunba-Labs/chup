import XCTest
@testable import ChupCore

final class DiagnosticsTests: XCTestCase {
  func testFocusInvalidatesSynchronouslyAcrossCallbacks() {
    let epoch = FocusEpoch()
    let initial = epoch.current
    DispatchQueue.concurrentPerform(iterations: 1000) { _ in epoch.advance() }
    XCTAssertEqual(epoch.current, initial + 1000)
  }
  func testTraceKeepsMissingStagesAndRejectsLateOrInvalidMarks() throws {
    var trace = DictationTrace()
    trace.mark(.requested, elapsed: 0)
    trace.mark(.firstAudio, elapsed: 0.05)
    trace.mark(.firstAudio, elapsed: 4)
    trace.mark(.localStarted, elapsed: .nan)
    trace.mark(.finished, elapsed: 1)
    trace.outcome = .copied
    trace.mark(.localFinished, elapsed: 2)
    XCTAssertEqual(trace.events.count, 3)
    XCTAssertEqual(trace.duration(from: .requested, to: .firstAudio), 50)
    XCTAssertNil(trace.duration(from: .cloudStarted, to: .cloudFinished))
    XCTAssertEqual(try JSONDecoder().decode(DictationTrace.self, from: JSONEncoder().encode(trace)), trace)
  }
}
