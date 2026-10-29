import AppKit
import SwiftUI
import ChupCore

@MainActor final class MeetingDetector: ObservableObject {
  @Published var candidate: MeetingCandidate?
  @Published var remaining = 10
  private var policy = MeetingDetectionPolicy()
  private var timer: Timer?
  private let panel = NonactivatingPanel(
    contentRect: NSRect(x: 0, y: 0, width: 336, height: 230),
    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
  private weak var state: WorkspaceState?
  init(state: WorkspaceState) {
    self.state = state
    panel.level = .statusBar
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.appearance = NSAppearance(named: .darkAqua)
    panel.hasShadow = true
    panel.contentView = NSHostingView(
      rootView: MeetingPrompt(detector: self).environment(\.colorScheme, .dark))
    timer = MainActorTimer.repeating(every: 1) { [weak self] in self?.tick() }
  }
  private func tick() {
    guard let state else { return }
    let now = ProcessInfo.processInfo.systemUptime
    guard state.meetingDetectionEnabled && state.activeMeetingID == nil else {
      policy.dismiss(now: now)
      candidate = nil
      panel.orderOut(nil)
      return
    }
    if let found = policy.observe(candidates(), now: now, recording: false) {
      candidate = found
      Task { @MainActor [weak self] in
        await Task.yield() // Allow the candidate's SwiftUI layout to settle.
        guard let self, candidate?.pid == found.pid else { return }
        let frame = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let size = panel.contentView?.fittingSize ?? NSSize(width: 336, height: 230)
        panel.setFrame(NSRect(x: frame.maxX - size.width - 16, y: frame.maxY - size.height - 16,
          width: size.width, height: size.height), display: true)
        panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ context in
          context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14
          self.panel.animator().alphaValue = 1
        }, completionHandler: nil)
      }
    }
    if let deadline = policy.deadline {
      remaining = max(0, Int(ceil(deadline - now)))
    } else {
      candidate = nil
      panel.orderOut(nil)
    }
  }
  func dismiss(snooze: Bool = false) {
    policy.dismiss(now: ProcessInfo.processInfo.systemUptime, snooze: snooze ? 120 : 0)
    candidate = nil
    panel.orderOut(nil)
  }
  func accept() {
    guard let selected = policy.accept(now: ProcessInfo.processInfo.systemUptime), let state else {
      dismiss()
      return
    }
    candidate = nil
    panel.orderOut(nil)
    state.newMeeting()
    state.selectedPID = selected.pid
    state.startMeeting()
    state.reveal?()
  }
  private static let browsers: Set<String> = [
    "com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "com.microsoft.edgemac",
    "company.thebrowser.Browser", "com.brave.Browser", "com.vivaldi.Vivaldi",
    "com.operasoftware.Opera",
  ]
  private static let callApps: Set<String> = [
    "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams", "com.cisco.webexmeetingsapp",
    "Cisco-Systems.Spark", "com.tinyspeck.slackmacgap", "com.apple.FaceTime", "com.hnc.Discord",
    "net.whatsapp.WhatsApp",
  ]
  private func candidates() -> [MeetingCandidate] {
    // Attribute helper processes to their app, so Meet in a browser and Slack huddles count.
    let pids = Set(AudioProcesses.list().filter(\.input).map(\.appPID))
    return pids.sorted().compactMap { pid in
      guard pid != ProcessInfo.processInfo.processIdentifier,
        let app = NSRunningApplication(processIdentifier: pid), let bundle = app.bundleIdentifier
      else { return nil }
      let browser = Self.browsers.contains(bundle)
      guard browser || Self.callApps.contains(bundle) else { return nil }
      return MeetingCandidate(pid: pid, name: app.localizedName ?? bundle, browser: browser)
    }
  }
}
struct MeetingPrompt: View {
  @ObservedObject var detector: MeetingDetector
  var body: some View {
    NotificationCard(
      kind: detector.candidate?.browser == true ? .browserDetected : .callDetected,
      appName: detector.candidate?.name ?? "Meeting", countdown: detector.remaining,
      primary: { detector.accept() }, secondary: { detector.dismiss() },
      tertiary: { detector.dismiss(snooze: true) })
  }
}
