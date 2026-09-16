import Foundation
import ChupCore

/// Foundation timer callbacks are not Swift actor tasks. Explicitly enqueue their
/// work instead of asserting executor identity inside the run-loop callback.
@MainActor enum MainActorTimer {
  static func repeating(every interval: TimeInterval, action: @escaping @MainActor () -> Void) -> Timer {
    Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
      Task { @MainActor in
        guard timer.isValid else { return }
        action()
      }
    }
  }

  static func validateDelivery() async throws {
    var delivered = 0
    let timer = repeating(every: 0.01) { delivered += 1 }
    defer { timer.invalidate() }
    // Exercise both Foundation's callback and the real main run loop.
    timer.fire()
    try await Task.sleep(for: .milliseconds(120))
    guard delivered >= 2 else {
      throw WorkspaceError.message("Main-actor timer did not deliver repeated callbacks.")
    }
    timer.fire()
    timer.invalidate()
    let stoppedAt = delivered
    try await Task.sleep(for: .milliseconds(40))
    guard delivered == stoppedAt else {
      throw WorkspaceError.message("Invalidated timer delivered queued work.")
    }
    print("PASS: Foundation timer delivers on MainActor and discards queued work after invalidation.")
  }
}
