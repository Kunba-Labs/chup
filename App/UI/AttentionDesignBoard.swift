import SwiftUI

/// Proposal: a background check surfaces two silent failures — global
/// shortcuts without their event stream, and a chosen microphone with no
/// input — in the island, the rail and the workspace sidebar. Mocks only.
struct AttentionDesignBoard: View {
  static let amber = Color(red: 0.93, green: 0.70, blue: 0.36)
  private let shortcuts = Alert(
    symbol: "keyboard", title: "Global shortcuts are off",
    detail: "Input Monitoring no longer covers this build", fix: "Open permissions")
  private let microphone = Alert(
    symbol: "mic.slash", title: "No input from MacBook Pro Microphone",
    detail: "Muted, unplugged or another device is selected", fix: "Choose microphone")

  var body: some View {
    VStack(alignment: .leading, spacing: 26) {
      Text("CHUP! / ATTENTION · PROPOSAL").font(.system(size: 10, weight: .semibold))
        .tracking(1.8).foregroundStyle(Palette.secondary)
      Text("When something quietly broke.").font(.system(size: 36, design: .serif))
      Text(
        "A check every five seconds notices two things you would otherwise discover mid-sentence: the shortcut event stream is gone, or the chosen microphone has nothing to give. Amber means attention. Red stays recording."
      ).font(.system(size: 14)).foregroundStyle(Palette.secondary)
        .fixedSize(horizontal: false, vertical: true).frame(width: 760, alignment: .leading)
      row("01  ISLAND · AT REST", "An idle island normally draws nothing. An alert is the one thing it shows at rest: the amber mark, and the cause beside the notch.") {
        IslandStage {
          IslandNotch(expanded: false) {
            HStack(spacing: 0) {
              mark(12)
              Spacer(minLength: 150)
              Image(systemName: shortcuts.symbol).font(.system(size: 11, weight: .medium))
                .foregroundStyle(Self.amber)
            }.padding(.horizontal, 14).frame(width: 300, height: 30)
          }
        }
      }
      row("02  ISLAND · SHORTCUTS", "Hover explains it in one line and offers the one action that fixes it. The usual controls stay on the right.") {
        IslandStage { IslandNotch { island(shortcuts) } }
      }
      row("03  ISLAND · MICROPHONE", "Same shape, other cause. The fix opens the microphone picker, never a generic settings page.") {
        IslandStage { IslandNotch { island(microphone) } }
      }
      HStack(alignment: .top, spacing: 56) {
        VStack(spacing: 22) {
          VStack(spacing: 18) {
            railRest(horizontal: false)
            railRest(horizontal: true)
          }
          Text("RAIL · AT REST").font(.system(size: 9, weight: .semibold)).tracking(1.5)
        }
        VStack(spacing: 22) {
          HStack(alignment: .top, spacing: 10) {
            railColumn
            RailOverlayLabel(title: "Shortcuts are off · Fix").padding(.top, 2)
          }
          Text("RAIL · HOVER LABEL").font(.system(size: 9, weight: .semibold)).tracking(1.5)
        }
        VStack(spacing: 22) {
          railDrawer
          Text("RAIL · ATTENTION DRAWER").font(.system(size: 9, weight: .semibold)).tracking(1.5)
        }
        VStack(spacing: 22) {
          sidebar
          Text("WORKSPACE SIDEBAR").font(.system(size: 9, weight: .semibold)).tracking(1.5)
        }
      }.padding(.top, 6)
      Divider()
      Text(
        "THE CHECK · MAIN ACTOR, EVERY 5 S · SHORTCUTS: A BINDING NEEDS THE EVENT STREAM AND THE TAP IS GONE · MICROPHONE: THE CHOSEN DEVICE IS ABSENT, OR SILENT FOR 10 S WHILE CAPTURING · CLEARS ITSELF · NEVER STOPS A RECORDING"
      ).font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(Palette.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Text("NATIVE SWIFTUI · MOCKED SURFACES · NO CHECK RUNS IN THIS RENDER")
        .font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(Palette.secondary)
    }.padding(48).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Palette.workspace).foregroundStyle(Palette.ink).environment(\.colorScheme, .light)
  }

  struct Alert {
    let symbol: String, title: String, detail: String, fix: String
  }

  private func mark(_ size: CGFloat) -> some View {
    Image(systemName: "exclamationmark.triangle.fill")
      .font(.system(size: size, weight: .medium)).foregroundStyle(Self.amber)
  }

