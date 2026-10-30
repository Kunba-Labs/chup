import ChupCore
import Foundation

extension WorkspaceState {
  /// Seconds the recording microphone has delivered exact digital silence (packets arriving,
  /// every sample zero), once that passes 20 s. A quiet room never reads exactly zero.
  var micSilentSeconds: Int? {
    guard meetingStatus == .recording, let started = captureStartedAt else { return nil }
    let quiet = Date().timeIntervalSince(max(micHeardAt ?? started, started))
    return quiet > 20 ? Int(quiet) : nil
  }
  /// The recording paused itself because microphone packets stopped.
  var inputLost: Bool {
    meetingStatus == .paused && currentGapReason.hasPrefix("Microphone packets stopped")
  }
  /// Restarts capture on a fresh input engine without ending the meeting; the gap is marked.
  func restartInput() {
    if meetingStatus == .recording { pauseMeeting(reason: "Input restarted") }
    micHeardAt = nil
    resumeMeeting()
  }
  /// Stops the recording and deletes it for good: audio, notes and the meeting itself.
  func discardMeeting() {
    guard let id = activeMeetingID else { return }
    meetingTask?.cancel()
    outlineTask?.cancel()
    outlineTask = nil
    stopAssistantRoute()
    closeRemoteGap()
    stopLiveCaptions()
    if let meetingConsumerID { try? audio?.removeConsumer(id: meetingConsumerID) }
    audio?.stopRemote()
    activeMeetingID = nil
    meetingStatus = .idle
    meetingStarted = nil
    activeLeg = nil
    pausedAt = nil
    currentGapID = nil
    if selectedMeetingID == id { leaveMeeting() }
    do {
      // The deletion plan is saved first, so an interrupted purge resumes at the next cleanup.
      try db().finishDeletion(db().planMeetingDeletion(id, root: root), root: root)
      notesQueue.removeAll { $0 == id }
      try refresh()
      try refreshPrivacy()
      syncBackendDeletions()
      notice = "Recording discarded. Nothing from it was kept."
    } catch {
      notice = "Discard paused; it will finish at the next cleanup. " + error.localizedDescription
    }
  }
}
