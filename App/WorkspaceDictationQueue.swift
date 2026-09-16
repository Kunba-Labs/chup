import Foundation
import ChupCore

@MainActor final class QueuedDictationTarget {
  var destination: TextInsertion.Destination?
  init(_ destination: TextInsertion.Destination?) { self.destination = destination }
}

extension WorkspaceState {
  /// Durable audio is committed before entering this queue. Each job owns its
  /// metadata and target; starting capture never invalidates older saved jobs.
  func enqueueDictation(_ entry: DictationEntry, captured: TextInsertion.Destination?,
    traceID: String?, insertResult: Bool = true, trigger: String = "Hold-to-dictate",
    process: ((DictationEntry, String?) async throws -> DictationEntry)? = nil,
    deliver: ((String, TextInsertion.Destination?) async -> TextDeliveryResult)? = nil) {
    guard queuedDictationTargets[entry.id] == nil else { return }
    let target = QueuedDictationTarget(captured)
    queuedDictationTargets[entry.id] = target
    dictationQueue.enqueue(id: entry.id) { [self] in
      defer { queuedDictationTargets[entry.id] = nil }
      do {
        try Task.checkCancellation()
        var result: DictationEntry
        if let process { result = try await process(entry, traceID) }
        else { result = try await processDictation(entry, traceID: traceID) }
        try Task.checkCancellation()
        dictationLiveText = result.text
        if dictationReviewActive, dictationReviewText == dictationReviewSeed {
          dictationReviewText = result.text
          dictationReviewSeed = result.text
        }
        if dictationReviewAppendRequested {
          dictationReviewAppendRequested = false
          appendDictationReview(result.text)
          finishTrace(traceID, .saved)
          return
        }
        if dictationReviewRequested {
          dictationReviewRequested = false
          if dictationReviewActive {
            // The editor may have opened while capture was still listening.
            // Replace its seed with the final transcript only when the user
            // has not edited the provisional text yet.
            if dictationReviewText == dictationReviewSeed {
              dictationReviewText = result.text
            }
            dictationReviewSeed = result.text
          } else {
            presentDictationReview(entryID: entry.id, text: result.text)
          }
          while dictationReviewActive {
            try await Task.sleep(for: .milliseconds(40))
          }
          guard dictationReviewApproved else {
            finishTrace(traceID, .cancelled)
            return
          }
          result.text = dictationReviewText
          result.original = dictationReviewText
          dictationReviewEntryID = nil
          dictationReviewApproved = false
        }
        // Do not paste while the user is holding the next capture shortcut.
        // Its waveform remains in front; the saved result waits in FIFO order.
        while dictationStatus == .listening {
          try await Task.sleep(for: .milliseconds(40))
        }
        try Task.checkCancellation()
        guard insertResult else {
          finishTrace(traceID, .saved)
          notice = "Retry saved to history. Copy into the intended field."
          return
        }
        markTrace(traceID, .insertionStarted)
        let original = target.destination
        let delivery: TextDeliveryResult
        if let application = original?.application {
          application.activate(options: [.activateIgnoringOtherApps])
          // Activation is asynchronous when the editor panel was key. Give
          // the target app time to restore its focused field before dispatch.
          try await Task.sleep(for: .milliseconds(180))
        }
        if let deliver { delivery = await deliver(result.text, original) }
        else { delivery = await insertion.insert(result.text, into: original) }
        let outcome: DictationTrace.Outcome
        switch delivery {
        case .inserted: outcome = .inserted
        case .copied: outcome = .copied
        case .sentToApplication, .unconfirmedCopied: outcome = .unconfirmed
        case .clipboardChanged: outcome = .clipboardChanged
        case .copyFailed: outcome = .copyFailed
        case .cancelled: outcome = .cancelled
        }
        finishTrace(traceID, outcome)
        recordDelivery(delivery, trigger: trigger)
        try Task.checkCancellation()
        if delivery == .inserted, let original {
          for other in queuedDictationTargets.values {
            if let candidate = other.destination,
              let advanced = insertion.advance(candidate, after: result.text, insertedInto: original) {
              other.destination = advanced
            }
          }
          if dictationStatus == .listening, let candidate = destination,
            let advanced = insertion.advance(candidate, after: result.text, insertedInto: original) {
            destination = advanced
          }
        }
        // A late result must never cover a newer live waveform or reset capture.
        if dictationStatus != .listening, pendingDictations == 1 {
          showDictationFeedback(delivery)
          // The queue owns processing state. Clear it as soon as delivery has
          // completed, including safe clipboard recovery, so the spinner cannot
          // outlive the actual work.
          dictationStatus = .idle
        }
      } catch {
        finishTrace(traceID, Task.isCancelled ? .cancelled : .failed)
        if !Task.isCancelled, dictationStatus != .listening, pendingDictations == 1 {
          dictationStatus = .error
          if error is DictationSignalError { showMicrophoneMessage(error.localizedDescription) }
          else { notice = "Dictation preserved for recovery. " + error.localizedDescription }
        }
      }
    }
  }
}
