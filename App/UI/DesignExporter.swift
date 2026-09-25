import AppKit
import SwiftUI
import ChupCore

@MainActor enum DesignExporter {
  static func export(state: WorkspaceState) {
    guard state.isPreview else { return }
    let destination = URL(
      fileURLWithPath: ProcessInfo.processInfo.environment["CHUP_DESIGN_OUTPUT"]
        ?? "/tmp/chup-design")
    do {
      try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
      if ProcessInfo.processInfo.environment["CHUP_SCROLL_REVIEW"] == "1" {
        for width in [741.0, 790, 1021] {
          for section in SettingsView().sections {
            try renderNative(SettingsView(section: section).environmentObject(state),
              size: CGSize(width: width, height: 640),
              to: destination.appendingPathComponent("scroll-\(Int(width))-\(section).png"))
          }
        }
        try exportLayoutReview(state: state, destination: destination)
        return
      }
      if ProcessInfo.processInfo.environment["CHUP_LAB_PREVIEW"] == "1" {
        var trace = DictationTrace()
        trace.mark(.requested, elapsed: 0); trace.mark(.firstAudio, elapsed: 0.08)
        trace.mark(.captureStopped, elapsed: 4); trace.mark(.localStarted, elapsed: 4.1)
        trace.mark(.localFinished, elapsed: 4.9); trace.mark(.insertionStarted, elapsed: 4.91)
        trace.mark(.finished, elapsed: 5.1); trace.outcome = .inserted
        state.dictationTraces = [trace]
        try renderNative(
          DesignFrame(title: "29 / DIAGNOSTICS", subtitle: "Native settings · illustrative timing sample") {
            SettingsView(section: "Diagnostics").environmentObject(state)
          }, size: CGSize(width: 1100, height: 900), to: destination.appendingPathComponent("29-diagnostics.png"))
        try renderNative(
          DesignFrame(title: "29 / TRANSCRIPTION LAB", subtitle: "Native settings · no recording processed by this preview") {
            SettingsView(section: "Transcription Lab").environmentObject(state)
          }, size: CGSize(width: 1100, height: 980), to: destination.appendingPathComponent("29-transcription-lab.png"))
        return
      }
      if ProcessInfo.processInfo.environment["CHUP_ALERT_PREVIEW"] == "1" {
        state.dictationStatus = .idle
        state.dictationFeedback = .clipboardChanged
        try renderNative(
          DesignFrame(title: "28 / ALERT LAYOUT", subtitle: "Native view · sample clipboard message") {
            DictationIndicatorView(state: state).frame(maxWidth: .infinity, maxHeight: .infinity)
          }, size: CGSize(width: 600, height: 250),
          to: destination.appendingPathComponent("28-clipboard-alert.png"))
        state.dictationFeedback = nil
        state.dictationMicMessage = "No input detected from C922 Pro Stream Webcam. Check mute, connection or microphone selection."
        try renderNative(
          DesignFrame(title: "28 / MICROPHONE ALERT", subtitle: "Native view · sample warning, no capture") {
            DictationIndicatorView(state: state).frame(maxWidth: .infinity, maxHeight: .infinity)
          }, size: CGSize(width: 600, height: 300),
          to: destination.appendingPathComponent("28-microphone-alert.png"))
        return
      }
      if ProcessInfo.processInfo.environment["CHUP_POPUP_PREVIEW"] == "1" {
        state.meetingStatus = .idle; state.dictationStatus = .idle; state.voiceScope = nil
        try renderNative(PopupStylePreview(state: state), size: CGSize(width: 1050, height: 610),
          to: destination.appendingPathComponent("23-unified-popups.png"))
        return
      }
      if ProcessInfo.processInfo.environment["CHUP_COMPACT_PREVIEW"] == "1" {
        try exportCompactMotion(state: state, destination: destination)
        return
      }
      if ProcessInfo.processInfo.environment["CHUP_ISLAND_PREVIEW"] == "1" {
        try exportIslandBoard(destination: destination)
        return
      }
      if ProcessInfo.processInfo.environment["CHUP_ATTENTION_PREVIEW"] == "1" {
        try renderNative(AttentionDesignBoard(), size: CGSize(width: 1180, height: 1420),
          to: destination.appendingPathComponent("32-attention.png"))
        print("Attention design board exported. Proposal mocks only; no checks run, no capture.")
        return
      }
      let now = Date(timeIntervalSince1970: 1_789_387_200)
      state.meetings = [
        Meeting(
          id: "preview-launch", title: "The autumn launch", created: now, status: "Summary ready",
          participants: "Mara de Vries, Oliver Chen, You", tags: "Product  ·  Launch"),
        Meeting(
          id: "preview-design", title: "A quieter kind of workspace",
          created: now.addingTimeInterval(-86400), status: "Summary ready",
          participants: "Sofia, Mara, You", tags: "Design  ·  Chup!"),
        Meeting(
          id: "preview-week", title: "Monday, with the team",
          created: now.addingTimeInterval(-172800), status: "Audio saved",
          participants: "Oliver, Sofia, You", tags: "Weekly"),
        Meeting(
          id: "preview-research", title: "Listening to our early users",
          created: now.addingTimeInterval(-345600), status: "Summary ready",
          participants: "Mara, You", tags: "Research"),
      ]
      state.page = .meetings
      state.notice = nil
      try renderNative(
        DesignFrame(
          title: "01 / THE WORKSPACE", subtitle: "Native SwiftUI · sample content for design review"
        ) {
          HStack(spacing: 0) {
            DesignSidebar()
            MeetingsView().environmentObject(state).background(Palette.workspace)
          }
        }, size: CGSize(width: 1360, height: 920),
        to: destination.appendingPathComponent("01-workspace.png"))
      state.selectedMeetingID = "preview-launch"
      state.segments = [
        .init(
          id: "s1", meetingID: "preview-launch", start: 138, end: 157,
          text:
            "Let’s keep the autumn launch to the Netherlands first. We need the Dutch dictation experience to feel as natural as English before we open it up.",
          speakerID: "mara", speakerName: "Mara de Vries", track: .remote),
        .init(
          id: "s2", meetingID: "preview-launch", start: 324, end: 341,
          text:
            "I’ll run the USB microphone tests. We should try reconnecting during a call, not only before we start recording.",
          speakerID: "oliver", speakerName: "Oliver Chen", track: .remote),
        .init(
          id: "s3", meetingID: "preview-launch", start: 601, end: 619,
          text:
            "We haven’t agreed on a public launch date yet. Let’s come back to it after we have the audio test results.",
          speakerID: "you", speakerName: "You", track: .microphone),
      ]
      state.summary = MeetingSummary(items: [
        SummaryItem(
          category: "overview",
          text:
            "A focused first release, with room to get the details right. The team discussed a Netherlands-first launch and the audio testing needed before choosing a date.",
          sources: [
            Evidence(segmentID: "s1", quote: "the Netherlands first"),
            Evidence(segmentID: "s3", quote: "after we have the audio test results"),
          ]),
        SummaryItem(
          category: "decision",
          text:
            "Start with the Netherlands. Dutch dictation should feel as natural as English before expanding.",
          sources: [
            Evidence(
              segmentID: "s1", quote: "Let’s keep the autumn launch to the Netherlands first.")
          ]),
        SummaryItem(
          category: "action",
          text: "Test USB microphones, including reconnecting during an active call.",
          owner: "Oliver Chen",
          sources: [Evidence(segmentID: "s2", quote: "I’ll run the USB microphone tests.")]),
        SummaryItem(
          category: "question",
          text:
            "When should the public launch happen? Revisit after the audio tests; no date has been agreed.",
          sources: [
            Evidence(segmentID: "s3", quote: "We haven’t agreed on a public launch date yet.")
          ]),
      ])
      try renderNative(
        DesignFrame(
          title: "02 / THE MEETING", subtitle: "Sample transcript and summary · no real recording"
        ) {
          HStack(spacing: 0) {
            DesignSidebar()
            MeetingDetailView(initialTab: "Summary").environmentObject(state).background(
              Palette.workspace)
          }
        }, size: CGSize(width: 1360, height: 1050),
        to: destination.appendingPathComponent("02-meeting.png"))
      var exchange = AssistantExchange(
        meetingID: "preview-launch", question: "What did we decide about the launch?",
        noteVersion: 0)
      exchange.answer =
        "Start with the Netherlands. The public launch date is still open; revisit it after the audio tests."
      exchange.status = "completed"
      exchange.sources = [
        Evidence(segmentID: "s1", quote: "the Netherlands first"),
        Evidence(segmentID: "s3", quote: "We haven’t agreed on a public launch date yet."),
      ]
      var followup = AssistantExchange(
        meetingID: "preview-launch", question: "Add that to my notes.", noteVersion: 0)
      followup.answer = "Here’s the note change to review before saving."
      followup.status = "completed"
      followup.write = ProposedNoteWrite(
        operation: "append_note",
        text:
          "Launch in the Netherlands first. Public date remains open until the audio tests are reviewed."
      )
      state.assistantHistory = [exchange, followup]
      try renderNative(
        DesignFrame(
          title: "08 / THE ASSISTANT",
          subtitle: "Saved conversation · sample content, no cloud request"
        ) {
          AssistantView().environmentObject(state).frame(width: 670, height: 650)
            .background(Palette.workspace, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 1) }
            .frame(maxWidth: .infinity)
        }, size: CGSize(width: 1000, height: 850),
        to: destination.appendingPathComponent("08-assistant.png"))
      state.enrollments = [
        VoiceEnrollment(
          id: "preview-reference", name: "Mara de Vries",
          meetingID: "preview-launch", segmentID: "s1", duration: 8,
          referencePath: "/sample-only/no-audio")
      ]
      try renderNative(
        DesignFrame(
          title: "09 / SPEAKERS & VOICE REFERENCES",
          subtitle: "Native controls · labeled sample identity, no biometric audio enrolled"
        ) {
          HStack(alignment: .top, spacing: 24) {
            SegmentEditor(segment: state.segments[0]).environmentObject(state)
              .background(Palette.paper, in: RoundedRectangle(cornerRadius: 12))
            VoiceEnrollmentSettings().environmentObject(state).padding(22).frame(width: 440)
              .background(Palette.paper, in: RoundedRectangle(cornerRadius: 12))
          }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }, size: CGSize(width: 1280, height: 850),
        to: destination.appendingPathComponent("09-speakers.png"))
      state.actions = [
        ActionRecord(
          meetingID: "preview-launch", title: "Test USB microphones during a call",
          owner: "Oliver Chen", dueDate: nil,
          sources: [Evidence(segmentID: "s2", quote: "I’ll run the USB microphone tests.")],
          origin: "transcript"),
        ActionRecord(
          meetingID: "preview-launch", title: "Review Dutch dictation with the pilot group",
          owner: "Mara de Vries", dueDate: "After the audio tests", status: "open"),
        ActionRecord(
          meetingID: "preview-launch", title: "Choose the public launch date", owner: nil,
          dueDate: nil, status: "open"),
      ]
      try renderNative(
        DesignFrame(
          title: "10 / WHAT HAPPENS NEXT",
          subtitle: "Sample actions · dates stay ambiguous, owners can remain unassigned"
        ) {
          HStack(spacing: 0) {
            DesignSidebar()
            MeetingDetailView(initialTab: "Actions").environmentObject(state).background(
              Palette.workspace)
          }
        }, size: CGSize(width: 1360, height: 960),
        to: destination.appendingPathComponent("10-actions.png"))
      try renderNative(
        DesignFrame(
          title: "11 / PRIVATE VOICE",
          subtitle:
            "Native idle controls · actual device availability, no voice session or simulated success"
        ) {
          VStack(alignment: .leading, spacing: 24) {
            Text("A moment to think aloud.").font(.system(size: 32, design: .serif))
            AssistantVoiceControls(
              voice: state.voice, router: state.voiceRouter, mode: .privateVoice
            ).environmentObject(state)
            Label(
              "Meeting voice requires a controlled microphone route. Private text is always available.",
              systemImage: "lock.shield"
            ).font(.callout).foregroundStyle(Palette.secondary)
          }.padding(36).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Palette.workspace)
        }, size: CGSize(width: 1000, height: 820),
        to: destination.appendingPathComponent("11-private-voice.png"))
      try renderNative(
        DesignFrame(
          title: "12 / WELCOME TO CHUP!",
          subtitle: "Native onboarding · no permissions requested by this design render"
        ) {
          OnboardingView().environmentObject(state)
        }, size: CGSize(width: 1100, height: 900),
        to: destination.appendingPathComponent("12-onboarding.png"))
      try renderNative(
        DesignFrame(
          title: "13 / MACOS ACCESS",
          subtitle: "Native Settings · actual permission status, no simulated grants"
        ) {
          SettingsView(section: "Permissions").environmentObject(state)
        }, size: CGSize(width: 1120, height: 1220),
        to: destination.appendingPathComponent("13-permissions.png"))
      state.setup.permissions = [.microphone: .allowed, .accessibility: .allowed,
        .inputMonitoring: .allowed, .systemAudio: .verifyDuringCapture, .screenCapture: .denied]
      try renderNative(
        DesignFrame(title: "16 / PERMISSION STATUS", subtitle: "Design preview · sample enabled states; no permissions changed") {
          PermissionCards(setup: state.setup, permissions: [.microphone, .accessibility, .inputMonitoring])
            .environmentObject(state).padding(26).background(Palette.workspace)
        }, size: CGSize(width: 900, height: 810),
        to: destination.appendingPathComponent("16-permission-status.png"))
      try renderNative(
        DesignFrame(
          title: "14 / STORAGE & RECOVERY",
          subtitle: "Encrypted preview database · sample meeting list · retention off"
        ) {
          SettingsView(section: "Privacy").environmentObject(state)
        }, size: CGSize(width: 1120, height: 1100),
        to: destination.appendingPathComponent("14-storage.png"))
      state.shortcuts.addControlShift()
      try renderNative(
        DesignFrame(
          title: "15 / YOUR KEYBOARDS, YOUR SHORTCUTS",
          subtitle: "Native Settings · sample Fn and Control–Shift bindings · no global hooks registered"
        ) {
          SettingsView(section: "Shortcuts").environmentObject(state)
        }, size: CGSize(width: 1120, height: 1480),
        to: destination.appendingPathComponent("15-shortcuts.png"))
      state.dictationStatus = .listening
      state.dictationReady = true
      state.micLevel = 0.12
      state.micWaveform = [0.25, 0.8, 0.95, 0.55, 0.4]
      try renderNative(
        DesignFrame(title: "17 / DICTATION STATUS", subtitle: "Native indicator · illustrative microphone level, no capture") {
          DictationIndicatorView(state: state).frame(maxWidth: .infinity, maxHeight: .infinity)
        }, size: CGSize(width: 740, height: 350),
        to: destination.appendingPathComponent("17-dictation-indicator.png"))
      state.dictationStatus = .idle
      state.dictationReady = false
      state.micLevel = 0
      state.micWaveform = Array(repeating: 0, count: 5)
      state.history = [DictationEntry(text: "", original: "", application: "TextEdit",
        mode: "Light cleanup", audioDirectory: "/sample-only/no-audio")]
      try renderNative(
        DesignFrame(title: "18 / DICTATION RECOVERY", subtitle: "Native controls · sample history entry, no real recording") {
          DictationView().environmentObject(state).background(Palette.workspace)
        }, size: CGSize(width: 1160, height: 780),
        to: destination.appendingPathComponent("18-dictation-recovery.png"))
      state.dictationStatus = .processing
      try renderNative(
        DesignFrame(title: "19 / PROCESSING", subtitle: "Native circular processing indicator · sample state") {
          DictationIndicatorView(state: state).frame(maxWidth: .infinity, maxHeight: .infinity)
        }, size: CGSize(width: 740, height: 350),
        to: destination.appendingPathComponent("19-dictation-processing.png"))
      state.dictationFeedback = .copied
      state.dictationStatus = .idle
      try renderNative(
        DesignFrame(title: "20 / CLIPBOARD RECOVERY", subtitle: "Native completion message · sample state, clipboard untouched") {
          DictationIndicatorView(state: state).frame(maxWidth: .infinity, maxHeight: .infinity)
        }, size: CGSize(width: 740, height: 350),
        to: destination.appendingPathComponent("20-dictation-copied.png"))
      state.dictationFeedback = nil
      try render(
        PanelBoard(state: state), size: CGSize(width: 1260, height: 1250),
        to: destination.appendingPathComponent("03-panels.png"))
      try render(
        RailDesignBoard(state: state), size: CGSize(width: 1260, height: 760),
        to: destination.appendingPathComponent("04-dark-glass-rail.png"))
      if ProcessInfo.processInfo.environment["CHUP_LAYOUT_REVIEW"] == "1" {
        try exportLayoutReview(state: state, destination: destination)
      }
    } catch { NSLog("Design export failed: %@", error.localizedDescription) }
  }
  private static func exportLayoutReview(state: WorkspaceState, destination: URL) throws {
    // All state belongs to an isolated preview workspace. No action is invoked.
    state.dictationMicMessage = nil; state.dictationFeedback = nil; state.dictationStatus = .idle
    state.meetingStatus = .idle; state.activeMeetingID = nil; state.voiceScope = nil
    state.storageMessage = "Sample cleanup finished — must only appear in Privacy."
    for section in SettingsView().sections {
      try renderNative(SettingsView(section: section).environmentObject(state), size: CGSize(width: 790, height: 640),
        to: destination.appendingPathComponent("layout-settings-" + section.lowercased().replacingOccurrences(of: " ", with: "-") + ".png"))
    }
    for section in ["Audio", "Privacy", "Shortcuts"] {
      try renderNative(SettingsView(section: section).environmentObject(state), size: CGSize(width: 1050, height: 1200),
        to: destination.appendingPathComponent("layout-tall-" + section.lowercased() + ".png"))
    }
    state.selectedMeetingID = nil
    try renderNative(MeetingsView().environmentObject(state).background(Palette.workspace), size: CGSize(width: 900, height: 720), to: destination.appendingPathComponent("layout-meetings.png"))
    try renderNative(NotebookView().environmentObject(state).background(Palette.workspace), size: CGSize(width: 900, height: 720), to: destination.appendingPathComponent("layout-notebook.png"))
    state.history = [DictationEntry(text: "We need to test the USB microphones before the next meeting.", original: "We need to test the USB microphones before the next meeting.", application: "Sample application", mode: CleanupMode.light.rawValue, audioDirectory: "")]
    try renderNative(DictationView().environmentObject(state).background(Palette.workspace), size: CGSize(width: 900, height: 720), to: destination.appendingPathComponent("layout-dictation.png"))
    state.personalization = [
      Personalization(kind: "dictionary", trigger: "Chup", replacement: "Chup!", language: "en"),
      Personalization(kind: "snippet", trigger: "my sign off", replacement: "Thanks, and speak soon.", language: "en"),
      Personalization(kind: "style", trigger: "com.apple.mail", replacement: "Friendly, concise and professional.", language: "en")
    ]
    for page in [WorkspacePage.dictionary, .snippets, .styles] {
      try renderNative(PersonalizationView(page: page).environmentObject(state).background(Palette.workspace), size: CGSize(width: 900, height: 720), to: destination.appendingPathComponent("layout-" + page.rawValue.lowercased() + ".png"))
    }
    state.selectedMeetingID = "preview-launch"
    for tab in ["Summary", "My notes", "Transcript", "Actions", "Private thoughts"] {
      try renderNative(MeetingDetailView(initialTab: tab).environmentObject(state).background(Palette.workspace), size: CGSize(width: 900, height: 760), to: destination.appendingPathComponent("layout-meeting-" + tab.lowercased().replacingOccurrences(of: " ", with: "-") + ".png"))
    }
    for step in 0..<5 {
      try renderNative(OnboardingView(step: step).environmentObject(state), size: CGSize(width: 950, height: 700), to: destination.appendingPathComponent("layout-onboarding-\(step).png"))
    }
    try renderNative(CaptureSetupView().environmentObject(state), size: CGSize(width: 560, height: 720), to: destination.appendingPathComponent("layout-capture.png"))
    try renderNative(BackupSettingsView().environmentObject(state), size: CGSize(width: 590, height: 650), to: destination.appendingPathComponent("layout-backup.png"))
    if let segment = state.segments.first {
      try renderNative(SegmentEditor(segment: segment).environmentObject(state), size: CGSize(width: 580, height: 650), to: destination.appendingPathComponent("layout-correction.png"))
    }
    try renderNative(AssistantView().environmentObject(state), size: CGSize(width: 620, height: 650), to: destination.appendingPathComponent("layout-assistant.png"))
    print("Native layout review exported: settings, library, meeting tabs, onboarding and sheets. Sample content only.")
  }
  /// Each tile needs its own state, so the board shows five simultaneous
  /// island states. Sample levels and text only; nothing is captured.
  private static func exportIslandBoard(destination: URL) throws {
    var states: [WorkspaceState] = []
    func stage(_ configure: (WorkspaceState) -> Void) -> WorkspaceState {
      let state = WorkspaceState(preview: true)
      states.append(state)
      configure(state)
      return state
    }
    defer { states.forEach { try? FileManager.default.removeItem(at: $0.root) } }
    let bars: [Float] = [0.42, 0.78, 0.55, 0.9, 0.36]
    let board = IslandDesignBoard(
      compact: stage {
        $0.dictationStatus = .listening
        $0.micWaveform = bars
        $0.dictationLiveText = "launch moves to the fourth"
      },
      listening: stage {
        $0.dictationStatus = .listening
        $0.micWaveform = bars
        $0.dictationLiveText = "launch moves to the fourth"
      },
      processing: stage { $0.dictationStatus = .processing },
      ready: stage { $0.dictationStatus = .idle },
      recording: stage {
        $0.meetingStatus = .recording
        $0.activeMeetingID = "preview-launch"
        $0.elapsed = 768
        $0.micWaveform = bars
      })
    try renderNative(board, size: CGSize(width: 1180, height: 1240),
      to: destination.appendingPathComponent("31-dynamic-island.png"))
    print("Island design board exported. Sample states only; no capture, no transcription.")
  }
  private static func renderNative<V: View>(_ view: V, size: CGSize, to url: URL) throws {
    let host = NSHostingView(
      rootView: view.environment(\.colorScheme, .light).tint(Palette.olive).frame(
        width: size.width, height: size.height))
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered,
      defer: false)
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = host
    window.setContentSize(size)
    window.orderFront(nil)
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    window.displayIfNeeded()
    if ProcessInfo.processInfo.environment["CHUP_SCROLL_REVIEW"] == "1" {
      func inspect(_ view: NSView) {
        if let scroll = view as? NSScrollView, let document = scroll.documentView {
          print("SCROLL \(url.lastPathComponent): viewport=\(scroll.contentSize.width) document=\(document.frame.width) horizontal=\(scroll.hasHorizontalScroller) type=\(type(of: document))")
        }
        view.subviews.forEach(inspect)
      }
      inspect(host)
    }
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
      throw WorkspaceError.message("Native bitmap failed.")
    }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
      throw WorkspaceError.message("Native PNG failed.")
    }
    try png.write(to: url)
    window.orderOut(nil)
  }
  /// Real native views animated with explicitly synthetic meter samples. No capture or global input.
  private static func exportCompactMotion(state: WorkspaceState, destination: URL) throws {
    state.railDock = "right"
    let frames = destination.appendingPathComponent("compact-frames")
    try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
    state.meetingStatus = .idle; state.voiceScope = nil; state.addressing = false
    state.dictationStatus = .idle; state.dictationFeedback = nil
    let size = CGSize(width: 640, height: 480)
    let host = NSHostingView(rootView: CompactMotionPreview(state: state).frame(width: size.width, height: size.height))
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host; window.setContentSize(size); window.orderFront(nil)
    defer { window.orderOut(nil) }
    for frame in 0..<80 {
      if frame == 10 { state.dictationReady = true; state.dictationStatus = .listening }
      if frame >= 10 && frame < 50 {
        let t = Double(frame - 10) * 0.1
        state.micWaveform = (0..<5).map { index in
          let envelope = frame >= 34 && frame < 40 ? 0.0 : 0.5 + 0.5 * sin(t * 5 + Double(index) * 0.7)
          return Float(envelope * (0.45 + 0.5 * abs(sin(t * 9 + Double(index)))))
        }
      }
      if frame == 50 { state.dictationStatus = .processing }
      if frame == 65 { state.dictationFeedback = .inserted; state.dictationStatus = .idle }
      if frame == 77 { state.dictationFeedback = nil }
      host.layoutSubtreeIfNeeded()
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
      window.displayIfNeeded()
      guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw WorkspaceError.message("Motion frame failed.") }
      host.cacheDisplay(in: host.bounds, to: bitmap)
      guard let png = bitmap.representation(using: .png, properties: [:]) else { throw WorkspaceError.message("Motion PNG failed.") }
      try png.write(to: frames.appendingPathComponent(String(format: "%03d.png", frame)))
    }
  }
  private static func render<V: View>(_ view: V, size: CGSize, to url: URL) throws {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = 1
    renderer.proposedSize = ProposedViewSize(size)
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
    else { throw WorkspaceError.message("Native view rendering failed.") }
    try png.write(to: url)
  }
}
struct DesignFrame<Content: View>: View {
  let title: String
  let subtitle: String
  @ViewBuilder let content: () -> Content
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        Text("CHUP!").font(.system(size: 11, weight: .semibold)).tracking(2)
        Spacer()
        Text(title).font(.system(size: 10, weight: .semibold)).tracking(1.6)
      }.foregroundStyle(Palette.secondary)
      VStack(spacing: 0) {
        HStack(spacing: 8) {
          Circle().fill(Color(red: 0.91, green: 0.43, blue: 0.39)).frame(width: 11, height: 11)
          Circle().fill(Color(red: 0.93, green: 0.74, blue: 0.35)).frame(width: 11, height: 11)
          Circle().fill(Color(red: 0.48, green: 0.69, blue: 0.42)).frame(width: 11, height: 11)
          Spacer()
          Text("Chup!").font(.system(size: 11)).foregroundStyle(Palette.secondary)
          Spacer()
          Text("DESIGN PREVIEW").font(.system(size: 8, weight: .semibold)).tracking(1)
            .foregroundStyle(Palette.secondary)
        }.padding(.horizontal, 20).frame(height: 38).background(Palette.sidebar)
        content()
      }.clipShape(RoundedRectangle(cornerRadius: 13)).overlay {
        RoundedRectangle(cornerRadius: 13).stroke(Palette.border, lineWidth: 1)
      }.shadow(color: .black.opacity(0.09), radius: 24, x: 0, y: 12)
      Text(subtitle).font(.system(size: 10)).foregroundStyle(Palette.secondary)
    }.padding(40).background(Palette.workspace)
  }
}
struct DesignSidebar: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 30) {
      HStack(spacing: 12) {
        WaveMark().scaleEffect(0.75).frame(width: 32)
        Text("Chup!").font(.system(size: 19, weight: .medium, design: .serif))
      }
      VStack(alignment: .leading, spacing: 5) {
        ForEach(WorkspacePage.allCases, id: \.self) { page in
          Label(page.rawValue, systemImage: page.icon).font(.system(size: 13)).padding(12).frame(
            maxWidth: .infinity, alignment: .leading
          ).background(
            page == .meetings ? Palette.paper : .clear, in: RoundedRectangle(cornerRadius: 8)
          ).foregroundStyle(page == .meetings ? Palette.ink : Palette.secondary)
        }
      }
      Spacer()
      Label("Saved on this Mac", systemImage: "lock.shield").font(.caption).foregroundStyle(
        Palette.secondary)
    }.padding(22).frame(width: 218).background(Palette.sidebar)
  }
}
struct PanelBoard: View {
  @ObservedObject var state: WorkspaceState
  private let columns = [
    GridItem(.fixed(352), spacing: 26), GridItem(.fixed(352), spacing: 26),
    GridItem(.fixed(352), spacing: 26),
  ]
  var body: some View {
    VStack(alignment: .leading, spacing: 30) {
      HStack {
        WaveMark(color: Palette.red)
        VStack(alignment: .leading, spacing: 6) {
          Text("Small moments. Thoughtfully handled.").font(.system(size: 34, design: .serif))
          Text("CHUP! / NOTIFICATIONS & FLOATING CONTROLS").font(
            .system(size: 10, weight: .semibold)
          ).tracking(1.8).foregroundStyle(Palette.secondary)
        }
        Spacer()
      }
      Text("Quiet by default. Clear when it matters. Every microphone action is yours.").font(
        .system(size: 15)
      ).foregroundStyle(Palette.secondary)
      LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
        panel(
          .callDetected, "01  MEETING DETECTED", "Dismisses after 10 seconds. Never auto-records.")
        panel(.browserDetected, "02  BROWSER CALL", "Cautious wording. App-wide scope is visible.")
        panel(.recording, "03  RECORDING", "A red icon and explicit status, not color alone.")
        panel(.paused, "04  PAUSED", "Recording pause is distinct from meeting mute.")
        panel(.dictating, "05  DICTATION", "Hold / release and Escape stay discoverable.")
        panel(.recovered, "06  INSERTION RECOVERY", "A changed field never receives surprise text.")
        panel(
          .privateAssistant, "07  PRIVATE ASSISTANT",
          "Private text, with a visible retrieval scope.")
        panel(.routeBlocked, "08  VOICE PRIVACY", "Explains the route problem and offers text.")
        VStack(alignment: .leading, spacing: 15) {
          Text("09  THE HOVER RAIL").font(.system(size: 9, weight: .semibold)).tracking(1.4)
            .foregroundStyle(Palette.secondary)
          HStack(spacing: 20) {
            RailContent(
              state: state, presentation: RailPresentation(), liveGlass: false,
              action: { _ in }, drag: {}
            ).frame(width: 30, height: 96)
            Image(systemName: "arrow.right").foregroundStyle(Palette.secondary)
            RailContent(
              state: state, presentation: RailPresentation(expanded: true),
              liveGlass: false, action: { _ in }, drag: {}
            ).frame(width: 56, height: 238)
          }
          Text("160 ms to expand · 450 ms to close\nHover never activates the microphone.").font(
            .system(size: 10)
          ).foregroundStyle(Palette.secondary).lineSpacing(3)
        }.frame(maxHeight: .infinity, alignment: .top)
      }
      Spacer(minLength: 0)
      HStack {
        Text("NATIVE SWIFTUI RENDERS · SAMPLE STATES, NOT LIVE ACTIVITY")
        Spacer()
        Text("CREAM / INK / OLIVE / SCANNER RED")
      }.font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(Palette.secondary)
    }.padding(52).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Palette.workspace).foregroundStyle(Palette.ink)
  }
  func panel(_ kind: NotificationCard.Kind, _ label: String, _ caption: String) -> some View {
    VStack(alignment: .leading, spacing: 13) {
      Text(label).font(.system(size: 9, weight: .semibold)).tracking(1.4).foregroundStyle(
        Palette.secondary)
      NotificationCard(
        kind: kind, appName: kind == .browserDetected ? "Chrome" : "Zoom",
        countdown: kind == .browserDetected ? 7 : 10, elapsed: "12:48"
      ).shadow(color: .black.opacity(0.045), radius: 9, x: 0, y: 5)
      Text(caption).font(.system(size: 10)).foregroundStyle(Palette.secondary)
    }.frame(maxHeight: .infinity, alignment: .top)
  }
}

