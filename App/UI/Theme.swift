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
  static let workspace = color(0xF7F3EB, 0x211F1B), paper = color(0xFFFCF6, 0x2A2722),
    sidebar = color(0xEEE7DC, 0x25231E)
  static let ink = color(0x29251F, 0xF7F3EB), secondary = color(0x70675D, 0xBEB5A7),
    olive = color(0x626C4C, 0xB4C396), red = color(0x9C4437, 0xF29A8C)
  static let border = color(0xDED6C9, 0x494237)
  static let title = Font.system(size: 32, weight: .regular, design: .serif)
}
struct WaveMark: View {
  var color: Color = Palette.olive
  var body: some View {
    HStack(spacing: 3) {
      ForEach(Array([10.0, 19, 29, 38, 29, 19, 10].enumerated()), id: \.offset) { _, height in
        Capsule().fill(color).frame(width: 4, height: height)
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
        Palette.olive)
      Text(title).font(.system(size: 25, design: .serif))
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
          Capsule().fill(Palette.olive).frame(
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
              .foregroundStyle(Palette.olive).frame(width: 30, height: 30)
              .background(Palette.sidebar.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
              .accessibilityHidden(true)
          }
          VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 20, design: .serif)).foregroundStyle(Palette.ink)
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
