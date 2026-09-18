import AppKit
import ChupCore
import Combine
import DynamicNotchKit
import SwiftUI

/// Native DynamicNotchKit-backed voice surface. The package owns the notch
/// safe-area measurement, panel geometry, masking and transitions; Chup! only
/// supplies its live state and content. With the island presenting, the hover
/// rail stays hidden and its controls appear here instead.
@MainActor final class DynamicIslandController {
  enum Presentation { case hidden, compact, expanded }

  private weak var state: WorkspaceState?
  private let notch: DynamicNotch<DynamicIslandContent, IslandGlyph, IslandLevel>
  private var transitionTask: Task<Void, Never>?
  private var presented: Presentation = .hidden
  private var desired: Presentation = .hidden
  private var hoverObserver: AnyCancellable?

  init(state: WorkspaceState) {
    self.state = state
    notch = DynamicNotch(hoverBehavior: .all, style: .auto) {
      DynamicIslandContent(state: state)
    } compactLeading: {
      IslandGlyph(state: state, size: 16, hideAtRest: true)
    } compactTrailing: {
      IslandLevel(state: state)
    }
    // Hovering the compact island opens the controls, the way hovering opened
    // the rail. The package publishes its own hover tracking.
    // Debounced: the pointer merely crossing the notch on its way to the menu
    // bar should not open the island.
    hoverObserver = notch.$isHovering.dropFirst()
      .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
      .sink { [weak self] _ in
        Task { @MainActor in self?.refresh() }
      }
  }

  /// A screen without a notch gets no compact state from the package, so the
  /// rail stays in charge there and the island never takes over.
  static func hasNotch(_ screen: NSScreen?) -> Bool {
    guard let screen else { return false }
    return screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
  }

  /// Pure decision, so the policy is checkable offline without a display.
  /// Compact stays present whenever the island owns the rail's job, so the
  /// notch is always there to hover; at rest it draws nothing.
  static func presentation(dictating: Bool, activity: Bool, hovering: Bool, enabled: Bool,
    notchScreen: Bool) -> Presentation
  {
    guard enabled, notchScreen else { return .hidden }
    return dictating || hovering ? .expanded : .compact
  }

  /// The screen the user is working on: the one under the pointer, falling back
  /// to the focused screen. Both the island and the rail are hover targets, so
  /// the pointer decides which display owns them — the rail picks its screen the
  /// same way, and on an external display there is no notch to hover.
  static var activeScreen: NSScreen {
    NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
      ?? NSScreen.main ?? NSScreen.screens[0]
  }

  private var screen: NSScreen { Self.activeScreen }

  func refresh() {
    guard let state else { return }
    let dictating = state.dictationStatus == .listening || state.dictationStatus == .processing
    let target = Self.presentation(
      dictating: dictating, activity: state.hasRailActivity, hovering: notch.isHovering,
      enabled: state.dynamicIslandEnabled, notchScreen: Self.hasNotch(screen))
    guard target != desired else { return }
    desired = target
    // Transitions run one at a time to completion. The package animates through
    // a detached hidden step, so cancelling one mid-flight left its window state
    // and ours disagreeing — the island stayed expanded with nothing happening.
    if transitionTask == nil {
      transitionTask = Task { @MainActor [weak self] in
        while let self, self.presented != self.desired {
          let next = self.desired
          switch next {
          case .expanded: await self.notch.expand(on: self.screen)
          case .compact: await self.notch.compact(on: self.screen)
          case .hidden: await self.notch.hide()
          }
          self.presented = next
        }
        self?.transitionTask = nil
      }
    }
    state.rail?.refresh()
  }

  static func validatePresentationPolicy() throws {
    let cases: [(Bool, Bool, Bool, Bool, Bool, Presentation)] = [
      // dictating, activity, hovering, enabled, notch, expected
      (true, true, false, true, true, .expanded),
      (false, true, false, true, true, .compact),
      (false, true, true, true, true, .expanded),
      (false, false, true, true, true, .expanded),
      (false, false, false, true, true, .compact),
      (true, true, false, false, true, .hidden),
      (true, true, false, true, false, .hidden),
    ]
    for (dictating, activity, hovering, enabled, notch, expected) in cases {
      let actual = presentation(
        dictating: dictating, activity: activity, hovering: hovering, enabled: enabled,
        notchScreen: notch)
      guard actual == expected else {
        throw WorkspaceError.message(
          "Island policy returned \(actual) instead of \(expected) for dictating=\(dictating) activity=\(activity) hovering=\(hovering) enabled=\(enabled) notch=\(notch).")
      }
    }
    print(
      "PASS: island shows only on a notch screen when enabled — expanded while dictating or hovered, compact otherwise so the notch stays hoverable, hidden when disabled or off a notch; the rail keeps every other case.")
  }
}

/// The live input envelope beside the notch: the rail's voice animation, compact.
/// Silent at rest, so an idle island is only a hover target.
struct IslandLevel: View {
  @ObservedObject var state: WorkspaceState
  var body: some View {
    if state.hasRailActivity {
      VoiceWaveform(
        samples: state.micWaveform, width: 20, height: 16,
        color: state.meetingStatus == .recording ? RailPalette.red : .white)
    }
  }
}

/// The rail's activity glyph, in island form: a real input envelope while
/// listening, a spinner while transcribing, otherwise the status symbol.
struct IslandGlyph: View {
  @ObservedObject var state: WorkspaceState
  var size: CGFloat = 22
  /// Beside the notch there is nothing to say when nothing is happening.
  var hideAtRest = false

