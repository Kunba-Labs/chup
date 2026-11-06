import AppKit
import Foundation
import ChupCore

extension WorkspaceState {
  func scheduleOutline(meetingID: String) {
    guard liveOutlineEnabled, cloudEnabled, outlineTask == nil else { return }
    outlineTask = Task {
      defer { outlineTask = nil }
      do {
        try await Task.sleep(for: .seconds(20))
        guard cloudEnabled, liveOutlineEnabled else { return }
        // Live notes accumulate: each pass covers only completed text after the last one.
        let source = try db().list(TranscriptSegment.self, kind: "segment", parent: meetingID)
        let covered = outlineCovered[meetingID] ?? []
        let recent = source.filter { !covered.contains($0.id) }.sorted { $0.start < $1.start }
        guard let end = recent.map(\.end).max(), end - (recent.first?.start ?? end) >= 60
        else { return }
        let result = try await backend(scope: meetingID).outline(recent)
        try Task.checkCancellation()
        try EvidenceValidator.validate(
          result, meetingID: meetingID, segments: TranscriptScope.outlineEvidence(recent))
        let revision = SummaryRevision(
          meetingID: meetingID, provisional: true, segments: recent, summary: result)
        try db().put(revision, kind: "liveOutline", id: revision.id, parent: meetingID)
        outlineCovered[meetingID, default: []].formUnion(recent.map(\.id))
        if selectedMeetingID == meetingID { try refreshDetail() }
      } catch {
        if !Task.isCancelled {
          notice =
            "Live outline paused. Recording and notes continue. " + error.localizedDescription
        }
      }
    }
  }
  func finalizeSummary(meetingID: String) async throws {
    let source = try db().list(TranscriptSegment.self, kind: "segment", parent: meetingID).filter {
      !$0.provisional
    }
    guard !source.isEmpty else {
      throw WorkspaceError.message("Refine the saved transcript first.")
    }
    let fingerprint = TranscriptScope.fingerprint(source)
    let usageID = startUsage(category: "backend.summary", meetingID: meetingID)
    do {
      let result = try await backend(scope: meetingID).summarize(
        source, language: meetings.first { $0.id == meetingID }?.notesLanguage)
      let current = try db().list(TranscriptSegment.self, kind: "segment", parent: meetingID).filter
      { !$0.provisional }
      guard TranscriptScope.fingerprint(current) == fingerprint else {
        throw WorkspaceError.staleVersion
      }
      try Task.checkCancellation()
      let revision = SummaryRevision(
        meetingID: meetingID, provisional: false, segments: current, summary: result)
      try db().saveSummaryRevision(revision, segments: current)
      finishUsage(usageID, status: "completed")
      await nameUntitledMeeting(meetingID, summary: result, segments: current)
      if selectedMeetingID == meetingID { try refreshDetail() }
    } catch {
      finishUsage(usageID, status: "failed")
      throw error
    }
  }
  static let inferredNamePrefix = "Named from the transcript: "
  /// Names speakers nobody named yet: a lone voice on your microphone as this Mac's user, the
  /// rest from introductions and being addressed by name (decided 2026-11-06, spec F12). Typed
  /// names and voice matches are never replaced; each name keeps the quote it came from.
  func nameSpeakersFromTranscript(meetingID: String) async throws {
    let source = try db().list(TranscriptSegment.self, kind: "segment", parent: meetingID)
      .filter { !$0.provisional }
    let unnamed = Set(source.filter { $0.speakerName == nil && $0.track != .assistant }.map(\.speakerID))
    guard !unnamed.isEmpty else { return }
    var names: [String: (name: String, why: String)] = [:]
    let mic = Set(source.filter { $0.track == .microphone }.map(\.speakerID))
    if mic.count == 1, let me = mic.first, unnamed.contains(me), !NSFullUserName().isEmpty {
      names[me] = (NSFullUserName(), "this Mac's user, the only voice on your microphone")
    }
    if cloudEnabled && !backendToken.isEmpty {
      let taken = Set(source.compactMap(\.speakerName).map { $0.lowercased() })
      for found in try await backend(scope: meetingID).speakers(source)
      where unnamed.contains(found.speakerID) && names[found.speakerID] == nil
        && !taken.contains(found.name.lowercased())
      {
        names[found.speakerID] = (found.name, found.sources.map { "“\($0.quote)”" }.joined(separator: " "))
      }
    }
    // Re-read after the backend call: a rename or text fix made meanwhile is never overwritten.
    // ponytail: one put per line, not one transaction; a crash mid-way leaves some lines named.
    let current = try db().list(TranscriptSegment.self, kind: "segment", parent: meetingID)
    for var segment in current
    where !segment.provisional && segment.speakerName == nil && segment.nameCorrected != true {
      guard let found = names[segment.speakerID] else { continue }
      segment.speakerName = found.name
      segment.attribution = Self.inferredNamePrefix + found.why
      try db().put(segment, kind: "segment", id: segment.id, parent: meetingID, searchable: segment.text)
    }
  }
  /// The quote behind a name Chup! inferred and nobody has confirmed yet.
  func inferredNameReason(_ speakerID: String) -> String? {
    segments.first {
      $0.speakerID == speakerID && $0.nameCorrected != true
        && $0.attribution?.hasPrefix(Self.inferredNamePrefix) == true
    }?.attribution.map { String($0.dropFirst(Self.inferredNamePrefix.count)) }
  }
  /// Undo: every unconfirmed inferred name in this meeting goes back to "Speaker N".
  func undoInferredNames() {
    do {
      for var segment in segments
      where segment.nameCorrected != true && segment.attribution?.hasPrefix(Self.inferredNamePrefix) == true {
        segment.speakerName = nil
        segment.attribution = "request-local acoustic group"
        try db().put(segment, kind: "segment", id: segment.id, parent: segment.meetingID, searchable: segment.text)
      }
      try refreshDetail()
    } catch { notice = error.localizedDescription }
  }
  /// Ask during the call, over the live captions (decided 2026-11-06, spec F12). Captions are
  /// sent as evidence copies, like the live outline; the answer joins the meeting's Ask history.
  func askLive(_ question: String, lastSeconds: Double? = nil) {
    guard liveAskTask == nil, let id = activeMeetingID, cloudEnabled, !backendToken.isEmpty,
      !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }
    let all = liveLines.filter { $0.meetingID == id }.map { line -> TranscriptSegment in
      var line = line
      line.provisional = false
      return line
    }
    // A recap covers only its window, by caption time, so an hour-long call can't answer it.
    let lines = lastSeconds.map { TranscriptScope.recent(all, seconds: $0) } ?? all
    guard !lines.isEmpty else {
      liveAnswer = (id, question, "Nothing has been transcribed yet.")
      return
    }
    liveAnswer = (id, question, nil)
    liveAskTask = Task {
      defer { liveAskTask = nil }
      var exchange = AssistantExchange(meetingID: id, question: question, noteVersion: 0)
      do {
        let note = try db().note(id)
        let answer = try await backend(scope: id, associationID: exchange.id)
          .ask(question, segments: lines, note: note)
        if !answer.sources.isEmpty {
          try EvidenceValidator.validate(
            MeetingSummary(items: [SummaryItem(category: "overview", text: answer.text, sources: answer.sources)]),
            meetingID: id, segments: lines)
        }
        // Caption lines are replaced after Stop, so history keeps the quotes as text instead of
        // links that would stop resolving.
        let quotes = answer.sources.map { "“\($0.quote)”" }.joined(separator: " ")
        exchange.answer = answer.text + (quotes.isEmpty ? "" : "\n\nFrom the live captions: " + quotes)
        exchange.status = "completed"
        try db().put(exchange, kind: "assistantExchange", id: exchange.id, parent: id)
        guard activeMeetingID == id else { return }  // A newer call's notepad never shows it.
        liveAnswer = (id, question, answer.text)
      } catch {
        guard activeMeetingID == id else { return }
        liveAnswer = (id, question, "Couldn't answer that: " + error.localizedDescription)
      }
    }
  }
  /// Gives a still-untitled meeting a topic title from its summary, "with" the people named on
  /// the call. Without a usable summary title it falls back to "Sunday morning with Rizwan".
  /// A title the user typed is never replaced.
  func nameUntitledMeeting(_ meetingID: String, summary: MeetingSummary, segments: [TranscriptSegment]) async {
    guard meetings.first(where: { $0.id == meetingID })?.title == "Untitled meeting" else { return }
    var people: [String] = []
    for name in segments.filter({ $0.track == .remote }).compactMap(\.speakerName)
    where !people.contains(name) && !name.hasSuffix("· voice match") { people.append(name) }
    let points = summary.items.map(\.text).filter { !$0.isEmpty }
    var title = points.isEmpty ? nil : try? await backend(scope: meetingID).title(points: points, people: people)
    if title == nil, !people.isEmpty, let created = meetings.first(where: { $0.id == meetingID })?.created {
      title = Self.dayPart(created) + " with " + people.prefix(2).joined(separator: " and ")
    }
    guard let title, var meeting = meetings.first(where: { $0.id == meetingID }),
      meeting.title == "Untitled meeting"
    else { return }
    meeting.title = title
    do { try saveMeeting(meeting) } catch { NSLog("Chup meeting title not saved: %@", "\(error)") }
  }
  /// "Sunday morning", "Monday evening".
  nonisolated static func dayPart(_ date: Date) -> String {
    let hour = Calendar.current.component(.hour, from: date)
    let part = hour < 12 ? "morning" : hour < 17 ? "afternoon" : hour < 21 ? "evening" : "night"
    return date.formatted(.dateTime.weekday(.wide)) + " " + part
  }
  /// Merges the user's notes with the refined transcript. Private thoughts are never included.
  func writeNotes(meetingID: String, template: String? = nil) async throws {
    let source = try db().list(TranscriptSegment.self, kind: "segment", parent: meetingID).filter {
      !$0.provisional
    }
    let note = try db().note(meetingID).text
    let previous = try db().list(EnhancedNotes.self, kind: "enhancedNotes", parent: meetingID).last
    let chosen = template ?? previous?.template ?? "general"
    notesMeetingID = meetingID
    defer { notesMeetingID = nil }
    let usageID = startUsage(category: "backend.notes", meetingID: meetingID)
    do {
      let blocks = try await backend(scope: meetingID).enhance(
        source, note: note, template: chosen,
        language: meetings.first { $0.id == meetingID }?.notesLanguage)
      let current = try db().list(TranscriptSegment.self, kind: "segment", parent: meetingID)
        .filter { !$0.provisional }
      guard TranscriptScope.fingerprint(current) == TranscriptScope.fingerprint(source),
        try db().note(meetingID).text == note
      else { throw WorkspaceError.staleVersion }
      try EvidenceValidator.validate(blocks, note: note, meetingID: meetingID, segments: current)
      try Task.checkCancellation()
      try db().put(
        EnhancedNotes(meetingID: meetingID, template: chosen, blocks: blocks),
        kind: "enhancedNotes", id: meetingID, parent: meetingID)
      notesQueue.removeAll { $0 == meetingID }
      finishUsage(usageID, status: "completed")
      if selectedMeetingID == meetingID { try refreshDetail() }
    } catch {
      finishUsage(usageID, status: "failed")
      throw error
    }
  }
  /// Per-meeting override (nil = the meeting's spoken language); rewrites summary and notes.
  func setNotesLanguage(_ language: String?) {
    guard var meeting = selectedMeeting, meeting.notesLanguage != language else { return }
    meeting.notesLanguage = language
    do { try saveMeeting(meeting) } catch { notice = error.localizedDescription; return }
    generateSummary()
    regenerateNotes(template: enhancedNotes?.template ?? "general")
  }
  func regenerateNotes(template: String) {
    guard let id = selectedMeetingID, !writingNotes else { return }
    notesTask = Task {
      defer { notesTask = nil }
      do { try await writeNotes(meetingID: id, template: template) } catch {
        notice = Task.isCancelled || error is CancellationError
          ? "Notes stopped." : "Notes weren’t written: " + error.localizedDescription
      }
    }
  }
  func copyNotesMarkdown() {
    let outline = SummaryOutline(summary: summary, actions: actions)
    let title = selectedMeeting?.title ?? "Meeting"
    // With topic-led notes, copy what the Summary tab shows: the notes, then next steps.
    let text = enhancedNotes.flatMap { $0.blocks.isEmpty ? nil : $0 }.map {
      $0.markdown(title: title) + outline.nextStepsMarkdown()
    } ?? outline.markdown(title: title, thoughts: noteDraft)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    notice = "Copied as Markdown."
  }
  func draftFollowup() {
    guard let id = selectedMeetingID, let notes = enhancedNotes else { return }
    let title = selectedMeeting?.title ?? "Meeting"
    Task {
      do {
        let draft = try await backend(scope: id).followup(title: title, blocks: notes.blocks)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Subject: \(draft.subject)\n\n\(draft.body)", forType: .string)
        notice = "Follow-up email copied."
      } catch { notice = "Follow-up not drafted: " + error.localizedDescription }
    }
  }
  func saveThoughts(_ text: String) {
    guard let id = selectedMeetingID, text != thoughts.text else { return }
    do {
      thoughts = try db().writeNote(
        meetingID: "private-thoughts/" + id, text: text,
        expectedVersion: thoughts.version, requestID: UUID().uuidString
      ).after
    } catch { notice = error.localizedDescription }
  }
  func saveSummaryEdit(_ item: SummaryItem) {
    guard let id = selectedMeetingID else { return }
    do {
      try db().put(item, kind: "summaryEdit", id: id + "/" + item.id, parent: id)
      try refreshDetail()
    } catch { notice = error.localizedDescription }
  }
  func createAction(from item: SummaryItem) {
    guard let id = selectedMeetingID else { return }
    let action = ActionRecord(
      id: id + "/summary/" + item.id, meetingID: id, title: item.text,
      owner: item.owner, dueDate: item.dueDate, status: item.status, sources: item.sources,
      origin: "transcript")
    do {
      lastActionReceipt = try db().writeAction(
        action, expectedVersion: 0, requestID: id + "/summary-action/" + item.id)
      try refreshDetail()
      notice = "Action saved."
    } catch { notice = error.localizedDescription }
  }
  /// Returns false when the write failed, so an editor can keep the user's text.
  @discardableResult func saveAction(_ action: ActionRecord) -> Bool {
    do {
      lastActionReceipt = try db().writeAction(
        action, expectedVersion: action.version, requestID: UUID().uuidString)
      try refreshDetail()
      return true
    } catch {
      notice = error.localizedDescription
      return false
    }
  }
  func undoAction() {
    guard let receipt = lastActionReceipt, receipt.after.meetingID == selectedMeetingID else {
      return
    }
    do {
      var restored = receipt.before ?? receipt.after
      if receipt.before == nil { restored.status = "archived" }
      restored.version = receipt.after.version
      _ = try db().writeAction(
        restored, expectedVersion: receipt.after.version, requestID: UUID().uuidString)
      lastActionReceipt = nil
      try refreshDetail()
    } catch { notice = error.localizedDescription }
  }
  func addAction(_ title: String) {
    guard let id = selectedMeetingID else { return }
    saveAction(ActionRecord(meetingID: id, title: title))
  }
  func revealSource(_ source: Evidence) {
    guard let segment = segments.first(where: { $0.id == source.segmentID }) else {
      notice = partial.transcript
        ? "Source deleted: this meeting's transcript was deleted."
        : "This source changed. Open its transcript revision."
      return
    }
    selectedTranscriptSource = segment.id
    meetingTab = "Transcript"
    if !partial.audio { play(at: segment.start) }
  }
  @discardableResult func startUsage(category: String, meetingID: String) -> String {
    let item = UsageRecord(meetingID: meetingID, category: category)
    do { try db().put(item, kind: "usage", id: item.id, parent: meetingID) } catch {
      notice = error.localizedDescription
    }
    return item.id
  }
  func finishUsage(_ id: String, status: String, providerUsage: String? = nil) {
    do {
      guard var item = try db().list(UsageRecord.self, kind: "usage").first(where: { $0.id == id })
      else { return }
      item.ended = Date()
      item.status = status
      item.providerUsage = providerUsage
      try db().put(item, kind: "usage", id: id, parent: item.meetingID)
      usageRecords = try db().list(UsageRecord.self, kind: "usage").sorted {
        $0.started > $1.started
      }
    } catch { notice = error.localizedDescription }
  }
}
