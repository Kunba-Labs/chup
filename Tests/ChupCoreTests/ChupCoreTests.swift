import CryptoKit
import XCTest

@testable import ChupCore

final class ChupCoreTests: XCTestCase {
  private func directory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
  func testNoteWriteIsIdempotentAndVersionCheckedAcrossReopen() throws {
    let url = try directory().appendingPathComponent("test.sqlite")
    let store = try WorkspaceStore(url: url)
    let first = try store.writeNote(
      meetingID: "m1", text: "Test USB microphones", expectedVersion: 0, requestID: "r1")
    XCTAssertEqual(
      try store.writeNote(
        meetingID: "m1", text: "Test USB microphones", expectedVersion: 0, requestID: "r1"), first)
    XCTAssertThrowsError(
      try store.writeNote(
        meetingID: "m1", text: "Different text", expectedVersion: 0, requestID: "r1"))
    XCTAssertThrowsError(
      try store.writeNote(meetingID: "m1", text: "Stale edit", expectedVersion: 0, requestID: "r2"))
    let reopened = try WorkspaceStore(url: url)
    XCTAssertEqual(try reopened.note("m1").version, 1)
    XCTAssertEqual(try reopened.undo(first).after.text, "")
    XCTAssertEqual(try reopened.note("m1").version, 2)
  }
  func testUndoCannotOverwriteANewerUserEdit() throws {
    let store = try WorkspaceStore(url: directory().appendingPathComponent("test.sqlite"))
    let receipt = try store.writeNote(
      meetingID: "m", text: "AI addition", expectedVersion: 0, requestID: "1")
    try store.writeNote(meetingID: "m", text: "My newer edit", expectedVersion: 1, requestID: "2")
    XCTAssertThrowsError(try store.undo(receipt))
    XCTAssertEqual(try store.note("m").text, "My newer edit")
  }
  func testSpeakerAndTextCorrectionsSurviveReprocessingAndSearch() throws {
    let store = try WorkspaceStore(url: directory().appendingPathComponent("test.sqlite"))
    var segment = TranscriptSegment(
      id: "chunk1:0", meetingID: "m", start: 0, end: 1, text: "Original",
      speakerID: "chunk1:speaker1", track: .remote)
    try store.saveSegments([segment], meetingID: "m", revisionID: "v1")
    segment.text = "We did not agree"
    segment.speakerName = "Mara"
    try store.correct(segment)
    var retry = segment
    retry.text = "We agreed"
    retry.speakerName = nil
    try store.saveSegments([retry], meetingID: "m", revisionID: "v2")
    XCTAssertEqual(
      try store.list(TranscriptSegment.self, kind: "segment", parent: "m").first, segment)
    XCTAssertTrue(try store.search("not agree", kind: "segment").contains(segment.id))
  }
  func testUnsupportedEvidenceAndCrossMeetingReferencesFail() throws {
    let segment = TranscriptSegment(
      id: "s", meetingID: "m", start: 0, end: 1, text: "No date agreed", speakerID: "unknown",
      track: .microphone)
    let valid = MeetingSummary(items: [
      SummaryItem(
        category: "question", text: "Date remains open",
        sources: [Evidence(segmentID: "s", quote: "No date agreed")])
    ])
    XCTAssertNoThrow(try EvidenceValidator.validate(valid, meetingID: "m", segments: [segment]))
    XCTAssertThrowsError(
      try EvidenceValidator.validate(valid, meetingID: "other", segments: [segment]))
    XCTAssertThrowsError(
      try EvidenceValidator.validate(
        MeetingSummary(items: [SummaryItem(category: "action", text: "Invented", sources: [])]),
        meetingID: "m", segments: [segment]))
  }
  func testEncryptedJournalRecoversTruncatedTailAndRejectsTampering() throws {
    let url = try directory().appendingPathComponent("track.vwj")
    let key = SymmetricKey(size: .bits256)
    let writer = try AudioJournal(url: url, key: key)
    let packet = AudioPacket(hostTime: 1, sampleRate: 24000, pcm: Data(repeating: 0, count: 4800))
    try writer.append(packet)
    try writer.append(packet)
    try writer.close()
    let complete = try AudioJournal.recover(url: url, key: key)
    XCTAssertEqual(complete.packets.count, 2)
    XCTAssertFalse(complete.truncatedTail)
    let data = try Data(contentsOf: url)
    try data.dropLast(10).write(to: url)
    let recovered = try AudioJournal.recover(url: url, key: key)
    XCTAssertEqual(recovered.packets.count, 1)
    XCTAssertTrue(recovered.truncatedTail)
    var tampered = data
    tampered[30] ^= 0xff
    try tampered.write(to: url)
    XCTAssertThrowsError(try AudioJournal.recover(url: url, key: key))
  }
  func testPrivateToBroadcastNeedsFreshVerifiedRoute() {
    let route = RoutingPolicy(meetingActive: true, headphones: true)
    XCTAssertTrue(route.allows(.privateText))
    XCTAssertFalse(route.allows(.privateVoice))
    XCTAssertFalse(route.allows(.broadcast))
    XCTAssertTrue(RoutingPolicy.requiresNewSession(from: .privateVoice, to: .broadcast))
    XCTAssertTrue(
      RoutingPolicy(
        meetingActive: true, verifiedInputIsolation: true, verifiedMixMinus: true, headphones: true
      ).allows(.broadcast))
  }
  func testLongerFnChordWinsDuringArbitrationAndRepeatDoesNotRetrigger() {
    var resolver = ShortcutResolver()
    XCTAssertTrue(resolver.update(modifiers: .fn, keys: [], time: 0).isEmpty)
    let signals = resolver.update(modifiers: .fn, keys: [49], time: 0.1)
    XCTAssertEqual(signals, [ShortcutSignal(action: .toggleDictation, began: true)])
    XCTAssertTrue(resolver.update(modifiers: .fn, keys: [49], time: 0.4).isEmpty)
  }
  func testHoldReleaseAndRebindingReset() {
    var resolver = ShortcutResolver()
    _ = resolver.update(modifiers: .fn, keys: [], time: 0)
    XCTAssertEqual(
      resolver.update(modifiers: .fn, keys: [], time: 0.2),
      [ShortcutSignal(action: .holdDictation, began: true)])
    XCTAssertEqual(
      resolver.update(modifiers: [], keys: [], time: 1),
      [ShortcutSignal(action: .holdDictation, began: false)])
    resolver.suspended = true
    XCTAssertTrue(resolver.update(modifiers: .option, keys: [46], time: 2).isEmpty)
  }
  func testInternalAndKnownSystemConflicts() {
    var bindings = ShortcutBinding.standard
    bindings.append(.init(.assistant, .option, keyCode: 46))
    XCTAssertFalse(ShortcutBinding.conflicts(bindings).isEmpty)
    XCTAssertFalse(ShortcutBinding.conflicts([.init(.assistant, .command, keyCode: 49)]).isEmpty)
  }
  func testMeetingPromptExpiresWithoutRecordAndDeduplicates() {
    var policy = MeetingDetectionPolicy()
    let candidate = MeetingCandidate(pid: 100, name: "Zoom", browser: false)
    XCTAssertNil(policy.observe([candidate], now: 0, recording: false))
    XCTAssertEqual(policy.observe([candidate], now: 4, recording: false), candidate)
    XCTAssertNil(policy.observe([candidate], now: 14, recording: false))
    XCTAssertNil(policy.pending)
    XCTAssertNil(policy.accept(now: 14))
    XCTAssertNil(policy.observe([candidate], now: 20, recording: false))
  }
  func testMeetingSnoozeAndRecordingSuppression() {
    var policy = MeetingDetectionPolicy()
    let c = MeetingCandidate(pid: 1, name: "Chrome", browser: true)
    _ = policy.observe([c], now: 0, recording: true)
    XCTAssertNil(policy.observe([c], now: 4, recording: true))
    XCTAssertNotNil(policy.observe([c], now: 5, recording: false))
    policy.dismiss(now: 6, snooze: 120)
    XCTAssertNil(policy.observe([c], now: 125, recording: false))
    XCTAssertNotNil(policy.observe([c], now: 126, recording: false))
    XCTAssertEqual(policy.accept(now: 130), c)
  }
  func testWrongFieldInsertionAndClipboardRaceFailClosed() {
    let original = DestinationFingerprint(
      pid: 1, elementID: "field-A", selectionLocation: 2, selectionLength: 0, value: "hello",
      focusEpoch: 1, secure: false)
    XCTAssertTrue(InsertionPolicy.canInsert(original: original, current: original))
    var changed = original
    changed.elementID = "field-B"
    XCTAssertFalse(InsertionPolicy.canInsert(original: original, current: changed))
    changed = original
    changed.focusEpoch += 1
    XCTAssertFalse(InsertionPolicy.canInsert(original: original, current: changed))
    changed = original
    changed.value = "new typing"
    XCTAssertFalse(InsertionPolicy.canInsert(original: original, current: changed))
    changed = original
    changed.selectionLocation = 3
    XCTAssertFalse(InsertionPolicy.canInsert(original: original, current: changed))
    changed = original
    changed.secure = true
    XCTAssertFalse(InsertionPolicy.canInsert(original: original, current: changed))
    XCTAssertFalse(InsertionPolicy.mayRestoreClipboard(insertionChange: 10, currentChange: 11))
  }
  func testInterruptionCountsOnlyRenderedBroadcastFrames() {
    var ledger = PlaybackLedger()
    ledger.enqueue(
      PlayedAudio(id: "private", sessionID: "s1", mode: .privateVoice, generatedFrames: 48000))
    ledger.rendered(id: "private", frames: 48000)
    ledger.enqueue(
      PlayedAudio(id: "shared", sessionID: "s2", mode: .broadcast, generatedFrames: 48000))
    ledger.rendered(id: "shared", frames: 12000)
    ledger.interrupt()
    XCTAssertEqual(ledger.broadcastSeconds, 0.5)
    XCTAssertTrue(ledger.entries[1].interrupted)
    XCTAssertFalse(ledger.entries[0].interrupted)
  }
  func testReleasingLongerChordDoesNotStartItsFnPrefix() {
    var resolver = ShortcutResolver()
    _ = resolver.update(modifiers: .fn, keys: [], time: 0)
    _ = resolver.update(modifiers: .fn, keys: [49], time: 0.1)
    XCTAssertTrue(resolver.update(modifiers: .fn, keys: [], time: 0.2).isEmpty)
    XCTAssertTrue(resolver.update(modifiers: .fn, keys: [], time: 0.6).isEmpty)
    _ = resolver.update(modifiers: [], keys: [], time: 0.8)
    _ = resolver.update(modifiers: .fn, keys: [], time: 1)
    XCTAssertEqual(
      resolver.update(modifiers: .fn, keys: [], time: 1.2),
      [ShortcutSignal(action: .holdDictation, began: true)])
  }
  func testPromotingActiveFnHoldCancelsItsInsertion() {
    var resolver = ShortcutResolver()
    _ = resolver.update(modifiers: .fn, keys: [], time: 0)
    _ = resolver.update(modifiers: .fn, keys: [], time: 0.2)
    let signals = resolver.update(modifiers: [.fn, .control], keys: [], time: 0.3)
    XCTAssertEqual(signals, [ShortcutSignal(action: .holdDictation, began: false, cancelled: true)])
  }
  func testMeetingToolsCannotReadOtherMeetingsOrWriteFromPassiveCapture() throws {
    let store = try WorkspaceStore(url: directory().appendingPathComponent("test.sqlite"))
    let tools = MeetingTools(store: store)
    let segment = TranscriptSegment(
      id: "s", meetingID: "secret", start: 0, end: 1, text: "launch", speakerID: "s1",
      track: .remote)
    try store.saveSegments([segment], meetingID: "secret", revisionID: "v1")
    let passive = MeetingToolScope(meetingID: "public", addressedRequestID: "r", canWrite: false)
    XCTAssertTrue(try tools.searchMeeting(query: "launch", scope: passive).isEmpty)
    XCTAssertThrowsError(
      try tools.appendNote(text: "Recorded command", expectedVersion: 0, scope: passive))
    let addressed = MeetingToolScope(
      meetingID: "public", addressedRequestID: "user-request", canWrite: true)
    let receipt = try tools.appendNote(
      text: "Test USB microphones", expectedVersion: 0, scope: addressed)
    XCTAssertEqual(
      try tools.appendNote(text: "Test USB microphones", expectedVersion: 0, scope: addressed),
      receipt)
    XCTAssertEqual(try store.note("public").text, "Test USB microphones")
  }
}
