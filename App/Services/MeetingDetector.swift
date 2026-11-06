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
  private var scanning = Set<pid_t>()
  private var timer: Timer?
  private let panel = NonactivatingPanel(
    contentRect: NSRect(x: 0, y: 0, width: 400, height: 90),
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
      // Beside the hover rail on its docked edge; mid-edge of the main screen if it is hidden.
      let edge = state?.railDock ?? "right"
      let main = NSScreen.main ?? NSScreen.screens[0]
      let rail = state?.rail?.restingFrame ?? FloatingEdgePlacement.frame(
        size: NSSize(width: 10, height: 36), screen: main.frame, visible: main.visibleFrame,
        edge: edge)
      let screen = NSScreen.screens.first { $0.frame.intersects(rail) } ?? main
      let size = panel.contentView?.fittingSize ?? NSSize(width: 400, height: 90)
      panel.setFrame(FloatingEdgePlacement.beside(rail, size: size, visible: screen.visibleFrame,
        edge: edge), display: true)
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
    if (cached == nil || now - cached!.checked >= 3) && !scanning.contains(pid) {
      browserCalls[pid] = (cached?.call, now)
      scanning.insert(pid)  // One scan per browser at a time; a slow tree can't pile them up.
      Task.detached(priority: .utility) {
        let call = BrowserMeetingAX.call(pid: pid)
        await MainActor.run { [weak self] in
          self?.browserCalls[pid]?.call = call
          self?.scanning.remove(pid)
        }
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
      // Wait for the first scan; if the browser can't be inspected, mic use alone still prompts.
      if browser {
        guard let call = browserCall(pid, now: now) else { return nil }
        if call.inspected && !call.meeting { return nil }
      }
      return MeetingCandidate(pid: pid, name: app.localizedName ?? bundle, browser: browser)
    }
  }
}
/// Reads a browser's windows through Accessibility: titles, document/web-area URLs and button
/// labels, within Hyprnote's bounds (depth 32, 4000 nodes).
enum BrowserMeetingAX {
  /// `meeting`: some window looks like a call. `live`: some window shows a Leave control.
  /// `inspected` is false when Accessibility is off, the windows can't be read, or a window was
  /// too large to scan fully without finding a call.
  struct Call {
    var inspected = true
    var meeting = false
    var live = false
    /// "Google Meet", "Zoom"…: the first window in a live call that names its service.
    var service: String?
  }
  static func call(pid: pid_t) -> Call {
    guard AXIsProcessTrusted() else { return Call(inspected: false) }
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 1)  // A hung browser can't stall the scan for long.
    var urls = [String](), titles = [String](), controls = [String]()
    var budget = 0
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
      guard depth < 32, budget > 0 else {
        budget = 0  // Depth or size cut the scan short: "couldn't inspect", not "no call".
        return
      }
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
    guard let windows = value(app, kAXWindowsAttribute) as? [AXUIElement] else {
      return Call(inspected: false)
    }
    var call = Call()
    var truncated = false
    for window in windows {
      urls = []
      titles = []
      controls = []
      budget = 4000  // Per window, so one large window can't hide the call window.
      walk(window, depth: 0)
      truncated = truncated || budget <= 0
      if BrowserMeetingEvidence.inCall(urls: urls, titles: titles, controls: controls) {
        call.meeting = true
      }
      // Only a window in a live call (a Leave control beside the call site) names the service:
      // a stale Meet title or another open tab says nothing about what is being recorded.
      if BrowserMeetingEvidence.inCall(
        urls: urls, titles: titles, controls: controls, requireControl: true)
      {
        call.live = true
        call.service = call.service ?? BrowserMeetingEvidence.service(urls: urls, titles: titles)
      }
    }
    if truncated && !call.meeting { call.inspected = false }
    return call
  }
}
/// Dark glass pill beside the hover rail: start a call's notes, or confirm that it ended.
struct MeetingPrompt: View {
  @ObservedObject var detector: MeetingDetector
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var name: String { detector.candidate?.name ?? "the call" }
  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: detector.ended ? "phone.down" : "video")
        .font(.system(size: 19, weight: .regular)).foregroundStyle(RailPalette.secondary)
        .frame(width: 26)
      VStack(alignment: .leading, spacing: 3) {
        Text(detector.ended ? "Did the call end?" : "Meeting detected")
          .font(.system(size: 15, weight: .semibold))
        HStack(spacing: 6) {
          Circle().fill(detector.ended ? RailPalette.red : Color.green).frame(width: 6, height: 6)
          Text(subtitle).lineLimit(1)
        }.font(.system(size: 11)).foregroundStyle(RailPalette.secondary)
      }
      Spacer(minLength: 8)
      if detector.ended {
        Button("Keep recording") { detector.keepRecording() }.buttonStyle(.plain)
          .font(.system(size: 12)).foregroundStyle(RailPalette.secondary)
        action("Stop and save", symbol: "stop.fill") { detector.stopEndedMeeting() }
      } else {
        HStack(spacing: 0) {
          action("Record", symbol: "record.circle") { detector.accept() }
          Rectangle().fill(RailPalette.base.opacity(0.15)).frame(width: 1, height: 26)
          Menu {
            Button("Snooze 2 minutes") { detector.dismiss(snooze: true) }
            Button("Not now") { detector.dismiss() }
          } label: {
            Image(systemName: "chevron.up").font(.system(size: 11, weight: .semibold))
              .frame(width: 30, height: 36)
          }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tint(RailPalette.base)
            .accessibilityLabel("More options")
        }.foregroundStyle(RailPalette.base)
          .background(RailPalette.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      }
    }
    .padding(.horizontal, 18).padding(.vertical, 14).frame(minWidth: 380)
    .background { RailSurface(cornerRadius: 22) }
    .overlay(alignment: .topLeading) { if !detector.ended { close.offset(x: -9, y: -9) } }
    .foregroundStyle(RailPalette.ink).tint(RailPalette.accent)
    .padding(12).fixedSize()  // Room for the close button outside the pill's corner.
  }
  /// The consent and capture caveats stay visible: they decide whether recording is OK.
  private var subtitle: String {
    if detector.ended { return "\(name) stopped using the mic. Still recording." }
    return detector.candidate?.browser == true
      ? "\(name) · capture can include other tabs" : "\(name) · tell everyone before you record"
  }
  private func action(_ title: String, symbol: String, run: @escaping () -> Void) -> some View {
    Button(action: run) {
      HStack(spacing: 8) {
        Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
          .foregroundStyle(RailPalette.ink).frame(width: 24, height: 24)
          .background(RailPalette.base, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        Text(title).font(.system(size: 13, weight: .medium))
      }.padding(.leading, 6).padding(.trailing, 12).frame(height: 36)
        .foregroundStyle(RailPalette.base)
        .background(RailPalette.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }.buttonStyle(.plain)
  }
  /// Not now, ringed by the 10-second countdown before the prompt dismisses itself.
  private var close: some View {
    Button { detector.dismiss() } label: {
      ZStack {
        Circle().fill(RailPalette.base)
        Circle().strokeBorder(.white.opacity(0.14))
        Circle().trim(from: 0, to: Double(detector.remaining) / 10)
          .stroke(RailPalette.secondary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
          .rotationEffect(.degrees(-90)).padding(0.75)
          .animation(reduceMotion ? nil : .linear(duration: 1), value: detector.remaining)
        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
          .foregroundStyle(RailPalette.secondary)
      }.frame(width: 24, height: 24)
    }.buttonStyle(.plain)
      .accessibilityLabel("Not now, dismisses in \(detector.remaining) seconds")
  }
}
