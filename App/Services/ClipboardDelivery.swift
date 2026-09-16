import AppKit
import ChupCore

/// A paste transaction owns only the clipboard revision it wrote. Recovery copying
/// is deliberate; successful paste restores all original formats when still owned.
@MainActor final class ClipboardDelivery {
  struct Snapshot {
    let change: Int
    let items: [[NSPasteboard.PasteboardType: Data]]
  }
  let board: NSPasteboard
  init(board: NSPasteboard = .general) { self.board = board }
  func snapshot() -> Snapshot? {
    let change = board.changeCount
    var items = [[NSPasteboard.PasteboardType: Data]]()
    for item in board.pasteboardItems ?? [] {
      var formats = [NSPasteboard.PasteboardType: Data]()
      for type in item.types {
        guard let data = item.data(forType: type) else { return nil }
        formats[type] = data
      }
      items.append(formats)
    }
    guard board.changeCount == change else { return nil }
    return Snapshot(change: change, items: items)
  }
  func copy(_ text: String, ifUnchanged expected: Int, unconfirmed: Bool = false) -> TextDeliveryResult {
    guard board.changeCount == expected else { return .clipboardChanged }
    board.clearContents()
    guard board.setString(text, forType: .string), board.string(forType: .string) == text else { return .copyFailed }
    return unconfirmed ? .unconfirmedCopied : .copied
  }
  @discardableResult func restore(_ snapshot: Snapshot, ifUnchanged expected: Int) -> Bool {
    guard InsertionPolicy.mayRestoreClipboard(insertionChange: expected, currentChange: board.changeCount) else { return false }
    let items = snapshot.items.map { formats in
      let item = NSPasteboardItem()
      for (type, data) in formats { item.setData(data, forType: type) }
      return item
    }
    board.clearContents()
    return items.isEmpty || board.writeObjects(items)
  }
}