  private func island(_ alert: Alert) -> some View {
    HStack(alignment: .center, spacing: 12) {
      mark(15)
      VStack(alignment: .leading, spacing: 2) {
        Text(alert.title).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.9))
        Text(alert.detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
      }.lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
      Text(alert.fix).font(.system(size: 12, weight: .medium)).foregroundStyle(.black)
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(Self.amber, in: Capsule())
      HStack(spacing: 4) {
        ForEach(["mic", "person.2", "sparkle", "gearshape"], id: \.self) { symbol in
          Image(systemName: symbol).font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white).frame(width: 26, height: 26)
            .background(.white.opacity(0.16), in: Circle())
        }
      }
    }.padding(.horizontal, 18).frame(width: 600, height: 64)
  }

  private func railRest(horizontal: Bool) -> some View {
    Group {
      if horizontal {
        HStack(spacing: 6) {
          Capsule().fill(RailPalette.secondary).frame(width: 18, height: 2)
          mark(11)
        }.frame(width: 64, height: 26)
      } else {
        mark(11).frame(width: 26, height: 64)
      }
    }.background(Capsule().fill(RailPalette.base.opacity(0.9)))
      .environment(\.colorScheme, .dark)
  }

  private var railColumn: some View {
    VStack(spacing: 4) {
      mark(11).frame(width: 32, height: 16)
      ForEach(["waveform", "person.2", "sparkle"], id: \.self) { symbol in
        Image(systemName: symbol).font(.system(size: 15, weight: .medium)).frame(width: 32, height: 32)
      }
      Rectangle().fill(.white.opacity(0.12)).frame(width: 20, height: 1).padding(2)
      Image(systemName: "gearshape").font(.system(size: 15, weight: .medium)).frame(width: 32, height: 32)
    }.padding(6).frame(width: 56, height: 238)
      .background { RailSurface(cornerRadius: 22, liveGlass: false) }
      .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
      .foregroundStyle(RailPalette.ink).environment(\.colorScheme, .dark)
  }

  private var railDrawer: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Attention").font(.system(size: 17, weight: .semibold))
        Spacer()
        Image(systemName: "chevron.left").padding(6).foregroundStyle(RailPalette.secondary)
      }
      ForEach([shortcuts, microphone], id: \.title) { alert in
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 6) {
            mark(10)
            Text(alert.title).font(.system(size: 11, weight: .medium)).foregroundStyle(Self.amber)
          }.lineLimit(1)
          HStack(spacing: 11) {
            Image(systemName: alert.symbol).frame(width: 19).foregroundStyle(RailPalette.secondary)
            Text(alert.fix)
            Spacer(minLength: 0)
          }.font(.system(size: 13, weight: .medium)).padding(.horizontal, 9).padding(.vertical, 8)
        }
      }
      Spacer(minLength: 0)
    }.padding(16).frame(width: 300, height: 230)
      .background { RailSurface(cornerRadius: 18, liveGlass: false) }
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .foregroundStyle(RailPalette.ink).environment(\.colorScheme, .dark)
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 5) {
      ForEach(WorkspacePage.allCases, id: \.self) { page in
        HStack {
          Label(page.rawValue, systemImage: page.icon).font(.system(size: 13))
          Spacer()
          if page == .settings { Circle().fill(Self.amber).frame(width: 7, height: 7) }
        }.padding(12)
          .background(page == .meetings ? Palette.paper : .clear, in: RoundedRectangle(cornerRadius: 8))
          .foregroundStyle(page == .meetings ? Palette.ink : Palette.secondary)
      }
      Divider().padding(.vertical, 6)
      HStack(alignment: .top, spacing: 8) {
        mark(10).padding(.top, 2)
        Text("Global shortcuts are off. Open permissions.").font(.system(size: 11))
          .foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
      }.padding(10).background(Self.amber.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
    }.padding(14).frame(width: 218).background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 12))
  }

  private func row<V: View>(_ label: String, _ caption: String, @ViewBuilder content: () -> V)
    -> some View
  {
    HStack(alignment: .center, spacing: 30) {
      content()
      VStack(alignment: .leading, spacing: 8) {
        Text(label).font(.system(size: 9, weight: .semibold)).tracking(1.4)
          .foregroundStyle(Palette.secondary)
        Text(caption).font(.system(size: 13)).lineSpacing(4)
          .fixedSize(horizontal: false, vertical: true).frame(width: 300, alignment: .leading)
      }
    }
  }
}
