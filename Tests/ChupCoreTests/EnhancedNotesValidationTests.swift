import XCTest

@testable import ChupCore

final class EnhancedNotesValidationTests: XCTestCase {
  func testRejectsInventedUserLinesAndUnsourcedAILines() throws {
    let segment = TranscriptSegment(
      id: "s1", meetingID: "m", start: 0, end: 2, text: "Priya will own QA.", speakerID: "a",
      track: .remote)
    let note = "# Q3\nwho owns QA"
    let ok = [
      NoteBlock(id: "1", kind: "user", text: "# Q3"),
      NoteBlock(id: "2", kind: "user", text: "who owns QA"),
      NoteBlock(id: "3", kind: "ai", text: "Priya owns QA.", sources: [Evidence(segmentID: "s1", quote: "Priya will own QA")]),
    ]
    XCTAssertNoThrow(try EvidenceValidator.validate(ok, note: note, meetingID: "m", segments: [segment]))
    let crlf = [NoteBlock(id: "1", kind: "user", text: "# Q3\r")]
    XCTAssertNoThrow(try EvidenceValidator.validate(crlf, note: "# Q3\r\nwho owns QA", meetingID: "m", segments: [segment]))
    let invented = [NoteBlock(id: "1", kind: "user", text: "budget approved")]
    XCTAssertThrowsError(try EvidenceValidator.validate(invented, note: note, meetingID: "m", segments: [segment]))
    let unsourced = [NoteBlock(id: "1", kind: "ai", text: "Launch moved.", sources: [Evidence(segmentID: "s1", quote: "launch moved")])]
    XCTAssertThrowsError(try EvidenceValidator.validate(unsourced, note: note, meetingID: "m", segments: [segment]))
  }
}
