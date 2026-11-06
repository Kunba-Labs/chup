import AppKit
import SwiftUI

/// The whole type scale (design pass 2026-11-06): SF Pro at macOS sizes. Use these, not
/// `.system(size:)`; weight changes go through `.weight(_:)`. Icons size themselves.
extension Font {
  /// Page and meeting titles.
  static let pageTitle = Font.system(size: 26, weight: .bold)
  /// Sheet titles and empty-state titles.
  static let sectionTitle = Font.system(size: 20, weight: .semibold)
  /// Section headings inside a page or card.
  static let heading = Font.system(size: 15, weight: .semibold)
  /// Long-form reading text: notes, summaries, transcript lines.
  static let reading = Font.system(size: 15)
  /// Interface text: controls, list rows, labels. macOS body size.
  static let ui = Font.system(size: 13)
  /// Secondary detail: metadata, descriptions, captions.
  static let detail = Font.system(size: 11)
  /// Badges and counters only.
  static let micro = Font.system(size: 10, weight: .medium)
}
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
  // Light: neutral greys with the violet accent, for the floating notepad and panels that stay
  // light. Dark: membox's Bauhaus (membox/desktop/src/tokens.css), which the main window uses
  // (decided 2026-11-06): ink ground, ruled panels, three unmixed primaries at full strength —
  // blue selects, red files, yellow marks.
  static let workspace = color(0xF5F5F7, 0x17171C), paper = color(0xFFFFFF, 0x202027),
    sidebar = color(0xEDEDF0, 0x0D0D10)
  static let ink = color(0x1D1D1F, 0xF2F1EE), secondary = color(0x6E6E73, 0x98979F),
    tertiary = color(0x8A8A93, 0x66656D),
    accent = color(0x5B3DE6, 0x2D51E0), red = color(0xB03D30, 0xD93B2B)
  static let border = color(0xE3E3E8, 0x2C2C34)
  /// Text on an accent, folder or record block.
  static let onAccent = color(0xFFFFFF, 0xF2F1EE)
  /// Bauhaus yellow: marks (open counts, stars). Folders and tags are `red`.
  static let star = color(0xC98A06, 0xF0B323)
  /// Record and Stop: Apple red in light panels, Bauhaus red in the window.
  static let record = color(0xFF3B30, 0xD93B2B)
  /// Unselected sidebar symbols: label grey, darker than `secondary` so outlines hold up.
  static let railIcon = color(0x3C3C43, 0x98979F).opacity(0.85)
  static let backdrop = color(0xF5ECE6, 0x0D0D10)  // Voice gradient end (sidebar is the start).
  static let violet = Color(red: 106 / 255, green: 76 / 255, blue: 245 / 255)
  static let coral = Color(red: 232 / 255, green: 115 / 255, blue: 90 / 255)
  static let gradient = LinearGradient(
    colors: [violet, coral], startPoint: .leading, endPoint: .trailing)
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
  @Environment(\.colorScheme) private var scheme
  /// Bauhaus bars in the three primaries, as in membox's mark.
  private static let primaries = [Palette.accent, Palette.accent, Palette.red, Palette.star, Palette.ink]
  var body: some View {
    let heights = [12.0, 22, 30, 20, 11]
    HStack(spacing: 3) {
      ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
        Rectangle().fill(color ?? (scheme == .dark ? Self.primaries[index]
          : Palette.gradient(at: Double(index) / Double(heights.count - 1))))
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
    VStack(spacing: 8) {
      Image(systemName: icon).font(.system(size: 40, weight: .light)).foregroundStyle(Palette.secondary.opacity(0.7))
        .padding(.bottom, 6).accessibilityHidden(true)
      Text(title).font(.sectionTitle)
      Text(subtitle).font(.ui).foregroundStyle(Palette.secondary)
        .multilineTextAlignment(.center).frame(maxWidth: 340)
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
    }.font(.detail).foregroundStyle(Palette.secondary).accessibilityLabel(
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
            Image(systemName: icon).font(.system(size: 14, weight: .medium))
              .foregroundStyle(Palette.accent).frame(width: 26, height: 26)
              .background(Palette.sidebar.opacity(0.55), in: Rectangle())
              .accessibilityHidden(true)
          }
          VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.heading).foregroundStyle(Palette.ink)
              .accessibilityAddTraits(.isHeader)
            if let subtitle {
              Text(subtitle).font(.detail).foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
            }
          }
        }
      }
      content
    }.frame(maxWidth: .infinity, alignment: .leading).padding(22).workspaceSurface()
  }
}

/// Bauhaus (the dark window) is square and held by a 1 pt keyline; the light panels keep soft
/// corners and a hairline. Shape is a token, like membox's --r-tile.
private struct Surface: ViewModifier {
  var fill: Color
  var radius: CGFloat
  var keyline: Bool
  @Environment(\.colorScheme) private var scheme
  func body(content: Content) -> some View {
    let bauhaus = scheme == .dark
    let shape = RoundedRectangle(cornerRadius: bauhaus ? 0 : radius, style: .continuous)
    return content.background(fill, in: shape).overlay {
      if keyline || bauhaus {
        shape.strokeBorder(Palette.border.opacity(bauhaus ? 1 : 0.6), lineWidth: bauhaus ? 1 : 0.75)
          .allowsHitTesting(false)
      }
    }
  }
}
extension View {
  func workspaceSurface() -> some View {
    modifier(Surface(fill: Palette.paper, radius: 12, keyline: true))
  }
  func insetSurface() -> some View {
    self.padding(16).frame(maxWidth: .infinity, alignment: .leading)
      .modifier(Surface(fill: Palette.workspace, radius: 10, keyline: false))
  }
  /// membox's label: a word that names something. 10 pt semibold, tracked, uppercase.
  func bauhausLabel(_ color: Color = Palette.tertiary) -> some View {
    font(.system(size: 10, weight: .semibold)).tracking(1.2).textCase(.uppercase).foregroundStyle(color)
  }
}

