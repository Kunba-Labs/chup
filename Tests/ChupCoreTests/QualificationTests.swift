import CryptoKit
import XCTest
@testable import ChupCore

final class QualificationTests: XCTestCase {
  func testInvalidUsageCannotProduceNegativeOrInfiniteEstimates() {
    var item = ProviderUsage(id: "u", category: "file", model: "m", inputTokens: 10, cachedTokens: 2, outputTokens: 5, confirmed: true, raw: "{}")
    let rates = UsageRates(inputPerMillion: 1, cachedPerMillion: 0.5, outputPerMillion: 2, perMinute: 1)
    XCTAssertEqual(rates.estimate(item)!, 0.000019, accuracy: 0.0000001)
    item.cachedTokens = 11; XCTAssertNil(rates.estimate(item))
    item.cachedTokens = 2; item.inputTokens = -.infinity; XCTAssertNil(rates.estimate(item))
    item.inputTokens = 10; item.seconds = -1; XCTAssertNil(rates.estimate(item))
    item.seconds = nil
    XCTAssertNil(UsageRates(inputPerMillion: .infinity, outputPerMillion: 1).estimate(item))
    item.confirmed = false; XCTAssertNil(rates.estimate(item))
  }
  func directory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: root) }
    return root
  }
  func testJournalNeverOverwritesAndStreamsTruncatedTail() throws {
    let url = try directory().appendingPathComponent("microphone.vwj")
    let key = SymmetricKey(size: .bits256)
    let journal = try AudioJournal(url: url, key: key)
    for time in 0..<4 { try journal.append(AudioPacket(hostTime: Double(time), sampleRate: 24000, pcm: Data(repeating: 0, count: 48000))) }
    try journal.close()
    let original = try Data(contentsOf: url)
    XCTAssertThrowsError(try AudioJournal(url: url, key: key))
    XCTAssertEqual(try Data(contentsOf: url), original)
    try (original + Data([90, 0])).write(to: url)
    var times: [Double] = []
    XCTAssertTrue(try AudioJournal.scan(url: url, key: key) { times.append($0.hostTime) })
    XCTAssertEqual(times, [0, 1, 2, 3])
    enum ConsumerError: Error { case stop }
    XCTAssertThrowsError(try AudioJournal.scan(url: url, key: key) { _ in throw ConsumerError.stop }) {
      XCTAssertTrue($0 is ConsumerError)
    }
  }
  func testJournalRejectsMalformedPacketsAndUnboundedRecordBeforeAllocation() throws {
    let url = try directory().appendingPathComponent("audio.vwj")
    let key = SymmetricKey(size: .bits256)
    let journal = try AudioJournal(url: url, key: key)
    for packet in [AudioPacket(hostTime: .nan, sampleRate: 24000, pcm: Data()), AudioPacket(hostTime: 0, sampleRate: 0, pcm: Data()), AudioPacket(hostTime: 0, sampleRate: 24000, channels: Int.max, pcm: Data()), AudioPacket(hostTime: 0, sampleRate: 24000, pcm: Data([1]))] {
      XCTAssertThrowsError(try journal.append(packet))
    }
    try journal.close()
    try (Data("VWJ1".utf8) + Data(repeating: 255, count: 4)).write(to: url)
    XCTAssertThrowsError(try AudioJournal.scan(url: url, key: key) { _ in XCTFail("Must not yield a packet") })
  }
  func testStreamingWaveHeaderSamplesAndExclusiveCommit() throws {
    let root = try directory(), url = root.appendingPathComponent("audio.wav")
    let writer = try WaveFileWriter(destination: url, frames: 4)
    try writer.append([0, 0.5]); try writer.append([-1, 1]); try writer.finish()
    let bytes = try Data(contentsOf: url)
    XCTAssertEqual(bytes.count, 52)
    XCTAssertEqual(String(decoding: bytes.prefix(4), as: UTF8.self), "RIFF")
    XCTAssertEqual(bytes[4], 44)
    XCTAssertEqual(bytes[40], 8)
    let pcm = bytes.dropFirst(44).withUnsafeBytes { Array($0.bindMemory(to: Int16.self)).map(Int16.init(littleEndian:)) }
    XCTAssertEqual(pcm, [0, 16383, -32767, 32767])
    XCTAssertThrowsError(try WaveFileWriter(destination: url, frames: 4))
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    let race = root.appendingPathComponent("race.wav")
    let competing = try WaveFileWriter(destination: race, frames: 1)
    try competing.append([0]); try Data([42]).write(to: race)
    XCTAssertThrowsError(try competing.finish())
    XCTAssertEqual(try Data(contentsOf: race), Data([42]))
  }
  func testIncompleteWaveIsCleanedAndInvalidSamplesDoNotCommit() throws {
    let root = try directory(), url = root.appendingPathComponent("audio.wav")
    do {
      let writer = try WaveFileWriter(destination: url, frames: 4)
      XCTAssertThrowsError(try writer.append([.nan]))
      try writer.append([0])
      XCTAssertThrowsError(try writer.finish())
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    XCTAssertThrowsError(try WaveFileWriter(destination: url, frames: Int.max))
  }
  func testDurableReplacementAndFailureLeaveExistingContent() throws {
    let root = try directory(), url = root.appendingPathComponent("index")
    try DurableFile.write(Data([1]), to: url)
    try DurableFile.write(Data([2, 3]), to: url)
    XCTAssertEqual(try Data(contentsOf: url), Data([2, 3]))
    let blocker = root.appendingPathComponent("directory")
    try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)
    try Data([99]).write(to: blocker.appendingPathComponent("keep"))
    XCTAssertThrowsError(try DurableFile.write(Data([8]), to: blocker))
    XCTAssertEqual(try Data(contentsOf: blocker.appendingPathComponent("keep")), Data([99]))
    XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".chup") })
  }
  func testMeetingSearchFindsCorrectedTranscriptAndExcludesPrivateScopes() throws {
    let store = try WorkspaceStore(url: directory().appendingPathComponent("db"), key: Data(repeating: 17, count: 32))
    try store.put(Meeting(id: "m", title: "Launch"), kind: "meeting", id: "m", searchable: "Launch")
    var segment = TranscriptSegment(id: "s", meetingID: "m", start: 10, end: 12, text: "Test USB microphones", speakerID: "unknown", track: .microphone)
    try store.put(segment, kind: "segment", id: segment.id, parent: "m", searchable: segment.text)
    try store.writeNote(meetingID: "m", text: "Check speakers", expectedVersion: 0, requestID: "n")
    try store.writeNote(meetingID: "private-thoughts/m", text: "Secret pineapple", expectedVersion: 0, requestID: "p")
    XCTAssertEqual(try store.searchMeetings("USB micro").first?.segmentID, "s")
    XCTAssertEqual(try store.searchMeetings("speakers").first?.meetingID, "m")
    XCTAssertTrue(try store.searchMeetings("pineapple").isEmpty)
    XCTAssertEqual(try store.searchMeetings("Launch").count, 1)
    XCTAssertNoThrow(try store.searchMeetings("\" OR NEAR(foo) * :"))
    segment.text = "Test thunderbolt interface"
    try store.correct(segment)
    XCTAssertTrue(try store.searchMeetings("USB").isEmpty)
    XCTAssertEqual(try store.searchMeetings("thunderbolt").first?.segmentID, "s")
  }
}
