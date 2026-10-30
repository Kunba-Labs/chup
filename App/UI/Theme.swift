import AppKit
import SwiftUI

enum Palette {
  static func color(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        return NSColor(
          srgbRed: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
          blue: Double(hex & 255) / 255, alpha: 1)
      })
  }
  // Voice palette (picked 2026-10-30, docs/PLAN.md increment 10).
  static let workspace = color(0xEEECF4, 0x17161C), paper = color(0xFFFFFF, 0x201F27),
    sidebar = color(0xE6E4F0, 0x1B1A21)
  static let ink = color(0x16151A, 0xF4F3F8), secondary = color(0x615E6D, 0xA9A6B5),
    accent = color(0x5B3DE6, 0xB9A8FF), red = color(0xB03D30, 0xF29A8C)
  static let border = color(0xDCD9E6, 0x34323D)
  static let backdrop = color(0xF5ECE6, 0x121116)
  static let violet = Color(red: 106 / 255, green: 76 / 255, blue: 245 / 255)
  static let coral = Color(red: 232 / 255, green: 115 / 255, blue: 90 / 255)
  static let gradient = LinearGradient(
    colors: [violet, coral], startPoint: .leading, endPoint: .trailing)
  static let title = Font.system(size: 30, weight: .semibold)
  /// Brand gradient sampled at `t` in 0...1, for per-bar waveform fills.
  static func gradient(at t: Double) -> Color {
    let t = min(1, max(0, t))
    return Color(
      red: (106 + (232 - 106) * t) / 255, green: (76 + (115 - 76) * t) / 255,
      blue: (245 + (90 - 245) * t) / 255)
  }
  /// Stable per-speaker colour. Keyed by speaker ID so a rename keeps the colour;
  /// FNV-1a because Swift's `hashValue` is reseeded every launch.
  static func speaker(_ id: String) -> Color {
    let hues: [UInt32] = [0x6A4CF5, 0xD9573F, 0x1F8A70, 0xC2387D, 0x2F6FD6, 0xA46A12, 0x7A4FB0]
    let hash = id.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
    let hex = hues[Int(hash % UInt32(hues.count))]
    return color(hex, hex)
  }
}
struct WaveMark: View {
  var color: Color?
  var body: some View {
    let heights = [12.0, 22, 30, 20, 11]
    HStack(spacing: 3) {
      ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
        Capsule().fill(color ?? Palette.gradient(at: Double(index) / Double(heights.count - 1)))
          .frame(width: 5, height: height)
      }
    }.accessibilityHidden(true)
  }
}
struct QuietEmpty: View {
  var icon: String
  var title: String
  var subtitle: String
  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: icon).font(.system(size: 32, weight: .ultraLight)).foregroundStyle(
        Palette.accent)
      Text(title).font(.system(size: 25, weight: .semibold))
      Text(subtitle).font(.system(size: 14)).foregroundStyle(Palette.secondary)
        .multilineTextAlignment(.center).frame(maxWidth: 370)
    }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
struct SourceMeter: View {
  var name: String
  var level: Float
  var receiving: Bool
  var body: some View {
    HStack(spacing: 7) {
      Image(systemName: receiving ? "waveform" : "waveform.slash")
      Text(name)
      GeometryReader { g in
        Capsule().fill(Palette.border).overlay(alignment: .leading) {
          Capsule().fill(Palette.accent).frame(
            width: g.size.width * CGFloat(min(1, max(0.02, level))))
        }
      }.frame(width: 42, height: 4)
    }.font(.caption).foregroundStyle(Palette.secondary).accessibilityLabel(
      "\(name): \(receiving ? "receiving audio" : "no audio packets")")
  }
}

/// Shared reading/control surface. Group one decision or task, not every label.
struct WorkspaceCard<Content: View>: View {
  var title: String?
  var subtitle: String?
  var icon: String?
  @ViewBuilder var content: Content
  init(
    _ title: String? = nil, subtitle: String? = nil, icon: String? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.subtitle = subtitle
    self.icon = icon
    self.content = content()
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if let title {
        HStack(alignment: .top, spacing: 12) {
          if let icon {
            Image(systemName: icon).font(.system(size: 17, weight: .medium))
              .foregroundStyle(Palette.accent).frame(width: 30, height: 30)
              .background(Palette.sidebar.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
              .accessibilityHidden(true)
          }
          VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.ink)
              .accessibilityAddTraits(.isHeader)
            if let subtitle {
              Text(subtitle).font(.callout).foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
            }
          }
        }
      }
      content
    }.frame(maxWidth: .infinity, alignment: .leading).padding(22).workspaceSurface()
  }
}

extension View {
  func workspaceSurface() -> some View {
    self.background(Palette.paper, in: RoundedRectangle(cornerRadius: 16))
      .overlay {
        RoundedRectangle(cornerRadius: 16).strokeBorder(
          Palette.border.opacity(0.6), lineWidth: 0.75
        ).allowsHitTesting(false)
      }
  }
  func insetSurface() -> some View {
    self.padding(16).frame(maxWidth: .infinity, alignment: .leading)
      .background(Palette.workspace, in: RoundedRectangle(cornerRadius: 10))
  }
}

struct SettingSwitch: View {
  let title: String
  var detail: String?
  @Binding var isOn: Bool
  var body: some View {
    Toggle(isOn: $isOn) {
      VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.system(size: 13, weight: .medium))
        if let detail {
          Text(detail).font(.callout).foregroundStyle(Palette.secondary).fixedSize(
            horizontal: false, vertical: true
          ).lineSpacing(3)
        }
      }.padding(.trailing, 12)
    }.toggleStyle(.switch).controlSize(.small)
  }
}

struct DetailDisclosure: View {
  let title: String
  let text: String
  var body: some View {
    DisclosureGroup(title) {
      Text(text).font(.callout).foregroundStyle(Palette.secondary).lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true).frame(
          maxWidth: .infinity, alignment: .leading
        )
        .padding(.top, 8)
    }.font(.callout).foregroundStyle(Palette.secondary)
  }
}

struct InlineStatus: View {
  let text: String
  var icon = "info.circle"
  var warning = false
  var body: some View {
    Label {
      Text(text).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
    } icon: {
      Image(systemName: icon)
    }
    .font(.callout).foregroundStyle(warning ? Palette.red : Palette.secondary)
    .frame(maxWidth: .infinity, alignment: .leading).insetSurface()
  }
}
