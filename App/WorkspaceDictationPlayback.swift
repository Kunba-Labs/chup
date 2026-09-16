import Foundation
import ChupCore

extension WorkspaceState {
  var canPlayDictation: Bool {
    activeMeetingID == nil && dictationStatus != .listening && voiceScope == nil && !storageBusy
  }
  func configureDictationPlayback() {
    dictationPlayback.onChange = { [weak self] time, duration, playing, loading in
      guard let self else { return }
      self.dictationPlaybackTime = time
      self.dictationPlaybackDuration = duration
      self.dictationPlaying = playing
      self.dictationPlaybackLoading = loading
      if self.dictationAutoplay, !loading, duration > 0 {
        self.dictationAutoplay = false
        self.dictationPlayback.play(at: 0)
      }
    }
    dictationPlayback.onFailure = { [weak self] message in
      self?.dictationAutoplay = false
      self?.notice = message
    }
  }
  func playDictation(_ entry: DictationEntry) {
    guard canPlayDictation, let key else { return }
    if dictationPlaybackID == entry.id {
      if dictationPlaying { dictationPlayback.pause() }
      else if !dictationPlaybackLoading { dictationPlayback.play(at: dictationPlaybackTime) }
      return
    }
    stopDictationPlayback()
    stopPlayback()
    dictationPlaybackID = entry.id
    dictationAutoplay = true
    var leg = RecordingLeg(meetingID: entry.id, directory: entry.audioDirectory, offset: 0)
    leg.id = "dictation-" + entry.id
    dictationPlayback.prepare(legs: [leg], key: key)
  }
  func stopDictationPlayback() {
    dictationAutoplay = false
    dictationPlayback.reset()
    dictationPlaybackID = nil
  }
  func updateDictationIndicator() {
    guard !isPreview, !dictationIndicatorUpdatePending else { return }
    dictationIndicatorUpdatePending = true
    // Property observers can run inside a SwiftUI button/view update. Coalesce
    // state changes and perform native measurement outside that rendering pass.
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.dictationIndicatorUpdatePending = false
      self.refreshDictationIndicator()
    }
  }
  private func refreshDictationIndicator() {
    // The island already carries listening and transcribing, so the edge
    // indicator is left with what the island does not say: delivery results
    // and microphone problems.
    let live = !islandCoversRail && (dictationStatus == .listening || dictationStatus == .processing)
    if live || dictationFeedback != nil || dictationMicMessage != nil {
      if dictationIndicator == nil { dictationIndicator = DictationIndicatorController(state: self) }
      dictationIndicator?.show()
    } else { dictationIndicator?.hide() }
    rail?.refresh()
    dynamicIsland?.refresh()
  }
  func clearDictationFeedback() {
    dictationFeedbackTask?.cancel()
    dictationFeedbackTask = nil
    if let feedback = dictationFeedback, notice == feedback.message { notice = nil }
    dictationFeedback = nil
  }
  func showDictationFeedback(_ result: TextDeliveryResult) {
    clearDictationFeedback()
    // Keep dispatch verification in diagnostics, without a completion popup or
    // workspace banner. Returning to idle immediately collapses the controls.
    // Clipboard recovery remains available silently in the pasteboard and
    // diagnostics. Do not interrupt the user's flow with a copy-status toast.
    guard result != .sentToApplication,
      result != .copied,
      result != .unconfirmedCopied else { return }
    notice = result.message
    dictationFeedback = result
    dictationFeedbackTask = Task {
      do { try await Task.sleep(for: .seconds(1.5)) }
      catch { return }
      guard !Task.isCancelled else { return }
      dictationFeedback = nil
      if notice == result.message { notice = nil }
    }
  }
}
