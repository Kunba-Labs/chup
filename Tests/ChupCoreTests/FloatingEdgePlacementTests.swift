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
  func testPromptSitsBesideRailClearOfItsExpandedWidth() {
    let visible = CGRect(x: 0, y: 0, width: 1600, height: 976)
    let size = CGSize(width: 380, height: 70)
    let right = FloatingEdgePlacement.beside(CGRect(x: 1590, y: 400, width: 10, height: 36),
      size: size, visible: visible, edge: "right")
    XCTAssertEqual(right.maxX, 1600 - 44 - 10)
    XCTAssertEqual(right.midY, 418)
    let left = FloatingEdgePlacement.beside(CGRect(x: 0, y: 950, width: 10, height: 36),
      size: size, visible: visible, edge: "left")
    XCTAssertEqual(left.minX, 54)
    XCTAssertEqual(left.maxY, visible.maxY - 8)
    let bottom = FloatingEdgePlacement.beside(CGRect(x: 800, y: 2, width: 36, height: 10),
      size: size, visible: visible, edge: "bottom")
    XCTAssertEqual(bottom.minY, 56)
    XCTAssertEqual(bottom.midX, 818)
  }
  func testPromptClearsAnOpenDrawer() {
    let visible = CGRect(x: 0, y: 0, width: 1600, height: 976)
    let drawer = CGRect(x: 1300, y: 300, width: 300, height: 230)
    let right = FloatingEdgePlacement.beside(drawer, size: CGSize(width: 380, height: 70),
      visible: visible, edge: "right")
    XCTAssertEqual(right.maxX, 1290)
  }
}
