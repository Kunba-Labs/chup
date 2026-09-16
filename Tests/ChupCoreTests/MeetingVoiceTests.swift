import XCTest

@testable import ChupCore

final class MeetingVoiceTests: XCTestCase {
  private func store() throws -> WorkspaceStore {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    return try WorkspaceStore(url: directory.appendingPathComponent("workspace.sqlite"))
  }
  func testStructuredActionsAreVersionedIdempotentAndPreserveAmbiguousDates() throws {
    let store = try store()
    let item = ActionRecord(
      id: "a", meetingID: "m", title: "Test USB microphones",
      dueDate: "next Friday, date unconfirmed")
    let first = try store.writeAction(item, expectedVersion: 0, requestID: "request")
    XCTAssertEqual(first, try store.writeAction(item, expectedVersion: 0, requestID: "request"))
    XCTAssertNil(first.after.owner)
    XCTAssertEqual(first.after.dueDate, item.dueDate)
    var changed = first.after
    changed.status = "done"
    _ = try store.writeAction(changed, expectedVersion: 1, requestID: "done")
    XCTAssertThrowsError(try store.writeAction(item, expectedVersion: 1, requestID: "stale"))
    XCTAssertThrowsError(try store.writeAction(changed, expectedVersion: 0, requestID: "request"))
  }
  func testTranscriptActionRequiresEvidenceAndPrivateNotesAreSeparate() throws {
    let store = try store()
    XCTAssertThrowsError(
      try store.writeAction(
        ActionRecord(meetingID: "m", title: "Invented agreement", origin: "transcript"),
        expectedVersion: 0, requestID: "r"))
    try store.writeNote(meetingID: "m", text: "Shared note", expectedVersion: 0, requestID: "s")
    try store.writeNote(
      meetingID: "private-thoughts/m", text: "Private concern", expectedVersion: 0, requestID: "p")
    XCTAssertEqual(try store.note("m").text, "Shared note")
    XCTAssertEqual(try store.note("private-thoughts/m").text, "Private concern")
  }
  func testActionCannotOverwriteAnotherMeetingWithTheSameIdentifier() throws {
    let store = try store()
    let original = ActionRecord(id: "same", meetingID: "m1", title: "First meeting action")
    _ = try store.writeAction(original, expectedVersion: 0, requestID: "first")
    XCTAssertThrowsError(
      try store.writeAction(
        ActionRecord(id: "same", meetingID: "m2", title: "Other meeting action"),
        expectedVersion: 0, requestID: "second"))
    XCTAssertEqual(
      try store.list(ActionRecord.self, kind: "action", parent: "m1").first?.title, original.title)
    XCTAssertTrue(try store.list(ActionRecord.self, kind: "action", parent: "m2").isEmpty)
  }
  func testSummaryVersionCommitRejectsChangedEvidenceAndKeepsPinnedEdits() throws {
    let store = try store()
    let segment = TranscriptSegment(
      id: "s", meetingID: "m", start: 0, end: 2,
      text: "No date agreed", speakerID: "unknown", track: .remote)
    let item = SummaryItem(
      category: "question", text: "No date agreed",
      sources: [Evidence(segmentID: "s", quote: "No date agreed")])
    let revision = SummaryRevision(
      meetingID: "m", provisional: false, segments: [segment],
      summary: MeetingSummary(items: [item]))
    try store.put(item, kind: "summaryEdit", id: "m/pinned", parent: "m")
    var changed = segment
    changed.text = "A changed transcript"
    XCTAssertThrowsError(try store.saveSummaryRevision(revision, segments: [changed]))
    XCTAssertTrue(try store.list(MeetingSummary.self, kind: "summary", parent: "m").isEmpty)
    XCTAssertTrue(try store.list(SummaryRevision.self, kind: "summaryVersion", parent: "m").isEmpty)
    try store.saveSummaryRevision(revision, segments: [segment])
    XCTAssertEqual(
      try store.list(SummaryRevision.self, kind: "summaryVersion", parent: "m"), [revision])
    XCTAssertEqual(try store.list(SummaryItem.self, kind: "summaryEdit", parent: "m"), [item])
  }
  func testBroadcastScopeDropsPrivateContextAndRequiresVerifiedRoute() {
    let history = [
      AssistantExchange(meetingID: "m", question: "Private salary question", noteVersion: 1)
    ]
    let privateScope = VoiceTurnScope(meetingID: "m", mode: .privateVoice)
    let publicScope = VoiceTurnScope(meetingID: "m", mode: .broadcast)
    XCTAssertNotEqual(privateScope.id, publicScope.id)
    XCTAssertTrue(
      publicScope.backendContext(note: Note(text: "Private notes"), history: history).1.isEmpty)
    XCTAssertEqual(
      publicScope.backendContext(note: Note(text: "Private notes"), history: history).0.text, "")
    let unsafe = RouteEvidence(microphoneUID: "mic", outputUID: "headphones", headphones: true)
    XCTAssertFalse(unsafe.policy(meetingActive: true).allows(.privateVoice))
    XCTAssertFalse(unsafe.policy(meetingActive: true).allows(.broadcast))
    let controlled = RouteEvidence(
      microphoneUID: "mic", outputUID: "headphones", virtualUID: "virtual", headphones: true,
      callUsesOnlyVirtualInput: true)
    XCTAssertTrue(controlled.policy(meetingActive: true).allows(.broadcast))
    XCTAssertTrue(controlled.policy(meetingActive: true).allows(.privateVoice))
  }
  func testRenderQueueCountsPartialPlaybackAndRevokesLateAudio() throws {
    let queue = VoiceRenderQueue()
    let context = UUID()
    queue.reset(context: context, active: true)
    try queue.append(
      [Int16](repeating: 16384, count: 200).withUnsafeBytes { Data($0) }, context: context)
    var samples = [Float](repeating: 0, count: 80)
    XCTAssertEqual(samples.withUnsafeMutableBufferPointer { queue.render(into: $0) }, 80)
    XCTAssertEqual(queue.consumed(context: context), 80)
    XCTAssertTrue(samples.allSatisfy { $0 == 0.5 })
    queue.reset(context: UUID(), active: false)
    XCTAssertThrowsError(try queue.append(Data([0, 1]), context: context))
    XCTAssertEqual(samples.withUnsafeMutableBufferPointer { queue.render(into: $0) }, 0)
    XCTAssertTrue(samples.allSatisfy { $0 == 0 })
  }
  func testMixMinusExcludesPrivateMicrophoneAndLimitsGain() {
    XCTAssertEqual(MixMinus.outgoing(microphone: 1, assistant: 0, privateAddress: true), 0)
    XCTAssertEqual(MixMinus.outgoing(microphone: 1, assistant: 1, privateAddress: false), 0.95)
    XCTAssertEqual(
      MixMinus.outgoing(microphone: .nan, assistant: .infinity, privateAddress: false), 0)
  }
  func testLiveOutlineDoesNotPromoteCanonicalTranscriptAndFingerprintsEdits() {
    let segment = TranscriptSegment(
      id: "s", meetingID: "m", start: 500, end: 510, text: "No deadline agreed",
      speakerID: "unknown", track: .remote, provisional: true)
    let copy = TranscriptScope.outlineEvidence([segment])
    XCTAssertTrue(segment.provisional)
    XCTAssertFalse(copy[0].provisional)
    var edited = segment
    edited.text = "Changed"
    XCTAssertNotEqual(TranscriptScope.fingerprint([segment]), TranscriptScope.fingerprint([edited]))
    XCTAssertEqual(TranscriptScope.recent([segment], seconds: 600), [segment])
  }
}
