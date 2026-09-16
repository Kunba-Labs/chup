import Foundation

public enum TextDeliveryResult: Equatable {
  case inserted, sentToApplication, copied, unconfirmedCopied, clipboardChanged, copyFailed, cancelled

  /// A dispatched request is not proof of the target's final contents. Keep
  /// unverified delivery distinct in diagnostics and clipboard recovery.
  public var isCompactCompletion: Bool { self == .inserted || self == .sentToApplication }

  public var title: String {
    switch self {
    case .inserted: return "Inserted"
    case .sentToApplication: return "Text sent"
    case .copied: return "Copied to clipboard"
    case .unconfirmedCopied: return "Paste not confirmed"
    case .clipboardChanged, .copyFailed: return "Text saved"
    case .cancelled: return "Cancelled"
    }
  }
  public var detail: String {
    switch self {
    case .inserted: return "Dictation complete"
    case .sentToApplication: return "Kept on clipboard if needed"
    case .copied: return "Paste manually into the intended field"
    case .unconfirmedCopied: return "The app may have accepted it; text remains on the clipboard"
    case .clipboardChanged: return "Clipboard changed · see history"
    case .copyFailed: return "Copy failed · see history"
    case .cancelled: return "Text remains in history"
    }
  }
  public var message: String { title + " · " + detail }
  public var icon: String {
    switch self {
    case .inserted: return "checkmark.circle.fill"
    case .sentToApplication: return "arrow.up.forward.circle"
    case .copied, .unconfirmedCopied: return "doc.on.clipboard"
    case .clipboardChanged, .copyFailed: return "exclamationmark.circle"
    case .cancelled: return "xmark.circle"
    }
  }
}

public enum TextDeliveryPolicy {
  public static func afterDispatch(confirmed: Bool, dispatched: Bool, recovery: TextDeliveryResult) -> TextDeliveryResult {
    if confirmed { return .inserted }
    guard recovery == .copied else { return recovery }
    return dispatched ? .sentToApplication : .unconfirmedCopied
  }
  /// AX ranges use UTF-16. Never manufacture a range from an invalid selection.
  public static func expectedValue(original: String, location: Int, length: Int, text: String) -> String? {
    guard location >= 0, length >= 0, location <= original.utf16.count,
      length <= original.utf16.count - location else { return nil }
    let units = Array(original.utf16)
    func boundary(_ offset: Int) -> Bool {
      offset == 0 || offset == units.count
        || !((0xDC00...0xDFFF).contains(units[offset]) && (0xD800...0xDBFF).contains(units[offset - 1]))
    }
    guard boundary(location), boundary(location + length) else { return nil }
    return (original as NSString).replacingCharacters(in: NSRange(location: location, length: length), with: text)
  }
}
