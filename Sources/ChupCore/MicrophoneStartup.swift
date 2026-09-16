import Foundation

/// Wait out delayed I/O notifications before advertising capture as ready.
/// Recovery must validate the original device and format; never substitute input.
@MainActor public enum MicrophoneStartup {
  public enum Failure: Error { case didNotSettle }
  public static func settle(
    isReady: () -> Bool,
    resumeMatchingInput: () throws -> Void,
    wait: () async throws -> Void = { try await Task.sleep(for: .milliseconds(250)) }
  ) async throws {
    for attempt in 0..<3 {
      try await wait()
      try Task.checkCancellation()
      if isReady() { return }
      guard attempt < 2 else { throw Failure.didNotSettle }
      try resumeMatchingInput()
    }
  }
}
