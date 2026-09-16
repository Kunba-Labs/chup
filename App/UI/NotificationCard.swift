import SwiftUI

/// Shared native panel vocabulary. Preview actions are inert; production owners provide handlers.
struct NotificationCard: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  enum Kind {
    case callDetected, browserDetected, recording, paused, dictating, recovered, privateAssistant,
      routeBlocked
  }
  let kind: Kind
  var appName = "Zoom"
  var countdown = 10
  var elapsed = "00:00"
  var primary: () -> Void = {}
  var secondary: () -> Void = {}
  var tertiary: () -> Void = {}
  private var recording: Bool { kind == .recording || kind == .dictating }
  private var accent: Color {
    [.recording, .dictating, .paused, .routeBlocked].contains(kind) ? RailPalette.red : RailPalette.olive
  }
  private var icon: String {
    switch kind {
    case .callDetected, .browserDetected: return "person.2.wave.2"
    case .recording: return "record.circle.fill"
    case .paused: return "pause.circle"
    case .dictating: return "waveform"
    case .recovered: return "text.badge.checkmark"
    case .privateAssistant: return "sparkle"
    case .routeBlocked: return "mic.slash"
    }
  }
  private var title: String {
    switch kind {
    case .callDetected: return "A conversation to remember?"
    case .browserDetected: return "A call in your browser?"
    case .recording: return "You’re free to be here."
    case .paused: return "Recording is paused"
    case .dictating: return "Go on. I’m listening."
    case .recovered: return "Your words are safe"
    case .privateAssistant: return "Just between us"
    case .routeBlocked: return "Let’s keep this private"
    }
  }
  private var detail: String {
    switch kind {
    case .callDetected: return "Take notes for your conversation in \(appName)."
    case .browserDetected: return "Possible call in \(appName). App capture can include other tabs."
    case .recording: return "Microphone and call audio are being saved on this Mac."
    case .paused: return "Audio is not being saved. You may still be heard in the call."
    case .dictating: return "Release your shortcut to finish. Escape to cancel."
    case .recovered: return "The original text field changed. Your dictation is ready to copy."
    case .privateAssistant:
      return "Ask about this meeting in private text. Only its context is shared with AI."
    case .routeBlocked:
      return "Your call may still hear this microphone. A verified private input route is required."
    }
  }
  private var primaryTitle: String {
    switch kind {
    case .callDetected, .browserDetected: return "Record"
    case .recording: return "Open notes"
    case .paused: return "Resume"
    case .dictating: return "Finish"
    case .recovered: return "Copy text"
    case .privateAssistant, .routeBlocked: return "Ask in text"
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 9) {
        Image(systemName: icon).font(.system(size: 14, weight: .medium)).foregroundStyle(accent)
        Text(
          kind == .callDetected || kind == .browserDetected
            ? appName.uppercased() : recording ? "CHUP! · LIVE" : "CHUP!"
        ).font(.system(size: 9, weight: .semibold)).tracking(1.4).foregroundStyle(RailPalette.secondary)
        Spacer()
        if kind == .callDetected || kind == .browserDetected {
          ZStack {
            Circle().stroke(.white.opacity(0.16), lineWidth: 1.5)
            Circle().trim(from: 0, to: Double(countdown) / 10).stroke(
              RailPalette.olive, style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
            ).rotationEffect(.degrees(-90))
              .animation(reduceMotion ? nil : .linear(duration: 1), value: countdown)
            Text("\(countdown)").font(.system(size: 9, weight: .medium, design: .monospaced))
          }.frame(width: 23, height: 23).accessibilityLabel("Dismisses in \(countdown) seconds")
        } else if kind == .recording {
          Text(elapsed).font(.system(size: 11, design: .monospaced)).foregroundStyle(RailPalette.red)
        }
      }
      VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.system(size: 16, weight: .semibold))
        Text(detail).font(.system(size: 12)).lineSpacing(2).foregroundStyle(RailPalette.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      if kind == .callDetected {
        Text("Let participants know before recording.").font(.system(size: 10)).foregroundStyle(
          RailPalette.secondary)
      }
      HStack(spacing: 10) {
        if kind == .callDetected || kind == .browserDetected {
          Button("Not now", action: secondary).buttonStyle(.plain).foregroundStyle(
            RailPalette.secondary)
          Button("Snooze 2m", action: tertiary).buttonStyle(.plain).foregroundStyle(
            RailPalette.secondary)
        } else {
          Button(
            kind == .recording ? "Pause" : kind == .paused ? "Stop & save" : "Dismiss",
            action: secondary
          ).buttonStyle(.plain).foregroundStyle(RailPalette.secondary)
        }
        Spacer()
        Button(action: primary) {
          Text(primaryTitle).font(.system(size: 12, weight: .semibold))
            .foregroundStyle(RailPalette.base).padding(.horizontal, 14).padding(.vertical, 7)
            .background(RailPalette.ink, in: Capsule())
        }.buttonStyle(.plain)

      }.font(.system(size: 11))
    }.padding(16).frame(width: 336, alignment: .leading)
      .background { RailSurface() }
      .foregroundStyle(RailPalette.ink).environment(\.colorScheme, .dark)
  }
}
