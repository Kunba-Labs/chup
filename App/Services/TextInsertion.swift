import AppKit
import ApplicationServices
import Carbon
import ChupCore

@MainActor final class TextInsertion {
  struct Destination {
    let application: NSRunningApplication
    let element: AXUIElement
    let selection: CFRange
    let value: String
    let selectedText: String
    let focusEpoch: Int
    let observingFocus: Bool
    let focusedPaste: Bool
    let window: AXUIElement?
    let interactionEpoch: Int
  }
  private(set) var lastDeliveryRoute = "None"
  private(set) var lastDiagnostic = "Idle"
  private func delivery(_ message: String) { lastDiagnostic = message }
  private func unavailable(_ reason: String) -> Destination? {
    lastDiagnostic = reason
    return nil
  }
  private let focusEpoch = FocusEpoch()
  private var epoch: Int { focusEpoch.current }
  private var interactionEpoch = 0
  var interactionMonitoringAvailable: () -> Bool = { false }
  func noteUserInteraction() { interactionEpoch &+= 1 }
  private var observer: NSObjectProtocol?
  private let focusNotifications: NotificationCenter
  private var focusObserver: AXObserver?
  private var observedPID: pid_t?
  private let clipboard: ClipboardDelivery
  init(pasteboard: NSPasteboard = .general, observeFocus: Bool = true, notifications: NotificationCenter? = nil) {
    focusNotifications = notifications ?? NSWorkspace.shared.notificationCenter
    clipboard = ClipboardDelivery(board: pasteboard)
    guard observeFocus else { return }
    observer = focusNotifications.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil
    ) { [focusEpoch] _ in
      focusEpoch.advance()
    }
  }
  deinit {
    if let observer { focusNotifications.removeObserver(observer) }
    if let focusObserver { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(focusObserver), .commonModes) }
  }
  static var trusted: Bool { AXIsProcessTrusted() }
  static func requestPermission() {
    AXIsProcessTrustedWithOptions(
      [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
  }
  private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
      return nil
    }
    return value
  }
  private func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
    var settable: DarwinBoolean = false
    return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
  }
  private func secure(_ element: AXUIElement) -> Bool {
    if IsSecureEventInputEnabled() { return true }
    var node = element
    for _ in 0..<8 {
      if attribute(node, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole {
        return true
      }
      guard let parent = attribute(node, kAXParentAttribute),
        CFGetTypeID(parent) == AXUIElementGetTypeID()
      else { break }
      node = unsafeBitCast(parent, to: AXUIElement.self)
    }
    return false
  }
  private func range(_ element: AXUIElement) -> CFRange? {
    guard let raw = attribute(element, kAXSelectedTextRangeAttribute),
      CFGetTypeID(raw) == AXValueGetTypeID()
    else { return nil }
    var r = CFRange()
    guard AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cfRange, &r) else { return nil }
    return r
  }
  func capture() -> Destination? {
    guard Self.trusted, let app = NSWorkspace.shared.frontmostApplication,
      app.processIdentifier != ProcessInfo.processInfo.processIdentifier
    else { return unavailable("Accessibility unavailable or Chup is active") }
    let application = AXUIElementCreateApplication(app.processIdentifier)
    if observedPID != app.processIdentifier {
      if let old = focusObserver {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(old), .commonModes)
      }
      focusObserver = nil
      observedPID = nil
      var next: AXObserver?
      if AXObserverCreate(
        app.processIdentifier,
        { _, _, _, context in
          guard let context else { return }
          let epoch = Unmanaged<FocusEpoch>.fromOpaque(context).takeUnretainedValue()
          epoch.advance()
        }, &next) == .success, let next
      {
        let status = AXObserverAddNotification(
          next, application, kAXFocusedUIElementChangedNotification as CFString,
          Unmanaged.passUnretained(focusEpoch).toOpaque())
        if status == .success {
          focusObserver = next
          observedPID = app.processIdentifier
          CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(next), .commonModes)
        }
      }
    }
    guard let raw = attribute(application, kAXFocusedUIElementAttribute),
      CFGetTypeID(raw) == AXUIElementGetTypeID()
    else { return unavailable("No focused Accessibility element") }
    let element = unsafeBitCast(raw, to: AXUIElement.self)
    guard !secure(element) else { return unavailable("Secure input active") }
    guard FocusedPastePolicy.supports(role: attribute(element, kAXRoleAttribute) as? String) else { return unavailable("Focused control is not a text input") }
    let capturedRange = range(element)
    let capturedValue = attribute(element, kAXValueAttribute) as? String
    let validSnapshot: Bool
    if let capturedRange, let capturedValue {
      validSnapshot = TextDeliveryPolicy.expectedValue(original: capturedValue,
        location: capturedRange.location, length: capturedRange.length, text: "") != nil
    } else { validSnapshot = false }
    let focusedPaste = FocusedPastePolicy.requiresFocusedPaste(
      canWriteSelection: isSettable(element, kAXSelectedTextAttribute),
      canWriteValue: isSettable(element, kAXValueAttribute), hasSelectionSnapshot: validSnapshot)
    let selection: CFRange
    let value: String
    let selected: String
    var window: AXUIElement?
    if focusedPaste {
      guard interactionMonitoringAvailable(),
        let rawWindow = attribute(element, kAXWindowAttribute), CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else { return unavailable("Input monitoring or original window unavailable") }
      window = unsafeBitCast(rawWindow, to: AXUIElement.self)
      selection = capturedRange ?? CFRange(location: 0, length: 0)
      value = capturedValue ?? ""
      // Read-only or missing selection metadata cannot support selected-text editing.
      selected = ""
    } else {
      guard let capturedRange, let capturedValue else { return unavailable("Missing editable value or selection") }
      selection = capturedRange
      value = capturedValue
      selected = attribute(element, kAXSelectedTextAttribute) as? String ?? ""
    }
    lastDiagnostic = focusedPaste ? "Captured focused paste control" : "Captured editable field"
    return Destination(
      application: app, element: element, selection: selection, value: value,
      selectedText: selected, focusEpoch: epoch,
      observingFocus: observedPID == app.processIdentifier,
      focusedPaste: focusedPaste, window: window, interactionEpoch: interactionEpoch)
  }
  func isValid(_ destination: Destination) -> Bool {
    guard destination.observingFocus, destination.focusEpoch == epoch, let current = capture()
    else { return false }
    guard CFEqual(current.element, destination.element) else { return false }
    if destination.focusedPaste {
      guard current.focusedPaste, let originalWindow = destination.window, let currentWindow = current.window else { return false }
      return FocusedPastePolicy.canPaste(samePane: CFEqual(current.element, destination.element),
        sameWindow: CFEqual(originalWindow, currentWindow), sameFocusEpoch: current.focusEpoch == destination.focusEpoch,
        sameInteractionEpoch: current.interactionEpoch == destination.interactionEpoch,
        monitoring: interactionMonitoringAvailable(), secureInput: secure(current.element),
        selectionEmpty: destination.selection.length == 0 && current.selection.length == 0)
    }
    func fingerprint(_ d: Destination) -> DestinationFingerprint {
      DestinationFingerprint(
        pid: d.application.processIdentifier, elementID: String(CFHash(d.element)),
        selectionLocation: d.selection.location, selectionLength: d.selection.length,
        value: d.value, focusEpoch: d.focusEpoch, secure: secure(d.element))
    }
    return InsertionPolicy.canInsert(
      original: fingerprint(destination), current: fingerprint(current))
  }
  /// Only our own verified insertion can advance a queued snapshot. User edits,
  /// cursor movement, focus changes and selected-text commands never rebase.
  func advance(_ candidate: Destination, after text: String, insertedInto original: Destination) -> Destination? {
    guard !candidate.focusedPaste, !original.focusedPaste,
      candidate.selectedText.isEmpty, original.selectedText.isEmpty,
      candidate.observingFocus, original.observingFocus,
      candidate.application.processIdentifier == original.application.processIdentifier,
      CFEqual(candidate.element, original.element),
      candidate.focusEpoch == original.focusEpoch,
      candidate.interactionEpoch == original.interactionEpoch,
      candidate.value == original.value,
      candidate.selection.location == original.selection.location,
      candidate.selection.length == 0, original.selection.length == 0,
      let current = capture(), !current.focusedPaste, current.observingFocus,
      current.application.processIdentifier == original.application.processIdentifier,
      CFEqual(current.element, original.element), !secure(current.element),
      current.focusEpoch == original.focusEpoch,
      current.interactionEpoch == original.interactionEpoch,
      current.value == TextDeliveryPolicy.expectedValue(original: original.value,
        location: original.selection.location, length: 0, text: text),
      current.selection.length == 0,
      current.selection.location == original.selection.location + text.utf16.count
    else { return nil }
    return current
  }
  /// Discover the ordinary native Paste action independently of its key binding.
  /// Never opens a menu, activates another app, or selects Paste and Go.
  private func pasteMenuItem(for destination: Destination) -> AXUIElement? {
    let app = AXUIElementCreateApplication(destination.application.processIdentifier)
    guard let raw = attribute(app, kAXMenuBarAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
    var remaining = 500
    var matches: [AXUIElement] = []
    func visit(_ element: AXUIElement, depth: Int) {
      guard depth <= 4, remaining > 0 else { return }
      remaining -= 1
      if PasteCommandPolicy.isPlainPaste(title: attribute(element, kAXTitleAttribute) as? String),
        attribute(element, kAXRoleAttribute) as? String == kAXMenuItemRole,
        (attribute(element, kAXEnabledAttribute) as? NSNumber)?.boolValue == true {
        var actions: CFArray?
        if AXUIElementCopyActionNames(element, &actions) == .success,
          (actions as? [String])?.contains(kAXPressAction) == true { matches.append(element) }
      }
      for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []) {
        visit(child, depth: depth + 1)
      }
    }
    visit(unsafeBitCast(raw, to: AXUIElement.self), depth: 0)
    return matches.count == 1 && remaining > 0 ? matches[0] : nil
  }
  private func waitForModifierRelease() async -> Bool {
    let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate, .maskSecondaryFn]
    for _ in 0..<40 {
      if Task.isCancelled { return false }
      if CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty { return true }
      do { try await Task.sleep(for: .milliseconds(40)) } catch { return false }
    }
    return false
  }
  private func confirms(_ expected: String, in destination: Destination, pasteBefore: String?) -> Bool {
    guard let front = NSWorkspace.shared.frontmostApplication,
      front.processIdentifier == destination.application.processIdentifier,
      !secure(destination.element),
      let focused = attribute(AXUIElementCreateApplication(front.processIdentifier), kAXFocusedUIElementAttribute),
      CFEqual(focused, destination.element),
      let value = attribute(destination.element, kAXValueAttribute) as? String else { return false }
    if let pasteBefore { return FocusedPastePolicy.confirms(before: pasteBefore, after: value, text: expected) }
    return value == expected
  }
  private func confirm(_ expected: String, in destination: Destination, pasteBefore: String? = nil) async -> Bool {
    // Keep the status pill responsive after a paste has landed. A short
    // confirmation window catches normal AX/terminal updates without leaving
    // the spinner visible for nearly a second after visible text is present.
    for _ in 0..<8 {
      if Task.isCancelled { return false }
      if confirms(expected, in: destination, pasteBefore: pasteBefore) { return true }
      do { try await Task.sleep(for: .milliseconds(35)) } catch { return false }
    }
    return false
  }
  /// Never activates an app or posts Return. A changed or unverified field is
  /// never targeted; recovery copying happens only after a clipboard write succeeds.
  func insert(_ text: String, into destination: Destination?) async -> TextDeliveryResult {
    guard !Task.isCancelled else { return .cancelled }
    lastDeliveryRoute = "None"
    let initialChange = clipboard.board.changeCount
    guard !text.isEmpty else { delivery("Empty transcript"); return .copyFailed }
    guard let destination, isValid(destination) else {
      delivery(destination == nil ? "No safe destination; copied for recovery" : "Destination changed or lost focus; copied for recovery")
      return clipboard.copy(text, ifUnchanged: initialChange)
    }
    let expected: String
    if destination.focusedPaste {
      guard FocusedPastePolicy.allowsAutomaticPaste(text) else { delivery("Focused paste policy rejected automatic paste"); return clipboard.copy(text, ifUnchanged: initialChange) }
      expected = text
    } else {
      guard let replacement = TextDeliveryPolicy.expectedValue(original: destination.value,
        location: destination.selection.location, length: destination.selection.length, text: text) else {
        delivery("Selection range was no longer valid; copied for recovery")
        return clipboard.copy(text, ifUnchanged: initialChange)
      }
      expected = replacement
    }
    var settable: DarwinBoolean = false
    if !destination.focusedPaste,
      AXUIElementIsAttributeSettable(destination.element, kAXSelectedTextAttribute as CFString, &settable) == .success,
      settable.boolValue {
      lastDeliveryRoute = "Accessibility selection"
      let status = AXUIElementSetAttributeValue(destination.element, kAXSelectedTextAttribute as CFString, text as CFString)
      // Even a failed AX call may have modified content. Never follow it with a
      // second insertion attempt; verify the result, then copy if unconfirmed.
      let confirmed = await confirm(expected, in: destination)
      if Task.isCancelled { return .cancelled }
      if confirmed { delivery("Accessibility selection confirmed"); return .inserted }
      delivery("Accessibility dispatch was not confirmed; copied for recovery")
      let recovery = clipboard.copy(text, ifUnchanged: initialChange)
      return TextDeliveryPolicy.afterDispatch(confirmed: false, dispatched: status == .success, recovery: recovery)
    }
    guard await waitForModifierRelease(), !Task.isCancelled else {
      delivery(Task.isCancelled ? "Cancelled while waiting for modifier release" : "Modifier keys stayed down; copied for recovery")
      return Task.isCancelled ? .cancelled : clipboard.copy(text, ifUnchanged: initialChange)
    }
    guard let snapshot = clipboard.snapshot() else {
      delivery("Clipboard snapshot was unavailable or changed")
      return clipboard.copy(text, ifUnchanged: initialChange)
    }
    guard snapshot.change == initialChange, isValid(destination) else {
      delivery("Focus or clipboard changed before dispatch; copied for recovery")
      return clipboard.copy(text, ifUnchanged: initialChange)
    }
    let copied = clipboard.copy(text, ifUnchanged: snapshot.change)
    guard copied == .copied else { return copied }
    let pasteChange = clipboard.board.changeCount
    guard !Task.isCancelled else {
      clipboard.restore(snapshot, ifUnchanged: pasteChange)
      return .cancelled
    }
    guard isValid(destination) else { delivery("Destination changed after clipboard write; left recovery text"); return .copied } // Leave the recovery text available.
    let menuItem = pasteMenuItem(for: destination)
    // Menu discovery is read-only but may take time. Recheck both destination and
    // clipboard immediately before the one and only delivery operation.
    guard isValid(destination), clipboard.board.changeCount == pasteChange else {
      delivery(clipboard.board.changeCount == pasteChange ? "Paste destination changed before dispatch" : "Clipboard changed before dispatch")
      return clipboard.board.changeCount == pasteChange ? .copied : .clipboardChanged
    }
    let pasteBefore = destination.focusedPaste ? (attribute(destination.element, kAXValueAttribute) as? String ?? "") : nil
    func dispatch() -> Bool {
      if let menuItem {
        lastDeliveryRoute = "Native Paste command"
        return AXUIElementPerformAction(menuItem, kAXPressAction as CFString) == .success
      }
      lastDeliveryRoute = "Command-V event"
      let source = CGEventSource(stateID: .privateState)
      guard let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
      down.flags = .maskCommand
      up.flags = .maskCommand
      down.postToPid(destination.application.processIdentifier)
      up.postToPid(destination.application.processIdentifier)
      return true
    }
    var dispatched = dispatch()
    var confirmed = await confirm(expected, in: destination, pasteBefore: pasteBefore)
    var retried = false
    // A dropped paste (target busy or still restoring focus) leaves the field
    // exactly as it was. Allow late renders to land first, then retry once only
    // when the same field, focus, interaction epoch and clipboard are all intact.
    if !confirmed, !Task.isCancelled, clipboard.board.changeCount == pasteChange,
      (try? await Task.sleep(for: .milliseconds(300))) != nil {
      if confirms(expected, in: destination, pasteBefore: pasteBefore) {
        confirmed = true
      } else if clipboard.board.changeCount == pasteChange, isValid(destination),
        attribute(destination.element, kAXValueAttribute) as? String == (pasteBefore ?? destination.value) {
        retried = true
        dispatched = dispatch() || dispatched
        confirmed = await confirm(expected, in: destination, pasteBefore: pasteBefore)
      }
    }
    if Task.isCancelled {
      clipboard.restore(snapshot, ifUnchanged: pasteChange)
      return .cancelled
    }
    if confirmed {
      clipboard.restore(snapshot, ifUnchanged: pasteChange)
      delivery("Paste confirmed via \(lastDeliveryRoute)" + (retried ? " after one retry" : ""))
      return .inserted
    }
    // Retain the text for manual paste, without overwriting a newer user copy.
    guard clipboard.board.changeCount == pasteChange else { delivery("User clipboard action replaced recovery text"); return .clipboardChanged }
    delivery("Paste dispatched via \(lastDeliveryRoute)" + (retried ? " twice" : "") + ", but target did not confirm; recovery text retained")
    return TextDeliveryPolicy.afterDispatch(confirmed: false, dispatched: dispatched, recovery: .copied)
  }
  static func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
}


extension TextInsertion {
  static func validateFocusObservation() async throws {
    let notifications = NotificationCenter()
    let insertion = TextInsertion(pasteboard: NSPasteboard(name: .init("com.chup.focus-fixture." + UUID().uuidString)), notifications: notifications)
    let before = insertion.epoch
    await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        for _ in 0..<1000 {
          notifications.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        }
        continuation.resume()
      }
    }
    guard insertion.epoch == before + 1000 else {
      throw WorkspaceError.message("Focus notifications did not synchronously invalidate the insertion epoch.")
    }
    print("PASS: production app-focus observer handles 1,000 notifications from a native queue without actor assertions; destination invalidation is synchronous. Private notification center only.")
  }
}
