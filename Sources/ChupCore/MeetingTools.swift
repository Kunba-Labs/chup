import Foundation

public struct MeetingToolScope {
  public let meetingID: String
  public let addressedRequestID: String
  public let canWrite: Bool
  public init(meetingID: String, addressedRequestID: String, canWrite: Bool) {
    self.meetingID = meetingID
    self.addressedRequestID = addressedRequestID
    self.canWrite = canWrite
  }
}
/// All tools are local and meeting-scoped. No passive transcript listener owns a write scope.
public final class MeetingTools {
  private let store: WorkspaceStore
  public init(store: WorkspaceStore) { self.store = store }
  public func searchMeeting(query: String, scope: MeetingToolScope) throws -> [TranscriptSegment] {
    let ids = try store.search(query, kind: "segment")
    return try store.list(TranscriptSegment.self, kind: "segment", parent: scope.meetingID).filter {
      ids.contains($0.id)
    }.sorted { $0.start < $1.start }
  }
  public func getTranscriptRange(start: Double, end: Double, scope: MeetingToolScope) throws
    -> [TranscriptSegment]
  {
    guard start.isFinite, end.isFinite, start >= 0, end >= start else {
      throw WorkspaceError.message("Invalid transcript interval.")
    }
    return try store.list(TranscriptSegment.self, kind: "segment", parent: scope.meetingID).filter {
      $0.end >= start && $0.start <= end
    }.sorted { $0.start < $1.start }
  }
  public func appendNote(text: String, expectedVersion: Int, scope: MeetingToolScope) throws
    -> MutationReceipt
  {
    guard scope.canWrite else {
      throw WorkspaceError.message("Only an explicitly addressed request may edit notes.")
    }
    // Resolve an existing receipt BEFORE reading the current note; retries must use the original body.
    if let receipt = try store.receipt(requestID: scope.addressedRequestID) {
      guard receipt.meetingID == scope.meetingID, receipt.before.version == expectedVersion,
        receipt.after.text == receipt.before.text + (receipt.before.text.isEmpty ? "" : "\n\n")
          + text
      else { throw WorkspaceError.requestCollision }
      return receipt
    }
    let note = try store.note(scope.meetingID)
    return try store.writeNote(
      meetingID: scope.meetingID, text: note.text + (note.text.isEmpty ? "" : "\n\n") + text,
      expectedVersion: expectedVersion, requestID: scope.addressedRequestID)
  }
  public func updateNote(text: String, expectedVersion: Int, scope: MeetingToolScope) throws
    -> MutationReceipt
  {
    guard scope.canWrite else {
      throw WorkspaceError.message("Only an explicitly addressed request may edit notes.")
    }
    return try store.writeNote(
      meetingID: scope.meetingID, text: text, expectedVersion: expectedVersion,
      requestID: scope.addressedRequestID)
  }
  public func createActionItem(_ action: SummaryItem, expectedVersion: Int, scope: MeetingToolScope)
    throws -> MutationReceipt
  {
    let segments = try store.list(TranscriptSegment.self, kind: "segment", parent: scope.meetingID)
    try EvidenceValidator.validate(
      MeetingSummary(items: [action]), meetingID: scope.meetingID, segments: segments)
    guard action.category == "action" else { throw WorkspaceError.invalidEvidence }
    let title =
      "- [ ] " + action.text + (action.owner.map { " — " + $0 } ?? "")
      + (action.dueDate.map { " (" + $0 + ")" } ?? "")
    return try appendNote(text: title, expectedVersion: expectedVersion, scope: scope)
  }
}
