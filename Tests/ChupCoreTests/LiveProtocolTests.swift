import Foundation
import XCTest

@testable import ChupCore

final class LiveProtocolTests: XCTestCase {
  private func decode(_ value: [String: Any]) throws -> LiveEvent {
    try LiveEvent.decode(JSONSerialization.data(withJSONObject: value))
  }
  func testLivePCMAndDelegationUseTheirOwnProtocol() throws {
    let pcm = Data([0, 0, 255, 127])
    XCTAssertEqual(
      try decode([
        "type": "session.output_audio.delta", "event_id": "e1", "delta": pcm.base64EncodedString(),
      ]),
      .outputAudio(id: "e1", pcm: pcm))
    XCTAssertEqual(
      try decode([
        "type": "session.delegation.created",
        "delegation": ["id": "opaque-request", "target": "client"],
      ]), .delegation("opaque-request"))
    XCTAssertEqual(
      try decode(["type": "response.audio.delta", "delta": pcm.base64EncodedString()]),
      .other("response.audio.delta"))
    XCTAssertThrowsError(
      try decode(["type": "session.output_audio.delta", "delta": Data([1]).base64EncodedString()]))
  }
  func testInterruptionRevokesLateOutputAndLateCallbacks() throws {
    let context = UUID()
    var output = try VoiceOutputQueue(
      context: context, sessionID: "s", mode: .privateVoice,
      policy: RoutingPolicy(meetingActive: false))
    XCTAssertTrue(
      try output.enqueue(id: "a", pcm: Data(repeating: 0, count: 4800), context: context))
    XCTAssertFalse(
      try output.enqueue(id: "a", pcm: Data(repeating: 0, count: 4800), context: context))
    output.revoke(renderedThrough: 1000)
    output.rendered(through: 2400, context: context)
    XCTAssertEqual(output.ledger.entries[0].playedFrames, 1000)
    XCTAssertTrue(output.ledger.entries[0].interrupted)
    XCTAssertThrowsError(try output.enqueue(id: "late", pcm: Data([0, 0]), context: context))
    XCTAssertThrowsError(try output.enqueue(id: "new-context", pcm: Data([0, 0]), context: UUID()))
  }
  func testQueueBackpressureAndPrivacyGates() throws {
    XCTAssertThrowsError(
      try VoiceOutputQueue(
        context: UUID(), sessionID: "s", mode: .broadcast,
        policy: RoutingPolicy(meetingActive: true)))
    let context = UUID()
    var output = try VoiceOutputQueue(
      context: context, sessionID: "s", mode: .privateVoice,
      policy: RoutingPolicy(meetingActive: false))
    XCTAssertTrue(
      try output.enqueue(id: "full", pcm: Data(repeating: 0, count: 192000), context: context))
    XCTAssertThrowsError(try output.enqueue(id: "overflow", pcm: Data([0, 0]), context: context))
    output.rendered(through: 24000, context: context)
    XCTAssertTrue(
      try output.enqueue(id: "next", pcm: Data(repeating: 0, count: 48000), context: context))
    XCTAssertEqual(output.renderedFrames, 24000)
  }
  func testClosedUsageIsSeparateFromAudioCompletion() throws {
    XCTAssertEqual(
      try decode(["type": "session.closed", "usage": ["audio_tokens": 20]]),
      .closed(usageJSON: "{\"audio_tokens\":20}"))
    XCTAssertEqual(try decode(["type": "session.closed"]), .closed(usageJSON: nil))
  }
}
