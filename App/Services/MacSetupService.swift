import AVFoundation
import AppKit
import ServiceManagement
import ChupCore

@MainActor final class MacSetupService: ObservableObject {
  @Published var permissions: [WorkspacePermission: PermissionState] = [:]
  @Published var loginStatus = SMAppService.Status.notRegistered
  @Published var message: String?
  @Published var requesting: WorkspacePermission?
  @Published var lastAudioCapture: Date?
  private var observer: NSObjectProtocol?
  var onRefresh: (() -> Void)?
  init() {
    refresh()
    observer = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }
  deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
  func refresh() {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: permissions[.microphone] = .allowed
    case .notDetermined: permissions[.microphone] = .notRequested
    case .restricted: permissions[.microphone] = .restricted
    default: permissions[.microphone] = .denied
    }
    permissions[.accessibility] = TextInsertion.trusted ? .allowed : .denied
    permissions[.inputMonitoring] = CGPreflightListenEventAccess() ? .allowed : .denied
    permissions[.screenCapture] = CGPreflightScreenCaptureAccess() ? .allowed : .denied
    permissions[.systemAudio] = .verifyDuringCapture
    loginStatus = SMAppService.mainApp.status
    onRefresh?()
  }
  func request(_ permission: WorkspacePermission) {
    guard requesting == nil else { return }
    requesting = permission
    message = nil
    Task {
      switch permission {
      case .microphone:
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
          _ = await AVCaptureDevice.requestAccess(for: .audio)
        } else {
          openPrivacy(permission)
        }
      case .accessibility: TextInsertion.requestPermission()
      case .inputMonitoring: _ = CGRequestListenEventAccess()
      case .screenCapture:
        _ = CGRequestScreenCaptureAccess()
        message =
          "If macOS asks you to quit and reopen Chup!, finish your recording first. Access is checked again when you return."
      case .systemAudio:
        openPrivacy(permission)
        message =
          "macOS requests audio-only access when you first record a selected meeting app. There is no separate public permission check for this route. Choose ScreenCaptureKit only if you need its fallback."
      }
      requesting = nil
      refresh()
    }
  }
  func openPrivacy(_ permission: WorkspacePermission) {
    // Pane anchors are best-effort OS links, not a supported TCC grant API.
    let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?" + permission.pane)!
    if !NSWorkspace.shared.open(url) {
      NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
    message =
      permission.breadcrumb
      + ". Enable Chup! if it appears in the list. Only you can grant access in macOS."
    if permission == .systemAudio || permission == .screenCapture {
      message = permission.breadcrumb
        + ". If Chup! is missing, use + below the recording list to add Applications → Chup!. Audio-only access can appear in its own section."
    }
  }
  var loginDescription: String {
    switch loginStatus {
    case .enabled: return "Chup! will open when you log in. It never begins recording on startup."
    case .requiresApproval:
      return "Waiting for approval in System Settings → General → Login Items & Extensions."
    case .notFound:
      return
        "macOS could not find this app service. Run a signed copy from Applications and try again."
    default: return "Open Chup! yourself, or enable it here to launch when you log in."
    }
  }
  func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      refresh()
    } catch {
      message = "Could not change launch at login: " + error.localizedDescription
      refresh()
    }
  }
  func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}
