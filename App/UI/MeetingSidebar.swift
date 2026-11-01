import AppKit
import ChupCore
import SwiftUI

/// Notes column while recording (Wispr's Notepad): full height against the right screen edge, dragged anywhere by its header and kept there. Hidden from screen sharing, takes
/// keyboard focus without activating Chup!.
@MainActor final class MeetingSidebar: ObservableObject {
  @Published var collapsed = false
  private var closedFor: String?
  private var shownFor: String?
  private var timer: Timer?
  /// Where the user dragged the column (its top-left); nil keeps it docked at the edge.
  private var placed: NSPoint?
  private var placing = false
  /// Edge chosen from the move menu; nil follows the rail (opposite side).
  private var dockLeft: Bool?
  private weak var state: WorkspaceState?
  /// Column width: 20% wider than the original 360 pt card.
  static let width: CGFloat = 432
  private let panel = NonactivatingPanel(
    contentRect: NSRect(x: 0, y: 0, width: MeetingSidebar.width, height: 600),
    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
  init(state: WorkspaceState) {
    self.state = state
    panel.keyboardRequested = true
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.sharingType = .none
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.appearance = NSAppearance(named: .aqua)
    panel.hasShadow = true
    panel.contentView = NSHostingView(
      rootView: MeetingSidebarView(sidebar: self).environmentObject(state)
        .environment(\.colorScheme, .light))
    timer = MainActorTimer.repeating(every: 1) { [weak self] in self?.tick() }
    NotificationCenter.default.addObserver(
      forName: NSWindow.didMoveNotification, object: panel, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, !self.placing else { return }
        self.placed = NSPoint(x: self.panel.frame.minX, y: self.panel.frame.maxY)
      }
    }
  }
  private func tick() {
    guard let state, let id = state.activeMeetingID, closedFor != id else {
      if state?.activeMeetingID == nil { closedFor = nil }
      shownFor = nil
      panel.orderOut(nil)
      return
    }
    if shownFor != id {
      shownFor = id
      collapsed = false
      layout()
      panel.orderFrontRegardless()
    }
  }
  var visible: Bool { panel.isVisible }
  func toggle() {
    collapsed.toggle()
    layout()
  }
  func close() {
    closedFor = state?.activeMeetingID
    panel.orderOut(nil)
  }
  /// Right is the default edge; when the hover rail also sits there, the column stops short of it.
  private var railGap: CGFloat { state?.railDock == "right" ? 56 : 8 }
  /// Keyboard and VoiceOver route for moving the column: dock it to either screen edge.
  func dock(left: Bool) {
    placed = nil
    dockLeft = left
    layout()
  }
  private func layout() {
    // A saved spot on a display that is gone falls back to the main screen, clamped on screen.
    let screen = placed.flatMap { point in NSScreen.screens.first { $0.visibleFrame.insetBy(dx: -1, dy: -1).contains(point) } }
      ?? panel.screen ?? NSScreen.main ?? NSScreen.screens[0]
    let frame = screen.visibleFrame
    let left = dockLeft ?? false  // Right edge by default; the move menu can dock it left.
    // Docked: a column the full height of the screen. Placed: the user's spot, same top edge.
    let top = min(max(placed?.y ?? frame.maxY - 8, frame.minY + 120), frame.maxY)
    let x = min(max(placed?.x ?? (left ? frame.minX + 8 : frame.maxX - Self.width - railGap), frame.minX), frame.maxX - Self.width)
    let height = collapsed ? 56 : max(112, top - frame.minY - 8)
    placing = true
    panel.setFrame(NSRect(x: x, y: top - height, width: Self.width, height: height), display: true)
    placing = false
  }
}

