import Foundation

/// Captured when WorkspaceState starts, so Settings identifies this process even
/// if somebody later replaces a bundle on disk.
struct RunningBuild {
  let version: String
  let build: String
  let appPath: String
  let pid: Int32
  init(bundle: Bundle = .main) {
    version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    appPath = bundle.bundleURL.resolvingSymlinksInPath().path
    pid = ProcessInfo.processInfo.processIdentifier
  }
  var label: String { "Chup! \(version) (\(build))" }
}
