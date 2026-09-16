import Foundation
import ChupCore

/// One addressed context; the application owns capture, playback, evidence and durable writes.
@MainActor final class LiveConversation: ObservableObject {
  @Published private(set) var status = "Disconnected"
  @Published private(set) var ready = false
  @Published private(set) var inputTranscript = ""
  @Published private(set) var outputTranscript = ""
  private var session: LiveSession?
  private var context = UUID()
  private var delegations = Set<String>()
  private var pendingDelegations = Set<String>()
  private var inputClosed = true
  var onReady: (() -> Void)?
  var onDelegation: ((String, String, UUID) -> Void)?
  var onAudio: ((String, Data, UUID) -> Void)?
  var onUsage: ((UUID, String, Bool) -> Void)?
  var onClosed: ((String?, String) -> Void)?
  func connect(backend: URL, token: String, scope: VoiceTurnScope, policy: RoutingPolicy)
    async throws
  {
    interrupt(notify: false)
    context = scope.id
    inputTranscript = ""
    outputTranscript = ""
    status = "Connecting"
    let transport = LiveSession(onUsage: { [weak self] raw, final in
      await self?.onUsage?(scope.id, raw, final)
    }) { [weak self] event in await self?.receive(event, context: scope.id)
    }
    session = transport
    do {
      try await transport.connect(backend: backend, token: token, mode: scope.mode, policy: policy)
    } catch {
      status = error.localizedDescription
      throw error
    }
  }
  func appendAddressedPCM24k(_ data: Data) async throws {
    guard ready, let session else { throw WorkspaceError.message("Voice is not ready.") }
    try await session.appendPCM24k(data)
  }
  func mute(_ value: Bool) async throws {
    guard let session else { throw WorkspaceError.unsafeRoute }
    let scope = context
    if !value { inputClosed = false }
    try await session.muteInput(value)
    guard context == scope else { return }
    inputClosed = value
    flushDelegations()
  }
  func finishInput() {
    guard let transport = session else { return }
    let scope = context
    Task {
      do {
        try await transport.muteInput(true)
        guard context == scope else { return }
        inputClosed = true
        flushDelegations()
      } catch {
        guard context == scope else { return }
        interrupt(notify: false)
        onClosed?(nil, "input control failed: " + error.localizedDescription)
      }
    }
  }
  private func flushDelegations() {
    guard ready, inputClosed,
      !inputTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }
    let pending = pendingDelegations
    pendingDelegations = []
    for id in pending { onDelegation?(id, inputTranscript, context) }
  }
  func returnDelegation(id: String, result: String, context: UUID) async throws {
    guard self.context == context, delegations.contains(id), let session, ready else {
      throw WorkspaceError.unsafeRoute
    }
    try await session.returnDelegation(id: id, committedResult: result)
  }
  func interrupt(notify: Bool = true) {
    let wasReady = session != nil
    context = UUID()
    ready = false
    delegations = []
    pendingDelegations = []
    inputClosed = true
    let old = session
    session = nil
    status = "Disconnected"
    Task { await old?.close() }
    if notify && wasReady { onClosed?(nil, "interrupted") }
  }
  private func receive(_ event: LiveEvent, context: UUID) {
    guard self.context == context else { return }
    switch event {
    case .started:
      ready = true
      status = "Ready · hold to address"
      onReady?()
    case .inputTranscript(let text):
      inputTranscript += text
      flushDelegations()
    case .outputTranscript(let text): outputTranscript += text
    case .outputAudio(let id, let data): if ready { onAudio?(id, data, context) }
    case .delegation(let id):
      if ready && delegations.insert(id).inserted {
        pendingDelegations.insert(id)
        flushDelegations()
      }
    case .closed(let usage):
      ready = false
      session = nil
      status = "Disconnected"
      onClosed?(usage, "closed")
    case .failure(let message):
      interrupt(notify: false)
      status = message
      onClosed?(nil, "failed: " + message)
    case .other: break
    }
  }
}
