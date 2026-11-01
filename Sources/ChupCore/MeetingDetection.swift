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
/// Browser tab evidence read through Accessibility (Hyprnote's rule): a meeting needs a call
/// site plus an in-call control, or a Meet code title, so a browser merely holding the mic
/// doesn't count.
public enum BrowserMeetingEvidence {
  static let services: [(host: String, name: String)] = [
    ("meet.google.com", "Google Meet"), ("teams.microsoft.com", "Microsoft Teams"),
    ("teams.live.com", "Microsoft Teams"), ("zoom.us", "Zoom"), ("webex.com", "Webex"),
    ("app.slack.com", "Slack"), ("discord.com", "Discord"), ("whereby.com", "Whereby"),
    ("meet.jit.si", "Jitsi Meet"),
  ]
  static let leaveControls: Set<String> = [
    "leave call", "hang up", "leave", "leave meeting", "end meeting", "end call",
    "leave huddle", "end huddle", "disconnect",
  ]
  public static func isMeetingURL(_ url: String) -> Bool { service(url) != nil }
  static func service(_ url: String) -> String? {
    guard let host = URL(string: url)?.host?.lowercased() else { return nil }
    return services.first { host == $0.host || host.hasSuffix("." + $0.host) }?.name
  }
  /// The call service a window shows: a Meet code title (the active tab), or call-site URLs that
  /// all name one service. Tabs naming different services are ambiguous, so nothing is named.
  public static func service(urls: [String], titles: [String]) -> String? {
    if titles.contains(where: isMeetTitle) { return "Google Meet" }
    let named = Set(urls.compactMap(service))
    return named.count == 1 ? named.first : nil
  }
  /// "Meet - abc-defg-hij" (optionally followed by " - Google Chrome" etc).
  public static func isMeetTitle(_ title: String) -> Bool {
    let lower = title.lowercased()
    guard lower.hasPrefix("meet - ") else { return false }
    let code = lower.dropFirst(7).prefix { !$0.isWhitespace }.split(separator: "-")
    return code.map(\.count) == [3, 4, 3] && code.joined().allSatisfy { $0.isLetter }
  }
  /// Evaluate one window at a time. `requireControl` is for "still in the call?": a Meet title
  /// can outlive the call, a visible Leave control can't.
  public static func inCall(
    urls: [String], titles: [String], controls: [String], requireControl: Bool = false
  ) -> Bool {
    let meetTitle = titles.contains(where: isMeetTitle)
    let leave = controls.contains {
      leaveControls.contains($0.trimmingCharacters(in: .whitespaces).lowercased())
    }
    return (meetTitle && !requireControl) || (leave && (meetTitle || urls.contains(where: isMeetingURL)))
  }
}
/// Asks once per quiet spell whether the call ended; never stops a recording by itself. Arms
/// only after the call app has been seen in the call, so a listen-only recording never asks.
public struct MeetingEndPolicy {
  private var armed = false
  private var quietSince: Double?
  private var asked = false
  public init() {}
  /// Returns true when the "did the call end?" prompt should appear.
  public mutating func observe(active: Bool, now: Double, after quiet: Double = 10) -> Bool {
    if active {
      armed = true
      quietSince = nil
      asked = false
      return false
    }
    guard armed else { return false }
    let since = quietSince ?? now
    quietSince = since
    guard !asked, now - since >= quiet else { return false }
    asked = true
    return true
  }
  public mutating func reset() { self = .init() }
}