  private var listening: Bool { state.dictationStatus == .listening || state.addressing }
  private var recording: Bool { state.meetingStatus == .recording }

  private var symbol: String {
    if state.voiceRouter.privateInput { return "mic.slash.fill" }
    if recording { return "record.circle.fill" }
    if state.meetingStatus == .paused { return "pause.circle" }
    if state.dictationStatus == .error { return "exclamationmark.circle" }
    return "waveform"
  }

  var body: some View {
    if state.dictationStatus == .processing {
      ProcessingCircle(size: size * 0.82).foregroundStyle(.white)
    } else if listening || recording {
      VoiceWaveform(
        samples: state.micWaveform, width: size, height: size,
        color: recording && !listening ? RailPalette.red : .white)
    } else if !hideAtRest || state.hasRailActivity {
      Image(systemName: symbol)
        .font(.system(size: size * 0.6, weight: .medium))
        .foregroundStyle(state.dictationStatus == .error ? RailPalette.red : .white.opacity(0.62))
    }
  }
}

/// Content occupies only the visible band below the physical notch. The
/// package supplies the notch-height inset and black masked surface around it.
/// With the island on, the hover rail stays hidden and its controls live here.
struct DynamicIslandContent: View {
  @ObservedObject var state: WorkspaceState
  /// Design renders pin the hover state; live use tracks the pointer.
  var pinnedHover: Bool?
  @State private var isHovering = false

  private var hovering: Bool { pinnedHover ?? isHovering }
  private var transcribing: Bool {
    state.dictationStatus == .listening || state.dictationStatus == .processing
  }
  private var recording: Bool {
    state.meetingStatus == .recording || state.meetingStatus == .paused
  }

  private var text: String {
    state.dictationLiveText.isEmpty
      ? (state.dictationStatus == .processing ? "Transcribing…" : "Listening…")
      : state.dictationLiveText
  }

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      IslandGlyph(state: state, size: 22)
      if transcribing {
        MarqueeText(text: text, animate: state.dictationStatus == .listening)
          .frame(maxWidth: .infinity, alignment: .leading)
        if hovering {
          circleButton("pencil", "Review before pasting") { state.requestDictationReview() }
            .transition(.scale.combined(with: .opacity))
        }
      } else {
        Text(state.statusText)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(.white.opacity(0.85))
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      if hovering { controls.transition(.opacity) }
    }
    .padding(.horizontal, 18)
    .frame(width: hovering ? 560 : (transcribing ? 340 : 420), height: 64, alignment: .center)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Chup! island · " + (transcribing ? text : state.statusText))
    .onHover { entered in
      withAnimation(.easeInOut(duration: 0.16)) { isHovering = entered }
    }
    .animation(.smooth(duration: 0.28), value: state.dictationStatus)
  }

  /// The rail's icon row. Recording swaps Meeting for pause and stop, so a
  /// running capture is never more than one click from being controlled.
  @ViewBuilder private var controls: some View {
    HStack(spacing: 4) {
      circleButton("mic", "Dictate") { state.toggleDictation() }
      if recording {
        circleButton(state.meetingStatus == .paused ? "play" : "pause", "Pause or resume") {
          state.meetingStatus == .paused ? state.resumeMeeting() : state.pauseMeeting()
        }
        circleButton("stop.fill", "Stop and save") { state.stopMeeting() }
      } else {
        circleButton("person.2", "Meeting") {
          if let id = state.activeMeetingID { state.selectMeeting(id) } else { state.newMeeting() }
          state.page = .meetings
          state.reveal?()
        }
      }
      circleButton("sparkle", "Assistant") {
        state.assistantVisible = true
        state.reveal?()
      }
      circleButton("gearshape", "Settings") {
        state.page = .settings
        state.reveal?()
      }
    }
  }

  private func circleButton(_ symbol: String, _ title: String, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .frame(width: 26, height: 26)
        .background(.white.opacity(0.16), in: Circle())
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
    .help(title)
  }
}

/// A compact, non-interactive marquee for live dictation. It only animates
/// when the sentence is wider than the island's available text lane.
private struct MarqueeText: View {
  let text: String
  let animate: Bool
  @State private var contentWidth: CGFloat = 0
  @State private var offset: CGFloat = 0

  var body: some View {
    GeometryReader { proxy in
      let overflow = max(0, contentWidth - proxy.size.width)
      Text(text)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .background {
          GeometryReader { textProxy in
            Color.clear.preference(key: MarqueeWidthKey.self, value: textProxy.size.width)
          }
        }
        .offset(x: overflow > 1 ? -min(offset, overflow) : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onPreferenceChange(MarqueeWidthKey.self) { width in
          contentWidth = width
          followTail(overflow: max(0, width - proxy.size.width))
        }
        .onAppear { followTail(overflow: overflow, animated: false) }
    }
    .clipped()
    .frame(height: 24, alignment: .center)
    .onChange(of: text) { _, _ in
      offset = 0
      if animate { followTail(overflow: max(0, contentWidth), animated: false) }
    }
    .onChange(of: animate) { _, enabled in
      if enabled { followTail(overflow: max(0, contentWidth), animated: false) }
      else { offset = 0 }
    }
  }

  private func followTail(overflow: CGFloat, animated: Bool = true) {
    guard animate, overflow > 1 else {
      offset = 0
      return
    }
    if animated {
      withAnimation(.easeOut(duration: 0.22)) { offset = overflow }
    } else {
      offset = overflow
    }
  }
}

private struct MarqueeWidthKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
