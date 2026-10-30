import ChupCore
import Foundation

/// The toast shown after a delete; Undo restores every item it names.
struct UndoToast: Identifiable, Equatable {
  let id = UUID()
  let ids: [String]
  let message: String
}

extension WorkspaceState {
  func trashMeetings(_ list: [Meeting]) {
    moveToTrash(list.map { TrashEntry(id: $0.id, kind: "meeting", title: $0.title) })
  }
  func trashDictations(_ list: [DictationEntry]) {
    moveToTrash(list.map {
      TrashEntry(id: $0.id, kind: "dictation", title: String($0.text.prefix(80)))
    })
  }
  private func moveToTrash(_ entries: [TrashEntry]) {
    guard !entries.isEmpty else { return }
    guard privacyWorkAllowed else {
      notice = "Finish active capture and AI work before deleting."
      return
    }
    do {
      stopPlayback()
      if entries.contains(where: { $0.id == dictationPlaybackID }) { stopDictationPlayback() }
      try db().moveToTrash(entries)
      if let id = selectedMeetingID, entries.contains(where: { $0.id == id }) { leaveMeeting() }
      try refresh()
      let noun = entries.count == 1 ? "“\(entries[0].title)”" : "\(entries.count) items"
      showUndo(UndoToast(ids: entries.map(\.id), message: "Moved \(noun) to Trash."))
    } catch { notice = error.localizedDescription }
  }
  func restoreFromTrash(_ ids: [String]) {
    do {
      try db().restoreFromTrash(ids)
      try refresh()
      if undoToast.map({ Set($0.ids) == Set(ids) }) == true { undoToast = nil }
    } catch { notice = error.localizedDescription }
  }
  func showUndo(_ toast: UndoToast) {
    undoToast = toast
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(8))
      if undoToast?.id == toast.id { undoToast = nil }
    }
  }
  /// Permanent removal through the verified deletion plan (audio, records, FTS rows).
  func deleteForever(_ entries: [TrashEntry]) {
    guard privacyWorkAllowed else {
      notice = "Finish active capture and AI work before deleting."
      return
    }
    do {
      for entry in entries {
        if entry.kind == "meeting" {
          try db().finishDeletion(db().planMeetingDeletion(entry.id, root: root), root: root)
          notesQueue.removeAll { $0 == entry.id }
        } else if let item = try db().list(DictationEntry.self, kind: "dictation")
          .first(where: { $0.id == entry.id })
        {
          try db().finishDeletion(
            db().planItemDeletion(
              id: item.id, kind: "dictation", directory: item.audioDirectory, root: root),
            root: root)
        }
        try db().restoreFromTrash([entry.id])
      }
      try refresh()
      try refreshPrivacy()
      try db().checkpoint()
      syncBackendDeletions()
    } catch { notice = error.localizedDescription }
  }
  func purgeExpiredTrash() {
    deleteForever(trash.filter { $0.expired() })
  }

  func deleteSelectedAudio() {
    guard let id = selectedMeetingID, privacyWorkAllowed else {
      notice = "Finish active capture and AI work before deleting."
      return
    }
    do {
      stopPlayback()
      // Voice clips remembered from this meeting are its audio too.
      for profile in enrollments where profile.meetingID == id { deleteEnrollmentWithPlan(profile) }
      try db().deleteMeetingAudio(id, root: root)
      playback.reset()
      try refreshDetail()
      try refreshPrivacy()
      notice = "Audio and voice clips from this meeting deleted. The transcript and notes stay."
    } catch { notice = error.localizedDescription }
  }
  func deleteSelectedTranscript() {
    guard let id = selectedMeetingID, privacyWorkAllowed else {
      notice = "Finish active capture and AI work before deleting."
      return
    }
    do {
      try db().deleteMeetingTranscript(id)
      selectedTranscriptSource = nil
      try refreshDetail()
      notice = "Transcript deleted. Your notes stay; their sources now show as deleted."
    } catch { notice = error.localizedDescription }
  }

  /// Cancels refine, summary and notes work for the open meeting. Nothing partial is saved:
  /// each job checks for cancellation before it writes.
  func cancelMeetingJobs() {
    transcriptionTask?.cancel()
    summaryTask?.cancel()
    notesTask?.cancel()
  }

  // MARK: Tags

  /// Every tag in use, for autocomplete, most used first.
  var allTags: [String] {
    var counts: [String: Int] = [:]
    for meeting in meetings { for tag in Meeting.tagList(meeting.tags) { counts[tag, default: 0] += 1 } }
    return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
  }
  func setTags(_ tags: [String], on meeting: Meeting) {
    var copy = meeting
    copy.tags = Meeting.tagList(tags.joined(separator: ", ")).joined(separator: ", ")
    do { try saveMeeting(copy) } catch { notice = error.localizedDescription }
  }
  func addTag(_ tag: String, to list: [Meeting]) {
    for meeting in list { setTags(Meeting.tagList(meeting.tags) + [tag], on: meeting) }
  }
  /// Renames (or with `to: nil` removes) a tag on every meeting that has it.
  func renameTag(_ old: String, to new: String?) {
    for meeting in meetings where Meeting.tagList(meeting.tags).contains(where: {
      $0.caseInsensitiveCompare(old) == .orderedSame
    }) {
      let tags = Meeting.tagList(meeting.tags).compactMap {
        $0.caseInsensitiveCompare(old) == .orderedSame ? new : $0
      }
      setTags(tags, on: meeting)
    }
  }
}
