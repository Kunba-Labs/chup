import AVFoundation
import Combine
import CoreAudio
import ChupCore

@MainActor final class AssistantAudioRouter: ObservableObject {
  @Published var outputs: [OutputDevice] = []
  @Published var monitorUID = ""
  @Published var virtualUID = ""
  @Published private(set) var routeActive = false
  @Published private(set) var privateInput = false
  @Published private(set) var message =
    "Select headphones for voice. Meeting voice also requires Chup! Mic."
  @Published private(set) var level: Float = 0
  private var monitor: VoiceOutputEngine?
  private var outgoing: VoiceOutputEngine?
  private var routeContext = UUID()
  private var voiceContext = UUID()
  private var micAfter: Double = 0
  private var mode = AssistantMode.privateText
  private var checker: Timer?
  private var voiceChecker: Timer?
  private var voiceMeetingActive = false
  private var physical: InputDevice?
  private var callPID: pid_t = 0
  private let sink = VoiceRenderSink()
  var onViolation: ((String) -> Void)?
  var onRendered: ((UUID, Int) -> Void)?
  init() { refresh() }
  var virtualDevices: [OutputDevice] { outputs.filter { $0.id == "ChupMic2ch_UID" } }
  func refresh() {
    outputs = AssistantRouteDevices.outputs()
    if monitorUID.isEmpty { monitorUID = outputs.first(where: \.headphones)?.id ?? "" }
    if virtualUID.isEmpty { virtualUID = virtualDevices.first?.id ?? "" }
  }
  func selectedOutput() throws -> OutputDevice {
    refresh()
    guard let output = outputs.first(where: { $0.id == monitorUID }), output.headphones else {
      throw WorkspaceError.message(
        "Select an output macOS identifies as headphones. Speakers and unclassified outputs are not qualified for this prototype."
      )
    }
    return output
  }
  func enableRoute(microphone: InputDevice, pid: pid_t) throws {
    stopRoute()
    let output = try selectedOutput()
    guard
      let transport = AssistantRouteDevices.scalar(
        microphone.objectID, selector: kAudioDevicePropertyTransportType),
      transport != kAudioDeviceTransportTypeVirtual, transport != kAudioDeviceTransportTypeAggregate
    else {
      throw WorkspaceError.message(
        "The outgoing route needs a physical microphone, not another virtual or aggregate source.")
    }
    guard let virtual = virtualDevices.first(where: { $0.id == virtualUID }),
      virtual.id != microphone.id
    else {
      throw WorkspaceError.message(
        "Chup! Mic is not installed. Build and install the separate driver prototype before using a meeting voice route."
      )
    }
    physical = microphone
    callPID = pid
    routeContext = UUID()
    let sink = self.sink
    let engine = VoiceOutputEngine(outgoing: true) { [weak self] samples, count, time, context in
      sink.render(samples, count: count, time: time, context: context)
      let level = samples.prefix(count).reduce(Float(0)) { max($0, abs($1)) }
      Task { @MainActor in self?.rendered(context: context, count: count, level: level) }
    }
    engine.onFailure = { [weak self] message in Task { @MainActor in self?.violation(message) } }
    try engine.start(device: virtual.objectID, context: routeContext)
    engine.microphoneQueue.reset(context: routeContext, active: true)
    outgoing = engine
    routeActive = true
    privateInput = false
    micAfter = ProcessInfo.processInfo.systemUptime
    message =
      "Microphone feeds Chup! Mic. Select it as the call app’s input. Local assistant output: \(output.name)."
    checker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.check() }
    }
  }
  func policy(microphone: InputDevice, meetingActive: Bool, pid: pid_t) throws -> RoutingPolicy {
    let output = try selectedOutput()
    try validateOtherInputs(meetingActive: meetingActive, pid: pid)
    let virtual = routeActive ? virtualDevices.first(where: { $0.id == virtualUID }) : nil
    let evidence = AssistantRouteDevices.evidence(
      microphone: microphone, output: output, virtual: virtual, pid: pid)
    let policy = evidence.policy(meetingActive: meetingActive)
    guard !meetingActive || (routeActive && policy.verifiedMixMinus) else {
      throw WorkspaceError.message(
        "The call’s input is not verified as exclusively Chup! Mic. Private voice and broadcast remain unavailable; use private text."
      )
    }
    return policy
  }
  func beginVoice(context: UUID, mode: AssistantMode, owner: AudioOwner, meetingActive: Bool) throws
  {
    stopVoice()
    self.voiceContext = context
    self.mode = mode
    voiceMeetingActive = meetingActive
    if mode == .privateVoice {
      if meetingActive { muteCallInput() }
      let output = try selectedOutput()
      let player = VoiceOutputEngine { [weak self] samples, count, _, context in
        let level = samples.prefix(count).reduce(Float(0)) { max($0, abs($1)) }
        Task { @MainActor in self?.rendered(context: context, count: count, level: level) }
      }
      player.onFailure = { [weak self] message in Task { @MainActor in self?.violation(message) } }
      try player.start(device: output.objectID, context: context)
      monitor = player
    } else {
      guard routeActive, let outgoing else { throw WorkspaceError.unsafeRoute }
      guard resumeCallInput() else { throw WorkspaceError.unsafeRoute }
      outgoing.queue.reset(context: context, active: true)
      sink.bind(owner: owner, lease: owner.beginAssistantSource(), context: context)
      let output = try selectedOutput()
      let player = VoiceOutputEngine()
      player.onFailure = { [weak self] message in Task { @MainActor in self?.violation(message) } }
      try player.start(device: output.objectID, context: context)
      monitor = player
    }
    voiceChecker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        do {
          _ = try self.selectedOutput()
          try self.validateOtherInputs(meetingActive: self.voiceMeetingActive, pid: self.callPID)
        } catch { self.violation(error.localizedDescription) }
      }
    }
  }
  private func validateOtherInputs(meetingActive: Bool, pid: pid_t) throws {
    guard let readers = AssistantRouteDevices.foreignInputPIDs(),
      readers.allSatisfy({ meetingActive && $0 == pid })
    else {
      throw WorkspaceError.message(
        "Another application is using audio input, or its route could not be checked. Use private text until only the selected call reads Chup! Mic."
      )
    }
  }
  func appendVoice(_ data: Data, context: UUID) throws {
    guard voiceContext == context else { throw WorkspaceError.unsafeRoute }
    try monitor?.queue.append(data, context: context)
    if mode == .broadcast { try outgoing?.queue.append(data, context: context) }
  }
  func appendMicrophone(_ data: Data, hostTime: Double) throws {
    guard routeActive, !privateInput, hostTime >= micAfter else { return }
    try outgoing?.microphoneQueue.append(data, context: routeContext)
  }
  func muteCallInput() {
    privateInput = true
    outgoing?.microphoneQueue.reset(context: routeContext, active: false)
    message =
      "Call microphone muted by Chup! for private addressing. It stays muted on voice failure."
  }
  @discardableResult func resumeCallInput() -> Bool {
    guard routeActive, outgoing?.isRunning == true else {
      message = "Restart the outgoing route before resuming the call microphone."
      return false
    }
    privateInput = false
    micAfter = ProcessInfo.processInfo.systemUptime
    outgoing?.microphoneQueue.reset(context: routeContext, active: routeActive)
    message =
      routeActive ? "Call microphone resumed through Chup! Mic." : "Voice disconnected."
    return true
  }
  func renderedFrames(context: UUID) -> Int {
    (mode == .broadcast ? outgoing : monitor)?.queue.consumed(context: context) ?? 0
  }
  func stopVoice() {
    voiceChecker?.invalidate()
    voiceChecker = nil
    mode = .privateText
    voiceContext = UUID()
    level = 0
    monitor?.stop()
    monitor = nil
    outgoing?.queue.reset(context: UUID(), active: false)
    sink.bind(owner: nil, lease: nil, context: UUID())
  }
  func stopRoute() {
    stopVoice()
    checker?.invalidate()
    checker = nil
    outgoing?.stop()
    outgoing = nil
    routeActive = false
    privateInput = false
    message = "Outgoing route stopped. Select another input in the call app to speak there."
  }
  private func rendered(context: UUID, count: Int, level: Float) {
    guard context == voiceContext else { return }
    self.level = level
    onRendered?(context, count)
  }
  private func check() {
    let devices = AssistantRouteDevices.outputs()
    guard devices.contains(where: { $0.id == monitorUID && $0.headphones }),
      devices.contains(where: { $0.id == virtualUID })
    else {
      violation("A routed audio device disappeared. Voice stopped.")
      return
    }
    if mode != .privateText, let physical {
      let output = devices.first { $0.id == monitorUID }!
      let virtual = devices.first { $0.id == virtualUID }
      let evidence = AssistantRouteDevices.evidence(
        microphone: physical, output: output, virtual: virtual, pid: callPID)
      if !evidence.callUsesOnlyVirtualInput {
        violation(
          "The call input changed. Private voice/broadcast stopped; verify the call app’s microphone."
        )
      }
    }
  }
  private func violation(_ message: String) {
    checker?.invalidate()
    checker = nil
    muteCallInput()
    stopVoice()
    self.message = message
    onViolation?(message)
  }
}
