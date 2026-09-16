import XCTest
@testable import ChupCore
final class PasteCommandTests: XCTestCase {
  func testOnlyOrdinaryPasteCanBeInvokedWithoutSendingOrExecuting() {
    XCTAssertTrue(PasteCommandPolicy.isPlainPaste(title: "Paste"))
    XCTAssertTrue(PasteCommandPolicy.isPlainPaste(title: "Plakken"))
    for title in ["Paste and Go", "Paste and Execute", "Paste Selection", "Paste and Match Style", "Plakken en zoeken", "Send", ""] {
      XCTAssertFalse(PasteCommandPolicy.isPlainPaste(title: title))
    }
    XCTAssertFalse(PasteCommandPolicy.isPlainPaste(title: nil))
  }
}
