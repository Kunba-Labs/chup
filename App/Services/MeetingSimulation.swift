import AppKit
import ChupCore
import Foundation

/// `--simulate-meeting <wav> --simulate-report <json>`: an end-to-end rehearsal in the real app.
/// An `afplay` process plays a synthetic call and is recorded through the real process tap
/// (muted, so nothing is heard), with typed notes, the live sidebar and live notes, then Stop &
/// save runs the real transcript → summary → notes pipeline. The report records what happened;
/// nothing is simulated inside the app's own logic.
@MainActor enum MeetingSimulation {
  static var active: Bool { ProcessInfo.processInfo.arguments.contains("--simulate-meeting") }
  static var started = false
  static func argument(_ name: String) -> String? {
    let args = ProcessInfo.processInfo.arguments
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
  }
  static func run(state: WorkspaceState) async {
    guard let audio = argument("--simulate-meeting"),
      let reportPath = argument("--simulate-report")
    else { return }
    var report: [String: Any] = ["started": ISO8601DateFormatter().string(from: Date())]
    var checks: [String: Bool] = [:]
    func finish() {
      report["checks"] = checks
      report["passed"] = !checks.values.contains(false)
      report["notice"] = state.notice
      let data = try? JSONSerialization.data(
        withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      FileManager.default.createFile(atPath: reportPath, contents: data)
    }
    try? await Task.sleep(for: .seconds(3))  // Let the shell and store settle.
    let player = Process()
    player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
    player.arguments = [audio]
    do { try player.run() } catch {
      report["error"] = "afplay failed: \(error.localizedDescription)"
      return finish()
    }
    try? await Task.sleep(for: .seconds(1))
    state.newMeeting()
    guard let id = state.selectedMeetingID else {
      report["error"] = "No meeting created"
      player.terminate()
      return finish()
    }
    report["meetingID"] = id
    state.renameMeeting(
      "Simulated meeting · Q3 launch", participants: "Samantha, Daniel", tags: "simulation")
    let notes = "# Q3 launch\nbudget??\nwho owns QA"
    state.noteDraft = notes
    state.saveNote(notes)
    state.selectedPID = player.processIdentifier
    state.startMeeting()
    let started = Date()
    var sidebarSeen = false
    var timeline: [String] = []
    func note(_ event: String) {
      let line = "\(Int(Date().timeIntervalSince(started)))s \(event)"
      if timeline.last.map({ !$0.hasSuffix(event) }) ?? true { timeline.append(line) }
    }
    while player.isRunning, Date().timeIntervalSince(started) < 600 {
      note("status=\(state.meetingStatus) mic=\(state.micLastPacket != nil) call=\(state.remoteLastPacket != nil) device=\(state.activeMicrophone?.name ?? "-") notice=\(state.notice ?? "")")
      try? await Task.sleep(for: .seconds(1))
      sidebarSeen = sidebarSeen || (state.sidebar?.visible ?? false)
    }
    report["timeline"] = timeline
    let legs = (try? state.db().list(RecordingLeg.self, kind: "leg", parent: id)) ?? []
    let gaps = (try? state.db().list(CaptureGap.self, kind: "gap", parent: id)) ?? []
    report["legs"] = legs.count
    report["gaps"] = gaps.map(\.reason)
    try? await Task.sleep(for: .seconds(4))  // Let the last live segments land.
    report["recordedSeconds"] = Int(state.elapsed)
    let live = (try? state.db().list(TranscriptSegment.self, kind: "segment", parent: id)) ?? []
    let outlines =
      (try? state.db().list(SummaryRevision.self, kind: "liveOutline", parent: id)) ?? []
    report["liveSegments"] = live.count
    report["liveNotes"] = outlines.flatMap(\.summary.items).map(\.text)
    checks["recordingRunning"] = state.meetingStatus == .recording
    checks["callAudioReceived"] = state.remoteLastPacket != nil
    checks["sidebarShown"] = sidebarSeen
    checks["liveCaptions"] = !live.isEmpty
    checks["liveNotes"] = !outlines.isEmpty
    state.stopMeeting()
    let stopped = Date()
    try? await Task.sleep(for: .seconds(2))
    while (state.processingMeeting || state.writingNotes || !state.notesQueue.isEmpty),
      Date().timeIntervalSince(stopped) < 900
    {
      try? await Task.sleep(for: .seconds(2))
    }
    report["processingSeconds"] = Int(Date().timeIntervalSince(stopped))
    let final = ((try? state.db().list(TranscriptSegment.self, kind: "segment", parent: id)) ?? [])
      .filter { !$0.provisional }
    let summary = try? state.db().list(MeetingSummary.self, kind: "summary", parent: id).last
    let enhanced = try? state.db().list(EnhancedNotes.self, kind: "enhancedNotes", parent: id).last
    report["finalSegments"] = final.count
    report["summary"] = summary?.items.map { "[\($0.category)] \($0.text)" } ?? []
    report["notes"] = enhanced?.blocks.map { "\($0.kind): \($0.text)" } ?? []
    checks["finalTranscript"] = !final.isEmpty
    checks["summary"] = !(summary?.items.isEmpty ?? true)
    checks["notesWritten"] = !(enhanced?.blocks.isEmpty ?? true)
    checks["userLinesKept"] =
      notes.split(separator: "\n").allSatisfy { line in
        enhanced?.blocks.contains { $0.kind == "user" && $0.text == line } ?? false
      }
    checks["aiLinesSourced"] =
      enhanced?.blocks.filter { $0.kind == "ai" }.allSatisfy { !$0.sources.isEmpty } ?? false
    finish()
  }
}
