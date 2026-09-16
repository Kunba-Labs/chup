import Foundation
import ChupCore

@MainActor enum DictationTraceValidation {
  static func run() async throws {
    let state = WorkspaceState(preview: true)
    defer { try? FileManager.default.removeItem(at: state.root) }
    for _ in 0..<52 {
      let id = state.startDictationTrace()
      state.markTrace(id, .firstAudio)
      state.markTrace(id, .captureStopped)
      state.finishTrace(id, .copied)
      state.markTrace(id, .insertionStarted)
    }
    let traces = try state.db().list(DictationTrace.self, kind: "dictationTrace")
    guard traces.count == 50, traces.allSatisfy({ $0.outcome == .copied && !$0.events.contains(where: { $0.stage == .insertionStarted }) }) else {
      throw WorkspaceError.message("Durable dictation traces lost their bounds or accepted late stages.")
    }
    print("PASS: production timing store retains 50 attempts, commits outcomes and rejects late marks.")
    state.dictationStatus = .error
    state.showMicrophoneMessage("Synthetic silence error")
    try await Task.sleep(for: .milliseconds(1700))
    guard state.dictationStatus == .idle, state.dictationMicMessage == nil,
      !state.compactDictationVisible, !state.hasRailActivity else {
      throw WorkspaceError.message("Transient dictation error did not return to rest.")
    }
    state.dictationStatus = .error
    try await Task.sleep(for: .milliseconds(100))
    state.dictationGeneration = UUID()
    state.dictationStatus = .processing
    try await Task.sleep(for: .milliseconds(1600))
    guard state.dictationStatus == .processing else {
      throw WorkspaceError.message("Old error timeout changed a newer voice action.")
    }
    state.dictationStatus = .idle
    state.showDictationFeedback(.copyFailed)
    try await Task.sleep(for: .milliseconds(1700))
    guard state.dictationFeedback == nil, !state.compactDictationVisible else {
      throw WorkspaceError.message("Delivery error feedback did not clear.")
    }
    guard try state.db().list(DictationTrace.self, kind: "dictationTrace").count == 50 else {
      throw WorkspaceError.message("Error dismissal altered saved diagnostic history.")
    }
    print("PASS: dictation and delivery errors clear after 1.5 seconds; old timers cannot stop newer actions; saved diagnostics remain. No microphone opened.")
  }
}
