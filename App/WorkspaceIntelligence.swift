import AppKit
import Foundation
import ChupCore

extension WorkspaceState {
  func scheduleOutline(meetingID: String) {
    guard liveOutlineEnabled, cloudEnabled, outlineTask == nil else { return }
    outlineTask = Task {
      defer { outlineTask = nil }
      do {
        try await Task.sleep(for: .seconds(20))
        guard cloudEnabled, liveOutlineEnabled else { return }
        // Live notes accumulate: each pass covers only completed text after the last one.
        let source = try db().list(TranscriptSegment.self, kind: "segment", parent: meetingID)
        let covered = outlineCovered[meetingID] ?? []
        let recent = source.filter { !covered.contains($0.id) }.sorted { $0.start < $1.start }
        guard let end = recent.map(\.end).max(), end - (recent.first?.start ?? end) >= 60
        else { return }
        let result = try await backend(scope: meetingID).outline(recent)
        try Task.checkCancellation()
        try EvidenceValidator.validate(
          result, meetingID: meetingID, segments: TranscriptScope.outlineEvidence(recent))
        let revision = SummaryRevision(
          meetingID: meetingID, provisional: true, segments: recent, summary: result)
        try db().put(revision, kind: "liveOutline", id: revision.id, parent: meetingID)
        outlineCovered[meetingID, default: []].formUnion(recent.map(\.id))
        if selectedMeetingID == meetingID { try refreshDetail() }
      } catch {
        if !Task.isCancelled {
          notice =
            "Live outline paused. Recording and notes continue. " + error.localizedDescription
        }
      }
    }
  }
  func finalizeSummary(meetingID: String) async throws {
    let source = try db().list(TranscriptSegment.self, kind: "segment", parent: meetingID).filter {
      !$0.provisional
    }
    guard !source.isEmpty else {
      throw WorkspaceError.message("Refine the saved transcript first.")
    }
    let fingerprint = TranscriptScope.fingerprint(source)
    let usageID = startUsage(category: "backend.summary", meetingID: meetingID)
    do {
      let result = try await backend(scope: meetingID).summarize(source)
      let current = try db().list(TranscriptSegment.self, kind: "segment", parent: meetingID).filter
      { !$0.provisional }
      guard TranscriptScope.fingerprint(current) == fingerprint else {
        throw WorkspaceError.staleVersion
      }
      try Task.checkCancellation()
      let revision = SummaryRevision(
        meetingID: meetingID, provisional: false, segments: current, summary: result)
      try db().saveSummaryRevision(revision, segments: current)
      finishUsage(usageID, status: "completed")
      if selectedMeetingID == meetingID { try refreshDetail() }
    } catch {
      finishUsage(usageID, status: "failed")
      throw error
    }
  }
  /// Merges the user's notes with the refined transcript. Private thoughts are never included.
  func writeNotes(meetingID: String, template: String? = nil) async throws {
    let source = try db().list(TranscriptSegment.self, kind: "segment", parent: meetingID).filter {
      !$0.provisional
    }
    let note = try db().note(meetingID).text
    let previous = try db().list(EnhancedNotes.self, kind: "enhancedNotes", parent: meetingID).last
    let chosen = template ?? previous?.template ?? "general"
    notesMeetingID = meetingID
    defer { notesMeetingID = nil }
    let usageID = startUsage(category: "backend.notes", meetingID: meetingID)
    do {
      let blocks = try await backend(scope: meetingID).enhance(source, note: note, template: chosen)
      let current = try db().list(TranscriptSegment.self, kind: "segment", parent: meetingID)
        .filter { !$0.provisional }
      guard TranscriptScope.fingerprint(current) == TranscriptScope.fingerprint(source),
        try db().note(meetingID).text == note
      else { throw WorkspaceError.staleVersion }
      try EvidenceValidator.validate(blocks, note: note, meetingID: meetingID, segments: current)
      try Task.checkCancellation()
      try db().put(
        EnhancedNotes(meetingID: meetingID, template: chosen, blocks: blocks),
        kind: "enhancedNotes", id: meetingID, parent: meetingID)
      notesQueue.removeAll { $0 == meetingID }
      finishUsage(usageID, status: "completed")
      if selectedMeetingID == meetingID { try refreshDetail() }
    } catch {
      finishUsage(usageID, status: "failed")
      throw error
    }
  }
  func regenerateNotes(template: String) {
    guard let id = selectedMeetingID, !writingNotes else { return }
    notesTask = Task {
      defer { notesTask = nil }
      do { try await writeNotes(meetingID: id, template: template) } catch {
        notice = Task.isCancelled || error is CancellationError
          ? "Notes stopped." : "Notes weren’t written: " + error.localizedDescription
      }
    }
  }
  func copyNotesMarkdown() {
    let outline = SummaryOutline(summary: summary, actions: actions)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(
      outline.markdown(title: selectedMeeting?.title ?? "Meeting", thoughts: noteDraft), forType: .string)
    notice = "Copied as Markdown."
  }
  func draftFollowup() {
    guard let id = selectedMeetingID, let notes = enhancedNotes else { return }
    let title = selectedMeeting?.title ?? "Meeting"
    Task {
      do {
        let draft = try await backend(scope: id).followup(title: title, blocks: notes.blocks)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Subject: \(draft.subject)\n\n\(draft.body)", forType: .string)
        notice = "Follow-up email copied."
      } catch { notice = "Follow-up not drafted: " + error.localizedDescription }
    }
  }
  func saveThoughts(_ text: String) {
    guard let id = selectedMeetingID, text != thoughts.text else { return }
    do {
      thoughts = try db().writeNote(
        meetingID: "private-thoughts/" + id, text: text,
        expectedVersion: thoughts.version, requestID: UUID().uuidString
      ).after
    } catch { notice = error.localizedDescription }
  }
  func saveSummaryEdit(_ item: SummaryItem) {
    guard let id = selectedMeetingID else { return }
    do {
      try db().put(item, kind: "summaryEdit", id: id + "/" + item.id, parent: id)
      try refreshDetail()
    } catch { notice = error.localizedDescription }
  }
  func createAction(from item: SummaryItem) {
    guard let id = selectedMeetingID else { return }
    let action = ActionRecord(
      id: id + "/summary/" + item.id, meetingID: id, title: item.text,
      owner: item.owner, dueDate: item.dueDate, status: item.status, sources: item.sources,
      origin: "transcript")
    do {
      lastActionReceipt = try db().writeAction(
        action, expectedVersion: 0, requestID: id + "/summary-action/" + item.id)
      try refreshDetail()
      notice = "Action saved."
    } catch { notice = error.localizedDescription }
  }
  /// Returns false when the write failed, so an editor can keep the user's text.
  @discardableResult func saveAction(_ action: ActionRecord) -> Bool {
    do {
      lastActionReceipt = try db().writeAction(
        action, expectedVersion: action.version, requestID: UUID().uuidString)
      try refreshDetail()
      return true
    } catch {
      notice = error.localizedDescription
      return false
    }
  }
  func undoAction() {
    guard let receipt = lastActionReceipt, receipt.after.meetingID == selectedMeetingID else {
      return
    }
    do {
      var restored = receipt.before ?? receipt.after
      if receipt.before == nil { restored.status = "archived" }
      restored.version = receipt.after.version
      _ = try db().writeAction(
        restored, expectedVersion: receipt.after.version, requestID: UUID().uuidString)
      lastActionReceipt = nil
      try refreshDetail()
    } catch { notice = error.localizedDescription }
  }
  func addAction(_ title: String) {
    guard let id = selectedMeetingID else { return }
    saveAction(ActionRecord(meetingID: id, title: title))
  }
  func revealSource(_ source: Evidence) {
    guard let segment = segments.first(where: { $0.id == source.segmentID }) else {
      notice = partial.transcript
        ? "Source deleted: this meeting's transcript was deleted."
        : "This source changed. Open its transcript revision."
      return
    }
    selectedTranscriptSource = segment.id
    meetingTab = "Transcript"
    if !partial.audio { play(at: segment.start) }
  }
  @discardableResult func startUsage(category: String, meetingID: String) -> String {
    let item = UsageRecord(meetingID: meetingID, category: category)
    do { try db().put(item, kind: "usage", id: item.id, parent: meetingID) } catch {
      notice = error.localizedDescription
    }
    return item.id
  }
  func finishUsage(_ id: String, status: String, providerUsage: String? = nil) {
    do {
      guard var item = try db().list(UsageRecord.self, kind: "usage").first(where: { $0.id == id })
      else { return }
      item.ended = Date()
      item.status = status
      item.providerUsage = providerUsage
      try db().put(item, kind: "usage", id: id, parent: item.meetingID)
      usageRecords = try db().list(UsageRecord.self, kind: "usage").sorted {
        $0.started > $1.started
      }
    } catch { notice = error.localizedDescription }
  }
}