struct RailDesignBoard: View {
  @ObservedObject var state: WorkspaceState
  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      Text("CHUP! / DARK GLASS CONTROLS").font(.system(size: 10, weight: .semibold))
        .tracking(1.8).foregroundStyle(Palette.secondary)
      Text("Warm paper. A darker edge.").font(.system(size: 38, design: .serif))
      Text("The workspace stays light. The independent rail and its drawers stay dark.")
        .foregroundStyle(Palette.secondary)
      HStack(alignment: .center, spacing: 56) {
        VStack(spacing: 22) {
          RailContent(
            state: state, presentation: RailPresentation(), liveGlass: false,
            action: { _ in }, drag: {}
          ).frame(width: 30, height: 96)
          Text("AT REST").font(.system(size: 9, weight: .semibold)).tracking(1.5)
        }.frame(width: 110)
        VStack(spacing: 22) {
          RailContent(
            state: state, presentation: RailPresentation(expanded: true),
            liveGlass: false, action: { _ in }, drag: {}
          ).frame(width: 56, height: 238)
            .overlay(alignment: .trailing) {
              RailOverlayLabel(title: "Assistant").offset(x: -65, y: 34)
            }
          Text("ICONS / HOVER LABELS").font(.system(size: 9, weight: .semibold)).tracking(1.5)
        }
        VStack(spacing: 22) {
          RailContent(
            state: state, presentation: RailPresentation(expanded: true, drawer: "Meeting"),
            liveGlass: false, action: { _ in }, drag: {}
          ).frame(width: 300, height: 230)
          Text("MEETING DRAWER").font(.system(size: 9, weight: .semibold)).tracking(1.5)
        }
        VStack(alignment: .leading, spacing: 18) {
          Text("A little life.").font(.system(size: 23, design: .serif))
          Text("240 ms expansion\n180 ms collapse\n120 ms hover feedback\n450 ms exit delay")
            .font(.system(size: 12)).lineSpacing(10)
          Text("Reduce Motion removes movement. Reduce Transparency uses solid charcoal.")
            .font(.system(size: 11)).lineSpacing(5)
        }.frame(width: 195).foregroundStyle(Palette.secondary)
      }.frame(maxWidth: .infinity, minHeight: 390)
      Divider()
      Text("NATIVE SWIFTUI · STATIC MATERIAL FALLBACK SHOWN · LIVE BACKDROP DEPENDS ON THE DESKTOP")
        .font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(Palette.secondary)
      Text("Open motion.html to try the animated speaking and interruption study.")
        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
    }.padding(48).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Palette.workspace).foregroundStyle(Palette.ink).environment(\.colorScheme, .light)
  }
}