/// Wispr-style notepad shown while a meeting records: Transcript (live bubbles) and
/// My thoughts tabs, warnings on top, recording controls pinned in the footer.
struct MeetingSidebarView: View {
  @EnvironmentObject var state: WorkspaceState
  @ObservedObject var sidebar: MeetingSidebar
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// The meeting a Discard confirmation is open for; a later meeting never inherits it.
  @State private var discardFor: String?
  @State private var tab = "Transcript"
  private var confirmDiscard: Bool { discardFor != nil && discardFor == state.activeMeetingID }
  private var onMeeting: Bool { state.selectedMeetingID == state.activeMeetingID }
  private var paused: Bool { state.meetingStatus == .paused }
  private var failed: Bool { state.meetingStatus == .error }
  /// Only the recording meeting's captions; a previous meeting's lines never carry over.
  private var lines: [TranscriptSegment] {
    state.liveLines.filter { $0.meetingID == state.activeMeetingID }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      if !sidebar.collapsed {
        if failed { errorBanner } else if state.inputLost || state.micSilentSeconds != nil { noAudioWarning }
        tabBar
        Group {
          if tab == "Transcript" { transcript } else { thoughts }
        }.frame(maxHeight: .infinity)
        footer
      }
    }.padding(14).frame(width: MeetingSidebar.width, alignment: .topLeading)
      .frame(maxHeight: .infinity, alignment: .top)
      .background(Palette.workspace, in: RoundedRectangle(cornerRadius: 18))
      .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.border) }
      .foregroundStyle(Palette.ink).tint(Palette.accent)
  }

  private var header: some View {
    HStack(spacing: 8) {
      Menu {
        Button("Dock to left edge") { sidebar.dock(left: true) }
        Button("Dock to right edge") { sidebar.dock(left: false) }
      } label: {
        Image(systemName: "line.3.horizontal").font(.system(size: 10))
      }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Drag the header to move, or dock to an edge").accessibilityLabel("Move notepad")
      Circle().fill(state.meetingStatus == .recording || failed ? Palette.red : Palette.secondary)
        .frame(width: 8, height: 8).accessibilityHidden(true)
      Text(failed ? "ERROR" : paused ? "PAUSED" : state.meetingStatus == .recording ? "REC" : "STARTING")
        .font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(Palette.secondary)
      Text(WorkspaceState.time(state.elapsed)).font(.system(size: 13, weight: .semibold).monospacedDigit())
      Text(state.activeMeeting?.title ?? "Meeting").font(.system(size: 13, weight: .medium)).lineLimit(1)
      Spacer()
      Button(action: sidebar.toggle) {
        Image(systemName: sidebar.collapsed ? "chevron.down" : "chevron.up")
      }.buttonStyle(.plain).accessibilityLabel(sidebar.collapsed ? "Expand notepad" : "Collapse notepad")
      Button(action: sidebar.close) { Image(systemName: "xmark") }.buttonStyle(.plain)
        .accessibilityLabel("Hide notepad for this meeting").help("Recording keeps going")
    }.foregroundStyle(Palette.secondary)
      // Drag the header to move the column; its buttons still take their clicks.
      .background { Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()) }
  }

  private var tabBar: some View {
    HStack(spacing: 18) {
      ForEach(["Transcript", "My thoughts"], id: \.self) { name in
        Button { tab = name } label: {
          VStack(spacing: 6) {
            Text(name).font(.system(size: 13, weight: tab == name ? .semibold : .regular))
              .foregroundStyle(tab == name ? Palette.ink : Palette.secondary)
            Capsule().fill(tab == name ? Palette.accent : .clear).frame(height: 2)
          }.fixedSize()
        }.buttonStyle(.plain).accessibilityAddTraits(tab == name ? .isSelected : [])
      }
      Spacer()
    }.overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 1) }
  }

  /// Live lines as speaker bubbles: yours on the right, everyone else on the left.
  /// Live captions know only your mic versus the call, so names come after Stop.
  private var transcript: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 8) {
          if lines.isEmpty {
            Text(state.liveCaptionsEnabled && state.cloudEnabled
              ? "Listening… Text shows a few seconds after someone speaks."
              : "Turn on Live captions in Settings → Meetings to see text here.")
              .font(.system(size: 13)).foregroundStyle(Palette.secondary).padding(.top, 8)
          }
          ForEach(lines) { segment in
            let mine = segment.speakerID.hasSuffix("microphone")
            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
              Text(mine ? "You" : "Others").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.secondary)
              Text(segment.text).font(.system(size: 14)).textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(mine ? Palette.accent.opacity(0.12) : Palette.paper, in: RoundedRectangle(cornerRadius: 14))
            }.frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
              .padding(mine ? .leading : .trailing, 36).id(segment.id)
          }
        }.padding(.vertical, 6)
      }.defaultScrollAnchor(.bottom)
        .onChange(of: lines.last?.id) { _, id in
          guard let id else { return }
          if reduceMotion { proxy.scrollTo(id, anchor: .bottom) } else {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
          }
        }
    }
  }

  @ViewBuilder private var thoughts: some View {
    if onMeeting {
      ZStack(alignment: .topLeading) {
        if state.noteDraft.isEmpty {
          Text("Type your notes. Chup! keeps them as you wrote them.")
            .foregroundStyle(Palette.secondary).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
        }
        TextEditor(text: $state.noteDraft).scrollContentBackground(.hidden)
          .onChange(of: state.noteDraft) { _, new in state.saveNote(new) }
          .accessibilityLabel("My thoughts")
      }.font(.system(size: 14)).padding(10).workspaceSurface().padding(.top, 8)
    } else {
      Button("Show this meeting’s notes") {
        if let id = state.activeMeetingID { state.selectMeeting(id) }
      }.buttonStyle(.pill).padding(.top, 10)
    }
  }

  private var errorBanner: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Recording stopped with an error").font(.system(size: 13, weight: .semibold))
      Text("Your audio so far is safe. Press Stop and save, then record again.")
        .font(.system(size: 12)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
      .background(Palette.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
      .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.red.opacity(0.35)) }
      .accessibilityElement(children: .combine)
  }

  private var noAudioWarning: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(state.inputLost ? "Microphone stopped" : "Microphone sending only silence for \(state.micSilentSeconds ?? 20) s")
          .font(.system(size: 13, weight: .semibold))
        Text("Check your mic is connected, or pick another in Settings → Dictation.")
          .font(.system(size: 12)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 4)
      Button("Restart input") { state.restartInput() }.buttonStyle(.pillPrimary).controlSize(.small)
    }.padding(10)
      .background(Palette.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
      .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.red.opacity(0.35)) }
      .accessibilityElement(children: .contain)
  }

  private var footer: some View {
    VStack(spacing: 8) {
      if confirmDiscard {
        VStack(alignment: .leading, spacing: 8) {
          // Discard removes the whole meeting, including anything saved before this recording.
          Text("Delete the whole meeting “\(state.activeMeeting?.title ?? "Meeting")”? Its recordings, transcript and notes are removed, including anything saved before this recording.")
            .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
          HStack(spacing: 8) {
            Spacer()
            Button("Keep") { discardFor = nil }.controlSize(.small)
            Button("Delete meeting", role: .destructive) {
              discardFor = nil
              state.discardMeeting()
            }.buttonStyle(.pillPrimary).tint(Palette.red).controlSize(.small)
              .disabled(state.meetingStatus == .processing)
          }
        }.padding(10).workspaceSurface()
      }
      HStack(spacing: 8) {
        VoiceWaveform(samples: paused ? [] : state.micWaveform, width: 44, height: 22, barCount: 7)
          .accessibilityHidden(true)
        Button {
          paused ? state.resumeMeeting() : state.pauseMeeting()
        } label: {
          Image(systemName: paused ? "play.fill" : "pause.fill").frame(width: 34, height: 34)
            .background(Palette.paper, in: Circle())
        }.buttonStyle(.plain).accessibilityLabel(paused ? "Resume recording" : "Pause recording")
          .disabled(state.meetingStatus != .recording && !paused)
        Button {
          state.stopMeeting()
        } label: {
          // Notes are written on stop only when cloud processing can run; otherwise audio is saved.
          Label(state.cloudEnabled && !state.backendToken.isEmpty ? "Stop and write notes" : "Stop and save",
            systemImage: "stop.fill").font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity).frame(height: 34).background(Palette.gradient, in: Capsule())
            .foregroundStyle(.white)
        }.buttonStyle(.plain)
        Menu {
          Button("Discard recording…", role: .destructive) { discardFor = state.activeMeetingID }
            .disabled(state.meetingStatus == .processing)
        } label: {
          Image(systemName: "ellipsis")
        }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("More recording actions")
      }
    }.padding(.top, 4)
  }
}
