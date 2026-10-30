import AppKit
import CryptoKit
import UniformTypeIdentifiers
import ChupCore

extension WorkspaceState {
  var privacyWorkAllowed: Bool {
    pendingDictations == 0 && !transcriptionLab.busy && !microphonePreviewBusy && activeMeetingID == nil && dictationStatus != .listening && dictationStatus != .processing
      && !processingMeeting && !assistantBusy && voiceScope == nil && delegationTasks.isEmpty
      && outlineTask == nil && !writingNotes && !storageBusy && privacyMaintenanceTask == nil
  }
  func refreshPrivacy() throws {
    durableRequests = try db().requestListings().sorted {
      $0.created > $1.created
    }
    providerUsage = try db().list(ProviderUsage.self, kind: "providerUsage").sorted {
      $0.created > $1.created
    }
    if let saved = try db().list(RetentionPolicy.self, kind: "retention").first {
      retention = saved
    }
  }
  func saveRetention() {
    do {
      try db().put(retention, kind: "retention", id: "policy")
      storageMessage =
        "Schedule saved. Cleanup runs while Chup! is open and idle."
    } catch { storageMessage = error.localizedDescription }
  }
  func runRetention() {
    guard privacyWorkAllowed else {
      storageMessage = "Wait until recording and AI jobs finish."
      return
    }
    do {
      for plan in try db().list(DeletionPlan.self, kind: "deletion") {
        try db().finishDeletion(plan, root: root)
      }
      let now = Date()
      for meeting in meetings
      where retention.expired(meeting.created, days: retention.meetingDays, now: now) {
        try db().finishDeletion(db().planMeetingDeletion(meeting.id, root: root), root: root)
      }
      for entry in history
      where retention.expired(entry.created, days: retention.dictationDays, now: now) {
        try db().finishDeletion(
          db().planItemDeletion(
            id: entry.id, kind: "dictation", directory: entry.audioDirectory, root: root),
          root: root)
      }
      for question in try db().list(VoiceQuestionRecord.self, kind: "voiceQuestion")
      where retention.expired(question.created, days: retention.questionDays, now: now) {
        try db().finishDeletion(
          db().planItemDeletion(
            id: question.id, kind: "voiceQuestion", directory: question.directory, root: root),
          root: root)
      }
      try db().checkpoint()
      try refresh()
      try refreshPrivacy()
      if let id = selectedMeetingID, !meetings.contains(where: { $0.id == id }) {
        selectedMeetingID = nil
      }
      syncBackendDeletions()
      purgeExpiredTrash()
      storageMessage =
        "Cleanup done."
    } catch {
      storageMessage =
        "Cleanup paused; its saved deletion plan will retry. " + error.localizedDescription
    }
  }
  func exportMeeting(includePrivate: Bool = false) {
    guard let id = selectedMeetingID, privacyWorkAllowed else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "Chup-meeting.json"
    panel.message =
      includePrivate
      ? "This export includes private thoughts. Save it somewhere safe."
      : "Exports notes, transcript, summary and actions. Private thoughts stay out."
    guard panel.runModal() == .OK, let destination = panel.url else { return }
    do {
      try db().exportMeeting(id, includePrivate: includePrivate).write(
        to: destination, options: .atomic)
      storageMessage = "Meeting exported. The file isn’t encrypted."
    } catch { storageMessage = error.localizedDescription }
  }
  func exportMeetingAudio() {
    guard let id = selectedMeetingID, privacyWorkAllowed, let key else { return }
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Chup-meeting-audio"
    panel.message = "Pick a new folder. Mic and call audio are saved as separate files."
    guard panel.runModal() == .OK, let destination = panel.url else { return }
    storageBusy = true
    audioExportProgress = 0
    audioExportTask = Task {
      defer { storageBusy = false; audioExportProgress = nil; audioExportTask = nil }
      do {
        let archive = MeetingAudioArchive(key: key)
        _ = try await archive.prepare(db().list(RecordingLeg.self, kind: "leg", parent: id))
        try await archive.exportTracks(to: destination) { value in
          await MainActor.run { self.audioExportProgress = value }
        }
        storageMessage = "Audio exported. These copies aren’t encrypted."
      } catch is CancellationError { storageMessage = "Audio export stopped." }
      catch { storageMessage = error.localizedDescription }
    }
  }
  func inspectStorage() {
    do { storageMessage = try db().maintenanceCheck() } catch {
      storageMessage = error.localizedDescription
    }
  }
  func resumeRequest(_ saved: DurableRequest, newAttempt: Bool = false) {
    guard privacyWorkAllowed else {
      storageMessage = "Finish active work before resuming."
      return
    }
    guard var job = try? db().request(id: saved.id) else { return }
    if !cloudEnabled && (newAttempt || job.status != "completed") {
      storageMessage = "Enable cloud processing before retrying a provider request."
      return
    }
    if newAttempt {
      job.id = UUID().uuidString
      job.status = "queued"
      job.response = nil
      job.applied = false
    }
    storageBusy = true
    Task {
      defer {
        storageBusy = false
        try? refreshPrivacy()
      }
      do {
        let data: Data
        if job.status == "completed", let cached = job.response {
          data = cached
        } else {
          data = try await backend(scope: job.scope, associationID: job.associationID).perform(job)
        }
        if job.route == "summary" {
          let original = try JSONDecoder().decode([TranscriptSegment].self, from: job.body)
          let current = try db().list(TranscriptSegment.self, kind: "segment", parent: job.scope)
            .filter { !$0.provisional }
          guard TranscriptScope.fingerprint(original) == TranscriptScope.fingerprint(current) else {
            throw WorkspaceError.staleVersion
          }
          let summary = try JSONDecoder().decode(MeetingSummary.self, from: data)
          if !(try db().list(SummaryRevision.self, kind: "summaryVersion", parent: job.scope))
            .contains(where: { $0.id == job.id })
          {
            var revision = SummaryRevision(
              meetingID: job.scope, provisional: false, segments: current, summary: summary)
            revision.id = job.id
            try db().saveSummaryRevision(revision, segments: current)
          }
        } else if job.route == "ask", let exchangeID = job.associationID,
          var exchange = try db().list(
            AssistantExchange.self, kind: "assistantExchange", parent: job.scope
          ).first(where: { $0.id == exchangeID }), exchange.status != "committed"
        {
          let answer = try JSONDecoder().decode(AssistantReply.self, from: data)
          let evidence = try db().list(TranscriptSegment.self, kind: "segment", parent: job.scope)
          if !answer.sources.isEmpty {
            try EvidenceValidator.validate(
              MeetingSummary(items: [
                SummaryItem(category: "overview", text: answer.text, sources: answer.sources)
              ]), meetingID: job.scope, segments: evidence)
          }
          exchange.answer = answer.text
          exchange.sources = answer.sources
          exchange.write = answer.write
          exchange.status = "completed"
          try db().put(
            exchange, kind: "assistantExchange", id: exchange.id, parent: exchange.meetingID)
        }
        try refreshPrivacy()
        if selectedMeetingID == job.scope { try refreshDetail() }
        storageMessage =
          "Answer recovered. Check any note changes before you save them."
      } catch { storageMessage = error.localizedDescription }
    }
  }
  func copyRequestResult(_ job: DurableRequest) {
    guard let complete = try? db().request(id: job.id), let response = complete.response else {
      return
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(String(decoding: response, as: UTF8.self), forType: .string)
    storageMessage = "Answer copied."
  }
  func createBackup(password: String) {
    guard privacyWorkAllowed, let audioKey = key else { return }
    let panel = NSSavePanel()
    panel.nameFieldStringValue =
      "Chup-\(Date().formatted(.iso8601.year().month().day())).chupbackup"
    panel.message =
      "Encrypted recovery folder. Keep the password separately; Chup! cannot recover it."
    guard panel.runModal() == .OK, let destination = panel.url else { return }
    storageBusy = true
    Task {
      let snapshot = FileManager.default.temporaryDirectory.appendingPathComponent(
        "Chup-snapshot-" + UUID().uuidString)
      defer {
        try? FileManager.default.removeItem(at: snapshot)
        storageBusy = false
      }
      do {
        let databaseKey = try KeyVault.databaseKey(existing: true, account: databaseKeyAccount)
        let keys = BackupKeys(database: databaseKey, audio: audioKey.withUnsafeBytes { Data($0) })
        try FileManager.default.createDirectory(
          at: snapshot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try db().encryptedSnapshot(
          to: snapshot.appendingPathComponent("workspace.sqlite"), key: databaseKey)
        let root = self.root
        try await Task.detached {
          for folder in ["Recordings", "Dictations", "VoiceQuestions", "VoiceReferences"] {
            let source = root.appendingPathComponent(folder)
            if FileManager.default.fileExists(atPath: source.path) {
              try FileManager.default.copyItem(
                at: source, to: snapshot.appendingPathComponent(folder))
            }
          }
          try WorkspaceBackup.create(
            snapshot: snapshot, destination: destination, password: password, keys: keys,
            originalRoot: root)
        }.value
        storageMessage = "Backup saved."
      } catch { storageMessage = error.localizedDescription }
    }
  }
  func restoreBackup(password: String, activate: Bool) {
    guard privacyWorkAllowed else { return }
    let open = NSOpenPanel()
    open.canChooseDirectories = true
    open.canChooseFiles = false
    open.message = "Choose a Chup! encrypted recovery folder."
    guard open.runModal() == .OK, let archive = open.url else { return }
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("ChupRestored")
    let identifier = UUID().uuidString
    let destination = base.appendingPathComponent(identifier)
    storageBusy = true
    Task {
      defer { storageBusy = false }
      do {
        let manifest = try await Task.detached {
          try WorkspaceBackup.restore(
            archive: archive, destination: destination, password: password)
        }.value
        if activate {
          let restored = try WorkspaceStore(
            url: destination.appendingPathComponent("workspace.sqlite"), key: manifest.keys.database
          )
          try restored.rebaseRecordingPaths(
            from: URL(fileURLWithPath: manifest.originalRoot), to: destination)
          try restored.recoverRequests()
          try KeyVault.write(manifest.keys.database, account: "database-key." + identifier)
          try KeyVault.write(manifest.keys.audio, account: "audio-key." + identifier)
          defaults.set(destination.path, forKey: "workspaceRootOverride")
          defaults.set("." + identifier, forKey: "workspaceKeySuffix")
          storageMessage =
            "Restore ready. Quit and reopen Chup! to use it."
        } else {
          try FileManager.default.removeItem(at: destination)
          storageMessage =
            "Backup checked. Everything in it is readable."
        }
      } catch {
        try? FileManager.default.removeItem(at: destination)
        storageMessage =
          "Recovery failed; the current workspace is unchanged. " + error.localizedDescription
      }
    }
  }
  var databaseKeyAccount: String { "database-key" + workspaceKeySuffix }
}

extension WorkspaceState {
  func recordProviderUsage(
    id: String, category: String, model: String, raw: String, final: Bool, scope: String
  ) {
    do {
      let value = (try JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] ?? [:]
      let item = ProviderUsage(
        id: id, category: category, model: model,
        inputTokens: value["input_tokens"] as? Double,
        cachedTokens: (value["input_tokens_details"] as? [String: Any])?["cached_tokens"]
          as? Double,
        outputTokens: value["output_tokens"] as? Double, seconds: value["seconds"] as? Double,
        confirmed: final, raw: raw)
      try db().saveProviderUsage(item, scope: scope)
      try refreshPrivacy()
    } catch { notice = error.localizedDescription }
  }
}

extension WorkspaceState {
  func syncBackendDeletions() {
    guard privacyMaintenanceTask == nil, !backendToken.isEmpty, let url = URL(string: backendURL),
      let pending = try? db().pendingBackendDeletions(), !pending.isEmpty
    else { return }
    let client = BackendClient(baseURL: url, token: backendToken)
    privacyMaintenanceTask = Task {
      defer { privacyMaintenanceTask = nil }
      do {
        struct Receipt: Decodable { var deleted: Bool }
        for item in pending {
          let result: Receipt = try await client.request(
            "forget", body: JSONEncoder().encode(["ids": item.requests]))
          guard result.deleted else {
            throw WorkspaceError.message("Backend deletion was not confirmed.")
          }
          try db().remove(kind: "backendDeletion", id: item.id)
        }
        storageMessage =
          "Deleted from this Mac and your server."
      } catch {
        storageMessage =
          "Local deletion completed; backend cache deletion is queued for retry. "
          + error.localizedDescription
      }
    }
  }
  func deleteEnrollmentWithPlan(_ profile: VoiceEnrollment) {
    guard privacyWorkAllowed else {
      notice = "Wait until recording and AI jobs finish."
      return
    }
    do {
      try removeEnrollment(profile)
      notice =
        "Voice forgotten. Names in past meetings stay."
    } catch { notice = error.localizedDescription }
  }
  /// Throwing core of deleteEnrollmentWithPlan, for callers that must stop on failure.
  func removeEnrollment(_ profile: VoiceEnrollment) throws {
    do {
      var disabled = profile
      disabled.cloudMatching = false
      try db().put(disabled, kind: "enrollment", id: disabled.id)
      let plan = try db().planItemDeletion(
        id: profile.id, kind: "enrollment", directory: profile.referencePath, root: root)
      try db().finishDeletion(plan, root: root)
      try refresh()
      try refreshPrivacy()
      syncBackendDeletions()
    }
  }
}
