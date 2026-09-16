import AppKit
import ApplicationServices
import ChupCore

/// Opt-in desktop test against a new, isolated terminal running only a raw input
/// receiver. No user shell or existing terminal is targeted; no Return is posted.
@MainActor enum PasteIntegrationValidation {
  static func run(script: URL) async throws {
    guard TextInsertion.trusted, CGPreflightListenEventAccess() else {
      throw WorkspaceError.message("Paste fixture requires existing Accessibility and Input Monitoring access.")
    }
    let bundle = URL(fileURLWithPath: "/Applications/Ghostty.app")
    let existing = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("chup-paste-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let receipt = folder.appendingPathComponent("receipt.json")
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    configuration.arguments = ["-e", script.path]
    configuration.environment = ["CHUP_PASTE_RECEIPT": receipt.path]
    let app = try await NSWorkspace.shared.openApplication(at: bundle, configuration: configuration)
    guard !existing.contains(app.processIdentifier) else {
      throw WorkspaceError.message("Fixture did not create an isolated terminal process; no input posted.")
    }
    defer { app.forceTerminate() }
    var ready = false
    for _ in 0..<100 {
      if FileManager.default.fileExists(atPath: receipt.path), NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
        ready = true; break
      }
      try await Task.sleep(for: .milliseconds(100))
    }
    guard ready else { throw WorkspaceError.message("Isolated input receiver was not ready; no input posted.") }
    // Verify receiver ancestry against the newly launched process, including any
    // intermediary process used by the terminal. Never target an existing shell.
    let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: receipt)) as? [String: Any]
    let ps = Process(); ps.executableURL = URL(fileURLWithPath: "/bin/ps")
    ps.arguments = ["-axo", "pid=,ppid="]
    let pipe = Pipe(); ps.standardOutput = pipe
    try ps.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); ps.waitUntilExit()
    var parents: [Int32: Int32] = [:]
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
      let values = line.split(whereSeparator: \.isWhitespace).compactMap { Int32($0) }
      if values.count == 2 { parents[values[0]] = values[1] }
    }
    var pid = (metadata?["pid"] as? NSNumber)?.int32Value ?? 0
    var isolated = false
    for _ in 0..<16 {
      if pid == app.processIdentifier { isolated = true; break }
      guard let parent = parents[pid], parent > 1, parent != pid else { break }
      pid = parent
    }
    guard isolated else { throw WorkspaceError.message("Isolated receiver ancestry did not match; no input posted.") }
    let registry = ShortcutRegistry(defaults: nil, initialBindings: [])
    let insertion = TextInsertion()
    registry.onUserInteraction = { insertion.noteUserInteraction() }
    insertion.interactionMonitoringAvailable = { registry.monitorsGlobalInput }
    registry.enable(request: false)
    var captured: TextInsertion.Destination?
    var allowedReceiver = false
    for _ in 0..<50 {
      guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { break }
      if !allowedReceiver {
        allowedReceiver = allowExactReceiverPrompt(app: app, script: script)
      }
      if let candidate = insertion.capture(), candidate.application.processIdentifier == app.processIdentifier,
        candidate.value.replacingOccurrences(of: "\n", with: "").contains(folder.lastPathComponent) {
        try await Task.sleep(for: .milliseconds(100))
        if insertion.isValid(candidate) { captured = candidate; break }
      }
      try await Task.sleep(for: .milliseconds(100))
    }
    guard let destination = captured else {
      throw WorkspaceError.message("Isolated receiver's focused text control was not ready: " + insertion.lastDiagnostic + "; no input posted.")
    }
    print("Paste fixture: captured; focused paste=\(destination.focusedPaste), focus observer=\(destination.observingFocus), valid=\(insertion.isValid(destination))")
    let clipboard = ClipboardDelivery(board: .general)
    let snapshot = clipboard.snapshot()
    let marker = "Chup isolated paste " + UUID().uuidString
    let result = await insertion.insert(marker, into: destination)
    let change = clipboard.board.changeCount
    defer {
      if let snapshot, clipboard.board.string(forType: .string) == marker { clipboard.restore(snapshot, ifUnchanged: change) }
    }
    try await Task.sleep(for: .milliseconds(500))
    let delivered = try JSONSerialization.jsonObject(with: Data(contentsOf: receipt)) as? [String: Any]
    let received = delivered?["received"] as? String ?? ""
    print("Paste fixture: status=\(result.title), route=\(insertion.lastDeliveryRoute), receiver matched=\(received == marker), received bytes=\(received.utf8.count)")
    guard received == marker else { throw WorkspaceError.message("Real terminal paste did not reach isolated receiver exactly once.") }
    guard result == .inserted else { throw WorkspaceError.message("Real terminal paste arrived but confirmation failed.") }
    print("PASS: production insertion delivered exactly one synthetic line into an isolated terminal and confirmed it; no Return or shell execution.")
  }
  /// The desktop fixture explicitly launches this harmless receiver. Approve only
  /// the matching execute-script dialog in its newly created terminal process;
  /// never dismiss an unrelated permission prompt or alter a persistent setting.
  private static func allowExactReceiverPrompt(app: NSRunningApplication, script: URL) -> Bool {
    func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
      var value: CFTypeRef?
      return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    let application = AXUIElementCreateApplication(app.processIdentifier)
    guard let raw = attribute(application, kAXFocusedUIElementAttribute),
      CFGetTypeID(raw) == AXUIElementGetTypeID() else { return false }
    let dialog = unsafeBitCast(raw, to: AXUIElement.self)
    guard attribute(dialog, kAXSubroleAttribute) as? String == "AXDialog" else { return false }
    var exactPrompt = false
    var allow: AXUIElement?
    var budget = 50
    func walk(_ element: AXUIElement, depth: Int) {
      guard depth < 5, budget > 0 else { return }; budget -= 1
      let role = attribute(element, kAXRoleAttribute) as? String
      if role == kAXStaticTextRole {
        let text = attribute(element, kAXTitleAttribute) as? String ?? attribute(element, kAXValueAttribute) as? String ?? ""
        if text == "Allow Ghostty to execute \"" + script.path + "\"?" { exactPrompt = true }
      }
      if role == kAXButtonRole, attribute(element, kAXTitleAttribute) as? String == "Allow" { allow = element }
      for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] { walk(child, depth: depth + 1) }
    }
    walk(dialog, depth: 0)
    guard exactPrompt, let allow, NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return false }
    return AXUIElementPerformAction(allow, kAXPressAction as CFString) == .success
  }

}
