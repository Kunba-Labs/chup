import AppKit
import Carbon
import ChupCore
import Combine

@MainActor final class ShortcutRegistry: ObservableObject {
  @Published var bindings: [ShortcutBinding]
  @Published var registrationStatus =
    "Global shortcuts are off. Enable Input Monitoring to use them."
  @Published var rebinding: ShortcutAction?
  @Published var rebindingID: String?
  @Published private(set) var registrationFailures: [String: String] = [:]
  @Published var lastTest = "Press a shortcut to test it here."
  var dispatch: ((ShortcutSignal) -> Void)?
  var onUserInteraction: (() -> Void)?
  var monitorsGlobalInput: Bool {
    guard let tap else { return false }
    return CGEvent.tapIsEnabled(tap: tap) && CGPreflightListenEventAccess()
  }
  @Published private(set) var testing = false
  private var resolver: ShortcutResolver
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?
  private var timer: Timer?
  private var hotKeys: [UInt32: EventHotKeyRef] = [:]
  private var hotBindings: [UInt32: ShortcutBinding] = [:]
  private var handler: EventHandlerRef?
  private var tapDelivery: ShortcutCallbackDelivery?
  private var hotKeyDelivery: ShortcutCallbackDelivery?
  private var localMonitor: Any?
  private let defaults: UserDefaults?
  private var keys = Set<UInt16>()
  private var carbonKeys = Set<UInt16>()
  private var buttons = Set<Int>()
  private var modifiers: KeyModifiers = []
  private var lastInput = Date()
  private var requiresRelease = false
  private var capture = ShortcutCapture()
  private var enabled = false
  private var nextHotKeyID: UInt32 = 1
  init(defaults: UserDefaults? = .standard, initialBindings: [ShortcutBinding]? = nil) {
    self.defaults = defaults
    let saved = defaults?.data(forKey: "shortcutBindings").flatMap {
      try? JSONDecoder().decode([ShortcutBinding].self, from: $0)
    }
    var restored = initialBindings ?? saved ?? ShortcutBinding.standard
    var identities = Set<String>()
    for index in restored.indices {
      if !identities.insert(restored[index].id).inserted { restored[index].id = UUID().uuidString }
    }
    bindings = restored
    resolver = ShortcutResolver(bindings: restored)
    // Older saved bindings did not have IDs. Commit the decoded identities once.
    defaults?.set(try? JSONEncoder().encode(restored), forKey: "shortcutBindings")
  }
  private func registerChords() {
    guard enabled else {
      resolver.bindings = bindings
      return
    }
    hotKeys.values.forEach { UnregisterEventHotKey($0) }
    hotKeys = [:]
    hotBindings = [:]
    registrationFailures = [:]
    if handler == nil {
      let delivery = ShortcutCallbackDelivery { [weak self] input in
        guard case .hotKey(let id, let down) = input else { return }
        self?.receiveHotKey(id, down: down)
      }
      hotKeyDelivery = delivery
      var types = [
        EventTypeSpec(
          eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
        EventTypeSpec(
          eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
      ]
      let handlerStatus = InstallEventHandler(
        GetApplicationEventTarget(),
        { _, event, context in
          guard let event, let context else { return OSStatus(eventNotHandledErr) }
          var id = EventHotKeyID()
          guard
            GetEventParameter(
              event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
              nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr
          else { return OSStatus(eventNotHandledErr) }
          guard id.signature == 0x5657_5350 else { return OSStatus(eventNotHandledErr) }
          let delivery = Unmanaged<ShortcutCallbackDelivery>.fromOpaque(context).takeUnretainedValue()
          delivery.enqueue(.hotKey(id.id, down: GetEventKind(event) == UInt32(kEventHotKeyPressed)))
          return noErr
        }, types.count, &types, Unmanaged.passUnretained(delivery).toOpaque(), &handler)
      guard handlerStatus == noErr else {
        delivery.invalidate()
        hotKeyDelivery = nil
        registrationStatus =
          "macOS rejected the shortcut event handler (\(handlerStatus)). Retry registration."
        resolver.bindings = bindings.filter {
          $0.keyCode == nil || $0.modifiers.contains(.fn) || $0.modifiers.isEmpty
            || $0.mouseButton != nil
        }
        return
      }
    }
    guard rebinding == nil else { return }
    for binding in bindings {
      guard let key = binding.keyCode, !binding.modifiers.isEmpty,
        !binding.modifiers.contains(.fn), binding.mouseButton == nil
      else { continue }
      var flags: UInt32 = 0
      if binding.modifiers.contains(.control) { flags |= UInt32(controlKey) }
      if binding.modifiers.contains(.option) { flags |= UInt32(optionKey) }
      if binding.modifiers.contains(.command) { flags |= UInt32(cmdKey) }
      if binding.modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
      var ref: EventHotKeyRef?
      let id = nextHotKeyID
      nextHotKeyID &+= 1
      let status = RegisterEventHotKey(
        UInt32(key), flags, EventHotKeyID(signature: 0x5657_5350, id: id),
        GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref)
      if status == noErr, let ref {
        hotKeys[id] = ref
        hotBindings[id] = binding
      } else {
        registrationFailures[binding.id] = "macOS could not register \(binding.label) (\(status))."
      }
    }
    resolver.bindings = bindings.filter { registrationFailures[$0.id] == nil }
    registrationStatus =
      "\(hotKeys.count) chords registered with macOS. "
      + (registrationFailures.isEmpty
        ? "" : "\(registrationFailures.count) binding(s) could not register. ")
      + (tap == nil
        ? "Fn, modifier-only holds and mouse gestures need Input Monitoring."
        : "Fn, modifier-only and mouse monitoring active.")
  }
  private func receiveHotKey(_ id: UInt32, down: Bool) {
    guard rebinding == nil, let binding = hotBindings[id], let key = binding.keyCode else { return }
    if down {
      keys.insert(key)
      carbonKeys.insert(key)
      modifiers = binding.modifiers
    } else {
      keys.remove(key)
      carbonKeys.remove(key)
      if !CGPreflightListenEventAccess() { modifiers = [] }
    }
    process()
  }
  func enable(request: Bool = true) {
    enabled = true
    registerChords()
    if timer == nil {
      timer = MainActorTimer.repeating(every: 0.03) { [weak self] in self?.tick() }
    }
    if localMonitor == nil {
      localMonitor = NSEvent.addLocalMonitorForEvents(matching: [
        .keyDown, .keyUp, .flagsChanged, .otherMouseDown, .otherMouseUp,
      ]) {
        [weak self] event in
        if let self, self.tap == nil, let cg = event.cgEvent {
          self.receive(cg.type, cg)
        }
        return event
      }
    }
    if request && !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
    guard CGPreflightListenEventAccess() else {
      if tap != nil { stopMonitoring() }
      registerChords()
      return
    }
    if tap != nil { return }
    let events: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .otherMouseDown, .otherMouseUp,
      .leftMouseDown, .rightMouseDown, .scrollWheel]
    let mask = events.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
    let delivery = ShortcutCallbackDelivery { [weak self] input in
      guard case .event(let event) = input else { return }
      self?.receive(event)
    }
    tapDelivery = delivery
    tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
      eventsOfInterest: mask, callback: Self.eventTapCallback,
      userInfo: Unmanaged.passUnretained(delivery).toOpaque())
    guard let tap else {
      delivery.invalidate()
      tapDelivery = nil
      registrationStatus =
        "macOS rejected shortcut event registration. Recheck Input Monitoring permission."
      return
    }
    source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    registerChords()
  }

  nonisolated private static let eventTapCallback: CGEventTapCallBack = { _, type, event, pointer in
    if let pointer {
      let delivery = Unmanaged<ShortcutCallbackDelivery>.fromOpaque(pointer).takeUnretainedValue()
      delivery.enqueue(.event(ShortcutInput(type: type, event: event)))
    }
    return Unmanaged.passUnretained(event)
  }

  func replace(_ binding: ShortcutBinding) {
    var updated = bindings
    if let index = updated.firstIndex(where: { $0.id == binding.id }) {
      updated[index] = binding
    } else {
      updated.append(binding)
    }
    apply(updated)
  }
  func remove(_ id: String) { apply(bindings.filter { $0.id != id }) }
  func addControlShift() {
    replace(.init(.holdDictation, [.control, .shift], hold: true))
  }
  private func apply(_ updated: [ShortcutBinding]) {
    let issues = ShortcutBinding.conflicts(updated)
    guard issues.isEmpty else {
      registrationStatus = issues.joined(separator: " ")
      return
    }
    reset()
    bindings = updated
    persist()
  }
  func preset(_ alternative: Bool) {
    cancelRebind()
    apply(alternative ? ShortcutBinding.alternative : ShortcutBinding.standard)
  }
  func beginRebind(_ action: ShortcutAction, bindingID: String? = nil) {
    reset()
    rebinding = action
    rebindingID = bindingID
    resolver.suspended = true
    capture = ShortcutCapture()
    registerChords()
  }
  func cancelRebind() {
    rebinding = nil
    rebindingID = nil
    resolver.suspended = false
    capture = ShortcutCapture()
    reset()
    registerChords()
  }
  func setTesting(_ enabled: Bool) {
    guard enabled != testing else { return }
    reset()
    testing = enabled
  }
  private func persist() {
    defaults?.set(try? JSONEncoder().encode(bindings), forKey: "shortcutBindings")
    registerChords()
  }
  func reset() {
    onUserInteraction?() // Missing events invalidate any pending opaque input destination.
    requiresRelease = true
    for signal in resolver.reset() { if !testing { dispatch?(signal) } }
    keys = []
    carbonKeys = []
    buttons = []
    modifiers = []
  }
  private func receive(_ type: CGEventType, _ event: CGEvent) {
    receive(ShortcutInput(type: type, event: event))
  }
  private func receive(_ input: ShortcutInput) {
    let type = input.type
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      reset()
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      registrationStatus = "Shortcut stream restarted after interruption."
      return
    }
    if type == .leftMouseDown || type == .rightMouseDown || type == .scrollWheel {
      onUserInteraction?()
      return
    }
    lastInput = Date()
    let flags = input.flags
    modifiers = []
    if flags.contains(.maskControl) { modifiers.insert(.control) }
    if flags.contains(.maskAlternate) { modifiers.insert(.option) }
    if flags.contains(.maskShift) { modifiers.insert(.shift) }
    if flags.contains(.maskCommand) { modifiers.insert(.command) }
    if flags.contains(.maskSecondaryFn) { modifiers.insert(.fn) }
    let key = input.key
    if type == .keyDown && !bindings.contains(where: { $0.keyCode == key && $0.modifiers == modifiers && $0.mouseButton == nil }) {
      onUserInteraction?()
    }
    if type == .otherMouseDown && !bindings.contains(where: {
      $0.mouseButton == input.button && $0.modifiers == modifiers
    }) { onUserInteraction?() }
    if rebinding == nil {
      if type == .keyDown
        && hotBindings.values.contains(where: { $0.keyCode == key && $0.modifiers == modifiers })
      {
        return
      }
      if type == .keyUp && carbonKeys.contains(key) { return }
    }
    if type == .keyDown {
      if input.repeated { return }
      keys.insert(key)
    }
    if type == .keyUp { keys.remove(key) }
    let button = input.button
    if type == .otherMouseDown { buttons.insert(button) }
    if type == .otherMouseUp { buttons.remove(button) }
    if let action = rebinding {
      if type == .keyDown && key == 53 && action != .cancel {
        cancelRebind()
        return
      }
      let hold =
        bindings.first(where: { $0.id == rebindingID })?.hold
        ?? (action == .holdDictation || action == .editSelection)
      capture.update(action: action, modifiers: modifiers, keys: keys, buttons: buttons, hold: hold)
      if modifiers.isEmpty && keys.isEmpty && buttons.isEmpty {
        if capture.invalid {
          cancelRebind()
          registrationStatus =
            "Use modifiers alone, one key with modifiers, or one side mouse button."
        } else if var candidate = capture.candidate {
          if let id = rebindingID { candidate.id = id }
          cancelRebind()
          replace(candidate)
        }
      }
      return
    }
    if type == .keyDown
      && hotBindings.values.contains(where: { $0.keyCode == key && $0.modifiers == modifiers })
    {
      return
    }
    process()
  }
  private func tick() {
    guard rebinding == nil else { return }
    if tap != nil && !CGPreflightListenEventAccess() {
      stopMonitoring()
      registerChords()
    }
    if CGPreflightListenEventAccess() {
      // Reconcile missed key-up events using the current hardware state.
      for key in keys where !CGEventSource.keyState(.combinedSessionState, key: key) {
        keys.remove(key)
      }
      buttons = buttons.filter {
        CGEventSource.buttonState(
          .combinedSessionState, button: CGMouseButton(rawValue: UInt32($0))!)
      }
      let flags = CGEventSource.flagsState(.combinedSessionState)
      modifiers = []
      if flags.contains(.maskControl) { modifiers.insert(.control) }
      if flags.contains(.maskAlternate) { modifiers.insert(.option) }
      if flags.contains(.maskShift) { modifiers.insert(.shift) }
      if flags.contains(.maskCommand) { modifiers.insert(.command) }
      if flags.contains(.maskSecondaryFn) { modifiers.insert(.fn) }
    }
    process()
  }
  private func stopMonitoring() {
    tapDelivery?.invalidate()
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    if let tap { CFMachPortInvalidate(tap) }
    source = nil
    tap = nil
    tapDelivery = nil
    reset()
  }
  private func process() {
    if requiresRelease {
      if keys.isEmpty && buttons.isEmpty && modifiers.isEmpty { requiresRelease = false }
      return
    }
    for signal in resolver.update(
      modifiers: modifiers, keys: keys, buttons: buttons, time: ProcessInfo.processInfo.systemUptime
    ) {
      lastTest = "\(signal.action.title) — \(signal.began ? "pressed" : "released")"
      if !testing { dispatch?(signal) }
    }
  }
}

