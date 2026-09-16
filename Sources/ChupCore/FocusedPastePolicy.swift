import Foundation

public enum FocusedPastePolicy {
  public static func supports(role: String?) -> Bool {
    ["AXTextArea", "AXTextField", "AXComboBox"].contains(role ?? "")
  }
  public static func requiresFocusedPaste(canWriteSelection: Bool, canWriteValue: Bool, hasSelectionSnapshot: Bool) -> Bool {
    !hasSelectionSnapshot || (!canWriteSelection && !canWriteValue)
  }
  /// An opaque input can interpret newline/control characters as commands. Keep
  /// these for deliberate manual paste instead of flattening or sending them.
  public static func allowsAutomaticPaste(_ text: String) -> Bool {
    !text.isEmpty && text.unicodeScalars.allSatisfy {
      !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0)
    }
  }
  public static func canPaste(samePane: Bool, sameWindow: Bool, sameFocusEpoch: Bool,
    sameInteractionEpoch: Bool, monitoring: Bool, secureInput: Bool, selectionEmpty: Bool) -> Bool {
    samePane && sameWindow && sameFocusEpoch && sameInteractionEpoch && monitoring && !secureInput && selectionEmpty
  }
  /// A custom control may expose rendered content rather than an editable value. Confirm only
  /// when the new screen can be explained by insertion of exactly this text.
  /// Ignore soft-wrap line breaks. Complex TUI redraws remain unconfirmed.
  public static func confirms(before: String, after: String, text: String) -> Bool {
    guard allowsAutomaticPaste(text) else { return false }
    let old = before.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
    let new = after.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
    guard new.utf16.count == old.utf16.count + text.utf16.count else { return false }
    var start = new.startIndex
    while start < new.endIndex, let range = new.range(of: text, range: start..<new.endIndex) {
      if new.replacingCharacters(in: range, with: "") == old { return true }
      start = new.index(after: range.lowerBound)
    }
    return false
  }
}
