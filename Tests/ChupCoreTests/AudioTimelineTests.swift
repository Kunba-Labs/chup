import Foundation
import XCTest

@testable import ChupCore

final class AudioTimelineTests: XCTestCase {
  private func packet(_ value: Int16, count: Int, rate: Double = 48000) -> AudioPacket {
    let samples = [Int16](repeating: value.littleEndian, count: count)
    return AudioPacket(hostTime: 100, sampleRate: rate, pcm: samples.withUnsafeBytes { Data($0) })
  }
  func testTrackAlignmentAndCaptureGap() throws {
    let data = [
      PositionedAudio(start: 0, track: .microphone, packet: packet(16384, count: 480)),
      PositionedAudio(start: 0.005, track: .remote, packet: packet(16384, count: 240)),
      PositionedAudio(start: 0.02, track: .microphone, packet: packet(16384, count: 480)),
    ]
    let mixed = try AudioTimeline.mix(data, start: 0, frames: 1440)
    XCTAssertEqual(mixed[0], 0.25)
    XCTAssertEqual(mixed[239], 0.25)
    XCTAssertEqual(mixed[240], 0.5)
    XCTAssertEqual(mixed[479], 0.5)
    XCTAssertTrue(
      mixed[480..<960].allSatisfy { $0 == 0 }, "A capture gap must not pull later audio forward")
    XCTAssertEqual(mixed[960], 0.25)
  }
  func testChunkBoundaryAndSeekProduceSameAudio() throws {
    let data = [
      PositionedAudio(start: 29.99, track: .remote, packet: packet(8192, count: 480)),
      PositionedAudio(start: 30, track: .remote, packet: packet(16384, count: 480)),
    ]
    let entire = try AudioTimeline.mix(data, start: 29.99, frames: 960)
    let seek = try AudioTimeline.mix(data, start: 30, frames: 480)
    XCTAssertEqual(Array(entire.suffix(480)), seek)
    XCTAssertEqual(entire[479], 0.125)
    XCTAssertEqual(entire[480], 0.25)
  }
  func testRateChangesAndLongMeetingOffsets() throws {
    let data = [
      PositionedAudio(
        start: 7199, track: .remote, packet: packet(16384, count: 24000, rate: 24000)),
      PositionedAudio(start: 7200, track: .remote, packet: packet(8192, count: 44100, rate: 44100)),
    ]
    let mixed = try AudioTimeline.mix(data, start: 7199.5, frames: 48000)
    XCTAssertEqual(mixed[23999], 0.25, accuracy: 0.00001)
    XCTAssertEqual(mixed[24000], 0.125, accuracy: 0.00001)
    XCTAssertEqual(mixed[47999], 0.125, accuracy: 0.00001)
  }
  func testMalformedAudioAndUnboundedWindowRejected() throws {
    XCTAssertThrowsError(try AudioTimeline.mix([], start: .nan, frames: 48))
    XCTAssertThrowsError(try AudioTimeline.mix([], start: 0, frames: 480001))
    let broken = AudioPacket(hostTime: 0, sampleRate: 48000, channels: 1, pcm: Data([1]))
    XCTAssertThrowsError(
      try AudioTimeline.mix(
        [.init(start: 0, track: .microphone, packet: broken)], start: 0, frames: 48))
  }
  func testMixedOutputDoesNotClipBeyondFullScale() throws {
    let packets = TrackKind.allCases.map {
      PositionedAudio(start: 0, track: $0, packet: packet(32767, count: 100))
    }
    let mixed = try AudioTimeline.mix(packets, start: 0, frames: 100)
    XCTAssertTrue(mixed.allSatisfy { $0 <= 1 && $0 >= -1 })
  }
}