extension ShortcutRegistry {
  /// Runs the same C callback Quartz calls, without installing a tap or posting
  /// synthetic keystrokes into any application.
  static func validateCallbackDelivery() async throws {
    var received: [ShortcutCallbackInput] = []
    let delivery = ShortcutCallbackDelivery { received.append($0) }
    let created: Bool = await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else {
          continuation.resume(returning: false)
          return
        }
        for index in 0..<1000 {
          event.flags = index.isMultiple(of: 2) ? .maskShift : .maskControl
          event.setIntegerValueField(.keyboardEventKeycode, value: Int64(index % 128))
          _ = eventTapCallback(OpaquePointer(bitPattern: 1)!, .flagsChanged, event,
            Unmanaged.passUnretained(delivery).toOpaque())
          // Quartz owns/reuses its event after our callback returns.
          event.flags = []
          event.setIntegerValueField(.keyboardEventKeycode, value: 255)
        }
        delivery.enqueue(.hotKey(42, down: true))
        delivery.enqueue(.hotKey(42, down: false))
        DispatchQueue.main.async { continuation.resume(returning: true) }
      }
    }
    guard created, received.count == 1002 else {
      throw WorkspaceError.message("Native shortcut callback dropped queued input.")
    }
    for index in 0..<1000 {
      guard case .event(let input) = received[index], input.key == UInt16(index % 128),
        input.flags == (index.isMultiple(of: 2) ? .maskShift : .maskControl) else {
        throw WorkspaceError.message("Native shortcut callback snapshot mismatch at fixture index \(index): \(received[index]).")
      }
    }
    guard case .hotKey(42, down: true) = received[1000],
      case .hotKey(42, down: false) = received[1001] else {
      throw WorkspaceError.message("Queued Carbon press/release order changed.")
    }
    delivery.enqueue(.hotKey(99, down: true))
    delivery.invalidate()
    delivery.enqueue(.hotKey(99, down: false))
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
    guard received.count == 1002 else {
      throw WorkspaceError.message("Invalidated shortcut callback dispatched stale input.")
    }
    print("PASS: actual Quartz callback delivers 1,000 copied events in order on MainActor, preserves Carbon press/release order and drops invalidated work. No global hooks or input posted.")
  }

  /// Exercises the actual settings capture/persistence path with in-memory events.
  /// Never registers global hooks, posts input, or reads the user's preference domain.
  static func validateBindings() throws {
    let suite = "com.chup.shortcut-validation." + UUID().uuidString
    guard let preferences = UserDefaults(suiteName: suite) else {
      throw WorkspaceError.message("Could not create isolated shortcut preferences.")
    }
    defer { preferences.removePersistentDomain(forName: suite) }
    let original = ShortcutBinding(.holdDictation, .fn, hold: true)
    let registry = ShortcutRegistry(defaults: preferences, initialBindings: [original])
    var dispatchCount = 0
    registry.dispatch = { _ in dispatchCount += 1 }
    func flags(_ value: CGEventFlags) throws {
      guard let event = CGEvent(source: nil) else {
        throw WorkspaceError.message("Cannot create fixture event.")
      }
      event.flags = value
      registry.receive(.flagsChanged, event)
    }
    registry.beginRebind(.holdDictation)
    try flags(.maskControl)
    try flags([.maskControl, .maskShift])
    try flags(.maskShift)
    try flags([])
    guard registry.bindings.count == 2,
      let alternate = registry.bindings.first(where: { $0.id != original.id }),
      alternate.modifiers == [.control, .shift], alternate.modifierOnly, alternate.hold,
      registry.bindings.contains(original), dispatchCount == 0
    else {
      throw WorkspaceError.message(
        "Alternate binding capture replaced the original or lost a modifier.")
    }
    let reopened = ShortcutRegistry(defaults: preferences)
    guard reopened.bindings == registry.bindings else {
      throw WorkspaceError.message("Binding IDs did not persist.")
    }
    registry.beginRebind(.holdDictation, bindingID: alternate.id)
    try flags(.maskControl)
    try flags([.maskControl, .maskAlternate])
    try flags(.maskControl)
    try flags([])
    guard registry.bindings.count == 2,
      registry.bindings.first(where: { $0.id == alternate.id })?.modifiers == [.control, .option]
    else {
      throw WorkspaceError.message("Editing a binding did not retain its identity.")
    }
    registry.replace(.init(.meeting, .fn))
    guard registry.bindings.count == 2 else {
      throw WorkspaceError.message("Duplicate gesture was accepted.")
    }
    registry.remove(alternate.id)
    guard registry.bindings == [original],
      ShortcutRegistry(defaults: preferences).bindings == [original], dispatchCount == 0
    else {
      throw WorkspaceError.message(
        "Removing an alternate affected its sibling or dispatched an action.")
    }
    print(
      "PASS: native shortcut capture keeps Control–Shift through release, preserves Fn, persists IDs, edits/removes one binding and rejects duplicates. No global hooks or input posted."
    )
    let watcher = ShortcutRegistry(defaults: nil, initialBindings: [.init(.toggleDictation, .fn, keyCode: 49)])
    watcher.setTesting(true)
    var interactions = 0
    watcher.onUserInteraction = { interactions += 1 }
    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true) else { throw WorkspaceError.message("Cannot create interaction fixture.") }
    event.flags = .maskSecondaryFn
    event.setIntegerValueField(.keyboardEventKeycode, value: 49)
    watcher.receive(.keyDown, event)
    watcher.receive(.flagsChanged, event)
    guard interactions == 0 else { throw WorkspaceError.message("Dictation shortcut invalidated its own opaque input destination.") }
    event.flags = []
    event.setIntegerValueField(.keyboardEventKeycode, value: 0)
    watcher.receive(.keyDown, event)
    watcher.receive(.leftMouseDown, event)
    watcher.receive(.scrollWheel, event)
    watcher.reset()
    guard interactions == 4 else { throw WorkspaceError.message("Input interaction fencing missed typing, clicking, scrolling or event reset.") }
    print("PASS: opaque input fencing ignores its shortcut and detects typing, clicking, scrolling and interrupted event streams. Synthetic events only.")
  }
}