/// Proposed: with the island on, the hover rail stays hidden and its controls
/// move into the island. Native views on a mocked desktop band.
struct IslandDesignBoard: View {
  @ObservedObject var compact: WorkspaceState
  @ObservedObject var listening: WorkspaceState
  @ObservedObject var processing: WorkspaceState
  @ObservedObject var ready: WorkspaceState
  @ObservedObject var recording: WorkspaceState
  var body: some View {
    VStack(alignment: .leading, spacing: 26) {
      Text("CHUP! / DYNAMIC ISLAND · PROPOSAL").font(.system(size: 10, weight: .semibold))
        .tracking(1.8).foregroundStyle(Palette.secondary)
      Text("One surface at the top, instead of two.").font(.system(size: 36, design: .serif))
      Text(
        "When the island is on, the edge rail stays hidden. Its voice animation, dictate, meeting, assistant and settings controls move under the notch."
      ).font(.system(size: 14)).foregroundStyle(Palette.secondary)
        .fixedSize(horizontal: false, vertical: true).frame(width: 760, alignment: .leading)
      row("01  COMPACT · LISTENING", "Glyph and live input level flank the notch. Nothing else is shown while you talk.") {
        IslandStage {
          IslandNotch(expanded: false) {
            HStack(spacing: 0) {
              IslandGlyph(state: compact, size: 18)
              Spacer(minLength: 150)
              VoiceWaveform(samples: compact.micWaveform, width: 20, height: 16, color: .white)
            }.padding(.horizontal, 14).frame(width: 300, height: 30)
          }
        }
      }
      row("02  EXPANDED · DICTATING", "Hover reveals Review before pasting. The transcript keeps the tail of the sentence visible.") {
        IslandStage { IslandNotch { DynamicIslandContent(state: listening, pinnedHover: true) } }
      }
      row("03  EXPANDED · TRANSCRIBING", "The spinner is the only claim made while text is still being produced.") {
        IslandStage { IslandNotch { DynamicIslandContent(state: processing, pinnedHover: false) } }
      }
      row("04  EXPANDED · CONTROLS", "Hovering when idle gives the old rail row: dictate, meeting, assistant, settings.") {
        IslandStage { IslandNotch { DynamicIslandContent(state: ready, pinnedHover: true) } }
      }
      row("05  EXPANDED · RECORDING", "A running meeting swaps in pause and stop, so capture is one click from control.") {
        IslandStage { IslandNotch { DynamicIslandContent(state: recording, pinnedHover: true) } }
      }
      Divider()
      Text(
        "TRADE-OFF · FULLY IDLE, NOTHING IS SHOWN. THE MENU BAR ITEM AND SHORTCUTS STAY THE IDLE ENTRY POINTS."
      ).font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(Palette.secondary)
      Text("NATIVE SWIFTUI · MOCKED DESKTOP BAND · SAMPLE LEVELS AND TEXT, NO CAPTURE")
        .font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(Palette.secondary)
    }.padding(48).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Palette.workspace).foregroundStyle(Palette.ink).environment(\.colorScheme, .light)
  }
  private func row<V: View>(_ label: String, _ caption: String, @ViewBuilder content: () -> V)
    -> some View
  {
    HStack(alignment: .center, spacing: 30) {
      content()
      VStack(alignment: .leading, spacing: 8) {
        Text(label).font(.system(size: 9, weight: .semibold)).tracking(1.4)
          .foregroundStyle(Palette.secondary)
        Text(caption).font(.system(size: 13)).lineSpacing(4)
          .fixedSize(horizontal: false, vertical: true).frame(width: 300, alignment: .leading)
      }
    }
  }
}

