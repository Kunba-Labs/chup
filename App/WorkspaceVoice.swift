import AVFoundation
import Foundation
import ChupCore

extension WorkspaceState {
  func configureVoice() {
    voice.onUsage = { [weak self] context, raw, final in
      guard let self, let meeting = self.voiceUsageScopes[context] else { return }
      self.recordProviderUsage(
        id: "voice/" + context.uuidString, category: "voice", model: "gpt-live-1", raw: raw,
        final: final, scope: meeting)
      if final { self.voiceUsageScopes[context] = nil }
    }
    voice.onReady = { [weak self] in
      if self?.addressWhenReady == true {
        self?.addressWhenReady = false
        self?.startAddressing()
      }
    }
    voice.onAudio = { [weak self] id, data, context in
      guard let self, self.voiceScope?.id == context, self.voicePlaybackAllowed else { return }
      do {
        guard try self.voiceOutput?.enqueue(id: id, pcm: data, context: context) == true else {
          return
        }
        try self.voiceRouter.appendVoice(data, context: context)
      } catch {
        self.endVoice()
        self.notice = error.localizedDescription
      }
    }
    voiceRouter.onRendered = { [weak self] context, frames in
      guard let self, self.voiceScope?.id == context, let queue = self.voiceOutput else { return }
      self.voiceOutput?.rendered(through: queue.renderedFrames + frames, context: context)
    }
    voiceRouter.onViolation = { [weak self] message in
      self?.endVoice()
      self?.notice = message
    }
    voice.onClosed = { [weak self] usage, status in
      guard let self else { return }
      if let id = self.voiceUsageID { self.finishUsage(id, status: status, providerUsage: usage) }
      self.voiceUsageID = nil
      self.endVoice()
    }
    voice.onDelegation = { [weak self] id, question, context in
      self?.delegateVoice(id: id, question: question, context: context)
    }
  }
  func enableAssistantRoute() {
    guard let audio, let id = activeMeetingID, meetingStatus == .recording else {
      notice = "Start a microphone/call recording first, then configure its outgoing route."
      return
    }
    do {
      let device = try devices.resolve(audio.microphoneUID ?? microphoneUID)
      try voiceRouter.enableRoute(microphone: device, pid: meetingPID)
      audio.setPrivateAddress(false)
      closePrivateVoiceGap()
      let converter = VoicePCMConverter()
      let pair = AsyncStream<AudioPacket>.makeStream(bufferingPolicy: .bufferingOldest(64))
      routeFeed?.cancel()
      routeContinuation?.finish()
      routeContinuation = pair.continuation
      audio.setPacketHandler(
        { track, packet in
          guard track == .microphone else { return }
          if case .dropped = pair.continuation.yield(packet) {
            Task { @MainActor in
              self.stopAssistantRoute()
              self.notice =
                "Outgoing microphone queue fell behind. Route stopped; local recording continues."
            }
          }
        }, id: "outgoing")
      routeFeed = Task {
        for await packet in pair.stream {
          guard !Task.isCancelled, activeMeetingID == id, voiceRouter.routeActive else { break }
          do {
            try voiceRouter.appendMicrophone(converter.convert(packet), hostTime: packet.hostTime)
          } catch {
            stopAssistantRoute()
            notice = error.localizedDescription
            break
          }
        }
      }
    } catch { notice = error.localizedDescription }
  }
  func stopAssistantRoute() {
    endVoice()
    routeFeed?.cancel()
    routeContinuation?.finish()
    audio?.setPacketHandler(nil, id: "outgoing")
    voiceRouter.stopRoute()
    audio?.setPrivateAddress(false)
    closePrivateVoiceGap()
  }
  func connectVoice(mode: AssistantMode) {
    transcriptionLab.cancel()
    stopMicrophonePreview()
    stopDictationPlayback()
    guard mode != .privateText, let meetingID = selectedMeetingID, let audio else { return }
    endVoice()
    do {
      let client = try backend()
      guard mode != .broadcast || (activeMeetingID == meetingID && meetingStatus == .recording)
      else {
        throw WorkspaceError.message(
          "Broadcast requires the active meeting and a running recorder.")
      }
      let device = try devices.resolve(audio.microphoneUID ?? microphoneUID)
      let policy = try voiceRouter.policy(
        microphone: device, meetingActive: activeMeetingID != nil, pid: meetingPID)
      guard policy.allows(mode) else { throw WorkspaceError.unsafeRoute }
      let scope = VoiceTurnScope(meetingID: meetingID, mode: mode)
      voiceScope = scope
      voiceUsageScopes[scope.id] = meetingID
      recordProviderUsage(
        id: "voice/" + scope.id.uuidString, category: "voice", model: "gpt-live-1", raw: "{}",
        final: false, scope: meetingID)
      voiceMode = mode
      voicePlaybackAllowed = false
      if mode == .privateVoice, let activeMeetingID {
        audio.setPrivateAddress(true)
        let gapID = privateVoiceGap?.1 ?? UUID().uuidString
        if privateVoiceGap == nil { privateVoiceGap = (activeMeetingID, gapID, elapsed) }
        try db().put(
          CaptureGap(
            start: privateVoiceGap?.2 ?? elapsed, end: nil, reason: "Private voice input omitted",
            track: .microphone), kind: "gap", id: gapID, parent: activeMeetingID)
      }
      try voiceRouter.beginVoice(
        context: scope.id, mode: mode, owner: audio, meetingActive: activeMeetingID != nil)
      if mode == .broadcast {
        audio.setPrivateAddress(false)
        closePrivateVoiceGap()
      }
      voiceOutput = try VoiceOutputQueue(
        context: scope.id, sessionID: scope.id.uuidString, mode: mode, policy: policy)
      voiceUsageID = startUsage(category: "voice.gpt-live-1", meetingID: meetingID)
      voiceSessionTask = Task {
        do {
          try await voice.connect(
            backend: client.baseURL, token: client.token, scope: scope, policy: policy)
        } catch {
          endVoice()
          notice =
            "Voice unavailable. Use text; local recording continues. " + error.localizedDescription
        }
      }
      voiceIdleTask = Task {
        try? await Task.sleep(for: .seconds(120))
        guard !Task.isCancelled, voiceScope?.id == scope.id else { return }
        endVoice()
        notice = "Voice session closed after two minutes. Reconnect when ready."
      }
    } catch {
      endVoice()
      notice = error.localizedDescription
    }
  }
  func startAddressing() {
    guard voice.ready, let scope = voiceScope, !addressing, let audio else { return }
    if !voice.inputTranscript.isEmpty {
      connectVoice(mode: scope.mode)
      addressWhenReady = voiceScope != nil
      return
    }
    addressing = true
    voicePlaybackAllowed = false
    let consumer = "voice:" + UUID().uuidString
    voiceConsumerID = consumer
    let directory = root.appendingPathComponent("VoiceQuestions/\(scope.id.uuidString)")
    do {
      try db().put(
        VoiceQuestionRecord(
          id: scope.id.uuidString, meetingID: scope.meetingID, directory: directory.path),
        kind: "voiceQuestion", id: scope.id.uuidString, parent: scope.meetingID)
    } catch {
      endVoice()
      notice = error.localizedDescription
      return
    }
    let converter = VoicePCMConverter()
    let addressedAfter = ProcessInfo.processInfo.systemUptime
    let pair = AsyncStream<AudioPacket>.makeStream(bufferingPolicy: .bufferingOldest(64))
    voiceContinuation = pair.continuation
    voiceCaptureTask = Task {
      do {
        let device = try devices.resolve(audio.microphoneUID ?? microphoneUID)
        try await audio.addConsumer(
          id: consumer, directory: directory, tracks: [.microphone], device: device)
        guard !Task.isCancelled, voiceScope?.id == scope.id, addressing else {
          try audio.removeConsumer(id: consumer)
          return
        }
        try await voice.mute(false)
        guard !Task.isCancelled, addressing, voiceScope?.id == scope.id else { return }
        audio.setPacketHandler(
          { track, packet in
            guard packet.hostTime >= addressedAfter else { return }
            if track == .microphone, case .dropped = pair.continuation.yield(packet) {
              Task { @MainActor in
                self.endVoice()
                self.notice = "Voice uplink fell behind. Recording continues."
              }
            }
          }, id: "voice")
        for await packet in pair.stream {
          guard !Task.isCancelled, addressing, voiceScope?.id == scope.id else { break }
          try await voice.appendAddressedPCM24k(converter.convert(packet))
        }
      } catch {
        if !Task.isCancelled {
          endVoice()
          notice = "Voice input stopped. " + error.localizedDescription
        }
      }
    }
  }
  func finishAddressing() {
    addressWhenReady = false
    addressing = false
    voiceCaptureTask?.cancel()
    voiceContinuation?.finish()
    audio?.setPacketHandler(nil, id: "voice")
    if let voiceConsumerID { try? audio?.removeConsumer(id: voiceConsumerID) }
    voiceConsumerID = nil
    voice.finishInput()
  }
  func resumeCallMicrophone() {
    guard voiceScope == nil else {
      notice = "End private voice before returning to the call."
      return
    }
    guard voiceRouter.resumeCallInput() else {
      notice = voiceRouter.message
      return
    }
    audio?.setPrivateAddress(false)
    closePrivateVoiceGap()
  }
  func closePrivateVoiceGap() {
    if let (meeting, id, start) = privateVoiceGap {
      try? db().put(
        CaptureGap(
          start: start, end: elapsed, reason: "Private voice input omitted", track: .microphone),
        kind: "gap", id: id, parent: meeting)
      privateVoiceGap = nil
      try? refreshDetail()
    }
  }
  func endVoice() {
    finishAddressing()
    voiceIdleTask?.cancel()
    voiceSessionTask?.cancel()
    let rendered = voiceScope.map { voiceRouter.renderedFrames(context: $0.id) } ?? 0
    voiceRouter.stopVoice()
    audio?.endAssistantSource()
    if let scope = voiceScope, var queue = voiceOutput {
      queue.revoke(renderedThrough: max(rendered, queue.renderedFrames))
      try? db().put(
        queue.ledger.entries, kind: "voicePlayback", id: scope.id.uuidString,
        parent: scope.meetingID)
    }
    voiceOutput = nil
    voiceScope = nil
    voicePlaybackAllowed = false
    voice.interrupt(notify: false)
    if let id = voiceUsageID { finishUsage(id, status: "closed; provider usage unavailable") }
    voiceUsageID = nil
    // A failed private session must never automatically unmute the outgoing microphone.
    if activeMeetingID == nil { audio?.setPrivateAddress(false) }
  }
  func delegateVoice(id: String, question: String, context: UUID) {
    guard let scope = voiceScope, scope.id == context,
      !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }
    let requestID = context.uuidString + "/" + id
    guard delegationTasks[requestID] == nil else { return }
    delegationTasks[requestID] = Task {
      let usage = startUsage(category: "backend.voice-delegation", meetingID: scope.meetingID)
      defer { delegationTasks[requestID] = nil }
      do {
        let client = try backend(scope: scope.meetingID, associationID: requestID)
        let note = try db().note(scope.meetingID)
        let history = try db().list(
          AssistantExchange.self, kind: "assistantExchange", parent: scope.meetingID)
        let safe = scope.backendContext(note: note, history: history)
        let evidence = try db().list(
          TranscriptSegment.self, kind: "segment", parent: scope.meetingID
        ).filter { !$0.provisional }
        var exchange = AssistantExchange(
          id: requestID, meetingID: scope.meetingID, question: question, noteVersion: note.version)
        try db().put(exchange, kind: "assistantExchange", id: requestID, parent: scope.meetingID)
        let result = try await client.ask(
          question, segments: evidence, note: safe.0, history: safe.1)
        if !result.sources.isEmpty {
          try EvidenceValidator.validate(
            MeetingSummary(items: [
              SummaryItem(category: "overview", text: result.text, sources: result.sources)
            ]), meetingID: scope.meetingID, segments: evidence)
        }
        exchange.answer = result.text
        exchange.sources = result.sources
        exchange.write = result.write
        exchange.status = "completed"
        try db().put(exchange, kind: "assistantExchange", id: requestID, parent: scope.meetingID)
        finishUsage(usage, status: "completed")
        if selectedMeetingID == scope.meetingID { try refreshDetail() }
        guard voiceScope == scope else { return }  // Durable results survive interrupted speech; stale audio does not.
        if result.write != nil { reviewAssistantWrite(exchange) }
        let response =
          result.write == nil
          ? result.text
          : "A proposed change is ready for you to review in the app. It has not been saved."
        var short = String(response.prefix(400))
        while short.utf8.count > 480 { short.removeLast() }
        voicePlaybackAllowed = true
        try await voice.returnDelegation(id: id, result: short, context: context)
      } catch {
        finishUsage(usage, status: "failed")
        if voiceScope == scope {
          notice = error.localizedDescription
          endVoice()
        }
      }
    }
  }
}