struct SettingSwitch: View {
  let title: String
  var detail: String?
  @Binding var isOn: Bool
  var body: some View {
    Toggle(isOn: $isOn) {
      VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.ui.weight(.medium))
        if let detail {
          Text(detail).font(.detail).foregroundStyle(Palette.secondary).fixedSize(
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
      Text(text).font(.detail).foregroundStyle(Palette.secondary).lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true).frame(
          maxWidth: .infinity, alignment: .leading
        )
        .padding(.top, 8)
    }.font(.detail).foregroundStyle(Palette.secondary)
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
    .font(.detail).foregroundStyle(warning ? Palette.red : Palette.secondary)
    .frame(maxWidth: .infinity, alignment: .leading).insetSurface()
  }
}

/// The installed app's own icon, read at runtime; nothing third-party is bundled.
/// Apps that aren't installed show a generic symbol.
struct InstalledAppIcon: View {
  var bundleID: String?
  var image: NSImage?
  var size: CGFloat = 18
  var body: some View {
    if let icon = image ?? bundleID.flatMap(Self.icon) {
      Image(nsImage: icon).resizable().frame(width: size, height: size).accessibilityHidden(true)
    } else {
      Image(systemName: "app.dashed").font(.system(size: size * 0.8)).foregroundStyle(Palette.secondary)
        .frame(width: size, height: size).accessibilityHidden(true)
    }
  }
  static func icon(_ bundleID: String) -> NSImage? {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
      NSWorkspace.shared.icon(forFile: $0.path)
    }
  }
}

/// Page-level actions in the macOS idiom: 28 pt rounded rectangles (22 pt when small). Primary
/// is solid accent; secondary is white with a hairline. The names stay for the call sites.
struct PillButtonStyle: ButtonStyle {
  var primary = false
  @Environment(\.isEnabled) private var enabled
  @Environment(\.controlSize) private var controlSize
  @Environment(\.colorScheme) private var scheme
  private var compact: Bool { controlSize == .small || controlSize == .mini }
  func makeBody(configuration: Configuration) -> some View {
    let radius: CGFloat = scheme == .dark ? 0 : 7
    return configuration.label
      .font(.ui.weight(primary ? .semibold : .medium)).labelStyle(PillLabelStyle())
      .padding(.horizontal, compact ? 10 : 14).frame(minHeight: compact ? 22 : 28)
      .foregroundStyle(primary ? Palette.onAccent : Palette.ink)
      .background {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .fill(primary ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Palette.paper))
          .overlay {
            if !primary {
              RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Palette.border)
            }
          }
      }
      .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.05), radius: 0.5, y: 0.5)
      .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
      .contentShape(Rectangle())
  }
}
private struct PillLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 6) { configuration.icon; configuration.title }
  }
}
extension ButtonStyle where Self == PillButtonStyle {
  static var pill: PillButtonStyle { PillButtonStyle() }
  static var pillPrimary: PillButtonStyle { PillButtonStyle(primary: true) }
}

/// Segmented choice like a macOS segmented control: a grey track, the selected option a white
/// raised segment. Larger hit targets than `.pickerStyle(.segmented)`.
struct PillSegmented<Value: Hashable>: View {
  /// VoiceOver name for the group, like a Picker's label.
  let title: String
  @Binding var selection: Value
  let options: [Value]
  let label: (Value) -> String
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var scheme
  var body: some View {
    let bauhaus = scheme == .dark
    return HStack(spacing: 0) {
      ForEach(options, id: \.self) { option in
        let selected = option == selection
        Button { selection = option } label: {
          Text(label(option)).font(.ui.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? (bauhaus ? Palette.onAccent : Palette.ink) : Palette.secondary)
            .padding(.horizontal, 14).frame(minHeight: 24)
            .background {
              if selected {
                RoundedRectangle(cornerRadius: bauhaus ? 0 : 6, style: .continuous)
                  .fill(bauhaus ? Palette.accent : Palette.paper)
                  .shadow(color: .black.opacity(bauhaus ? 0 : 0.12), radius: 1, y: 0.5)
              }
            }
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
          .accessibilityAddTraits(selected ? .isSelected : [])
      }
    }.padding(bauhaus ? 0 : 2)
      .background(RoundedRectangle(cornerRadius: bauhaus ? 0 : 8, style: .continuous).fill(bauhaus ? Palette.paper : Palette.border.opacity(0.8)))
      .overlay { if bauhaus { Rectangle().strokeBorder(Palette.border) } }
      .accessibilityElement(children: .contain).accessibilityLabel(title)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: selection)
      .fixedSize()
  }
}

extension View {
  /// Whole-page scrolling: one full-width scroll area, so the scrollbar sits at the window's
  /// right edge and lists scroll with their page instead of inside a nested box.
  func pageScroll() -> some View {
    ScrollView { frame(maxWidth: .infinity, alignment: .topLeading) }
  }
}
