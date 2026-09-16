import AppKit
import QuartzCore
import SwiftUI
import ChupCore

final class NonactivatingPanel: NSPanel {
  var keyboardRequested = false
  override var canBecomeKey: Bool { keyboardRequested }
  override var canBecomeMain: Bool { false }
}

@MainActor final class RailPresentation: ObservableObject {
  @Published var expanded: Bool
  @Published var keyboardAccess = false
  @Published var drawer: String?
  init(expanded: Bool = false, drawer: String? = nil) {
    self.expanded = expanded
    self.drawer = drawer
  }
}

extension WorkspaceState {
  var hasPersistentRailActivity: Bool {
    meetingStatus != .idle || voiceScope != nil || addressing
  }
  var hasRailActivity: Bool {
    hasPersistentRailActivity || dictationStatus != .idle
  }
  var compactDictationVisible: Bool {
    dictationStatus == .listening || dictationStatus == .processing || dictationFeedback != nil || dictationMicMessage != nil
  }
}

@MainActor final class HoverRailController {
  private let panel: NonactivatingPanel
  private let presentation = RailPresentation()
  private let labelPanel = NonactivatingPanel(
    contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
    defer: false)
  private weak var state: WorkspaceState?
  private var hoverTask: Task<Void, Never>?
  private var exitTask: Task<Void, Never>?
  private var displayObserver: NSObjectProtocol?
  private var anchor: NSPoint?
  private var keyboardDestination: TextInsertion.Destination?
  init(state: WorkspaceState) {
    self.state = state
    panel = NonactivatingPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    panel.isFloatingPanel = true
    panel.becomesKeyOnlyIfNeeded = true
    panel.setAccessibilityLabel("Chup! floating voice controls")
    panel.level = .statusBar
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [
      .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
    ]
    panel.backgroundColor = .clear
    panel.appearance = NSAppearance(named: .darkAqua)
    panel.isOpaque = false
    panel.hasShadow = true
    panel.acceptsMouseMovedEvents = true
    labelPanel.backgroundColor = .clear
    labelPanel.isOpaque = false
    labelPanel.hasShadow = true
    labelPanel.ignoresMouseEvents = true
    labelPanel.appearance = NSAppearance(named: .darkAqua)
    labelPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    panel.addChildWindow(labelPanel, ordered: .above)
    displayObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in DispatchQueue.main.async { self?.relocate() } }
    // Keep the host and tracking area alive through expansion and drawer transitions.
    let host = TrackingHost(
      rootView: RailContent(
        state: state, presentation: presentation,
        action: { [weak self] in self?.select($0) }, drag: { [weak self] in self?.drag() },
        labelOverlay: { [weak self] in self?.showLabel($0, anchor: $1) },
        moveFocus: { [weak self] forward in
          if forward { self?.panel.selectNextKeyView(nil) } else { self?.panel.selectPreviousKeyView(nil) }
        }))
    host.enter = { [weak self] in self?.entered() }
    host.exit = { [weak self] in self?.exited() }
    panel.contentView = host
    relocate()
  }
  func focusControls() {
    keyboardDestination = state?.insertion.capture()
    hoverTask?.cancel(); exitTask?.cancel()
    panel.keyboardRequested = true
    presentation.keyboardAccess = true
    transition(expanded: true)
    panel.makeKeyAndOrderFront(nil)
  }
  static func validateRestingPlacement() async throws {
    let state = WorkspaceState(preview: true)
    defer { try? FileManager.default.removeItem(at: state.root) }
    state.railDock = "right"
    let controller = HoverRailController(state: state)
    defer { controller.hide() }
    for screen in NSScreen.screens {
      controller.anchor = NSPoint(x: screen.frame.midX, y: screen.visibleFrame.midY)
      state.dictationStatus = .error
      controller.position()
      guard controller.panel.frame.size == NSSize(width: 26, height: 64),
        abs(controller.panel.frame.maxX - screen.frame.maxX) < 0.5 else {
        throw WorkspaceError.message("Error rail is not docked to the physical screen edge.")
      }
      try await Task.sleep(for: .milliseconds(1700))
      controller.position()
      guard state.dictationStatus == .idle,
        controller.panel.frame.size == NSSize(width: 10, height: 36),
        abs(controller.panel.frame.maxX - screen.frame.maxX) < 0.5,
        !controller.panel.isKeyWindow else {
        throw WorkspaceError.message("Error rail did not return to its tiny resting handle.")
      }
    }
    print("PASS: real right-edge error rail returns to 10 × 36 after 1.5 seconds, keeping a 2-point physical-edge inset.")
  }
  @discardableResult func dismissKeyboard() -> Bool {
    guard presentation.keyboardAccess else { return false }
    presentation.keyboardAccess = false
    panel.resignKey()
    panel.keyboardRequested = false
    keyboardDestination = nil
    transition(expanded: false)
    return true
  }
  func refresh() {
    guard let state else { return }
    if state.showRail && (!state.compactDictationVisible || state.hasPersistentRailActivity) { show() }
    else { hide() }
  }
  func show() {
    guard let state, !state.compactDictationVisible || state.hasPersistentRailActivity else { hide(); return }
    relocate()
    panel.orderFrontRegardless()
  }
  func hide() {
    _ = dismissKeyboard()
    hoverTask?.cancel()
    exitTask?.cancel()
    labelPanel.orderOut(nil)
    panel.orderOut(nil)
    presentation.expanded = false
    presentation.drawer = nil
  }
  private var screen: NSScreen {
    NSScreen.screens.first(where: { $0.frame.contains(anchor ?? NSEvent.mouseLocation) })
      ?? NSScreen.main ?? NSScreen.screens[0]
  }
  private var screenKey: String {
    "rail-position-\(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? "main")"
  }
  func relocate() {
    if anchor == nil, let stored = UserDefaults.standard.array(forKey: screenKey) as? [Double],
      stored.count == 2
    {
      anchor = NSPoint(x: stored[0], y: stored[1])
    }
    position()
  }
  private func position(duration: Double = 0) {
    guard let state else { return }
    let size: NSSize =
      presentation.drawer != nil
      ? NSSize(width: 300, height: 230)
      : presentation.expanded
        ? NSSize(
          width: state.railDock == "bottom" ? 188 : 44,
          height: state.railDock == "bottom" ? 44 : 188)
        : NSSize(
          width: state.railDock == "bottom" ? (state.hasRailActivity ? 64 : 36) : (state.hasRailActivity ? 26 : 10),
          height: state.railDock == "bottom" ? (state.hasRailActivity ? 26 : 10) : (state.hasRailActivity ? 64 : 36))
    let target = FloatingEdgePlacement.frame(size: size, screen: screen.frame,
      visible: screen.visibleFrame, edge: state.railDock,
      along: state.railDock == "bottom" ? anchor?.x : anchor?.y,
      inset: state.railDock == "bottom" ? 2 : 0)
    if duration == 0 {
      panel.setFrame(target, display: true)
    } else {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = duration
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        panel.animator().setFrame(target, display: true)
      }
    }
  }
  private func showLabel(_ text: String?, anchor: NSRect) {
    guard let text, presentation.expanded, presentation.drawer == nil, panel.isVisible else {
      labelPanel.orderOut(nil)
      return
    }
    let host = NSHostingView(rootView: RailOverlayLabel(title: text))
    let size = host.fittingSize
    let visible = screen.visibleFrame
    var origin: NSPoint
    switch state?.railDock {
    case "left": origin = NSPoint(x: panel.frame.maxX + 9, y: anchor.midY - size.height / 2)
    case "bottom": origin = NSPoint(x: anchor.midX - size.width / 2, y: panel.frame.maxY + 9)
    default:
      origin = NSPoint(x: panel.frame.minX - size.width - 9, y: anchor.midY - size.height / 2)
    }
    origin.x = min(visible.maxX - size.width - 6, max(visible.minX + 6, origin.x))
    origin.y = min(visible.maxY - size.height - 6, max(visible.minY + 6, origin.y))
    labelPanel.contentView = host
    labelPanel.setFrame(NSRect(origin: origin, size: size), display: true)
    labelPanel.orderFrontRegardless()
  }
  private func transition(expanded: Bool, drawer: String? = nil) {
    labelPanel.orderOut(nil)
    let duration =
      NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : expanded ? 0.24 : 0.18
    withAnimation(duration == 0 ? nil : .easeOut(duration: duration)) {
      presentation.expanded = expanded
      presentation.drawer = drawer
    }
    position(duration: duration)
  }
  private func entered() {
    exitTask?.cancel()
    guard !presentation.expanded else { return }
    hoverTask?.cancel()
    hoverTask = Task {
      try? await Task.sleep(for: .milliseconds(160))
      guard !Task.isCancelled else { return }
      transition(expanded: true)
    }
  }
  private func exited() {
    guard !presentation.keyboardAccess else { return }
    hoverTask?.cancel()
    labelPanel.orderOut(nil)
    exitTask?.cancel()
    exitTask = Task {
      try? await Task.sleep(for: .milliseconds(450))
      guard !Task.isCancelled else { return }
      // Geometry only: the corridor adds no invisible click-catching window.
      if panel.frame.insetBy(dx: -16, dy: -16).contains(NSEvent.mouseLocation) {
        exited()
        return
      }
      transition(expanded: false)
    }
  }
  private func drag() {
    hoverTask?.cancel()
    anchor = NSEvent.mouseLocation
    UserDefaults.standard.set([anchor!.x, anchor!.y], forKey: screenKey)
    position()
  }
  private func select(_ action: String) {
    guard let state else { return }
    switch action {
    case "focus": focusControls()
    case "dismiss": _ = dismissKeyboard()
    case "dictate":
      let captured = keyboardDestination
      let fromKeyboard = presentation.keyboardAccess
      _ = dismissKeyboard()
      if fromKeyboard && state.dictationStatus != .listening {
        state.beginDictation(captured: captured, useCaptured: true)
      } else { state.toggleDictation() }
    case "meeting": transition(expanded: true, drawer: "Meeting")
    case "assistant": transition(expanded: true, drawer: "Assistant")
    case "settings":
      state.page = .settings
      state.reveal?()
    case "openMeeting":
      if let id = state.activeMeetingID { state.selectMeeting(id) } else { state.newMeeting() }
      state.page = .meetings
      state.reveal?()
    case "ask":
      state.assistantVisible = true
      state.reveal?()
    case "pause": state.meetingStatus == .paused ? state.resumeMeeting() : state.pauseMeeting()
    case "stop": state.stopMeeting()
    default: transition(expanded: true)
    }
  }
}

