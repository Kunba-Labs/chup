import AppKit
import Sparkle

/// In-app updates from GitHub releases. Every build carries `SUFeedURL` and the
/// public half of the EdDSA key that signs each release (project.yml); Sparkle
/// refuses anything that key did not sign. Only a copy in an Applications
/// folder — a release or a `deploy-local.py` install — updates itself, so
/// Xcode runs and design renders from DerivedData never do.
@MainActor final class AppUpdater: NSObject, SPUUpdaterDelegate {
  private weak var state: WorkspaceState?
  private var controller: SPUStandardUpdaterController?

  init?(state: WorkspaceState) {
    guard Bundle.main.bundlePath.contains("/Applications/") else { return nil }
    self.state = state
    super.init()
    controller = SPUStandardUpdaterController(
      startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
  }

  func check() { controller?.checkForUpdates(nil) }

  /// Installing relaunches the app, so no update is offered mid-recording or
  /// mid-dictation; the next scheduled check picks it up.
  nonisolated func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
    let busy = MainActor.assumeIsolated {
      state.map { $0.activeMeetingID != nil || $0.dictationStatus == .listening || $0.dictationStatus == .processing }
        ?? false
    }
    if busy {
      throw NSError(domain: "Chup", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "Finish the recording or dictation before updating Chup!."])
    }
  }
}
