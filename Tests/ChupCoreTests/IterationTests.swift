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
  func testRenamedSpeakerNameSurvivesAcceptedNewVersion() throws {
    let store = try WorkspaceStore(url: try directory().appendingPathComponent("store.sqlite"))
    let window = TranscriptionWindow(meetingID: "m", track: .remote, start: 0, end: 90, duration: 180)
    var old = segment(id: "old", start: 10, end: 14, text: "Salaam", speaker: "a")
    XCTAssertTrue(try store.commitWindow(TranscriptionJob(window: window, context: [old])))
    old.speakerName = "Waseem"
    try store.correct(old)
    let new = segment(id: "new", start: 10, end: 15, text: "Salaam Alaikum", speaker: "a")
    // Same label, but a turn that only grazes the named audio after boundary drift.
    let drift = segment(id: "drift", start: 13.6, end: 20, text: "Hi there", speaker: "a")
    // A rename alone never stages a review; the name follows its audio.
    XCTAssertTrue(try store.commitWindow(TranscriptionJob(window: window, context: [new, drift])))
    let names = try store.list(TranscriptSegment.self, kind: "segment")
    XCTAssertEqual(names.first { $0.id == "new" }?.speakerName, "Waseem")
    XCTAssertNil(names.first { $0.id == "drift" }?.speakerName)
    // A new line covering two corrections named differently stays unnamed.
    var other = segment(id: "other", start: 30, end: 32, text: "Hey", speaker: "b")
    var other2 = segment(id: "other2", start: 32, end: 34, text: "there", speaker: "b")
    XCTAssertTrue(try store.commitWindow(TranscriptionJob(window: window, context: [old, other, other2])))
    other.speakerName = "Mara"
    other2.speakerName = "Sam"
    try store.correct(other)
    try store.correct(other2)
    let both = segment(id: "both", start: 30, end: 34, text: "Hey there", speaker: "b")
    XCTAssertTrue(try store.commitWindow(
      TranscriptionJob(window: window, context: [old, both]), acceptReview: true))
    XCTAssertNil(try store.list(TranscriptSegment.self, kind: "segment").first { $0.id == "both" }?.speakerName)
    // The user's name beats an automatic voice-match name on the same audio.
    var matched = segment(id: "auto", start: 10, end: 14.5, text: "Salaam", speaker: "a")
    matched.speakerName = "Sam · voice match"
    XCTAssertTrue(try store.commitWindow(
      TranscriptionJob(window: window, context: [matched]), acceptReview: true))
    XCTAssertEqual(try store.list(TranscriptSegment.self, kind: "segment").first { $0.id == "auto" }?.speakerName, "Waseem")
    // The same request-local label on audio nobody named stays unnamed.
    let later = TranscriptionWindow(meetingID: "m", track: .remote, start: 90, end: 180, duration: 180)
    XCTAssertTrue(try store.commitWindow(TranscriptionJob(
      window: later, context: [segment(id: "far", start: 100, end: 104, text: "Hi", speaker: "a")])))
    XCTAssertNil(try store.list(TranscriptSegment.self, kind: "segment").first { $0.id == "far" }?.speakerName)
  }
  func testRenameOnlyReviewSettlesAndLatestRenameWins() throws {
    let store = try WorkspaceStore(url: try directory().appendingPathComponent("store.sqlite"))
    let window = TranscriptionWindow(meetingID: "m", track: .remote, start: 0, end: 90, duration: 180)
    var line = segment(id: "l1", start: 10, end: 14, text: "Salaam", speaker: "a")
    XCTAssertTrue(try store.commitWindow(TranscriptionJob(window: window, context: [line])))
    // A legacy rename (no flags) staged a review before; it settles and keeps the name.
    line.speakerName = "Waseem"
    try store.correct(line)
    let next = segment(id: "l2", start: 10, end: 14.2, text: "Salaam Alaikum", speaker: "a")
    try store.put(TranscriptReview(window: window, incoming: [next], current: [line]),
      kind: "transcriptReview", id: window.id, parent: "m")
    try store.settleRenameOnlyReviews(meetingID: "m")
    XCTAssertTrue(try store.list(TranscriptReview.self, kind: "transcriptReview").isEmpty)
    var shown = try XCTUnwrap(store.list(TranscriptSegment.self, kind: "segment").first)
    XCTAssertEqual(shown.speakerName, "Waseem")
    // Renamed again on the new line: the next refine uses the latest name, not the old one.
    shown.speakerName = "Waseem Ahmed"
    shown.nameCorrected = true
    shown.textCorrected = false
    try store.correct(shown)
    let third = segment(id: "l3", start: 10.1, end: 14.2, text: "Salaam Alaikum.", speaker: "a")
    XCTAssertTrue(try store.commitWindow(TranscriptionJob(window: window, context: [third])))
    XCTAssertEqual(try store.list(TranscriptSegment.self, kind: "segment").first?.speakerName, "Waseem Ahmed")
    // A text edit on an unnamed line is not a name clear: an automatic name survives.
    var edited = try XCTUnwrap(store.list(TranscriptSegment.self, kind: "segment").first)
    edited.speakerName = nil
    edited.text = "Salaam alaikum!"
    edited.nameCorrected = false
    edited.textCorrected = true
    try store.correct(edited)
    var matched = segment(id: "l4", start: 10.1, end: 14.2, text: "Salaam alaikum", speaker: "a")
    matched.speakerName = "Sam · voice match"
    XCTAssertTrue(try store.commitWindow(TranscriptionJob(window: window, context: [matched]), acceptReview: true))
    XCTAssertEqual(try store.list(TranscriptSegment.self, kind: "segment").first?.speakerName, "Sam · voice match")
  }
  func testRememberedSpellingReplacementDoesNotStageReview() throws {
    let store = try WorkspaceStore(url: try directory().appendingPathComponent("store.sqlite"))
    let window = TranscriptionWindow(meetingID: "m", track: .remote, start: 0, end: 90, duration: 180)
    var line = segment(id: "r1", start: 10, end: 14, text: "Doing good, Prasimba", speaker: "a")
    XCTAssertTrue(try store.commitWindow(TranscriptionJob(window: window, context: [line])))
    line.text = "Doing good, Waseem bhai"
    line.textCorrected = false  // A dictionary spelling: the refine applies it itself.
    line.nameCorrected = false
    try store.correct(line)
    let next = segment(id: "r2", start: 10, end: 14.3, text: "Doing good, Waseem bhai.", speaker: "a")
    XCTAssertTrue(try store.commitWindow(TranscriptionJob(window: window, context: [next])))
    XCTAssertTrue(try store.list(TranscriptReview.self, kind: "transcriptReview").isEmpty)
  }
  func testAccuracyPassSwapsWordsIntoDiarizedTurns() {
    XCTAssertEqual(
      AccuracyPass.merge(
        ["So, how do you", "want to start? I'm good", "how are you"],
        accurate: "So, how do you want to start? I'm good. How are you?"),
      ["So, how do you", "want to start? I'm good.", "How are you?"])
    // A misheard run inside one turn is replaced.
    XCTAssertEqual(
      AccuracyPass.merge(["Thank you for asking me now. Yes,", "we see it okay then"],
        accurate: "Thank you for asking now. Yes, we can see it. Okay then"),
      ["Thank you for asking now. Yes,", "we can see it. Okay then"])
    // A disagreement across a speaker change keeps both turns' diarized words.
    XCTAssertEqual(
      AccuracyPass.merge(["one two three four five", "six seven eight nine ten"],
        accurate: "one two three four fife sex seven eight nine ten"),
      ["one two three four five", "six seven eight nine ten"])
    // Lines of one speaker: a fully misheard line between agreeing lines is replaced.
    XCTAssertEqual(
      AccuracyPass.merge(["Salaam alaikum how are you", "So Harik I will sing my audio.", "Thank you for asking me now"],
        speakers: ["A", "A", "A"],
        accurate: "Salaam alaikum how are you. So, how do you want to start? Thank you for asking me now."),
      ["Salaam alaikum how are you.", "So, how do you want to start?", "Thank you for asking me now."])
    // One matching word never replaces a long turn.
    XCTAssertEqual(AccuracyPass.merge(["we should test all the microphones today"], accurate: "today"),
      ["we should test all the microphones today"])
    // Unrelated text keeps the diarized words.
    XCTAssertEqual(AccuracyPass.merge(["hello there friend"], accurate: "completely different"), ["hello there friend"])
    XCTAssertEqual(AccuracyPass.merge(["kept"], accurate: ""), ["kept"])
  }
  func testCarryReferencesPickLongestLinePerSpeakerByTalkTime() {
    var enrolled = segment(id: "e", start: 0, end: 30, text: "", speaker: "enrolled:x")
    enrolled.track = .remote
    let refs = SpeakerContinuity.carryReferences(
      [
        segment(id: "1", start: 0, end: 3, text: "", speaker: "a"),
        segment(id: "2", start: 5, end: 25, text: "", speaker: "a"),
        segment(id: "3", start: 30, end: 32, text: "", speaker: "b"),  // too short to reference
        segment(id: "4", start: 40, end: 44, text: "", speaker: "c"),
        enrolled,
      ], limit: 4)
    XCTAssertEqual(refs.map(\.speakerID), ["a", "c"])
    XCTAssertEqual(refs[0].start, 5)
    XCTAssertEqual(refs[0].end, 15)
    XCTAssertEqual(SpeakerContinuity.carryReferences([segment(id: "1", start: 0, end: 5, text: "", speaker: "a")], limit: 0).count, 0)
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
    XCTAssertEqual(
      DictationPersonalization.spellings("Mara", entries: entries, language: "auto"), "Maara")
    XCTAssertEqual(
      DictationPersonalization.vocabulary(entries, language: "en"), ["Maara"])
    XCTAssertEqual(
      DictationPersonalization.vocabulary(entries, language: "nl"), [])
    XCTAssertEqual(
      DictationPersonalization.vocabulary(entries, language: "auto"), ["Maara"])
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
