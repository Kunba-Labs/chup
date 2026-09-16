import AppKit
import ChupCore
import QuartzCore
import SwiftUI

@MainActor final class DictationIndicatorController {
  private let panel: NonactivatingPanel
  private let host: NSHostingController<DictationIndicatorView>
  private var selectedScreen: NSScreen?
  private var observer: NSObjectProtocol?
  private weak var state: WorkspaceState?
  init(state: WorkspaceState) {
    self.state = state
    host = NSHostingController(rootView: DictationIndicatorView(state: state))
    host.sizingOptions = []
    panel = NonactivatingPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    panel.isFloatingPanel = true
    panel.level = .statusBar
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [
      .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
    ]
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.appearance = NSAppearance(named: .darkAqua)
    panel.setAccessibilityLabel("Chup! dictation status")
    panel.contentViewController = host
    observer = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in
      DispatchQueue.main.async { self?.position() }
    }
  }
  deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
  func show(on screen: NSScreen? = nil) {
    if !panel.isVisible {
      selectedScreen =
        screen ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        ?? NSScreen.main
    }
    let appearing = !panel.isVisible
    position()
    if appearing {
      panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
    }
    panel.orderFrontRegardless()  // No activation or key status; destination was captured first.
    if appearing {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14
        panel.animator().alphaValue = 1
      }
    }
  }
  func hide() {
    panel.orderOut(nil)
    selectedScreen = nil
  }
  static func validatePanelLayout() async throws {
    let state = WorkspaceState(preview: true)
    defer { try? FileManager.default.removeItem(at: state.root) }
    let controller = DictationIndicatorController(state: state)
    defer { controller.hide() }
    var transitions = 0
    state.dictationReady = true
    state.micWaveform = [0.2, 0.6, 0.95, 0.45, 0.75]
    for dock in ["right", "left", "bottom"] {
      state.railDock = dock
      for screen in NSScreen.screens {
        controller.hide()
        for index in 0..<18 {
          state.dictationMicMessage = nil
          state.dictationFeedback = nil
          state.dictationStatus = .listening
          switch index % 6 {
          case 1: state.dictationStatus = .processing
          case 2:
            state.dictationMicMessage =
              "Audio device or sample rate changed. Capture is paused; check the device, then resume."
          case 3: state.dictationFeedback = .copied
          case 4: state.dictationFeedback = .inserted
          case 5:
            state.dictationMicMessage =
              "No input detected. Check your microphone’s mute switch, connection and input selection. A disconnected USB or Bluetooth microphone may need to reconnect before you can resume capture."
          default: break
          }
          controller.show(on: screen)
          try await Task.sleep(for: .milliseconds(50))
          let message = controller.host.rootView.messageVisible
          let expectedWidth: CGFloat = message ? 320 : controller.host.rootView.compactSize.width
          let expectedHeight: CGFloat = message ? 56 : controller.host.rootView.compactSize.height
          guard abs(controller.panel.frame.width - expectedWidth) < 1,
            message || abs(controller.panel.frame.height - expectedHeight) < 1,
            controller.host.view.frame.size == controller.panel.frame.size,
            screen.frame.contains(controller.panel.frame),
            (dock != "right" || abs(controller.panel.frame.maxX - (screen.frame.maxX - 2)) < 1.5),
            (dock != "left" || abs(controller.panel.frame.minX - (screen.frame.minX + 2)) < 1.5),
            !controller.panel.isKeyWindow
          else {
            print(
              "Invalid panel:", controller.panel.frame, "host:", controller.host.view.frame,
              "screen:", screen.visibleFrame)
            throw WorkspaceError.message(
              "Floating alert escaped its screen, clipped its host or stole focus.")
          }
          if index < 6, let directory = ProcessInfo.processInfo.environment["CHUP_PANEL_OUTPUT"] {
            let view = controller.host.view
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
              throw WorkspaceError.message("Cannot render the real alert window.")
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(
              to:
                URL(fileURLWithPath: directory).appendingPathComponent("panel-\(dock)-\(index).png")
            )
          }
          transitions += 1
        }
      }
    }
    print(
      "PASS: \(transitions) real panel transitions across \(NSScreen.screens.count) displays and three docks, including vertical waveform/processing, horizontal bottom controls, wrapped alerts and shrinking; content/window bounds agree, no focus stolen."
    )
    try await HoverRailController.validateRestingPlacement()
  }

  private func position() {
    let screen =
      NSScreen.screens.first { $0 == selectedScreen } ?? NSScreen.main ?? NSScreen.screens.first
    guard let screen else { return }
    let frame = screen.visibleFrame
    guard let state else { return }
    let inset: CGFloat = state.hasPersistentRailActivity ? 52 : 2
    let availableWidth = max(148, min(320, frame.width - inset - 16))
    host.rootView = DictationIndicatorView(state: state, alertWidth: availableWidth)
    // SwiftUI's fitting width can still describe the previous compact state.
    // Own the window width explicitly, before the hosting view expands, so its
    // right edge never grows out of the selected display.
    let width: CGFloat =
      host.rootView.messageVisible ? availableWidth : host.rootView.compactSize.width
    let fitted = host.sizeThatFits(in: CGSize(width: width, height: frame.height - 32))
    let size = CGSize(width: width, height: min(frame.height - 32, ceil(fitted.height)))
    let target = FloatingEdgePlacement.frame(size: size, screen: screen.frame,
      visible: frame, edge: state.railDock, inset: inset)
    // An earlier compact-frame animation can finish *after* a warning resize,
    // restoring the old x coordinate and pushing the wider alert offscreen.
    // Commit geometry atomically; animate opacity, waveform and spinner only.
    panel.setFrame(target, display: true)
  }
}
struct DictationIndicatorView: View {
  @ObservedObject var state: WorkspaceState
  var alertWidth: CGFloat = 320
  private let microphoneMessage: String?
  private let feedback: TextDeliveryResult?
  private let vertical: Bool
  // Layout is a value snapshot. Live waveform data stays observed, but a
  // published change cannot resize content before AppKit repositions its panel.
  init(state: WorkspaceState, alertWidth: CGFloat = 320) {
    self.state = state
    self.alertWidth = alertWidth
    microphoneMessage = state.dictationMicMessage
    feedback = state.dictationFeedback
    vertical = state.railDock != "bottom"
  }
  var compactSize: CGSize {
    let scale: CGFloat = 0.9
    return vertical
      ? CGSize(width: 36 * scale, height: (feedback?.isCompactCompletion == true ? 36 : 148) * scale)
      : CGSize(width: 148 * scale, height: 36 * scale)
  }
  var messageVisible: Bool { recovery || microphoneMessage != nil }
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var processing: Bool { state.dictationStatus == .processing || !state.dictationReady }
  private var recovery: Bool { feedback.map { !$0.isCompactCompletion } ?? false }
  private var status: String {
    microphoneMessage ?? feedback?.message
      ?? (state.dictationStatus == .processing
        ? "Thinking" : (state.dictationReady ? "Listening" : "Starting microphone"))
  }
  var body: some View {
    Group {
      if messageVisible {
        messageContent
      } else {
        compactContent
      }
    }
    .padding(.horizontal, messageVisible ? 12 : (vertical ? 6 : 8))
    .padding(.vertical, messageVisible ? 12 : (vertical ? 8 : 0))
    .frame(width: messageVisible ? alertWidth : compactSize.width)
    .frame(height: messageVisible ? nil : compactSize.height)
    .frame(minHeight: messageVisible ? 56 : nil)
    .fixedSize(horizontal: false, vertical: true)
    .foregroundStyle(RailPalette.ink)
    .background { RailSurface(tintOpacity: 0.72) }
    .clipShape(RoundedRectangle(cornerRadius: 18))
    .accessibilityElement(children: .contain).accessibilityLabel("Chup! · " + status)
    .help(status + " · " + state.microphoneLabel).environment(\.colorScheme, .dark)
  }
  private var messageContent: some View {
    HStack(spacing: 8) {
      if let message = microphoneMessage {
        Image(systemName: "mic.slash.fill").frame(width: 18).foregroundStyle(RailPalette.red)
        VStack(alignment: .leading, spacing: 3) {
          Text("Check microphone").font(.system(size: 12, weight: .semibold))
          Text(message).font(.system(size: 11)).foregroundStyle(RailPalette.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
        control("gearshape", label: "Choose microphone") { state.openMicrophoneSettings() }
        control("xmark", label: "Dismiss microphone message") { state.clearMicrophoneMessage() }
      } else if recovery, let feedback {
        Image(systemName: feedback.icon).font(.system(size: 17))
        VStack(alignment: .leading, spacing: 2) {
          Text(feedback.title).font(.system(size: 12, weight: .medium))
            .fixedSize(horizontal: false, vertical: true)
          Text(feedback.detail).font(.system(size: 11)).foregroundStyle(RailPalette.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
        control("xmark", label: "Dismiss message") { state.clearDictationFeedback() }
      }
    }
  }
  private var compactContent: some View {
    let layout =
      vertical ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
    return layout {
      if let feedback, feedback.isCompactCompletion {
        Image(systemName: feedback.icon).foregroundStyle(RailPalette.olive)
        if !vertical { Text(feedback.title).font(.system(size: 12, weight: .medium)) }
      } else {
        control("xmark", label: "Cancel dictation") { state.cancelDictation() }
        ZStack {
          if processing {
            ProcessingCircle(size: 18)
          } else {
            VoiceWaveform(
              samples: state.micWaveform, width: 68, height: 22,
              color: RailPalette.ink, barCount: 11
            )
            .rotationEffect(.degrees(vertical ? 90 : 0))
            .frame(width: vertical ? 22 : 68, height: vertical ? 68 : 22)
          }
        }.frame(width: vertical ? 24 : 68, height: vertical ? 68 : 24).accessibilityLabel(status)
        control("checkmark", label: "Finish dictation") { state.finishDictation() }
          .disabled(processing).opacity(processing ? 0.3 : 1)
      }
    }
  }
  private func control(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 10, weight: .bold))
        .frame(width: 24, height: 24).background(.white.opacity(0.12), in: Circle())
        .contentShape(Circle())
    }.buttonStyle(.plain).fixedSize().accessibilityLabel(label).help(label)
  }
}
