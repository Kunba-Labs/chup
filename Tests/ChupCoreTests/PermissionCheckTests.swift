import XCTest
@testable import ChupCore

final class PermissionCheckTests: XCTestCase {
  func testConfirmedPermissionsShowSuccess() {
    XCTAssertEqual(PermissionCheckResult.evaluate([.allowed, .allowed, .allowed]), .enabled)
  }
  func testCaptureOnlyPermissionIsPendingRatherThanFailureOrSuccess() {
    XCTAssertEqual(PermissionCheckResult.evaluate([.allowed, .verifyDuringCapture]), .awaitingCapture)
    XCTAssertEqual(PermissionCheckResult.evaluate([.verifyDuringCapture]), .awaitingCapture)
  }
  func testMissingAccessTakesPrecedenceOverPendingCapture() {
    for state: PermissionState? in [.denied, .restricted, .notRequested, nil] {
      XCTAssertEqual(PermissionCheckResult.evaluate([.allowed, .verifyDuringCapture, state]), .needsAccess)
    }
  }
  func testNoSelectionCannotClaimSuccess() {
    XCTAssertEqual(PermissionCheckResult.evaluate([]), .noSelection)
  }
}
