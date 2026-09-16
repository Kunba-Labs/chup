import Foundation

public struct DictationTrace: Codable, Identifiable, Equatable {
  public enum Stage: String, Codable, CaseIterable {
    case requested, firstAudio, captureStopped, cloudStarted, cloudFinished
    case localStarted, localFinished, cleanupStarted, cleanupFinished, insertionStarted, finished
  }
  public enum Outcome: String, Codable {
    case running, saved, inserted, copied, unconfirmed, clipboardChanged, copyFailed, cancelled, failed, noSignal, interrupted
  }
  public struct Event: Codable, Equatable {
    public let stage: Stage
    public let milliseconds: Double
  }
  public let id: String
  public let created: Date
  public var outcome: Outcome = .running
  public private(set) var events: [Event] = []
  public init(id: String = UUID().uuidString, created: Date = Date()) { self.id = id; self.created = created }
  public mutating func mark(_ stage: Stage, elapsed: Double) {
    guard outcome == .running, elapsed.isFinite, elapsed >= 0,
      !events.contains(where: { $0.stage == stage }) else { return }
    events.append(Event(stage: stage, milliseconds: max(events.last?.milliseconds ?? 0, elapsed * 1000)))
  }
  public func duration(from start: Stage, to end: Stage) -> Double? {
    guard let a = events.first(where: { $0.stage == start }), let b = events.first(where: { $0.stage == end }) else { return nil }
    return max(0, b.milliseconds - a.milliseconds)
  }
}
