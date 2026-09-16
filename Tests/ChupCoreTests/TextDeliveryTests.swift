import XCTest
@testable import ChupCore

final class TextDeliveryTests: XCTestCase {
  func testDispatchedPasteWithoutReadbackUsesQuietCompletion() {
    let result = TextDeliveryPolicy.afterDispatch(confirmed: false, dispatched: true, recovery: .copied)
    XCTAssertEqual(result, .sentToApplication)
    XCTAssertTrue(result.isCompactCompletion)
    XCTAssertNotEqual(result, .inserted)
    XCTAssertEqual(TextDeliveryPolicy.afterDispatch(confirmed: true, dispatched: true, recovery: .copied), .inserted)
  }
  func testUncertainOrFailedDeliveryDoesNotBecomeQuietSuccess() {
    XCTAssertEqual(TextDeliveryPolicy.afterDispatch(confirmed: false, dispatched: false, recovery: .copied), .unconfirmedCopied)
    for recovery in [TextDeliveryResult.clipboardChanged, .copyFailed, .cancelled] {
      XCTAssertEqual(TextDeliveryPolicy.afterDispatch(confirmed: false, dispatched: true, recovery: recovery), recovery)
      XCTAssertFalse(recovery.isCompactCompletion)
    }
    XCTAssertFalse(TextDeliveryResult.copied.isCompactCompletion)
  }
  func testInsertionAndReplacementUseUTF16Selection() {
    XCTAssertEqual(TextDeliveryPolicy.expectedValue(original: "Hello world", location: 6, length: 5, text: "Mac"), "Hello Mac")
    XCTAssertEqual(TextDeliveryPolicy.expectedValue(original: "😀 ok", location: 3, length: 2, text: "nee"), "😀 nee")
    XCTAssertEqual(TextDeliveryPolicy.expectedValue(original: "", location: 0, length: 0, text: "Hello"), "Hello")
  }
  func testInvalidSelectionNeverCreatesAnInsertionExpectation() {
    for (location, length) in [(-1, 0), (0, -1), (50, 0), (1, Int.max), (1, 0)] {
      XCTAssertNil(TextDeliveryPolicy.expectedValue(original: "😀", location: location, length: length, text: "x"))
    }
  }
  func testRecoveryMessagesDoNotClaimUnverifiedSuccess() {
    XCTAssertEqual(TextDeliveryResult.copied.message, "Copied to clipboard · Paste manually into the intended field")
    XCTAssertEqual(TextDeliveryResult.unconfirmedCopied.title, "Paste not confirmed")
    XCTAssertFalse(TextDeliveryResult.copyFailed.message.contains("Copied to clipboard"))
    XCTAssertFalse(TextDeliveryResult.clipboardChanged.message.contains("Copied to clipboard"))
  }
}
