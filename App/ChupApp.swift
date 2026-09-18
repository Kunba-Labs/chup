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
