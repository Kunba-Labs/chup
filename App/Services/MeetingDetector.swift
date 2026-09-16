import AppKit
import CoreAudio
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
  private func candidates() -> [MeetingCandidate] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard
      AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
    else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
    else { return [] }
    var found = [MeetingCandidate]()
    for id in ids {
      var pid: pid_t = 0
      address.mSelector = kAudioProcessPropertyPID
      size = UInt32(MemoryLayout<pid_t>.size)
      guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &pid) == noErr,
        let app = NSRunningApplication(processIdentifier: pid), let bundle = app.bundleIdentifier
      else { continue }
      let browser = [
        "com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "com.microsoft.edgemac",
        "company.thebrowser.Browser",
      ].contains(bundle)
      guard
        browser
          || [
            "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams",
            "com.cisco.webexmeetingsapp", "com.tinyspeck.slackmacgap",
          ].contains(bundle)
      else { continue }
      var running: UInt32 = 0
      address.mSelector = kAudioProcessPropertyIsRunningInput
      size = UInt32(MemoryLayout<UInt32>.size)
      guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &running) == noErr, running != 0
      else { continue }
      found.append(MeetingCandidate(pid: pid, name: app.localizedName ?? bundle, browser: browser))
    }
    return found.sorted { $0.pid < $1.pid }
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
