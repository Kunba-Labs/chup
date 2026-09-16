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
        let source = try db().list(TranscriptSegment.self, kind: "segment", parent: meetingID)
        let recent = TranscriptScope.recent(source, seconds: 600)
        guard !recent.isEmpty else { return }
        let result = try await backend(scope: meetingID).outline(recent)
        try Task.checkCancellation()
        try EvidenceValidator.validate(
          result, meetingID: meetingID, segments: TranscriptScope.outlineEvidence(recent))
        let revision = SummaryRevision(
          meetingID: meetingID, provisional: true, segments: recent, summary: result)
        try db().put(revision, kind: "liveOutline", id: revision.id, parent: meetingID)
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
  func saveAction(_ action: ActionRecord) {
    do {
      lastActionReceipt = try db().writeAction(
        action, expectedVersion: action.version, requestID: UUID().uuidString)
      try refreshDetail()
    } catch { notice = error.localizedDescription }
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
      notice = "This source changed. Open its transcript revision."
      return
    }
    selectedTranscriptSource = segment.id
    meetingTab = "Transcript"
    play(at: segment.start)
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
