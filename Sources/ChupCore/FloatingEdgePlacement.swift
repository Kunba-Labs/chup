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
  /// A prompt beside the rail on its docked edge, clear of the rail at full `reach` (expanded
  /// width) or its actual frame when wider (drawer open), centred on it and kept inside the reading area.
  public static func beside(_ rail: CGRect, size: CGSize, visible: CGRect, edge: String,
    reach: CGFloat = 44, gap: CGFloat = 10) -> CGRect {
    func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
      min(max(lower, upper), max(lower, value))
    }
    var x = rail.midX - size.width / 2, y = rail.midY - size.height / 2
    switch edge {
    case "left": x = max(rail.minX + reach, rail.maxX) + gap
    case "bottom": y = max(rail.minY + reach, rail.maxY) + gap
    default: x = min(rail.maxX - reach, rail.minX) - gap - size.width
    }
    return CGRect(x: clamp(x, visible.minX + 8, visible.maxX - size.width - 8),
      y: clamp(y, visible.minY + 8, visible.maxY - size.height - 8),
      width: size.width, height: size.height)
  }
}
