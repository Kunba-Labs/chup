import SwiftUI
import ChupCore

@main struct ChupApp: App {
  @StateObject private var state = WorkspaceState(
    preview: ProcessInfo.processInfo.arguments.contains("--render-design")
      || ProcessInfo.processInfo.arguments.contains("--validate-audio"))

  /// Offline checks run off the main actor queue, not off a window appearing:
  /// a signed bundle exec'd straight from its path never shows one, which left
  /// `--validate-audio` hanging until its deployment timeout.
  init() {
    _ = WorkspaceFrameRestorer.saved
    guard ProcessInfo.processInfo.arguments.contains("--validate-audio") else { return }
    Task { @MainActor in
      do {
        try await AudioValidation.run()
        exit(0)
      } catch {
        print("FAIL: " + error.localizedDescription)
        exit(1)
      }
    }
  }
  var body: some Scene {
    Window("Chup!", id: "workspace") {
      WorkspaceView().environmentObject(state).frame(minWidth: 960, minHeight: 650)
        .background(WorkspaceFrameRestorer())
        .preferredColorScheme(.light)
    }.defaultSize(width: 1240, height: 810)
      .commands {
        CommandGroup(after: .newItem) {
          Button("New Meeting Note") { state.newMeeting() }.keyboardShortcut("n")
          Button("Paste Last Dictation") { state.pasteLast() }.keyboardShortcut(
            "v", modifiers: [.control, .command])
        }
      }
    Settings {
      SettingsView().environmentObject(state).frame(width: 790, height: 640)
        .preferredColorScheme(.light)
    }
    MenuBarExtra {
      Text(state.runningBuild.label)
      Button("Open Chup!") { state.reveal?() }
      Button("Focus floating controls") { state.focusRail() }
      Text(state.statusText)
      Divider()
      Button(state.dictationStatus == .listening ? "Finish Dictation" : "Start Dictation") {
        state.toggleDictation()
      }
      Button("Edit Selected Text") { state.beginDictation(editSelection: true) }
      Button("Paste Last Dictation") { state.pasteLast() }
      Button("Start or Reveal Meeting") { state.handle(.init(action: .meeting, began: true)) }
      if state.activeMeetingID != nil {
        Button(state.meetingStatus == .paused ? "Resume Recording" : "Pause Recording") {
          state.meetingStatus == .paused ? state.resumeMeeting() : state.pauseMeeting()
        }
        Button("Stop Recording") { state.stopMeeting() }
      }
      Button("Ask Assistant") {
        state.assistantVisible = true
        state.reveal?()
      }
      Button("Stop Assistant Voice") { state.endVoice() }
      if state.voiceRouter.privateInput {
        Button("Resume Call Microphone") {
          state.endVoice()
          state.resumeCallMicrophone()
        }
      }
      Button("Cancel Voice Action") {
        state.endVoice()
        state.cancelDictation()
      }
      Divider()
      if let updater = state.updater {
        Button("Check for Updates…") { updater.check() }
      }
      SettingsLink()
      Button("Quit Chup!") {
        state.stopMeeting()
        state.cancelDictation()
        NSApp.terminate(nil)
      }.keyboardShortcut("q")
    } label: {
      Label(
        state.meetingStatus == .recording ? "Recording" : "Chup!",
        systemImage: state.meetingStatus == .recording ? "record.circle.fill" : "waveform")
      if state.meetingStatus == .recording { Text(WorkspaceState.time(state.elapsed)) }
    }
  }
}

/// SwiftUI reopens the workspace on the display under the mouse, keeping only the
/// saved offset, and autosaves that move; `setFrame(from:)` maps onto that same
/// display. Read the saved rect before the window exists and put it back once,
/// unless its display is gone.
@MainActor struct WorkspaceFrameRestorer: NSViewRepresentable {
  static var saved = UserDefaults.standard.string(forKey: "NSWindow Frame workspace")
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      guard let window = view.window, let values = Self.saved?.split(separator: " ").compactMap({ Double($0) }),
        values.count >= 4 else { return }
      Self.saved = nil
      let frame = NSRect(x: values[0], y: values[1], width: values[2], height: values[3])
      guard NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) else { return }
      window.setFrame(frame, display: true)
    }
    return view
  }
  func updateNSView(_ nsView: NSView, context: Context) {}
}
