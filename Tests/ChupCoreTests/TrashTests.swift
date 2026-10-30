import XCTest
@testable import ChupCore

final class TrashTests: XCTestCase {
  private func workspace() throws -> (WorkspaceStore, URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: root) }
    return (try WorkspaceStore(url: root.appendingPathComponent("db"), key: Data(repeating: 9, count: 32)), root)
  }

  func testTrashHidesFromSearchAndRestoreBringsItBack() throws {
    let (store, _) = try workspace()
    try store.put(Meeting(id: "m", title: "Launch"), kind: "meeting", id: "m", searchable: "Launch")
    try store.moveToTrash([TrashEntry(id: "m", kind: "meeting", title: "Launch")])
    XCTAssertTrue(try store.searchMeetings("Launch").isEmpty)
    XCTAssertEqual(try store.trashedIDs(), ["m"])
    try store.restoreFromTrash(["m"])
    XCTAssertEqual(try store.searchMeetings("Launch").first?.meetingID, "m")
    XCTAssertTrue(try store.trashEntries().isEmpty)
  }

  func testTrashExpiresAfterThirtyDays() {
    let entry = TrashEntry(id: "m", kind: "meeting", title: "", trashedAt: Date(timeIntervalSinceNow: -31 * 86_400))
    XCTAssertTrue(entry.expired())
    XCTAssertFalse(TrashEntry(id: "n", kind: "meeting", title: "").expired())
  }

  func testPartialDeletesKeepTheRest() throws {
    let (store, root) = try workspace()
    try store.put(Meeting(id: "m", title: "Launch"), kind: "meeting", id: "m", searchable: "Launch")
    let audio = root.appendingPathComponent("Recordings/m/leg")
    try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
    try Data([1]).write(to: audio.appendingPathComponent("a.vwj"))
    let leg = RecordingLeg(meetingID: "m", directory: audio.path, offset: 0)
    try store.put(leg, kind: "leg", id: leg.id, parent: "m")
    let segment = TranscriptSegment(id: "s", meetingID: "m", start: 0, end: 2, text: "Ship in May", speakerID: "a", track: .microphone)
    try store.put(segment, kind: "segment", id: "s", parent: "m", searchable: segment.text)
    try store.writeNote(meetingID: "m", text: "my note", expectedVersion: 0, requestID: "n")

    try store.deleteMeetingAudio("m", root: root)
    XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
    XCTAssertTrue(try store.list(RecordingLeg.self, kind: "leg", parent: "m").isEmpty)
    XCTAssertEqual(try store.list(TranscriptSegment.self, kind: "segment", parent: "m").count, 1)
    XCTAssertEqual(try store.partialDeletion("m"), PartialDeletion(audio: true))

    try store.put(segment, kind: "correction", id: "s", parent: "m")
    try store.put(["text": "Ship in May"], kind: "transcriptRevision", id: "r", parent: "m")
    try store.deleteMeetingTranscript("m")
    for kind in WorkspaceStore.transcriptKinds {
      XCTAssertTrue(try store.list(TranscriptSegment.self, kind: kind, parent: "m").isEmpty, kind)
    }
    XCTAssertNil(try store.searchMeetings("May").first?.segmentID)
    XCTAssertEqual(try store.note("m").text, "my note")
    XCTAssertEqual(try store.partialDeletion("m"), PartialDeletion(audio: true, transcript: true))
  }

  func testTranscriptLineSearchReturnsEveryMatchingLine() throws {
    let (store, _) = try workspace()
    try store.put(Meeting(id: "m", title: "Launch plan"), kind: "meeting", id: "m", searchable: "Launch plan")
    for (id, text) in [("a", "launch in May"), ("b", "launch copy review")] {
      let segment = TranscriptSegment(id: id, meetingID: "m", start: 0, end: 1, text: text, speakerID: "x", track: .microphone)
      try store.put(segment, kind: "segment", id: id, parent: "m", searchable: text)
    }
    XCTAssertEqual(Set(try store.searchTranscriptLines("launch").compactMap(\.segmentID)), ["a", "b"])
    try store.moveToTrash([TrashEntry(id: "m", kind: "meeting", title: "")])
    XCTAssertTrue(try store.searchTranscriptLines("launch").isEmpty)
  }

  func testTranscriptActionStaysEditableAfterTranscriptDelete() throws {
    let (store, _) = try workspace()
    try store.put(Meeting(id: "m", title: "Launch"), kind: "meeting", id: "m", searchable: "Launch")
    let segment = TranscriptSegment(id: "s", meetingID: "m", start: 0, end: 2, text: "Sam ships the beta", speakerID: "a", track: .microphone)
    try store.put(segment, kind: "segment", id: "s", parent: "m", searchable: segment.text)
    let action = ActionRecord(meetingID: "m", title: "Ship the beta", sources: [Evidence(segmentID: "s", quote: "Sam ships the beta")], origin: "transcript")
    var saved = try store.writeAction(action, expectedVersion: 0, requestID: "a1").after
    try store.deleteMeetingTranscript("m")
    saved.status = "done"
    XCTAssertEqual(try store.writeAction(saved, expectedVersion: saved.version, requestID: "a2").after.status, "done")
    var moved = saved
    moved.version = saved.version + 1
    moved.sources = [Evidence(segmentID: "gone", quote: "x")]
    XCTAssertThrowsError(try store.writeAction(moved, expectedVersion: moved.version, requestID: "a3"))
  }

  func testTagListSplitsOnCommaAndDot() {
    XCTAssertEqual(Meeting.tagList("Product · Launch, product,  , Q3"), ["Product", "Launch", "Q3"])
  }
}

final class SummaryOutlineTests: XCTestCase {
  func testNextStepsGroupByOwnerAndSavedActionsWin() {
    let ev = [Evidence(segmentID: "s", quote: "q")]
    let summary = MeetingSummary(items: [
      SummaryItem(category: "overview", text: "Ship in May.", sources: ev),
      SummaryItem(category: "decision", text: "Netherlands first.", sources: ev),
      SummaryItem(category: "action", text: "Write release notes", owner: "Sam", sources: ev),
      SummaryItem(category: "action", text: "Book the venue", sources: ev),
      SummaryItem(category: "question", text: "Pricing?", sources: ev),
    ])
    let saved = ActionRecord(meetingID: "m", title: "Write release notes", owner: "Sam", status: "done", sources: ev)
    let outline = SummaryOutline(summary: summary, actions: [saved])
    XCTAssertEqual(outline.tldr.map(\.text), ["Ship in May."])
    XCTAssertEqual(outline.decisions.count, 1)
    XCTAssertEqual(outline.nextSteps.map(\.owner), ["Sam", "No owner"])
    XCTAssertEqual(outline.nextSteps[0].steps.count, 1)
    XCTAssertTrue(outline.nextSteps[0].steps[0].done)
    XCTAssertNotNil(outline.nextSteps[0].steps[0].action)
    let md = outline.markdown(title: "Launch", thoughts: "budget??")
    XCTAssertTrue(md.contains("## My thoughts\nbudget??"))
    XCTAssertTrue(md.contains("- [x] Write release notes"))
  }
}
