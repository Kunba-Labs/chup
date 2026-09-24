import AppKit
import Sparkle

/// In-app updates from GitHub releases. The appcast and each DMG are signed with
/// an EdDSA key whose public half `package-release.py` writes into the release
/// Info.plist along with `SUFeedURL`; Sparkle refuses anything that key did not
/// sign. Local development installs carry neither key, so they never update
/// themselves and this returns nil.
@MainActor final class AppUpdater: NSObject, SPUUpdaterDelegate {
  private weak var state: WorkspaceState?
  private var controller: SPUStandardUpdaterController?

  init?(state: WorkspaceState) {
    guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return nil }
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
