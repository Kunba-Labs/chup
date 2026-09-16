import AppKit
import ChupCore

enum DictationSignalError: Error, LocalizedError {
  case unusable(String)
  var errorDescription: String? { if case .unusable(let reason) = self { return reason }; return nil }
}

extension WorkspaceState {
  func updateDictationErrorDismissal() {
    dictationErrorDismissalTask?.cancel()
    dictationErrorDismissalTask = nil
    guard dictationStatus == .error else { return }
    let generation = dictationGeneration
    dictationErrorDismissalTask = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
      guard let self, self.dictationGeneration == generation, self.dictationStatus == .error else { return }
      self.clearMicrophoneMessage()
      self.dictationStatus = .idle
    }
  }
  var microphoneLabel: String {
    if let uid = audio?.microphoneUID {
      return devices.inputs.first(where: { $0.id == uid })?.name ?? activeMicrophone?.name ?? "Microphone disconnected"
    }
    return (try? devices.selection(microphoneUID).name) ?? "Choose microphone"
  }
  func clearMicrophoneMessage() {
    microphoneMessageTask?.cancel(); microphoneMessageTask = nil
    dictationMicMessage = nil
  }
  func showMicrophoneMessage(_ message: String) {
    clearMicrophoneMessage()
    dictationMicMessage = message
    notice = message
    microphoneMessageTask = Task {
      do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
      dictationMicMessage = nil
    }
  }
  func stopForMicrophoneIssue(_ message: String) {
    if microphonePreviewActive || microphonePreviewStarting {
      stopMicrophonePreview(message: message)
      return
    }
    captureFailed(message)
    if microphoneUID.isEmpty { meetingMicrophone = nil }
    activeMicrophone = nil
    showMicrophoneMessage(message)
  }
  func microphoneEnvironmentChanged() {
    guard dictationStatus == .listening || meetingStatus == .recording || microphonePreviewActive else { return }
    guard let captured = activeMicrophone else { return }
    do {
      let selected = try devices.selection(microphoneUID.isEmpty ? "" : captured.id)
      guard selected.id == captured.id, selected.sampleRate == captured.sampleRate,
        selected.objectID == captured.objectID else {
        stopForMicrophoneIssue("Microphone changed. Audio saved; start again with \(selected.name).")
        return
      }
    } catch { stopForMicrophoneIssue(error.localizedDescription) }
  }
  func checkDictationMicrophone() {
    guard dictationStatus == .listening, dictationReady, let audio, !audio.microphoneStarting else { return }
    if let captured = activeMicrophone, let actual = audio.actualMicrophoneID, actual != captured.objectID {
      stopForMicrophoneIssue("The active microphone route changed. Audio saved; check Audio settings and start again.")
      return
    }
    if !audio.microphoneRunning {
      stopForMicrophoneIssue("Microphone capture was interrupted. Audio is saved; start again or check Audio settings.")
      return
    }
    switch microphoneSignal.status(at: ProcessInfo.processInfo.systemUptime) {
    case .missingPackets:
      stopForMicrophoneIssue("\(microphoneLabel) stopped sending audio. Check the connection and start again.")
    case .quiet:
      let warning = "No input detected from \(microphoneLabel). Check mute, connection or microphone selection."
      if dictationMicMessage != warning { dictationMicMessage = warning }
    case .receiving, .starting:
      if dictationMicMessage != nil { dictationMicMessage = nil }
    }
  }
  func openMicrophoneSettings() {
    if dictationStatus == .listening || meetingStatus == .recording || voiceScope != nil {
      captureFailed("Capture paused to choose another microphone. Audio is preserved.")
    }
    page = .settings
    microphoneSettingsRequested = true
    reveal?()
  }
}
