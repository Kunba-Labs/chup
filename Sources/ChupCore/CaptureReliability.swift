import Foundation

public struct AudioDiscontinuity: Equatable {
  public var start: Double
  public var end: Double
  public var reason: String
}

/// Source timestamps remain authoritative. Small clock-rate differences are measured separately
/// from dropped packets; a clock reset is rejected instead of moving new audio into the past.
public struct CaptureClockTracker {
  private var previousEnd: Double?
  private var previousStart: Double?
  private var rate: Double?
  private var baseline: Double?
  private var nominalDuration: Double = 0
  public private(set) var driftPPM: Double = 0
  public init() {}
  public mutating func observe(hostTime: Double, frames: Int, sampleRate: Double) throws
    -> AudioDiscontinuity?
  {
    guard hostTime.isFinite, hostTime >= 0, frames > 0, frames <= 32768,
      sampleRate.isFinite, (8000...192000).contains(sampleRate)
    else {
      throw WorkspaceError.message("Invalid capture clock or PCM format.")
    }
    if let previousStart, hostTime < previousStart - 0.002 {
      throw WorkspaceError.message("Audio source clock moved backwards. Reconnect the source.")
    }
    var gap: AudioDiscontinuity?
    if let end = previousEnd, hostTime - end > 0.08 {
      gap = AudioDiscontinuity(start: end, end: hostTime, reason: "Audio packets missing")
      baseline = nil
      nominalDuration = 0
      driftPPM = 0
    }
    if let rate, rate != sampleRate {
      gap = AudioDiscontinuity(
        start: previousEnd ?? hostTime, end: hostTime, reason: "Sample rate changed")
      baseline = nil
      nominalDuration = 0
      driftPPM = 0
    }
    if let baseline, nominalDuration >= 10 {
      let measured = ((hostTime - baseline) / nominalDuration - 1) * 1_000_000
      if measured.isFinite { driftPPM = measured }
    }
    if baseline == nil { baseline = hostTime }
    nominalDuration += Double(frames) / sampleRate
    previousStart = hostTime
    previousEnd = hostTime + Double(frames) / sampleRate
    rate = sampleRate
    return gap
  }
}

/// Used under the audio owner's lock. A stopped source cannot publish packets to a new leg.
public struct CaptureLease: Equatable, Sendable {
  public var id: UUID
  public init() { id = UUID() }
}

public struct RecordingRecoveryReport: Codable, Equatable {
  public var meetingID: String
  public var duration: Double
  public var completePackets: Int
  public var truncatedFiles: [String]
  public var corruptFiles: [String]
  public init(
    meetingID: String, duration: Double = 0, completePackets: Int = 0,
    truncatedFiles: [String] = [], corruptFiles: [String] = []
  ) {
    self.meetingID = meetingID
    self.duration = duration
    self.completePackets = completePackets
    self.truncatedFiles = truncatedFiles
    self.corruptFiles = corruptFiles
  }
}
