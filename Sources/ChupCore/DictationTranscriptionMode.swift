import Foundation

public enum DictationTranscriptionMode: String, Codable, CaseIterable {
  case automatic = "Cloud with local fallback"
  case local = "Local only"
  case cloud = "Cloud only"

  public func attemptsCloud(cloudEnabled: Bool, configured: Bool) -> Bool {
    self != .local && cloudEnabled && configured
  }
  public var allowsLocal: Bool { self != .cloud }
}
