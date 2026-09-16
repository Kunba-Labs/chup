import Foundation

/// Metadata signals only. Expiry and rejection never produce a recording action.
public struct MeetingCandidate: Equatable {
  public var pid: Int32
  public var name: String
  public var browser: Bool
  public init(pid: Int32, name: String, browser: Bool) {
    self.pid = pid
    self.name = name
    self.browser = browser
  }
}
public struct MeetingDetectionPolicy {
  private var firstSeen: [Int32: Double] = [:]
  private var lastSeen: [Int32: Double] = [:]
  private var prompted = Set<Int32>()
  private var snoozedUntil: [Int32: Double] = [:]
  public private(set) var pending: MeetingCandidate?
  public private(set) var deadline: Double?
  public init() {}
  public mutating func observe(_ candidates: [MeetingCandidate], now: Double, recording: Bool)
    -> MeetingCandidate?
  {
    if let deadline, now >= deadline { dismiss(now: now) }
    let live = Set(candidates.map(\.pid))
    for pid in Array(lastSeen.keys) where !live.contains(pid) && now - (lastSeen[pid] ?? now) > 90 {
      firstSeen[pid] = nil
      lastSeen[pid] = nil
      prompted.remove(pid)
    }
    for candidate in candidates {
      if firstSeen[candidate.pid] == nil { firstSeen[candidate.pid] = now }
      lastSeen[candidate.pid] = now
    }
    guard !recording, pending == nil else { return nil }
    guard
      let candidate = candidates.first(where: {
        now - (firstSeen[$0.pid] ?? now) >= 4 && !prompted.contains($0.pid)
          && now >= (snoozedUntil[$0.pid] ?? 0)
      })
    else { return nil }
    prompted.insert(candidate.pid)
    pending = candidate
    deadline = now + 10
    return candidate
  }
  public mutating func dismiss(now: Double, snooze: Double = 0) {
    if let pending, snooze > 0 {
      prompted.remove(pending.pid)
      snoozedUntil[pending.pid] = now + snooze
    }
    pending = nil
    deadline = nil
  }
  public mutating func accept(now: Double) -> MeetingCandidate? {
    guard let deadline, now < deadline else {
      dismiss(now: now)
      return nil
    }
    let candidate = pending
    dismiss(now: now)
    return candidate
  }
}
