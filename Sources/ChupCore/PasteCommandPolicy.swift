import Foundation

public enum PasteCommandPolicy {
  /// Exact ordinary Paste labels for the initial English/Dutch UI languages.
  /// Do not match Paste and Go / Paste and Execute / Paste Selection, even if
  /// an application assigns Command-V to one of those commands.
  public static func isPlainPaste(title: String?) -> Bool {
    guard let title else { return false }
    return ["paste", "plakken"].contains(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
  }
}
