import XCTest
@testable import ChupCore

final class MicrophoneStartupTests: XCTestCase {
  @MainActor func testLateStartupStopRecoversBeforeReportingReady() async throws {
    var running = true, waits = 0, restarts = 0
    try await MicrophoneStartup.settle(isReady: { running }, resumeMatchingInput: {
      restarts += 1
      running = true
    }, wait: {
      waits += 1
      if waits == 1 { running = false } // Notification after start() returned.
    })
    XCTAssertEqual(waits, 2)
    XCTAssertEqual(restarts, 1)
    XCTAssertTrue(running)
  }
  @MainActor func testHealthyStartupNeverRestarts() async throws {
    var restarts = 0
    try await MicrophoneStartup.settle(isReady: { true }, resumeMatchingInput: { restarts += 1 }, wait: {})
    XCTAssertEqual(restarts, 0)
  }
  @MainActor func testChangedDeviceOrFormatIsNotRetried() async {
    enum DeviceChanged: Error { case changed }
    var attempts = 0
    do {
      try await MicrophoneStartup.settle(isReady: { false }, resumeMatchingInput: {
        attempts += 1
        throw DeviceChanged.changed
      }, wait: {})
      XCTFail("Changed input should fail startup")
    } catch DeviceChanged.changed {} catch { XCTFail("Unexpected error: \(error)") }
    XCTAssertEqual(attempts, 1)
  }
  @MainActor func testRepeatedDriverStopsHaveBoundedRecovery() async {
    var attempts = 0
    do {
      try await MicrophoneStartup.settle(isReady: { false }, resumeMatchingInput: { attempts += 1 }, wait: {})
      XCTFail("Unstable capture must not report ready")
    } catch MicrophoneStartup.Failure.didNotSettle {} catch { XCTFail("Unexpected error: \(error)") }
    XCTAssertEqual(attempts, 2)
  }
  @MainActor func testCancellationCannotResumeInput() async {
    var attempts = 0
    let task = Task { @MainActor in
      try await MicrophoneStartup.settle(isReady: { false }, resumeMatchingInput: { attempts += 1 }, wait: {})
    }
    task.cancel()
    do { try await task.value; XCTFail("Cancelled startup should fail") }
    catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    XCTAssertEqual(attempts, 0)
  }
}
