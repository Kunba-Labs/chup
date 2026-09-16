import Foundation
import ChupCore

actor LiveValidationEvents {
  var values: [LiveEvent] = []
  func append(_ event: LiveEvent) { values.append(event) }
  func contains(_ predicate: (LiveEvent) -> Bool) -> Bool { values.contains(where: predicate) }
}
enum LiveValidation {
  static func run(port: String) async throws {
    guard let number = Int(port), (1...65535).contains(number) else {
      throw WorkspaceError.message("Invalid fixture port.")
    }
    let events = LiveValidationEvents()
    let session = LiveSession(onEvent: { event in await events.append(event) })
    try await session.connect(
      backend: URL(string: "http://127.0.0.1:\(number)")!, token: "native-fixture-only",
      mode: .privateVoice, policy: RoutingPolicy(meetingActive: false))
    func wait(_ predicate: @escaping (LiveEvent) -> Bool) async throws {
      for _ in 0..<200 {
        if await events.contains(predicate) { return }
        try await Task.sleep(for: .milliseconds(10))
      }
      throw WorkspaceError.message("Native Live protocol fixture timed out.")
    }
    try await wait {
      if case .started = $0 { return true }
      return false
    }
    try await session.muteInput(false)
    try await session.appendPCM24k(Data(repeating: 1, count: 960))
    try await wait { $0 == .delegation("fixture-delegation") }
    try await session.muteInput(true)
    try await session.returnDelegation(
      id: "fixture-delegation", committedResult: "The scoped result is ready.")
    try await wait {
      if case .outputAudio = $0 { return true }
      return false
    }
    await session.close()
    try await wait {
      if case .closed = $0 { return true }
      return false
    }
    await session.disconnect()
    try await validateAddressBoundary(port: number)
    print(
      "PASS: native URLSession Live WebSocket startup, PCM, correlated mute/unmute acknowledgment, delegation/commentary, output audio, and graceful close against a localhost fixture. No provider reached."
    )
  }
  @MainActor private static func validateAddressBoundary(port: Int) async throws {
    let conversation = LiveConversation()
    let scope = VoiceTurnScope(meetingID: "fixture", mode: .privateVoice)
    var question: String?
    conversation.onDelegation = { _, text, context in
      if context == scope.id { question = text }
    }
    try await conversation.connect(
      backend: URL(string: "http://127.0.0.1:\(port)")!, token: "native-fixture-only", scope: scope,
      policy: RoutingPolicy(meetingActive: false))
    for _ in 0..<200 {
      if conversation.ready { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    try await conversation.mute(false)
    try await conversation.appendAddressedPCM24k(Data(repeating: 1, count: 960))
    for _ in 0..<200 {
      if !conversation.inputTranscript.isEmpty { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    guard question == nil else {
      throw WorkspaceError.message("Delegated before the addressed question ended.")
    }
    conversation.finishInput()
    for _ in 0..<200 {
      if question != nil { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    guard question == "What did we decide?" else {
      throw WorkspaceError.message("Early delegation metadata lost the addressed question.")
    }
    conversation.interrupt(notify: false)
    print(
      "PASS: actual LiveConversation defers early delegation metadata until transcript and acknowledged end of addressed input."
    )
  }

}
