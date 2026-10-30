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
  /// Order matters: the recorder is closed first (abort if it won't close), then the durable
  /// deletion plan is saved, and only then is the meeting cleared and purged.
  func discardMeeting() {
    guard let id = activeMeetingID else { return }
    // While a leg is starting, beginLeg may still be adding the consumer or opening files that a
    // deletion plan made now would miss. Discard waits until capture has settled.
    guard meetingStatus != .processing else {
      notice = "Recording is still starting. Discard once it shows REC or PAUSED."
      return
    }
    guard recorderCloseFailed != id else {
      notice = "This recording's audio files didn't close cleanly, so it can't be discarded yet. "
        + "Quit and reopen Chup! (recovery closes them), then delete the meeting from the list."
      return
    }
    do {
      if let meetingConsumerID { try audio?.removeConsumer(id: meetingConsumerID) }
    } catch {
      // Capture has stopped, but the files may still be open: show the error and block deletion.
      recorderCloseFailed = id
      meetingStatus = .error
      notice = "Discard stopped: the recording's audio files could not be closed, so nothing was deleted. "
        + error.localizedDescription
      return
    }
    meetingTask?.cancel()
    outlineTask?.cancel()
    outlineTask = nil
    stopAssistantRoute()
    closeRemoteGap()
    stopLiveCaptions()
    audio?.stopRemote()
    let plan: DeletionPlan
    do {
      plan = try db().planMeetingDeletion(id, root: root)
    } catch {
      // No plan means no later retry: keep the meeting as a stopped recording and say so.
      if var meeting = activeMeeting {
        meeting.status = "Audio saved"
        try? saveMeeting(meeting)
      }
      endActiveMeeting(id)
      try? refresh()
      notice = "Recording stopped and kept; it could not be discarded. Delete it from the meeting list. "
        + error.localizedDescription
      return
    }
    endActiveMeeting(id)
    do {
      try db().finishDeletion(plan, root: root)
      notesQueue.removeAll { $0 == id }
      try refresh()
      try refreshPrivacy()
      syncBackendDeletions()
      notice = "Recording discarded. Nothing from it was kept."
    } catch {
      notice = "Discard paused; its saved deletion plan finishes at the next cleanup. "
        + error.localizedDescription
    }
  }
  private func endActiveMeeting(_ id: String) {
    activeMeetingID = nil
    meetingStatus = .idle
    meetingStarted = nil
    activeLeg = nil
    pausedAt = nil
    currentGapID = nil
    if selectedMeetingID == id { leaveMeeting() }
  }
}
