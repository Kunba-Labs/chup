import Foundation

public enum WorkspacePermission: String, CaseIterable, Identifiable {
  case microphone, accessibility, inputMonitoring, systemAudio, screenCapture
  public var id: String { rawValue }
  public var title: String {
    switch self {
    case .microphone: return "Microphone"
    case .accessibility: return "Text insertion"
    case .inputMonitoring: return "Global voice shortcuts"
    case .systemAudio: return "Meeting app audio"
    case .screenCapture: return "Screen & system audio fallback"
    }
  }
  public var purpose: String {
    switch self {
    case .microphone:
      return "Record your voice for dictation, meetings and addressed assistant questions."
    case .accessibility:
      return "Insert dictated text into your chosen field. Chup! never presses Send."
    case .inputMonitoring:
      return "Recognize Fn holds and mouse shortcuts while another app is focused."
    case .systemAudio:
      return
        "Capture remote participants from the meeting app you choose. Browsers may include other tabs."
    case .screenCapture:
      return
        "Enable the optional ScreenCaptureKit audio route. Chup! saves audio, not screen video, and does not share your screen with others."
    }
  }
  public var pane: String {
    switch self {
    case .microphone: return "Privacy_Microphone"
    case .accessibility: return "Privacy_Accessibility"
    case .inputMonitoring: return "Privacy_ListenEvent"
    case .systemAudio, .screenCapture: return "Privacy_ScreenCapture"
    }
  }
  public var breadcrumb: String {
    let section: String
    switch self {
    case .microphone: section = "Microphone"
    case .accessibility: section = "Accessibility"
    case .inputMonitoring: section = "Input Monitoring"
    case .systemAudio, .screenCapture: section = "Screen & System Audio Recording"
    }
    return "System Settings → Privacy & Security → " + section
  }
}
public enum PermissionState: String {
  case notRequested = "Not requested"
  case allowed = "Allowed"
  case denied = "Not enabled"
  case restricted = "Restricted by this Mac"
  case verifyDuringCapture = "Checked when capture starts"
}
public enum PermissionCheckResult: Equatable {
  case enabled, needsAccess, awaitingCapture, noSelection
  public static func evaluate(_ states: [PermissionState?]) -> Self {
    guard !states.isEmpty else { return .noSelection }
    if states.allSatisfy({ $0 == .allowed }) { return .enabled }
    if states.contains(where: { $0 != .allowed && $0 != .verifyDuringCapture }) {
      return .needsAccess
    }
    return .awaitingCapture
  }
}
public struct SetupChoices: Codable, Equatable {
  public var dictation = true
  public var meetings = true
  public var screenFallback = false
  public init() {}
  public var permissions: [WorkspacePermission] {
    var values: [WorkspacePermission] = []
    if dictation || meetings { values.append(.microphone) }
    if dictation { values += [.accessibility, .inputMonitoring] }
    if meetings { values.append(.systemAudio) }
    if meetings && screenFallback { values.append(.screenCapture) }
    return values
  }
}
