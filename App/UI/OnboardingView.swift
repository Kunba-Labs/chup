import ChupCore
import SwiftUI

struct PermissionCards: View {
  @EnvironmentObject var state: WorkspaceState
  @ObservedObject var setup: MacSetupService
  @State private var meetingSetup = false
  var permissions = WorkspacePermission.allCases
  var body: some View {
    VStack(spacing: 14) {
      ForEach(permissions) { permission in
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            HStack(spacing: 5) {
              Text(permission.title).font(.headline)
              Button {
                setup.openPrivacy(permission)
              } label: {
                Image(systemName: "arrow.up.right")
                  .font(.system(size: 13, weight: .semibold))
                  .foregroundStyle(Palette.olive)
                  .frame(width: 26, height: 26).contentShape(Rectangle())
              }
              .buttonStyle(.borderless)
              .help(permission.breadcrumb)
              .accessibilityLabel("Open macOS Privacy settings for \(permission.title)")
            }
            Spacer()
            PermissionStatusBadge(status: setup.permissions[permission])
          }
          Text(permission.purpose).font(.callout).foregroundStyle(Palette.secondary).fixedSize(
            horizontal: false, vertical: true)
          if permission == .systemAudio || setup.permissions[permission] != .allowed {
            HStack {
              if permission == .systemAudio {
                Button("Set up meeting audio…") { meetingSetup = true }
                  .disabled(state.activeMeetingID != nil || state.storageBusy)
              } else {
                Button("Enable access") { setup.request(permission) }.disabled(
                  setup.requesting != nil)
              }
              Spacer()
            }.font(.caption)
          }
          if permission == .systemAudio {
            Text(
              setup.lastAudioCapture.map { "Last successful capture: " + $0.formatted() }
                ?? "Choose a meeting app and start your first recording to request audio-only access. Opening System Settings alone does not add Chup! to its list."
            )
            .font(.caption).foregroundStyle(Palette.secondary)
          }
        }.padding(22).workspaceSurface()
      }
      HStack {
        PermissionRefreshButton(setup: setup, permissions: permissions)
        Spacer()
      }
      if let message = setup.message {
        Text(message).font(.callout).foregroundStyle(Palette.secondary).textSelection(.enabled)
      }
    }.sheet(isPresented: $meetingSetup) {
      CaptureSetupView(permissionSetup: true).environmentObject(state)
    }
  }
}
struct PermissionRefreshButton: View {
  @ObservedObject var setup: MacSetupService
  let permissions: [WorkspacePermission]
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var checking = false
  @State private var checked = false
  private var result: PermissionCheckResult {
    .evaluate(permissions.map { setup.permissions[$0] })
  }
  private var confirmed: Bool { checked && !checking && result == .enabled }
  private var resultIcon: String {
    guard checked else { return "arrow.clockwise" }
    switch result {
    case .enabled: return "checkmark"
    case .needsAccess: return "exclamationmark"
    case .awaitingCapture: return "clock"
    case .noSelection: return "arrow.clockwise"
    }
  }
  private var description: String {
    if checking { return "Checking access" }
    if confirmed { return "All displayed permissions are enabled. Check again." }
    if checked && result == .awaitingCapture {
      return
        "Available permission checks passed. Meeting audio access is checked when capture starts. Check again."
    }
    if checked {
      let pending = permissions.filter { setup.permissions[$0] != .allowed }.map(\.title)
      return pending.isEmpty
        ? "No permissions selected. Check again."
        : "Access still needs checking: " + pending.joined(separator: ", ") + ". Check again."
    }
    return "Check access again"
  }
  var body: some View {
    Button {
      checking = true
    } label: {
      HStack(spacing: 10) {
        ZStack {
          Circle().fill(confirmed ? Palette.olive : Palette.sidebar)
          if checking {
            if reduceMotion {
              Image(systemName: "hourglass").font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.olive)
            } else {
              ProgressView().progressViewStyle(.circular).controlSize(.small)
            }
          } else {
            Image(systemName: resultIcon)
              .font(.system(size: 17, weight: .semibold))
              .foregroundStyle(confirmed ? Color.white : Palette.olive)
          }
        }.frame(width: 40, height: 40)
        Text(checking ? "Checking access…" : "Check access again")
          .font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.olive)
      }.contentShape(Rectangle())
    }
    .buttonStyle(.plain).disabled(checking || setup.requesting != nil)
    .help(description).accessibilityLabel(description)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: checking)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: confirmed)
    .task(id: checking) {
      guard checking else { return }
      await Task.yield()
      guard !Task.isCancelled else { return }
      setup.refresh()
      // Keep the feedback legible even when local permission checks return immediately.
      do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
      guard !Task.isCancelled else { return }
      checked = true
      checking = false
    }
    .onDisappear {
      checking = false
      checked = false
    }
  }
}
struct PermissionStatusBadge: View {
  let status: PermissionState?
  private var enabled: Bool { status == .allowed }
  var body: some View {
    Label(
      enabled ? "Access enabled" : (status?.rawValue ?? "Check access"),
      systemImage: enabled ? "checkmark.circle.fill" : "circle.dashed"
    )
    .font(.system(size: 15, weight: .semibold))
    .foregroundStyle(enabled ? Color.white : Palette.ink)
    .padding(.horizontal, 13).padding(.vertical, 9)
    .background(enabled ? Palette.olive : Palette.sidebar, in: Capsule())
    .fixedSize(horizontal: true, vertical: false)
    .accessibilityElement(children: .combine)
  }
}
struct LoginSettings: View {
  @ObservedObject var setup: MacSetupService
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Toggle(
        "Open Chup! when I log in",
        isOn: Binding(
          get: { setup.loginStatus == .enabled || setup.loginStatus == .requiresApproval },
          set: setup.setLaunchAtLogin)).toggleStyle(.switch)
      Text(setup.loginDescription).font(.callout).foregroundStyle(Palette.secondary)
      Button("Open macOS Login Items") { setup.openLoginItems() }
      if let message = setup.message {
        Text(message).font(.caption).foregroundStyle(Palette.secondary)
      }
    }
  }
}
struct OnboardingView: View {
  @EnvironmentObject var state: WorkspaceState
  @State var step = 0
  @State private var choices = SetupChoices()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let steps = ["Welcome", "Your workflow", "Access", "Your privacy", "Ready"]
  var body: some View {
    HStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 28) {
        HStack {
          WaveMark(color: Palette.red)
          Text("Chup!").font(.system(size: 30, weight: .medium, design: .serif))
        }
        Text("A little setup.\nA calmer working day.").font(.system(size: 23, design: .serif))
          .lineSpacing(5)
        ForEach(steps.indices, id: \.self) { index in
          HStack(spacing: 12) {
            Image(systemName: index < step ? "checkmark.circle.fill" : "\(index + 1).circle")
            Text(steps[index]).fontWeight(index == step ? .semibold : .regular)
          }.foregroundStyle(index == step ? Palette.ink : Palette.secondary)
            .accessibilityLabel("Step \(index + 1): \(steps[index])")
        }
        Spacer()
        Text("Permissions are your choice.\nYou can change them in Settings.").font(.caption)
          .foregroundStyle(Palette.secondary)
      }.padding(28).frame(width: 265).background(Palette.sidebar)
      VStack(alignment: .leading, spacing: 20) {
        ScrollView {
          VStack(alignment: .leading, spacing: 22) {
            Text(title).font(.system(size: 33, design: .serif))
            switch step {
            case 0:
              Text("Speak naturally. Keep the conversation. Find the thought you need.").font(
                .system(size: 19)
              ).foregroundStyle(Palette.secondary)
              feature(
                "waveform", "Dictate into your own words",
                "Hold a shortcut, speak, and place the result in the field you chose.")
              feature(
                "person.2", "Stay present in meetings",
                "Keep audio, transcripts and notes together, with sources you can revisit.")
              feature(
                "sparkles", "Ask a thought partner",
                "Questions stay scoped to the meeting. You review proposed changes.")
              Text(
                "Nothing records automatically. Hovering over the rail never activates your microphone."
              ).font(.callout).foregroundStyle(Palette.secondary)
            case 1:
              WorkspaceCard("Your everyday tools", icon: "waveform") {
                SettingSwitch(title: "Dictation and voice shortcuts", isOn: $choices.dictation)
                Divider()
                SettingSwitch(title: "Meeting audio and notes", isOn: $choices.meetings)
              }
              if choices.meetings {
                WorkspaceCard("Alternative meeting capture", icon: "person.wave.2") {
                  SettingSwitch(
                    title: "Set up the fallback route too", isOn: $choices.screenFallback)
                  Text(
                    "Ordinary meeting capture uses Core Audio. The fallback needs broader Screen & System Audio Recording access; no video is saved."
                  ).font(.callout).foregroundStyle(Palette.secondary)
                }
              }
              Text("You can start with typed notes and add voice later.").foregroundStyle(
                Palette.secondary)
            case 2:
              Text("Enable only what you want to use. macOS owns the final permission switches.")
                .foregroundStyle(Palette.secondary)
              PermissionCards(setup: state.setup, permissions: choices.permissions)
            case 3:
              WorkspaceCard("Kept on this Mac", icon: "lock.shield") {
                Label(
                  state.store?.encrypted == true
                    ? "Audio, notes and search indexes are encrypted locally"
                    : "Workspace encryption needs attention", systemImage: "lock.shield"
                ).font(.headline)
                Text(
                  "Chup! keeps its encryption keys in this Mac’s Keychain. Keep a recovery backup before removing keys or changing Macs."
                ).foregroundStyle(Palette.secondary)
              }
              WorkspaceCard("Your cloud choice", icon: "cloud") {
                SettingSwitch(title: "Allow cloud AI processing", isOn: $state.cloudEnabled)
                Text(
                  "Transcription, summaries and assistant questions send the required content through your configured backend to OpenAI. Local recording alone does not send it. Private thoughts are excluded. Configure the backend in Advanced settings."
                ).font(.callout).foregroundStyle(Palette.secondary)
              }
              WorkspaceCard("Start with your Mac", icon: "sun.max") {
                LoginSettings(setup: state.setup)
              }
              Text(
                "Retention starts with Keep until I delete. You can choose a schedule in Privacy settings."
              ).font(.caption)
            default:
              Text(
                "Your workspace is ready. Features without permission stay available to set up later."
              ).font(.system(size: 18)).foregroundStyle(Palette.secondary)
              feature(
                "keyboard", "Try a short dictation",
                "Enable shortcuts, then hold Fn. A keyboard without Fn can use the alternative preset in Settings."
              )
              feature(
                "record.circle", "Start a meeting deliberately",
                "Choose its app, let participants know, then press Record. Pausing a recording does not mute the call."
              )
              Button("Review permissions") { step = 2 }
            }
          }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 12)
        }
        Divider()
        HStack {
          Button("Set up later") { finish() }
          Spacer()
          if step > 0 { Button("Back") { move(-1) } }
          Button(step == 4 ? "Open Chup!" : "Continue") { step == 4 ? finish() : move(1) }
            .buttonStyle(.borderedProminent)
        }
      }.padding(32).background(Palette.workspace)
    }.frame(width: 950, height: 700).foregroundStyle(Palette.ink).tint(Palette.olive)
      .preferredColorScheme(.light).onAppear { state.setup.refresh() }
  }
  private var title: String {
    [
      "Make room for your voice.", "What brings you here?", "A few doors to open.",
      "Your words. Your choices.", "Ready when you are.",
    ][step]
  }
  private func move(_ delta: Int) {
    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { step += delta }
  }
  private func finish() {
    state.defaults.set(true, forKey: "onboardingCompleted")
    state.onboardingVisible = false
  }
  private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
    HStack(alignment: .top, spacing: 16) {
      Image(systemName: icon).font(.system(size: 22)).foregroundStyle(Palette.olive).frame(
        width: 30)
      VStack(alignment: .leading, spacing: 7) {
        Text(title).font(.system(size: 21, design: .serif))
        Text(detail).font(.callout).foregroundStyle(Palette.secondary)
      }
    }.padding(20).workspaceSurface()
  }
}
