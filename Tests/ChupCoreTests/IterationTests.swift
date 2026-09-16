import CryptoKit
import XCTest

@testable import ChupCore

final class IterationTests: XCTestCase {
  private func directory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
  func testTwoHourClockDriftAndSourceRestart() throws {
    var clock = CaptureClockTracker()
    let count = Int(7200 * 48000 / 2048)
    for index in 0..<count {
      XCTAssertNil(
        try clock.observe(
          hostTime: 1000 + Double(index) * 2048 / 48000 * 1.0001, frames: 2048, sampleRate: 48000))
    }
    XCTAssertEqual(clock.driftPPM, 100, accuracy: 0.01)
    let gap = try clock.observe(hostTime: 8210, frames: 2048, sampleRate: 48000)
    XCTAssertNotNil(gap)
    XCTAssertEqual(clock.driftPPM, 0)
    XCTAssertThrowsError(try clock.observe(hostTime: 8200, frames: 2048, sampleRate: 48000))
    XCTAssertThrowsError(try clock.observe(hostTime: .nan, frames: 2048, sampleRate: 48000))
    XCTAssertNotNil(try clock.observe(hostTime: 8210.05, frames: 2048, sampleRate: 24000))
  }
  func testAcceleratedTwoHourRotatingEncryptedRecording() throws {
    let directory = try directory()
    let key = SymmetricKey(size: .bits256)
    let pcm = Data(repeating: 0x10, count: 16000)  // One second, mono 8 kHz, 16-bit.
    var packetCount = 0
    var end: Double = 0
    for chunk in 0..<240 {
      let path = directory.appendingPathComponent("mic-\(chunk).vwj")
      let writer = try AudioJournal(url: path, key: key)
      for second in 0..<30 {
        try writer.append(
          AudioPacket(hostTime: 1000 + Double(chunk * 30 + second), sampleRate: 8000, pcm: pcm))
      }
      try writer.close()
      let recovered = try AudioJournal.recover(url: path, key: key)
      XCTAssertFalse(recovered.truncatedTail)
      packetCount += recovered.packets.count
      end = recovered.packets.last!.hostTime + recovered.packets.last!.duration - 1000
      // Stream and verify each chunk, then release it: no two-hour in-memory audio buffer.
      try FileManager.default.removeItem(at: path)
    }
    XCTAssertEqual(packetCount, 7200)
    XCTAssertEqual(end, 7200)
  }
  func testWindowsBoundedAbsoluteOverlapsAndNoCrossTrackSpeakerGuess() {
    let plan = TranscriptionWindow.plan(meetingID: "m", track: .remote, duration: 7200)
    XCTAssertEqual(plan.count, 80)
    XCTAssertEqual(plan[1].audioStart, 87)
    XCTAssertEqual(plan[0].audioEnd, 93)
    XCTAssertTrue(plan.allSatisfy { $0.audioEnd - $0.audioStart <= 96 })
    let old = segment(
      id: "old", start: 88, end: 92, text: "We should test all the USB microphones", speaker: "a")
    var next = segment(id: "new", start: 87.9, end: 91.9, text: old.text, speaker: "b")
    let merged = SpeakerContinuity.reconcile([next], previous: [old]).first!
    XCTAssertEqual(merged.speakerID, "a")
    XCTAssertEqual(merged.start, old.start)
    XCTAssertEqual(merged.id, "old")
    next.track = .microphone
    XCTAssertEqual(SpeakerContinuity.reconcile([next], previous: [old]).first!.speakerID, "b")
    next.track = .remote
    next.start = 200
    next.end = 204
    XCTAssertEqual(SpeakerContinuity.reconcile([next], previous: [old]).first!.speakerID, "b")
  }
  func testCorrectionChangedSegmentationStagesReviewAndAtomicJobAcrossReopen() throws {
    let url = try directory().appendingPathComponent("store.sqlite")
    let store = try WorkspaceStore(url: url)
    let window = TranscriptionWindow(
      meetingID: "m", track: .remote, start: 0, end: 90, duration: 180)
    let old = segment(id: "old", start: 10, end: 14, text: "Original", speaker: "a")
    XCTAssertTrue(try store.commitWindow(TranscriptionJob(window: window, context: [old])))
    var manual = old
    manual.text = "We did not agree"
    manual.speakerName = "Mara"
    try store.correct(manual)
    let new = segment(id: "changed", start: 10, end: 15, text: "We agreed", speaker: "b")
    XCTAssertFalse(try store.commitWindow(TranscriptionJob(window: window, context: [new])))
    let reopened = try WorkspaceStore(url: url)
    XCTAssertEqual(try reopened.list(TranscriptSegment.self, kind: "segment"), [manual])
    XCTAssertEqual(
      try reopened.list(TranscriptionJob.self, kind: "transcriptionJob").first?.status, "review")
    XCTAssertTrue(try reopened.search("not agree", kind: "segment").contains("old"))
    let review = try XCTUnwrap(reopened.list(TranscriptReview.self, kind: "transcriptReview").first)
    try reopened.keepTranscriptReview(review)
    XCTAssertEqual(try reopened.list(TranscriptSegment.self, kind: "segment"), [manual])
    XCTAssertTrue(try reopened.list(TranscriptReview.self, kind: "transcriptReview").isEmpty)
    XCTAssertTrue(
      try reopened.commitWindow(
        TranscriptionJob(window: window, context: [new]), acceptReview: true))
    XCTAssertEqual(try reopened.list(TranscriptSegment.self, kind: "segment"), [new])
    XCTAssertFalse(try reopened.search("not agree", kind: "segment").contains("old"))
    XCTAssertEqual(try reopened.list(TranscriptSegment.self, kind: "correction"), [manual])  // Audit survives replacement.
  }
  func testInvalidWindowCannotPartiallyCommit() throws {
    let store = try WorkspaceStore(url: directory().appendingPathComponent("store.sqlite"))
    let window = TranscriptionWindow(
      meetingID: "m", track: .remote, start: 0, end: 90, duration: 90)
    let bad = segment(id: "bad", start: 3, end: 2, text: "Bad interval", speaker: "x")
    XCTAssertThrowsError(try store.commitWindow(TranscriptionJob(window: window, context: [bad])))
    XCTAssertTrue(try store.list(TranscriptSegment.self, kind: "segment").isEmpty)
    XCTAssertTrue(try store.list(TranscriptionJob.self, kind: "transcriptionJob").isEmpty)
    let repeated = segment(id: "same", start: 5, end: 6, text: "Duplicate", speaker: "x")
    XCTAssertThrowsError(
      try store.commitWindow(TranscriptionJob(window: window, context: [repeated, repeated])))
  }
  func testSnippetsAndAliasesPreserveLiteralFormattingAndWordBoundaries() {
    let entries = [
      Personalization(
        kind: "snippet", trigger: "my address", replacement: "Mara\n12 Test Street", language: "en"),
      Personalization(kind: "dictionary", trigger: "mara", replacement: "Maara", language: "en"),
    ]
    XCTAssertEqual(
      DictationPersonalization.snippet("My address.", entries: entries, language: "en"),
      "Mara\n12 Test Street")
    XCTAssertNil(
      DictationPersonalization.snippet("Write my address", entries: entries, language: "en"))
    XCTAssertEqual(
      DictationPersonalization.spellings(
        "Mara, not marathons: 12", entries: entries, language: "en"), "Maara, not marathons: 12")
    XCTAssertEqual(
      DictationPersonalization.spellings("Mara", entries: entries, language: "nl"), "Mara")
  }
  func testOldModelsDecodeWithoutNewOptionalMetadata() throws {
    let leg = try JSONDecoder().decode(
      RecordingLeg.self,
      from: Data(
        #"{"id":"l","meetingID":"m","directory":"/tmp/a","offset":0,"reason":"capture"}"#.utf8))
    XCTAssertNil(leg.hostStart)
    let gap = try JSONDecoder().decode(
      CaptureGap.self, from: Data(#"{"start":2,"reason":"paused"}"#.utf8))
    XCTAssertNil(gap.track)
  }
  private func segment(id: String, start: Double, end: Double, text: String, speaker: String)
    -> TranscriptSegment
  {
    TranscriptSegment(
      id: id, meetingID: "m", start: start, end: end, text: text, speakerID: speaker, track: .remote
    )
  }
}
