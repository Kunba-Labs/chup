import Foundation
import ChupCore

extension WorkspaceState {
  var microphonePreviewBusy: Bool { microphonePreviewActive || microphonePreviewStarting }
  var canPreviewMicrophone: Bool {
    !isPreview && !storageBusy && privacyMaintenanceTask == nil && audio != nil && voiceScope == nil && meetingStatus != .recording
      && meetingStatus != .processing && dictationStatus != .listening && dictationStatus != .processing
  }

  func startMicrophonePreview() {
    guard canPreviewMicrophone, !microphonePreviewBusy, let audio else { return }
    let input: InputDevice
    do { input = try devices.resolve(microphoneUID) }
    catch { microphonePreviewMessage = error.localizedDescription; return }
    stopPlayback()
    stopDictationPlayback()
    let id = "microphone-preview:" + UUID().uuidString
    microphonePreviewID = id
    microphonePreviewStarting = true
    microphonePreviewMessage = "Opening \(input.name)…"
    microphonePreviewTask = Task {
      do {
        // Empty tracks make this a meter-only lease: no journal, folder or provider input.
        try await audio.addConsumer(id: id, directory: root.appendingPathComponent("MicrophonePreview"),
          tracks: [], device: input, meterOnly: true)
        guard !Task.isCancelled, microphonePreviewID == id else {
          try audio.removeConsumer(id: id)
          return
        }
        activeMicrophone = input
        micLevel = 0
        micLastPacket = nil
        micEnvelope.reset()
        micWaveform = micEnvelope.bars
        let now = ProcessInfo.processInfo.systemUptime
        microphoneSignal.start(at: now)
        microphonePreviewStartedAt = now
        microphonePreviewStarting = false
        microphonePreviewActive = true
        microphonePreviewMessage = "Listening · speak to test your microphone."
        // Revalidate after a permission prompt or device change during startup.
        microphoneEnvironmentChanged()
      } catch {
        try? audio.removeConsumer(id: id)
        guard microphonePreviewID == id else { return }
        stopMicrophonePreview(message: error.localizedDescription)
      }
    }
  }

  func stopMicrophonePreview(message: String? = nil) {
    guard let id = microphonePreviewID else { return }
    microphonePreviewID = nil
    microphonePreviewTask?.cancel()
    microphonePreviewTask = nil
    microphonePreviewActive = false
    microphonePreviewStarting = false
    microphonePreviewStartedAt = nil
    microphonePreviewMessage = message ?? "Test stopped. No audio was saved or sent."
    do { try audio?.removeConsumer(id: id) }
    catch { microphonePreviewMessage = error.localizedDescription }
    activeMicrophone = nil
    micLevel = 0
    micLastPacket = nil
    micEnvelope.reset()
    micWaveform = micEnvelope.bars
  }

  func checkMicrophonePreview() {
    guard microphonePreviewActive, let started = microphonePreviewStartedAt else { return }
    let now = ProcessInfo.processInfo.systemUptime
    guard now - started < 30 else {
      stopMicrophonePreview(message: "30-second test finished. No audio was saved or sent.")
      return
    }
    if let actual = audio?.actualMicrophoneID, let expected = activeMicrophone?.objectID, actual != expected {
      stopMicrophonePreview(message: "Microphone route changed. Choose an input and test again.")
      return
    }
    guard audio?.microphoneRunning == true else {
      stopMicrophonePreview(message: "Microphone test was interrupted. Try again or choose another input.")
      return
    }
    switch microphoneSignal.status(at: now) {
    case .starting: microphonePreviewMessage = "Listening · speak to test your microphone."
    case .receiving: microphonePreviewMessage = "Input detected · \(Self.time(now - started)) / 00:30"
    case .quiet: microphonePreviewMessage = "No input detected. Check mute or choose another microphone."
    case .missingPackets: stopMicrophonePreview(message: "Microphone stopped sending audio. Check its connection and test again.")
    }
  }
}
