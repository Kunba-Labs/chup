import Foundation
import CoreGraphics

public enum FloatingEdgePlacement {
  /// Side controls follow the physical display edge, even when the Dock reserves
  /// part of visibleFrame. The reading area still bounds their vertical position.
  public static func frame(size: CGSize, screen: CGRect, visible: CGRect, edge: String,
    along: CGFloat? = nil, inset: CGFloat = 2) -> CGRect {
    func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
      min(max(lower, upper), max(lower, value))
    }
    let y = clamp(along ?? visible.midY - size.height / 2,
      visible.minY + 8, visible.maxY - size.height - 8)
    switch edge {
    case "left": return CGRect(x: screen.minX + inset, y: y, width: size.width, height: size.height)
    case "bottom":
      return CGRect(x: clamp(along ?? visible.midX - size.width / 2,
        visible.minX + 8, visible.maxX - size.width - 8),
        y: visible.minY + inset, width: size.width, height: size.height)
    default: return CGRect(x: screen.maxX - size.width - inset, y: y, width: size.width, height: size.height)
    }
  }
}
