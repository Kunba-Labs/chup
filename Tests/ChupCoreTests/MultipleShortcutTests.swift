import XCTest

@testable import ChupCore

final class MultipleShortcutTests: XCTestCase {
  func testLegacyBindingsAcquireStableUniqueIdentitiesWithoutLosingGestures() throws {
    let source = [
      ShortcutBinding(.holdDictation, .fn, hold: true),
      .init(.holdDictation, [.control, .shift], hold: true),
    ]
    var values =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as! [[String: Any]]
    for i in values.indices { values[i].removeValue(forKey: "id") }
    let decoded = try JSONDecoder().decode(
      [ShortcutBinding].self, from: JSONSerialization.data(withJSONObject: values))
    XCTAssertEqual(Set(decoded.map(\.id)).count, 2)
    XCTAssertEqual(decoded.map(\.label), source.map(\.label))
    XCTAssertEqual(
      try JSONDecoder().decode([ShortcutBinding].self, from: JSONEncoder().encode(decoded)), decoded
    )
  }
  func testEachAlternativeStartsAndFinishesExactlyOnce() {
    let fn = ShortcutBinding(.holdDictation, .fn, hold: true)
    let external = ShortcutBinding(.holdDictation, [.control, .shift], hold: true)
    var resolver = ShortcutResolver(bindings: [fn, external])
    for (index, binding) in [fn, external, fn, external].enumerated() {
      let start = Double(index * 2)
      XCTAssertTrue(resolver.update(modifiers: binding.modifiers, keys: [], time: start).isEmpty)
      XCTAssertEqual(
        resolver.update(modifiers: binding.modifiers, keys: [], time: start + 0.2),
        [.init(action: .holdDictation, began: true)])
      XCTAssertTrue(
        resolver.update(modifiers: binding.modifiers, keys: [], time: start + 0.4).isEmpty)
      XCTAssertEqual(
        resolver.update(modifiers: [], keys: [], time: start + 0.6),
        [.init(action: .holdDictation, began: false)])
    }
  }
  func testNavigationKeysCannotPromoteModifierOnlyDictationHold() {
    let hold = ShortcutBinding(.holdDictation, [.control, .shift], hold: true)
    var resolver = ShortcutResolver(bindings: [hold])
    XCTAssertTrue(resolver.update(modifiers: [.control, .shift], keys: [], time: 0).isEmpty)
    // Right/left arrows arrive as ordinary key events while modifiers remain held.
    XCTAssertTrue(resolver.update(modifiers: [.control, .shift], keys: [124], time: 0.05).isEmpty)
    XCTAssertTrue(resolver.update(modifiers: [.control, .shift], keys: [], time: 0.25).isEmpty)
    XCTAssertTrue(resolver.update(modifiers: [.control, .shift], keys: [123], time: 0.30).isEmpty)
    XCTAssertTrue(resolver.update(modifiers: [.control, .shift], keys: [], time: 0.50).isEmpty)
    XCTAssertTrue(resolver.update(modifiers: [], keys: [], time: 0.60).isEmpty)
    // A clean hold after the navigation keys still works.
    XCTAssertTrue(resolver.update(modifiers: [.control, .shift], keys: [], time: 1.0).isEmpty)
    XCTAssertEqual(
      resolver.update(modifiers: [.control, .shift], keys: [], time: 1.2),
      [.init(action: .holdDictation, began: true)])
  }
  func testArrowKeyWhoseFunctionFlagArrivesLateCannotStartTheFnHold() {
    let hold = ShortcutBinding(.holdDictation, .fn, hold: true)
    var resolver = ShortcutResolver(bindings: [hold])
    // macOS stamps the Fn flag onto arrow keys nobody pressed Fn for, and the
    // flag can land on the key-up, or on the session state, rather than on the
    // key-down that would otherwise fence the hold off.
    XCTAssertTrue(resolver.update(modifiers: [], keys: [125], time: 0).isEmpty)
    XCTAssertTrue(resolver.update(modifiers: [.fn], keys: [], time: 0.02).isEmpty)
    XCTAssertTrue(resolver.update(modifiers: [.fn], keys: [], time: 0.30).isEmpty)
    XCTAssertTrue(resolver.update(modifiers: [], keys: [], time: 0.40).isEmpty)
    // The real gesture still works once everything is released.
    XCTAssertTrue(resolver.update(modifiers: [.fn], keys: [], time: 1.0).isEmpty)
    XCTAssertEqual(
      resolver.update(modifiers: [.fn], keys: [], time: 1.2),
      [.init(action: .holdDictation, began: true)])
  }
  func testCaptureRetainsFullModifierAndOrdinaryChordsDuringPartialRelease() {
    var capture = ShortcutCapture()
    for modifiers: KeyModifiers in [.control, [.control, .shift], .shift, []] {
      capture.update(
        action: .holdDictation, modifiers: modifiers, keys: [], buttons: [], hold: true)
    }
    XCTAssertEqual(capture.candidate?.modifiers, [.control, .shift])
    XCTAssertNil(capture.candidate?.keyCode)
    capture = ShortcutCapture()
    capture.update(
      action: .meeting, modifiers: [.control, .shift], keys: [46], buttons: [], hold: false)
    capture.update(action: .meeting, modifiers: .shift, keys: [46], buttons: [], hold: false)
    capture.update(action: .meeting, modifiers: [], keys: [46], buttons: [], hold: false)
    capture.update(action: .meeting, modifiers: [], keys: [], buttons: [], hold: false)
    XCTAssertEqual(capture.candidate?.modifiers, [.control, .shift])
    XCTAssertEqual(capture.candidate?.keyCode, 46)
  }
  func testIndependentToggleAliasesDoNotClearEachOthersRepeatLatch() {
    let a = ShortcutBinding(.toggleDictation, .fn, keyCode: 49)
    let b = ShortcutBinding(.toggleDictation, [.control, .shift], keyCode: 49)
    var resolver = ShortcutResolver(bindings: [a, b])
    XCTAssertEqual(
      resolver.update(modifiers: .fn, keys: [49], time: 0),
      [.init(action: .toggleDictation, began: true)])
    XCTAssertTrue(resolver.update(modifiers: .fn, keys: [49], time: 0.2).isEmpty)
    _ = resolver.update(modifiers: [], keys: [], time: 0.3)
    XCTAssertEqual(
      resolver.update(modifiers: [.control, .shift], keys: [49], time: 0.4),
      [.init(action: .toggleDictation, began: true)])
    XCTAssertTrue(resolver.update(modifiers: [.control, .shift], keys: [49], time: 0.5).isEmpty)
  }
  func testOverlappingSameActionHoldsHandOverWithoutDuplicateSignals() {
    var resolver = ShortcutResolver(bindings: [
      .init(.holdDictation, .fn, hold: true),
      .init(.holdDictation, [.control, .shift], hold: true),
    ])
    _ = resolver.update(modifiers: .fn, keys: [], time: 0)
    XCTAssertEqual(
      resolver.update(modifiers: .fn, keys: [], time: 0.2),
      [.init(action: .holdDictation, began: true)])
    XCTAssertTrue(resolver.update(modifiers: [.fn, .control, .shift], keys: [], time: 0.3).isEmpty)
    XCTAssertTrue(resolver.update(modifiers: [.control, .shift], keys: [], time: 0.4).isEmpty)
    XCTAssertEqual(
      resolver.update(modifiers: [], keys: [], time: 0.5),
      [.init(action: .holdDictation, began: false)])
  }
  func testPromotedPrefixStaysSuppressedDespiteUnheldSiblingBinding() {
    var resolver = ShortcutResolver(
      bindings: ShortcutBinding.standard + [.init(.holdDictation, [.control, .shift], hold: true)])
    _ = resolver.update(modifiers: .fn, keys: [], time: 0)
    _ = resolver.update(modifiers: .fn, keys: [], time: 0.2)
    XCTAssertEqual(
      resolver.update(modifiers: .fn, keys: [49], time: 0.3),
      [
        .init(action: .holdDictation, began: false, cancelled: true),
        .init(action: .toggleDictation, began: true),
      ])
    XCTAssertTrue(resolver.update(modifiers: .fn, keys: [], time: 0.4).isEmpty)
    XCTAssertTrue(resolver.update(modifiers: .fn, keys: [], time: 0.8).isEmpty)
    _ = resolver.update(modifiers: [], keys: [], time: 1)
    _ = resolver.update(modifiers: [.control, .shift], keys: [], time: 1.1)
    XCTAssertEqual(
      resolver.update(modifiers: [.control, .shift], keys: [], time: 1.4),
      [.init(action: .holdDictation, began: true)])
    XCTAssertEqual(resolver.reset(), [.init(action: .holdDictation, began: false, cancelled: true)])
  }
  func testDuplicateGesturesConflictButSameActionAlternatesAreAllowed() {
    let fn = ShortcutBinding(.holdDictation, .fn, hold: true)
    let external = ShortcutBinding(.holdDictation, [.control, .shift], hold: true)
    XCTAssertTrue(ShortcutBinding.conflicts([fn, external]).isEmpty)
    XCTAssertFalse(ShortcutBinding.conflicts([fn, .init(.holdDictation, .fn, hold: true)]).isEmpty)
    XCTAssertFalse(
      ShortcutBinding.conflicts([fn, external, .init(.meeting, [.control, .shift])]).isEmpty)
    var capture = ShortcutCapture()
    capture.update(action: .meeting, modifiers: .control, keys: [0, 1], buttons: [], hold: false)
    XCTAssertTrue(capture.invalid)
  }
  func testMouseAliasesReleaseAndDoNotSuppressTheirSiblings() {
    var resolver = ShortcutResolver(bindings: [
      .init(.holdDictation, [], mouseButton: 3, hold: true),
      .init(.holdDictation, [], mouseButton: 4, hold: true),
    ])
    _ = resolver.update(modifiers: [], keys: [], buttons: [3], time: 0)
    XCTAssertEqual(
      resolver.update(modifiers: [], keys: [], buttons: [3], time: 0.2),
      [.init(action: .holdDictation, began: true)])
    XCTAssertEqual(
      resolver.update(modifiers: [], keys: [], buttons: [], time: 0.3),
      [.init(action: .holdDictation, began: false)])
    _ = resolver.update(modifiers: [], keys: [], buttons: [4], time: 0.4)
    XCTAssertEqual(
      resolver.update(modifiers: [], keys: [], buttons: [4], time: 0.7),
      [.init(action: .holdDictation, began: true)])
    resolver.suspended = true
    XCTAssertEqual(
      resolver.update(modifiers: [], keys: [], buttons: [4], time: 0.8),
      [.init(action: .holdDictation, began: false, cancelled: true)])
  }
}
