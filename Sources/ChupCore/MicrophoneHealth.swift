import Foundation

public struct MicrophoneCandidate {
  public let id: String
  public let builtIn: Bool
  public let physicalExternal: Bool
  public let available: Bool
  public init(id: String, builtIn: Bool, physicalExternal: Bool, available: Bool) {
    self.id = id; self.builtIn = builtIn; self.physicalExternal = physicalExternal; self.available = available
  }
}
public enum MicrophoneSelectionError: Error, LocalizedError {
  case closedLid, disconnected, ambiguous, unavailable
  public var errorDescription: String? {
    switch self {
    case .closedLid: return "MacBook lid closed. Choose an external microphone or open the lid."
    case .disconnected: return "Selected microphone disconnected. Reconnect it or choose another input."
    case .ambiguous: return "Choose an external microphone in Audio settings. More than one is available."
    case .unavailable: return "No usable microphone. Connect an input or open the MacBook lid."
    }
  }
}
public enum MicrophoneSelectionPolicy {
  public static func choose(_ inputs: [MicrophoneCandidate], preferred: String, systemDefault: String?, lidClosed: Bool?) throws -> String {
    if !preferred.isEmpty {
      guard let selected = inputs.first(where: { $0.id == preferred && $0.available }) else { throw MicrophoneSelectionError.disconnected }
      guard !(selected.builtIn && lidClosed == true) else { throw MicrophoneSelectionError.closedLid }
      return selected.id
    }
    if let selected = inputs.first(where: { $0.id == systemDefault && $0.available && !($0.builtIn && lidClosed == true) }) {
      return selected.id
    }
    let external = inputs.filter { $0.available && $0.physicalExternal }
    guard external.count <= 1 else { throw MicrophoneSelectionError.ambiguous }
    guard let selected = external.first else { throw MicrophoneSelectionError.unavailable }
    return selected.id
  }
}
public struct MicrophoneSignalHealth {
  public enum Status: Equatable { case starting, receiving, quiet, missingPackets }
  private var started: Double?
  private var packet: Double?
  private var signal: Double?
  public init() {}
  public mutating func start(at time: Double) { started = time; packet = nil; signal = nil }
  public mutating func receive(peak: Float, at time: Double) {
    guard started != nil, peak.isFinite, time.isFinite else { return }
    packet = time
    if peak > 0.0005 { signal = time }
  }
  public func status(at time: Double) -> Status {
    guard let started, time - started >= 3 else { return .starting }
    if time - (packet ?? started) > 2 { return .missingPackets }
    if time - (signal ?? started) >= 3 { return .quiet }
    return .receiving
  }
}
