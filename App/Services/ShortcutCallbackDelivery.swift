import CoreGraphics
import Foundation

/// Copy callback-owned values before returning to Quartz/Carbon. Never retain a
/// borrowed CGEvent or assert a Swift executor from a C run-loop callback.
struct ShortcutInput: Sendable {
  let type: CGEventType
  let flags: CGEventFlags
  let key: UInt16
  let button: Int
  let repeated: Bool
  init(type: CGEventType, event: CGEvent) {
    self.type = type
    flags = event.flags
    key = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
    repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
  }
}

enum ShortcutCallbackInput: Sendable {
  case event(ShortcutInput)
  case hotKey(UInt32, down: Bool)
}

/// The main dispatch queue preserves callback order. Invalidating a registration
/// also drops its queued events, so old key presses cannot enter a new binding.
final class ShortcutCallbackDelivery: @unchecked Sendable {
  private let lock = NSLock()
  private var active = true
  private let receive: @MainActor (ShortcutCallbackInput) -> Void
  init(receive: @escaping @MainActor (ShortcutCallbackInput) -> Void) { self.receive = receive }
  func invalidate() { lock.withLock { active = false } }
  func enqueue(_ input: ShortcutCallbackInput) {
    DispatchQueue.main.async { [self] in
      guard lock.withLock({ active }) else { return }
      receive(input)
    }
  }
}
