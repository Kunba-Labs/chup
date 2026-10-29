import AppKit
import SwiftUI
import ChupCore

@MainActor final class MeetingDetector: ObservableObject {
  @Published var candidate: MeetingCandidate?
  @Published var remaining = 10
  @Published var ended = false
  private var policy = MeetingDetectionPolicy()
  private var endPolicy = MeetingEndPolicy()
  private var browserCalls: [pid_t: (call: BrowserMeetingAX.Call?, checked: Double)] = [:]
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
      if !ended { candidate = nil }  // The end prompt keeps the recorded app's name.
      if state.meetingDetectionEnabled && state.activeMeetingID != nil {
        if !ended { panel.orderOut(nil) }  // A start prompt is stale once recording begins.
        watchEnd(state, now: now)
      } else {
        endPolicy.reset()
        hide()
      }
      return
    }
    endPolicy.reset()
    if ended { hide() }
    if let found = policy.observe(candidates(now: now), now: now, recording: false) {
      candidate = found
      show { [weak self] in self?.candidate?.pid == found.pid }
    }
    if let deadline = policy.deadline {
      remaining = max(0, Int(ceil(deadline - now)))
    } else {
      candidate = nil
      panel.orderOut(nil)
    }
  }
  private func show(when stillWanted: @escaping () -> Bool) {
    Task { @MainActor [weak self] in
      await Task.yield() // Allow the prompt's SwiftUI layout to settle.
      guard let self, stillWanted() else { return }
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
  private func hide() {
    ended = false
    panel.orderOut(nil)
  }
  /// While recording an app's call, ask once it stops using the microphone (and a browser shows
  /// no Leave control). The user decides; nothing stops on its own.
  private func watchEnd(_ state: WorkspaceState, now: Double) {
    let pid = state.meetingPID
    guard pid != 0, state.meetingStatus == .recording else {
      endPolicy.reset()
      if ended { hide() }
      return
    }
    let app = NSRunningApplication(processIdentifier: pid)
    let browser = Self.browsers.contains(app?.bundleIdentifier ?? "")
    let active =
      app?.isTerminated == false
      && (AudioProcesses.list().contains { $0.appPID == pid && $0.input }
        || (browser && browserCall(pid, now: now)?.live == true))
    if endPolicy.observe(active: active, now: now) {
      candidate = MeetingCandidate(
        pid: pid, name: app?.localizedName ?? "The call app", browser: browser)
      ended = true
      show { [weak self] in self?.ended == true }
    } else if active && ended {
      hide()
    }
  }
  func stopEndedMeeting() {
    hide()
    state?.stopMeeting()
  }
  func keepRecording() { hide() }
  /// Cached Accessibility read, refreshed off the main thread at most every 3 s; nil = unknown.
  private func browserCall(_ pid: pid_t, now: Double) -> BrowserMeetingAX.Call? {
    let cached = browserCalls[pid]
    if cached == nil || now - cached!.checked >= 3 {
      browserCalls[pid] = (cached?.call, now)
      Task.detached(priority: .utility) {
        let call = BrowserMeetingAX.call(pid: pid)
        await MainActor.run { [weak self] in self?.browserCalls[pid]?.call = call }
      }
    }
    return cached?.call
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
  private func candidates(now: Double) -> [MeetingCandidate] {
    // Attribute helper processes to their app, so Meet in a browser and Slack huddles count.
    let pids = Set(AudioProcesses.list().filter(\.input).map(\.appPID))
    browserCalls = browserCalls.filter { pids.contains($0.key) || $0.key == state?.meetingPID }
    return pids.sorted().compactMap { pid in
      guard pid != ProcessInfo.processInfo.processIdentifier,
        let app = NSRunningApplication(processIdentifier: pid), let bundle = app.bundleIdentifier
      else { return nil }
      let browser = Self.browsers.contains(bundle)
      guard browser || Self.callApps.contains(bundle) else { return nil }
      // Without Accessibility access, any browser using the mic still prompts.
      if browser, BrowserMeetingAX.trusted, browserCall(pid, now: now)?.meeting != true { return nil }
      return MeetingCandidate(pid: pid, name: app.localizedName ?? bundle, browser: browser)
    }
  }
}
/// Reads a browser's windows through Accessibility: titles, document/web-area URLs and button
/// labels, within Hyprnote's bounds (depth 32, 4000 nodes).
enum BrowserMeetingAX {
  /// `meeting`: some window looks like a call. `live`: some window shows a Leave control.
  struct Call {
    var meeting = false
    var live = false
  }
  static var trusted: Bool { AXIsProcessTrusted() }
  static func call(pid: pid_t) -> Call? {
    guard trusted else { return nil }
    let app = AXUIElementCreateApplication(pid)
    var urls = [String](), titles = [String](), controls = [String]()
    var budget = 4000
    func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
      var ref: CFTypeRef?
      return AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success
        ? ref : nil
    }
    func text(_ element: AXUIElement, _ attribute: String) -> String? {
      let ref = value(element, attribute)
      return (ref as? String) ?? (ref as? URL)?.absoluteString
    }
    func walk(_ element: AXUIElement, depth: Int) {
      guard depth < 32, budget > 0 else { return }
      budget -= 1
      switch text(element, kAXRoleAttribute) {
      case kAXWindowRole:
        titles += [text(element, kAXTitleAttribute)].compactMap { $0 }
        urls += [text(element, kAXDocumentAttribute)].compactMap { $0 }
      case "AXWebArea":
        urls += [text(element, "AXURL")].compactMap { $0 }
      case kAXButtonRole, kAXMenuItemRole, kAXPopUpButtonRole:
        if (value(element, kAXEnabledAttribute) as? Bool) != false {
          controls += [kAXTitleAttribute, kAXDescriptionAttribute].compactMap { text(element, $0) }
        }
      default: break
      }
      for child in (value(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
        walk(child, depth: depth + 1)
      }
    }
    var call = Call()
    for window in (value(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
      urls = []
      titles = []
      controls = []
      walk(window, depth: 0)
      call.meeting = call.meeting
        || BrowserMeetingEvidence.inCall(urls: urls, titles: titles, controls: controls)
      call.live = call.live
        || BrowserMeetingEvidence.inCall(
          urls: urls, titles: titles, controls: controls, requireControl: true)
    }
    return call
  }
}
struct MeetingPrompt: View {
  @ObservedObject var detector: MeetingDetector
  var body: some View {
    if detector.ended {
      NotificationCard(
        kind: .meetingEnded, appName: detector.candidate?.name ?? "the call",
        primary: { detector.stopEndedMeeting() }, secondary: { detector.keepRecording() })
    } else {
      callPrompt
    }
  }
  private var callPrompt: some View {
    NotificationCard(
      kind: detector.candidate?.browser == true ? .browserDetected : .callDetected,
      appName: detector.candidate?.name ?? "Meeting", countdown: detector.remaining,
      primary: { detector.accept() }, secondary: { detector.dismiss() },
      tertiary: { detector.dismiss(snooze: true) })
  }
}