/// A mocked desktop strip. The real backdrop is whatever is behind the notch.
struct IslandStage<Content: View>: View {
  @ViewBuilder let content: () -> Content
  var body: some View {
    ZStack(alignment: .top) {
      LinearGradient(
        colors: [Color(red: 0.20, green: 0.24, blue: 0.29), Color(red: 0.36, green: 0.31, blue: 0.28)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
      content()
    }.frame(width: 640, height: 170).clipShape(RoundedRectangle(cornerRadius: 14))
  }
}

/// Menu bar plus the black notch body the package masks the content into.
struct IslandNotch<Content: View>: View {
  var expanded = true
  @ViewBuilder let content: () -> Content
  var body: some View {
    VStack(spacing: 0) {
      Color.black.frame(height: 24)
      content()
        .background(
          .black,
          in: UnevenRoundedRectangle(
            bottomLeadingRadius: expanded ? 24 : 12, bottomTrailingRadius: expanded ? 24 : 12,
            style: .continuous))
    }.environment(\.colorScheme, .dark)
  }
}

private struct CompactMotionPreview: View {
  @ObservedObject var state: WorkspaceState
  var body: some View {
    VStack(spacing: 26) {
      Text("CHUP!  /  QUIETER VOICE CONTROLS").font(.system(size: 11, weight: .semibold)).tracking(1.8)
      ZStack {
        if state.compactDictationVisible {
          DictationIndicatorView(state: state).scaleEffect(2)
        } else {
          RailContent(state: state, presentation: RailPresentation(), liveGlass: false,
            action: { _ in }, drag: {}).frame(width: 10, height: 36).scaleEffect(2)
        }
      }.frame(height: 310)
      Text("2× detail · native controls · illustrative microphone levels")
        .font(.system(size: 11)).foregroundStyle(RailPalette.secondary)
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
      .foregroundStyle(RailPalette.ink).background(Color(red: 0.06, green: 0.065, blue: 0.07))
  }
}

private struct PopupStylePreview: View {
  @ObservedObject var state: WorkspaceState
  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      Text("CHUP! / ONE QUIET VOICE").font(.system(size: 12, weight: .semibold)).tracking(2)
      Text("Charcoal glass. Cream controls. Smaller, calmer popups.")
        .font(.system(size: 25, design: .serif))
      HStack(alignment: .top, spacing: 28) {
        VStack(alignment: .leading, spacing: 16) {
          Text("HOVER CONTROLS").font(.system(size: 10, weight: .semibold)).tracking(1)
          HStack(alignment: .top, spacing: 10) {
            RailContent(state: state, presentation: RailPresentation(expanded: true), liveGlass: false,
              action: { _ in }, drag: {}).frame(width: 44, height: 188)
            RailOverlayLabel(title: "Dictate").padding(.top, 32)
          }
          RailContent(state: state, presentation: RailPresentation(expanded: true, drawer: "Meeting"),
            liveGlass: false, action: { _ in }, drag: {}).frame(width: 230, height: 190)
        }.frame(width: 240, alignment: .leading)
        VStack(spacing: 18) {
          NotificationCard(kind: .callDetected)
          NotificationCard(kind: .recovered)
        }
        VStack(spacing: 18) {
          NotificationCard(kind: .browserDetected, appName: "Browser")
          NotificationCard(kind: .routeBlocked)
        }
      }
      Text("Native views · illustrative notifications · no capture or actions")
        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
    }.padding(36).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .foregroundStyle(Palette.ink).background(Palette.workspace)
  }
}
