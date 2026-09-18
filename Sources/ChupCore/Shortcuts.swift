import Foundation

public enum ShortcutAction: String, Codable, CaseIterable, Identifiable {
  case holdDictation, toggleDictation, editSelection, pasteLast, meeting, assistant, cancel, focusRail
  public var id: String { rawValue }
  public var title: String {
    switch self {
    case .holdDictation: return "Hold to dictate"
    case .toggleDictation: return "Hands-free dictation"
    case .editSelection: return "Edit selected text"
    case .pasteLast: return "Paste last dictation"
    case .meeting: return "Start or reveal meeting"
    case .assistant: return "Address assistant"
    case .cancel: return "Cancel voice action"
    case .focusRail: return "Focus floating controls"
    }
  }
}
public struct KeyModifiers: OptionSet, Codable, Hashable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let control = KeyModifiers(rawValue: 1), option = KeyModifiers(rawValue: 2),
    shift = KeyModifiers(rawValue: 4), command = KeyModifiers(rawValue: 8),
    fn = KeyModifiers(rawValue: 16)
  public var label: String {
    (contains(.fn) ? "fn " : "") + (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "")
      + (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
  }
}
public struct ShortcutBinding: Codable, Equatable, Identifiable {
  public var action: ShortcutAction
  public var modifiers: KeyModifiers
  public var keyCode: UInt16?
  public var mouseButton: Int?
  public var hold: Bool
  public var id: String
  public init(
    _ action: ShortcutAction, _ modifiers: KeyModifiers, keyCode: UInt16? = nil,
    mouseButton: Int? = nil, hold: Bool = false, id: String = UUID().uuidString
  ) {
    self.id = id
    self.action = action
    self.modifiers = modifiers
    self.keyCode = keyCode
    self.mouseButton = mouseButton
    self.hold = hold
  }
  private enum CodingKeys: String, CodingKey {
    case id, action, modifiers, keyCode, mouseButton, hold
  }
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
    action = try values.decode(ShortcutAction.self, forKey: .action)
    modifiers = try values.decode(KeyModifiers.self, forKey: .modifiers)
    keyCode = try values.decodeIfPresent(UInt16.self, forKey: .keyCode)
    mouseButton = try values.decodeIfPresent(Int.self, forKey: .mouseButton)
    hold = try values.decode(Bool.self, forKey: .hold)
  }
  public var modifierOnly: Bool { keyCode == nil && mouseButton == nil }
  public var specificity: Int {
    modifiers.rawValue.nonzeroBitCount + (keyCode == nil ? 0 : 100) + (mouseButton == nil ? 0 : 100)
  }
  public var label: String {
    modifiers.label + (keyCode.map { Self.keyNames[$0] ?? "Key \($0)" } ?? "")
      + (mouseButton.map { "Mouse \($0 + 1)" } ?? "")
  }
  public static let keyNames: [UInt16: String] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
    12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P",
    37: "L", 38: "J", 40: "K", 45: "N", 46: "M", 49: "Space", 53: "Esc", 36: "Return", 48: "Tab",
  ]
  public static let standard: [ShortcutBinding] = [
    .init(.holdDictation, .fn, hold: true), .init(.toggleDictation, .fn, keyCode: 49),
    .init(.editSelection, [.fn, .control], hold: true),
    .init(.pasteLast, [.control, .command], keyCode: 9),
    .init(.meeting, .option, keyCode: 46), .init(.assistant, [.control, .option], keyCode: 0),
    .init(.cancel, [], keyCode: 53), .init(.focusRail, [.control, .option], keyCode: 15),
  ]
  public static let alternative: [ShortcutBinding] = [
    .init(.holdDictation, [.control, .option], keyCode: 49, hold: true),
    .init(.toggleDictation, [.control, .option, .command], keyCode: 49),
    .init(.editSelection, [.control, .option], keyCode: 14, hold: true),
    .init(.pasteLast, [.control, .command], keyCode: 9),
    .init(.meeting, .option, keyCode: 46), .init(.assistant, [.control, .option], keyCode: 0),
    .init(.cancel, [], keyCode: 53), .init(.focusRail, [.control, .option], keyCode: 15),
  ]
  public static func conflicts(_ bindings: [ShortcutBinding]) -> [String] {
    var issues = [String]()
    for (i, a) in bindings.enumerated() {
      if a.modifiers.isEmpty && a.mouseButton == nil && a.keyCode != 53 {
        issues.append("\(a.action.title) needs a modifier.")
      }
      for b in bindings.dropFirst(i + 1)
      where a.modifiers == b.modifiers && a.keyCode == b.keyCode && a.mouseButton == b.mouseButton {
        issues.append(
          a.action == b.action
            ? "\(a.label) is already assigned to \(a.action.title)."
            : "\(a.label) is assigned to both \(a.action.title) and \(b.action.title).")
      }
      if a.modifiers == .command && [49, 48, 12].contains(a.keyCode ?? 999) {
        issues.append("\(a.label) is a known macOS shortcut.")
      }
    }
    return issues
  }
}
public struct ShortcutSignal: Equatable {
  public var action: ShortcutAction
  public var began: Bool
  public var cancelled: Bool
  public init(action: ShortcutAction, began: Bool, cancelled: Bool = false) {
    self.action = action
    self.began = began
    self.cancelled = cancelled
  }
}
/// Retain the complete gesture while its keys are released one at a time.
public struct ShortcutCapture {
  public private(set) var candidate: ShortcutBinding?
  public private(set) var invalid = false
  public init() {}
  public mutating func update(
    action: ShortcutAction, modifiers: KeyModifiers, keys: Set<UInt16>, buttons: Set<Int>,
    hold: Bool
  ) {
    if keys.count > 1 || buttons.count > 1 || (!keys.isEmpty && !buttons.isEmpty) { invalid = true }
    guard !modifiers.isEmpty || !keys.isEmpty || !buttons.isEmpty else { return }
    let next = ShortcutBinding(
      action, modifiers, keyCode: keys.sorted().first, mouseButton: buttons.sorted().first,
      hold: hold)
    if candidate == nil || next.specificity > candidate!.specificity { candidate = next }
  }
}

