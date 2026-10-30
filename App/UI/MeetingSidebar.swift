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
  private var onMeeting: Bool { state.selectedMeetingID == state.activeMeetingID }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: state.meetingStatus == .paused ? "pause.circle" : "record.circle.fill")
          .foregroundStyle(RailPalette.red)
        Text("CHUP! · LIVE NOTES").font(.system(size: 9, weight: .semibold)).tracking(1.4)
          .foregroundStyle(RailPalette.secondary)
        Text(WorkspaceState.time(state.elapsed)).font(.system(size: 11, design: .monospaced))
          .foregroundStyle(RailPalette.red)
        Spacer()
        Button(action: sidebar.toggle) {
          Image(systemName: sidebar.collapsed ? "chevron.down" : "chevron.up")
        }.buttonStyle(.plain).accessibilityLabel(sidebar.collapsed ? "Expand notes" : "Collapse notes")
        Button(action: sidebar.close) { Image(systemName: "xmark") }.buttonStyle(.plain)
          .accessibilityLabel("Hide notes for this meeting")
      }.foregroundStyle(RailPalette.secondary)
      if !sidebar.collapsed {
        if onMeeting {
          Text("Your notes").font(.system(size: 13, weight: .semibold))
          ZStack(alignment: .topLeading) {
            if state.noteDraft.isEmpty {
              Text("Jot a thought. Chup! keeps your words and fills in the rest.")
                .foregroundStyle(RailPalette.secondary).padding(.top, 8).padding(.leading, 5)
                .allowsHitTesting(false)
            }
            TextEditor(text: $state.noteDraft).scrollContentBackground(.hidden)
              .onChange(of: state.noteDraft) { _, new in state.saveNote(new) }
              .accessibilityLabel("Your meeting notes")
          }.font(.system(size: 14)).padding(8).frame(minHeight: 140, maxHeight: 220)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
          if state.liveCaptionsEnabled && state.cloudEnabled {
            Divider().overlay(.white.opacity(0.12))
            Label("Live transcript", systemImage: "captions.bubble").font(.system(size: 13, weight: .semibold))
            let recent = state.segments.filter(\.provisional).suffix(3)
            // Bounded so long captions never push Live notes out of the fixed-height panel.
            ScrollView {
              VStack(alignment: .leading, spacing: 6) {
                if recent.isEmpty {
                  Text("Listening… text appears a few seconds after someone speaks.")
                    .foregroundStyle(RailPalette.secondary)
                }
                ForEach(recent) { segment in
                  Text(segment.text).foregroundStyle(segment.id == recent.last?.id ? RailPalette.ink : RailPalette.secondary)
                    .textSelection(.enabled)
                }
              }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 96).defaultScrollAnchor(.bottom)
          }
          Divider().overlay(.white.opacity(0.12))
          Label("Live notes", systemImage: "sparkle").font(.system(size: 13, weight: .semibold))
          ScrollView {
            VStack(alignment: .leading, spacing: 8) {
              let items = LiveOutlineView.items(state.liveOutlines)
              if items.isEmpty {
                Text(
                  state.liveOutlineEnabled && state.liveCaptionsEnabled && state.cloudEnabled
                    ? "Notes appear here about a minute into the conversation."
                    : "Turn on Live captions and Live outline in Settings to see notes as you talk."
                ).font(.system(size: 12)).foregroundStyle(RailPalette.secondary)
              }
              ForEach(items, id: \.key) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                  Text("•").foregroundStyle(RailPalette.accent)
                  Text(item.text).font(.system(size: 13)).textSelection(.enabled)
                }
              }
            }.frame(maxWidth: .infinity, alignment: .leading)
          }
        } else {
          Button("Show this meeting’s notes") {
            if let id = state.activeMeetingID { state.selectMeeting(id) }
          }.buttonStyle(.bordered)
        }
      }
    }.padding(14).frame(width: 320, alignment: .topLeading)
      .frame(maxHeight: .infinity, alignment: .top)
      .background { RailSurface() }
      .foregroundStyle(RailPalette.ink)
  }
}
