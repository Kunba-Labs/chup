import AppKit
import ChupCore

@MainActor enum TextDeliveryValidation {
  static func run() async throws {
    let board = NSPasteboard(name: .init("com.chup.delivery-fixture." + UUID().uuidString))
    defer { board.releaseGlobally() }
    let delivery = ClipboardDelivery(board: board)
    let type = NSPasteboard.PasteboardType("com.chup.fixture.binary")
    let original = NSPasteboardItem()
    let binary = Data([0, 255, 3, 0, 42])
    original.setString("Previous clipboard", forType: .string)
    original.setData(binary, forType: type)
    board.clearContents()
    guard board.writeObjects([original]), let snapshot = delivery.snapshot() else {
      throw WorkspaceError.message("Cannot create isolated clipboard fixture.")
    }
    guard delivery.copy("Dictated text", ifUnchanged: snapshot.change) == .copied else {
      throw WorkspaceError.message("Recovery text was not copied.")
    }
    guard delivery.restore(snapshot, ifUnchanged: board.changeCount),
      board.string(forType: .string) == "Previous clipboard", board.data(forType: type) == binary else {
      throw WorkspaceError.message("Clipboard restoration lost a format.")
    }
    let beforeNewCopy = board.changeCount
    board.clearContents(); board.setString("Newer user copy", forType: .string)
    guard !delivery.restore(snapshot, ifUnchanged: beforeNewCopy),
      delivery.copy("Stale dictation", ifUnchanged: beforeNewCopy) == .clipboardChanged,
      board.string(forType: .string) == "Newer user copy" else {
      throw WorkspaceError.message("Delivery overwrote a newer clipboard action.")
    }
    let insertion = TextInsertion(pasteboard: board, observeFocus: false)
    guard await insertion.insert("Recovered dictation", into: nil) == .copied,
      board.string(forType: .string) == "Recovered dictation" else {
      throw WorkspaceError.message("Missing-field insertion did not copy the text for recovery.")
    }
    let beforeCancel = board.changeCount
    let cancelled = Task { @MainActor in await insertion.insert("Cancelled text", into: nil) }
    cancelled.cancel()
    guard await cancelled.value == .cancelled, board.changeCount == beforeCancel else {
      throw WorkspaceError.message("Cancelled delivery changed the clipboard.")
    }
    print("PASS: missing-field delivery copies recovery text; all clipboard formats restore; newer copies survive; cancellation does not write. Isolated pasteboard only, no global input posted.")
  }
}