final class TrackingHost<Content: View>: NSHostingView<Content> {
  var enter: (() -> Void)?
  var exit: (() -> Void)?
  private var tracking: NSTrackingArea?
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    tracking = NSTrackingArea(
      rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self,
      userInfo: nil)
    addTrackingArea(tracking!)
  }
  override func mouseEntered(with event: NSEvent) { enter?() }
  override func mouseExited(with event: NSEvent) { exit?() }
}

enum RailPalette {
  static let ink = Color(red: 0.98, green: 0.96, blue: 0.92)
  static let secondary = Color(red: 0.73, green: 0.73, blue: 0.70)
  static let olive = Color(red: 0.75, green: 0.80, blue: 0.63)
  static let red = Color(red: 0.98, green: 0.49, blue: 0.42)
  static let base = Color(red: 0.12, green: 0.13, blue: 0.13)
}

/// AppKit material works on macOS 15; no dependency on macOS 26 Liquid Glass.
private struct RailMaterial: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .hudWindow
    view.blendingMode = .behindWindow
    view.state = .active
    view.appearance = NSAppearance(named: .darkAqua)
    return view
  }
  func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct RailSurface: View {
  var tintOpacity: Double = 0.72
  var cornerRadius: CGFloat = 18
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast
  var liveGlass = true
  var body: some View {
    ZStack {
      if liveGlass && !reduceTransparency {
        RailMaterial()
        RailPalette.base.opacity(tintOpacity)
      } else {
        RailPalette.base
      }
      LinearGradient(
        colors: [.white.opacity(0.09), .clear, .black.opacity(0.09)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .strokeBorder(Color.black.opacity(contrast == .increased ? 0.72 : 0.58), lineWidth: 1)
    }
    .accessibilityHidden(true)
  }
}

struct RailContent: View {
  @ObservedObject var state: WorkspaceState
  @ObservedObject var presentation: RailPresentation
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast
  var liveGlass = true
  let action: (String) -> Void
  let drag: () -> Void
  var labelOverlay: (String?, NSRect) -> Void = { _, _ in }
  var moveFocus: (Bool) -> Void = { _ in }
  private var recording: Bool { state.meetingStatus == .recording }
  private var listening: Bool { state.dictationStatus == .listening || state.addressing }
  private var processing: Bool { state.dictationStatus == .processing }
  private var speaking: Bool { state.voiceScope != nil && state.voiceRouter.level > 0 }
  private var voiceLevel: Float { speaking ? state.voiceRouter.level : state.micLevel }
  private var statusIcon: String {
    if state.voiceScope?.mode == .broadcast { return "dot.radiowaves.left.and.right" }
    if state.voiceRouter.privateInput { return "mic.slash.fill" }
    if speaking { return "speaker.wave.2.fill" }
    if recording { return "record.circle.fill" }
    if state.meetingStatus == .paused { return "pause.circle" }
    if listening { return "waveform" }
    if state.dictationStatus == .processing { return "ellipsis.circle" }
    if state.dictationStatus == .error { return "exclamationmark.circle" }
    return "circle.dotted"
  }
  private var statusColor: Color {
    recording || listening || state.dictationStatus == .error
      ? RailPalette.red : RailPalette.secondary
  }
  var body: some View {
    Group {
      if !presentation.expanded {
        handle.transition(.opacity)
      } else if let drawer = presentation.drawer {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text(drawer).font(.system(size: 17, weight: .semibold))
            Spacer()
            Button {
              action("back")
            } label: {
              Image(systemName: "chevron.left").padding(6)
            }
            .buttonStyle(RailButtonStyle()).accessibilityLabel("Back to voice controls")
          }
          status
          if drawer == "Meeting" {
            row(
              state.activeMeetingID == nil ? "Open meeting setup" : "Open meeting notes",
              "doc.text", "openMeeting")
            if state.activeMeetingID != nil {
              HStack {
                Button(state.meetingStatus == .paused ? "Resume" : "Pause") { action("pause") }
                Button("Stop & save") { action("stop") }
              }.buttonStyle(.bordered)
            }
          } else {
            Label("Private text · this meeting", systemImage: "lock").font(.caption)
              .foregroundStyle(RailPalette.secondary)
            row("Ask assistant", "sparkle", "ask")
          }
          Spacer(minLength: 0)
        }.padding(16).transition(.opacity)
      } else {
        let bottom = state.railDock == "bottom"
        let layout =
          bottom ? AnyLayout(HStackLayout(spacing: 4)) : AnyLayout(VStackLayout(spacing: 4))
        layout {
          activityGlyph
            .frame(width: bottom ? 16 : 32, height: bottom ? 32 : 16)
            .accessibilityLabel(state.statusText).help(state.statusText)
          icon("Dictate", "waveform", "dictate")
          icon("Meeting", "person.2", "meeting")
          icon("Assistant", "sparkle", "assistant")
          Rectangle().fill(.white.opacity(0.12))
            .frame(width: bottom ? 1 : 20, height: bottom ? 20 : 1).padding(2)
            .accessibilityHidden(true)
          icon("Settings", "gearshape", "settings")
        }.padding(6).transition(.opacity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background {
      if !presentation.expanded && !state.hasRailActivity {
        Capsule().fill(RailPalette.base.opacity(reduceTransparency ? 1 : 0.8))
          .overlay { Capsule().strokeBorder(.white.opacity(contrast == .increased ? 0.5 : 0), lineWidth: 1) }
      } else { RailSurface(cornerRadius: presentation.drawer == nil ? 22 : 18, liveGlass: liveGlass) }
    }
    .clipShape(RoundedRectangle(cornerRadius: presentation.drawer == nil ? 22 : 18, style: .continuous))
    .foregroundStyle(RailPalette.ink).tint(RailPalette.olive)
    .environment(\.colorScheme, .dark)
    .onExitCommand { action("dismiss") }
    .onMoveCommand { direction in
      guard presentation.keyboardAccess else { return }
      moveFocus(direction == .down || direction == .right)
    }
  }
  private var handle: some View {
    let bottom = state.railDock == "bottom"
    return Group {
      if !state.hasRailActivity {
        grip(horizontal: bottom)
      } else if bottom {
        HStack(spacing: 6) {
          grip(horizontal: true)
          statusGlyph
        }
      } else {
        VStack(spacing: 6) {
          statusGlyph
        }
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
      .gesture(DragGesture(minimumDistance: 5).onChanged { _ in drag() })
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Chup! rail. \(state.statusText)")
      .accessibilityAddTraits(.isButton)
      .accessibilityAction { action("focus") }
      .help(state.statusText)
  }
  private func grip(horizontal: Bool) -> some View {
    Capsule().fill(recording || listening ? RailPalette.red : RailPalette.secondary)
      .frame(width: horizontal ? 18 : 2, height: horizontal ? 2 : 18)
  }
  @ViewBuilder private var statusGlyph: some View {
    if processing || recording || listening || speaking || state.voiceRouter.privateInput
      || state.meetingStatus == .paused || state.dictationStatus == .error
    {
      activityGlyph
    }
  }
  @ViewBuilder private var activityGlyph: some View {
    if processing {
      HStack(spacing: 3) {
        ProcessingCircle(size: 13)
        if recording || state.voiceScope?.mode == .broadcast {
          Image(systemName: statusIcon).font(.system(size: 9)).foregroundStyle(RailPalette.red)
        }
      }.foregroundStyle(RailPalette.ink)
    } else if listening {
      HStack(spacing: 3) {
        VoiceWaveform(samples: state.micWaveform, width: 17, height: 18)
        if recording || state.voiceScope?.mode == .broadcast {
          Image(systemName: statusIcon).font(.system(size: 8)).foregroundStyle(RailPalette.red)
        }
      }
    } else {
      Image(systemName: statusIcon).font(.system(size: 11)).foregroundStyle(statusColor)
    }
  }
  private var status: some View {
    HStack(spacing: 6) {
      activityGlyph
      Text(processing ? "Processing dictation" : state.statusText).lineLimit(2).contentTransition(.opacity)
      if speaking && !listening {
        // A real input envelope, not a decorative animation pretending that audio is arriving.
        HStack(spacing: 2) {
          ForEach(0..<5) { index in
            Capsule().frame(
              width: 2, height: 3 + CGFloat(voiceLevel) * CGFloat([9, 16, 23, 16, 9][index]))
          }
        }.frame(height: 26)
          .animation(reduceMotion ? nil : .easeOut(duration: 0.09), value: voiceLevel)
          .accessibilityHidden(true)
      }
    }.font(.system(size: 11, weight: .medium)).foregroundStyle(statusColor)
  }
  private func icon(_ title: String, _ symbol: String, _ key: String) -> some View {
    RailIconButton(
      title: title, symbol: symbol, action: { action(key) }, trackHover: liveGlass,
      labelOverlay: labelOverlay, preferredFocus: presentation.keyboardAccess && key == "dictate",
      waveform: key == "dictate" && state.dictationStatus == .listening ? state.micWaveform : nil,
      processing: key == "dictate" && processing)
  }
  private func row(_ title: String, _ icon: String, _ key: String) -> some View {
    Button {
      action(key)
    } label: {
      HStack(spacing: 11) {
        Image(systemName: icon).frame(width: 19).foregroundStyle(RailPalette.secondary)
        Text(title)
        Spacer(minLength: 0)
      }.font(.system(size: 13, weight: .medium)).padding(.horizontal, 9).padding(.vertical, 10)
        .contentShape(Rectangle())
    }.buttonStyle(RailButtonStyle())
  }
}

struct RailButtonStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  func makeBody(configuration: Configuration) -> some View {
    RailButtonBody(configuration: configuration, reduceMotion: reduceMotion)
  }
  private struct RailButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let reduceMotion: Bool
    @State private var hovering = false
    var body: some View {
      configuration.label
        .background(
          .white.opacity(configuration.isPressed ? 0.15 : hovering ? 0.08 : 0),
          in: RoundedRectangle(cornerRadius: 16)
        )
        .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
        .onHover { hovering = $0 }
    }
  }
}

struct RailOverlayLabel: View {
  let title: String
  var body: some View {
    Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(RailPalette.ink)
      .padding(.horizontal, 10).padding(.vertical, 6)
      .background { RailSurface(cornerRadius: 12) }
      .fixedSize().environment(\.colorScheme, .dark)
  }
}

private struct RailIconButton: View {
  let title: String
  let symbol: String
  let action: () -> Void
  var trackHover = true
  let labelOverlay: (String?, NSRect) -> Void
  var preferredFocus = false
  var waveform: [Float]?
  var processing = false
  @FocusState private var focused: Bool
  var body: some View {
    Button(action: action) {
      Group {
        if processing { ProcessingCircle(size: 19) }
        else if let waveform { VoiceWaveform(samples: waveform, width: 25, height: 26) }
        else { Image(systemName: symbol).font(.system(size: 15, weight: .medium)) }
      }.frame(width: 32, height: 32).contentShape(Circle())
    }.buttonStyle(RailButtonStyle()).accessibilityLabel(title).focused($focused)
      .onAppear { if preferredFocus { focused = true } }
      .onChange(of: preferredFocus) { _, value in if value { focused = true } }
      .onKeyPress(.return) { action(); return .handled }
      .background {
        if trackHover { RailLabelAnchor(title: title, focused: focused, show: labelOverlay) }
      }
  }
}

/// Separate click-through label windows let labels extend inward without widening the hit area.
private struct RailLabelAnchor: NSViewRepresentable {
  let title: String
  let focused: Bool
  let show: (String?, NSRect) -> Void
  func makeNSView(context: Context) -> AnchorView { AnchorView() }
  func updateNSView(_ view: AnchorView, context: Context) {
    view.title = title
    view.show = show
    if view.focused != focused {
      view.focused = focused
      view.displayLabel(focused || view.hovered)
    }
  }
  final class AnchorView: NSView {
    var title = ""
    var focused = false
    var hovered = false
    var show: (String?, NSRect) -> Void = { _, _ in }
    private var tracking: NSTrackingArea?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
      super.updateTrackingAreas()
      if let tracking { removeTrackingArea(tracking) }
      tracking = NSTrackingArea(
        rect: bounds,
        options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil
      )
      addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) {
      hovered = true
      displayLabel(true)
    }
    override func mouseExited(with event: NSEvent) {
      hovered = false
      displayLabel(focused)
    }
    func displayLabel(_ visible: Bool) {
      guard let window else { return }
      show(visible ? title : nil, window.convertToScreen(convert(bounds, to: nil)))
    }
  }
}
