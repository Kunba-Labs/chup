import XCTest
@testable import ChupCore

final class FocusedPasteTests: XCTestCase {
  func testSelectsPasteByCapabilitiesInsteadOfApplicationName() {
    XCTAssertTrue(FocusedPastePolicy.supports(role: "AXTextArea"))
    XCTAssertTrue(FocusedPastePolicy.supports(role: "AXTextField"))
    XCTAssertTrue(FocusedPastePolicy.supports(role: "AXComboBox"))
    XCTAssertFalse(FocusedPastePolicy.supports(role: "AXWindow"))
    XCTAssertFalse(FocusedPastePolicy.supports(role: "AXStaticText"))
    XCTAssertTrue(FocusedPastePolicy.requiresFocusedPaste(canWriteSelection: false, canWriteValue: false, hasSelectionSnapshot: true))
    XCTAssertTrue(FocusedPastePolicy.requiresFocusedPaste(canWriteSelection: true, canWriteValue: true, hasSelectionSnapshot: false))
    XCTAssertFalse(FocusedPastePolicy.requiresFocusedPaste(canWriteSelection: true, canWriteValue: false, hasSelectionSnapshot: true))
    XCTAssertFalse(FocusedPastePolicy.requiresFocusedPaste(canWriteSelection: false, canWriteValue: true, hasSelectionSnapshot: true))
  }
  func testOpaqueInputControlsCannotExecuteAutomatically() {
    XCTAssertTrue(FocusedPastePolicy.allowsAutomaticPaste("Test USB microphones, niet verzenden."))
    for text in ["", "echo hello\n", "hello\r", "a\t", "\u{1b}[200~", "x\u{7f}", "a\u{2028}b"] {
      XCTAssertFalse(FocusedPastePolicy.allowsAutomaticPaste(text))
    }
  }
  func testEveryFocusedDestinationGuardMustHold() {
    func allowed(_ flags: [Bool]) -> Bool {
      FocusedPastePolicy.canPaste(samePane: flags[0], sameWindow: flags[1], sameFocusEpoch: flags[2],
        sameInteractionEpoch: flags[3], monitoring: flags[4], secureInput: !flags[5], selectionEmpty: flags[6])
    }
    XCTAssertTrue(allowed(Array(repeating: true, count: 7)))
    for i in 0..<7 {
      var flags = Array(repeating: true, count: 7); flags[i] = false
      XCTAssertFalse(allowed(flags))
    }
  }
  func testRenderedTextConfirmationDoesNotUseSelectionAsCaret() {
    XCTAssertTrue(FocusedPastePolicy.confirms(before: "history\n$ ", after: "history\n$ hello", text: "hello"))
    XCTAssertTrue(FocusedPastePolicy.confirms(before: "$ abcXYZ", after: "$ abcXheyXYZ", text: "Xhey"))
    XCTAssertTrue(FocusedPastePolicy.confirms(before: "$ ", after: "$ micro\nphones", text: "microphones"))
    XCTAssertFalse(FocusedPastePolicy.confirms(before: "$ hello", after: "$ hello", text: "hello"))
    XCTAssertFalse(FocusedPastePolicy.confirms(before: "$ ", after: "$ other output", text: "hello"))
    XCTAssertFalse(FocusedPastePolicy.confirms(before: "$ ", after: "redraw hello", text: "hello"))
  }
}
