import XCTest
import CoreGraphics
@testable import ChupCore

final class FloatingEdgePlacementTests: XCTestCase {
  func testRightEdgeIgnoresReservedDockSpace() {
    let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    let visible = CGRect(x: 0, y: 0, width: 1520, height: 976)
    for width in [10.0, 26, 36, 44, 300, 320] {
      let result = FloatingEdgePlacement.frame(size: CGSize(width: width, height: 148),
        screen: screen, visible: visible, edge: "right")
      XCTAssertEqual(result.maxX, 1598)
      XCTAssertTrue(screen.contains(result))
    }
  }
  func testSecondaryDisplayCoordinatesAndDraggedAnchor() {
    let screen = CGRect(x: -1920, y: -100, width: 1920, height: 1080)
    let visible = CGRect(x: -1860, y: -100, width: 1860, height: 1056)
    let result = FloatingEdgePlacement.frame(size: CGSize(width: 36, height: 148),
      screen: screen, visible: visible, edge: "left", along: 5000)
    XCTAssertEqual(result.minX, -1918)
    XCTAssertEqual(result.maxY, visible.maxY - 8)
    XCTAssertTrue(screen.contains(result))
  }
  func testBottomKeepsDockClearAndConcurrentPanelKeepsSeparation() {
    let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    let visible = CGRect(x: 0, y: 70, width: 1600, height: 906)
    let bottom = FloatingEdgePlacement.frame(size: CGSize(width: 148, height: 36),
      screen: screen, visible: visible, edge: "bottom", along: -100)
    XCTAssertEqual(bottom.minX, 8)
    XCTAssertEqual(bottom.minY, 72)
    let alongside = FloatingEdgePlacement.frame(size: CGSize(width: 320, height: 100),
      screen: screen, visible: visible, edge: "right", inset: 52)
    XCTAssertEqual(alongside.maxX, screen.maxX - 52)
  }
}