/// Bindings have independent identities; alternate gestures share one action lifecycle.
public struct ShortcutResolver {
  public var bindings: [ShortcutBinding]
  public var suspended = false
  private var active: ShortcutBinding?
  private var pending: (ShortcutBinding, Double)?
  private var latched: Set<String> = []
  private var suppressed: Set<String> = []
  public init(bindings: [ShortcutBinding] = ShortcutBinding.standard) { self.bindings = bindings }
  public mutating func reset() -> [ShortcutSignal] {
    defer {
      active = nil
      pending = nil
      latched = []
      suppressed = []
    }
    return active.map { [ShortcutSignal(action: $0.action, began: false, cancelled: true)] } ?? []
  }
  public mutating func update(
    modifiers: KeyModifiers, keys: Set<UInt16>, buttons: Set<Int> = [], time: Double
  ) -> [ShortcutSignal] {
    if suspended { return reset() }
    func held(_ b: ShortcutBinding) -> Bool {
      modifiers.isSuperset(of: b.modifiers) && (b.keyCode.map(keys.contains) ?? true)
        && (b.mouseButton.map(buttons.contains) ?? true)
    }
    func matches(_ b: ShortcutBinding) -> Bool {
      b.modifiers == modifiers && keys == (b.keyCode.map { [$0] } ?? [])
        && buttons == (b.mouseButton.map { [$0] } ?? [])
    }
    func prefix(_ shorter: ShortcutBinding, _ longer: ShortcutBinding) -> Bool {
      shorter.id != longer.id && longer.specificity > shorter.specificity
        && longer.modifiers.isSuperset(of: shorter.modifiers)
        && (shorter.keyCode == nil || shorter.keyCode == longer.keyCode)
        && (shorter.mouseButton == nil || shorter.mouseButton == longer.mouseButton)
    }
    let heldIDs = Set(bindings.filter(held).map(\.id))
    latched.formIntersection(heldIDs)
    // Suppression lasts until everything is released, not merely until the
    // suppressed gesture stops being held: macOS stamps the Fn flag onto arrow
    // and page keys, and it can arrive on the key-up or in the session's flag
    // state, after the key that should have fenced the gesture off is gone.
    if modifiers.isEmpty, keys.isEmpty, buttons.isEmpty { suppressed = [] }
    // Any key press fences off the modifier-only holds. Its modifiers cannot be
    // trusted to have arrived yet, so this does not ask which ones are down.
    if !keys.isEmpty || !buttons.isEmpty {
      for binding in bindings where binding.modifierOnly && binding.hold {
        suppressed.insert(binding.id)
      }
    }
    let match = bindings.filter { matches($0) && !suppressed.contains($0.id) }
      .sorted { $0.specificity > $1.specificity }.first
    var result: [ShortcutSignal] = []
    if let current = active {
      if let match, match.hold, match.action == current.action {
        // Pressing an alternate or handing over between keyboards must not stop/restart capture.
        active = match
        pending = nil
        return []
      }
      let promoted = match.map { prefix(current, $0) } ?? false
      if promoted || !held(current) {
        result.append(.init(action: current.action, began: false, cancelled: promoted))
        if promoted { suppressed.insert(current.id) }
        active = nil
      } else {
        return []
      }
    }
    guard let match else {
      pending = nil
      return result
    }
    if latched.contains(match.id) { return result }
    if bindings.contains(where: { $0.action == match.action && latched.contains($0.id) }) {
      latched.insert(match.id)
      return result
    }
    for shorter in bindings where prefix(shorter, match) {
      // A same-action hold may hand back to its shorter alias without a new recording.
      if !(shorter.action == match.action && shorter.hold && match.hold) {
        suppressed.insert(shorter.id)
      }
    }
    if match.hold || match.modifierOnly {
      if pending?.0.id != match.id { pending = (match, time) }
      guard time - (pending?.1 ?? time) >= 0.18 else { return result }
    }
    pending = nil
    if match.hold { active = match } else { latched.insert(match.id) }
    result.append(.init(action: match.action, began: true))
    return result
  }
}
