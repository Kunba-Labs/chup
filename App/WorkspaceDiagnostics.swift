import AppKit
import ChupCore

extension WorkspaceState {
  /// Explicit allowlist: never serialize state, error strings, destinations, device names or content.
  func exportDiagnostics() {
    setup.refresh()
    let report: [String: Any] = [
      "format": "Chup diagnostics v2",
      "created": ISO8601DateFormatter().string(from: Date()),
      "dictationTimings": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(dictationTraces))) ?? [],
      "appVersion": runningBuild.version,
      "appBuild": runningBuild.build,
      "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
      "architecture": "arm64",
      "permissions": Dictionary(uniqueKeysWithValues: setup.permissions.map { ($0.key.rawValue, $0.value.rawValue) }),
      "cloudEnabled": cloudEnabled,
      "encryptedDatabase": store?.encrypted == true,
      "dictationState": dictationStatus.rawValue,
      "meetingState": meetingStatus.rawValue,
      "screenCaptureFallback": captureFallback,
      "shortcutCount": shortcuts.bindings.count,
      "shortcutRegistrationFailureCount": shortcuts.registrationFailures.count,
      "meetingCount": meetings.count,
      "dictationCount": history.count,
      "unconfirmedUsageCount": providerUsage.filter { !$0.confirmed }.count,
      "interruptedRequestCount": durableRequests.filter { $0.status == "interrupted" }.count,
      "disclosure": "Only timings, states and counts. No recordings, text, names or passwords."
    ]
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Chup-diagnostics.json"
    panel.message = "Saves versions, permissions and counts. No recordings, text or passwords."
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try DurableFile.write(JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), to: url)
      storageMessage = "Diagnostics saved."
    } catch { storageMessage = "Diagnostics export failed: " + error.localizedDescription }
  }
}
