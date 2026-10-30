import AppKit
import ChupCore
import SwiftUI

/// Floating notes panel while recording: the user's notepad above the live AI notes. Hidden from
/// screen sharing, takes keyboard focus without activating Chup!, and sits opposite the rail.
@MainActor final class MeetingSidebar: ObservableObject {
  @Published var collapsed = false
  private var closedFor: String?
  private var shownFor: String?
  private var timer: Timer?
  private weak var state: WorkspaceState?
  private let panel = NonactivatingPanel(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 560),
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
    panel.appearance = NSAppearance(named: .darkAqua)
    panel.hasShadow = true
    panel.contentView = NSHostingView(
      rootView: MeetingSidebarView(sidebar: self).environmentObject(state)
        .environment(\.colorScheme, .dark))
    timer = MainActorTimer.repeating(every: 1) { [weak self] in self?.tick() }
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
  private func layout() {
    let frame = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
    let height = collapsed ? 52 : min(620, frame.height * 0.7)
    let left = state?.railDock == "right"
    panel.setFrame(
      NSRect(
        x: left ? frame.minX + 16 : frame.maxX - 336, y: frame.maxY - height - 16, width: 320,
        height: height), display: true)
  }
}

struct MeetingSidebarView: View {
  @EnvironmentObject var state: WorkspaceState
  @ObservedObject var sidebar: MeetingSidebar
  /// The meeting a Discard confirmation is open for; a later meeting never inherits it.
  @State private var discardFor: String?
  private var confirmDiscard: Bool { discardFor != nil && discardFor == state.activeMeetingID }
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var onMeeting: Bool { state.selectedMeetingID == state.activeMeetingID }
  private var paused: Bool { state.meetingStatus == .paused }
  /// Only the recording meeting's captions; a previous meeting's lines never carry over.
  private var lines: [TranscriptSegment] {
    state.liveLines.filter { $0.meetingID == state.activeMeetingID }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      if !sidebar.collapsed {
        // Everything scrolls except the recording controls, which stay pinned at the bottom.
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            level
            if state.inputLost || state.micSilentSeconds != nil { noAudioWarning }
            if (state.liveCaptionsEnabled && state.cloudEnabled) || !lines.isEmpty {
              liveText
            }
            if onMeeting { notes } else {
              Button("Show this meeting’s notes") {
                if let id = state.activeMeetingID { state.selectMeeting(id) }
              }.buttonStyle(.bordered)
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }.scrollIndicators(.automatic).frame(maxHeight: .infinity)
        controls
      }
    }.padding(14).frame(width: 320, alignment: .topLeading)
      .frame(maxHeight: .infinity, alignment: .top)
      .background { RailSurface() }
      .foregroundStyle(RailPalette.ink)
  }

  private var header: some View {
    HStack(spacing: 8) {
      Circle().fill(paused ? RailPalette.secondary : RailPalette.red).frame(width: 8, height: 8)
        .accessibilityHidden(true)
      Text(paused ? "PAUSED" : "REC").font(.system(size: 10, weight: .semibold)).tracking(1.4)
        .foregroundStyle(RailPalette.secondary)
      Text(WorkspaceState.time(state.elapsed)).font(.system(size: 13, weight: .semibold).monospacedDigit())
      Text("· " + (state.activeMeeting?.title ?? "Meeting")).font(.system(size: 12))
        .foregroundStyle(RailPalette.secondary).lineLimit(1)
      Spacer()
      Button(action: sidebar.toggle) {
        Image(systemName: sidebar.collapsed ? "chevron.down" : "chevron.up")
      }.buttonStyle(.plain).accessibilityLabel(sidebar.collapsed ? "Expand sidebar" : "Collapse sidebar")
      Button(action: sidebar.close) { Image(systemName: "xmark") }.buttonStyle(.plain)
        .accessibilityLabel("Hide sidebar for this meeting")
    }.foregroundStyle(RailPalette.secondary)
  }

  /// The big gradient level with a playhead; still bars under Reduce Motion (VoiceWaveform).
  private var level: some View {
    VStack(spacing: 6) {
      ZStack {
        VoiceWaveform(samples: paused ? [] : state.micWaveform, width: 288, height: 64, barCount: 30)
          .accessibilityHidden(true)
        Capsule().fill(.white.opacity(0.85)).frame(width: 2, height: 58).accessibilityHidden(true)
      }.frame(maxWidth: .infinity)
      HStack(spacing: 12) {
        SourceMeter(name: "Mic", level: state.micLevel,
          receiving: state.micLastPacket.map { Date().timeIntervalSince($0) < 3 } ?? false)
        if state.meetingPID != 0 {
          SourceMeter(name: "Call", level: state.remoteLevel,
            receiving: state.remoteLastPacket.map { Date().timeIntervalSince($0) < 3 } ?? false)
        }
      }
    }
  }

  private var noAudioWarning: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(state.inputLost ? "Microphone stopped" : "No microphone audio for \(state.micSilentSeconds ?? 20) s")
          .font(.system(size: 13, weight: .semibold))
        Text("Headphones may have disconnected. Restarting keeps this meeting going.")
          .font(.system(size: 12)).foregroundStyle(RailPalette.secondary)
      }
      Spacer(minLength: 4)
      Button { state.restartInput() } label: {
        Text("Restart input").font(.system(size: 12, weight: .semibold)).foregroundStyle(.black)
          .padding(.horizontal, 12).frame(height: 30).background(.white, in: Capsule())
      }.buttonStyle(.plain).fixedSize()
    }.padding(10)
      .background(RailPalette.red.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
      .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(RailPalette.red.opacity(0.45)) }
      .accessibilityElement(children: .contain)
  }

  /// Older lines fade and blur; the current line is large. Live captions only know mic vs call.
  private var liveText: some View {
    let recent = lines
    return VStack(alignment: .leading, spacing: 10) {
      if recent.isEmpty {
        Text("Listening… text appears a few seconds after someone speaks.")
          .font(.system(size: 13)).foregroundStyle(RailPalette.secondary)
      }
      ForEach(Array(recent.enumerated()), id: \.element.id) { index, segment in
        let current = index == recent.count - 1
        let age = Double(recent.count - 1 - index)
        VStack(alignment: .leading, spacing: 3) {
          Text(segment.speakerID.hasSuffix("microphone") ? "YOU" : "THEM")
            .font(.system(size: 10, weight: .bold)).tracking(1.2)
            .foregroundStyle(current ? RailPalette.accent : RailPalette.secondary)
          Text(segment.text)
            .font(current ? .system(size: 19, weight: .semibold) : .system(size: 14))
            .lineLimit(current ? 4 : 2).textSelection(.enabled)
        }.opacity(current ? 1 : max(0.35, 0.8 - age * 0.2)).blur(radius: current ? 0 : age * 0.5)
      }
    }.frame(maxWidth: .infinity, alignment: .leading).frame(maxHeight: 210, alignment: .bottom)
      .clipped().animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: recent.map(\.id))
  }

  private var notes: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("YOUR NOTES").font(.system(size: 10, weight: .semibold)).tracking(1.2)
        .foregroundStyle(RailPalette.secondary)
      ZStack(alignment: .topLeading) {
        if state.noteDraft.isEmpty {
          Text("Jot a thought. Chup! keeps your words and fills in the rest.")
            .foregroundStyle(RailPalette.secondary).padding(.top, 8).padding(.leading, 5)
            .allowsHitTesting(false)
        }
        TextEditor(text: $state.noteDraft).scrollContentBackground(.hidden)
          .onChange(of: state.noteDraft) { _, new in state.saveNote(new) }
          .accessibilityLabel("Your meeting notes")
      }.font(.system(size: 14)).padding(8).frame(minHeight: 90, maxHeight: 150)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
      let items = LiveOutlineView.items(state.liveOutlines)
      if !items.isEmpty {
        Label("Live notes", systemImage: "sparkle").font(.system(size: 12, weight: .semibold))
          .padding(.top, 4)
        ScrollView {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.key) { _, item in
              HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(RailPalette.accent)
                Text(item.text).font(.system(size: 12)).textSelection(.enabled)
              }
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxHeight: 90)
      }
    }
  }

  private var controls: some View {
    VStack(spacing: 8) {
      if confirmDiscard {
        VStack(alignment: .leading, spacing: 8) {
          Text("Delete this recording and its notes? This can’t be undone.").font(.system(size: 12))
            .fixedSize(horizontal: false, vertical: true)
          HStack(spacing: 8) {
          Spacer()
          Button("Keep") { discardFor = nil }.controlSize(.small)
          Button("Discard", role: .destructive) {
            discardFor = nil
            state.discardMeeting()
          }.buttonStyle(.borderedProminent).tint(RailPalette.red).controlSize(.small)
          }
        }
      }
      HStack(spacing: 8) {
        Button {
          paused ? state.resumeMeeting() : state.pauseMeeting()
        } label: {
          Image(systemName: paused ? "play.fill" : "pause.fill").frame(width: 40, height: 40)
            .background(.white.opacity(0.10), in: Circle())
        }.buttonStyle(.plain).accessibilityLabel(paused ? "Resume recording" : "Pause recording")
          .disabled(state.meetingStatus != .recording && !paused)
        Button {
          state.stopMeeting()
        } label: {
          // Notes are written on stop only when cloud processing can run; otherwise audio is saved.
          Label(state.cloudEnabled && !state.backendToken.isEmpty ? "Stop and write notes" : "Stop and save",
            systemImage: "stop.fill").font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity).frame(height: 40).background(Palette.gradient, in: Capsule())
            .foregroundStyle(.white)
        }.buttonStyle(.plain)
        Button { discardFor = state.activeMeetingID } label: {
          Text("Discard").font(.system(size: 12)).padding(.horizontal, 12).frame(height: 40)
            .background(Capsule().strokeBorder(.white.opacity(0.22)))
        }.buttonStyle(.plain).fixedSize()
          .accessibilityHint("Asks before deleting the recording")
      }
    }
  }
}
