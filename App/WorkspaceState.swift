import AVFoundation
import AppKit
import Combine
import CryptoKit
import ChupCore

enum WorkspacePage: String, CaseIterable, Identifiable {
  case dictation = "Dictation"
  case meetings = "Meetings"
  case notebook = "Notebook"
  case dictionary = "Dictionary"
  case snippets = "Snippets"
  case styles = "Styles"
  case settings = "Settings"
  var id: String { rawValue }
  var icon: String {
    switch self {
    case .dictation: return "waveform"
    case .meetings: return "person.2"
    case .notebook: return "book.closed"
    case .dictionary: return "character.book.closed"
    case .snippets: return "text.insert"
    case .styles: return "textformat"
    case .settings: return "gearshape"
    }
  }
}

@MainActor final class WorkspaceState: ObservableObject {
  let runningBuild = RunningBuild()
  @Published var page: WorkspacePage = .meetings
  @Published var meetings: [Meeting] = []
  @Published var history: [DictationEntry] = []
  @Published var personalization: [Personalization] = []
  @Published var selectedMeetingID: String?
  @Published var segments: [TranscriptSegment] = []
  @Published var summary: MeetingSummary?
  @Published var liveOutline: SummaryRevision?
  @Published var summaryVersions: [SummaryRevision] = []
  @Published var summaryEdits: [SummaryItem] = []
  @Published var actions: [ActionRecord] = []
  @Published var lastActionReceipt: ActionReceipt?
  @Published var thoughts = Note()
  @Published var thoughtsDraft = ""
  @Published var meetingTab = "Summary"
  @Published var selectedTranscriptSource: String?
  @Published var usageRecords: [UsageRecord] = []
  @Published var liveOutlineEnabled = UserDefaults.standard.bool(forKey: "liveOutlineEnabled") {
    didSet { defaults.set(liveOutlineEnabled, forKey: "liveOutlineEnabled") }
  }
  @Published var autoSummaryEnabled =
    UserDefaults.standard.object(forKey: "autoSummaryEnabled") as? Bool ?? true
  { didSet { defaults.set(autoSummaryEnabled, forKey: "autoSummaryEnabled") } }
  var outlineTask: Task<Void, Never>?
  @Published var captureGaps: [CaptureGap] = []
  @Published var note = Note()
  @Published var noteDraft = ""
  @Published var dictationTraces: [DictationTrace] = []
  @Published var traceStorageFailed = false
  var traceOrigins: [String: Double] = [:]
  var dictationTraceID: String?
  @Published var notice: String?
  @Published var dynamicIslandEnabled = UserDefaults.standard.object(forKey: "dynamicIslandEnabled") as? Bool ?? true {
    didSet {
      defaults.set(dynamicIslandEnabled, forKey: "dynamicIslandEnabled")
      dynamicIsland?.refresh()
      rail?.refresh()
      updateDictationIndicator()
    }
  }
  @Published var dictationLiveText = "" { didSet { dynamicIsland?.refresh() } }
  @Published var deliveryDiagnostics: [DeliveryDiagnostic] = []
  var nextDeliveryTrigger = "Hold-to-dictate"
  @Published var dictationStatus: CaptureStatus = .idle {
    didSet { updateDictationErrorDismissal(); updateDictationIndicator() }
  }
  var dictationErrorDismissalTask: Task<Void, Never>?
  @Published var dictationMicMessage: String? { didSet { updateDictationIndicator() } }
  @Published var microphoneSettingsRequested = false
  @Published var activeMicrophone: InputDevice?
  @Published var microphonePreviewActive = false
  @Published var microphonePreviewStarting = false
  @Published var microphonePreviewMessage = "Speak to check your input. No audio is saved or sent."
  var microphonePreviewID: String?
  var microphonePreviewTask: Task<Void, Never>?
  var microphonePreviewStartedAt: Double?
  var microphoneSignal = MicrophoneSignalHealth()
  var microphoneMessageTask: Task<Void, Never>?
  @Published var dictationReady = false
  var dictationIndicatorUpdatePending = false
  @Published var dictationFeedback: TextDeliveryResult? { didSet { updateDictationIndicator() } }
  var dictationFeedbackTask: Task<Void, Never>?
  @Published var dictationPlaybackID: String?
  @Published var dictationPlaybackTime = 0.0
  @Published var dictationPlaybackDuration = 0.0
  @Published var dictationPlaying = false
  @Published var dictationPlaybackLoading = false
  var dictationAutoplay = false
  var dictationIndicator: DictationIndicatorController?
  var dynamicIsland: DynamicIslandController?
  @Published var meetingStatus: CaptureStatus = .idle { didSet { updateDictationIndicator() } }
  @Published var micLevel: Float = 0
  @Published var micWaveform: [Float] = Array(repeating: 0, count: 5)
  var micEnvelope = VoiceWaveformEnvelope()
  @Published var remoteLevel: Float = 0
  @Published var micLastPacket: Date?
  @Published var remoteLastPacket: Date?
  @Published var activeMeetingID: String?
  @Published var elapsed: Double = 0
  @Published var processingMeeting = false
  @Published var transcriptionProgress = ""
  @Published var transcriptReviews: [TranscriptReview] = []
  @Published var enrollments: [VoiceEnrollment] = []
  var transcriptionTask: Task<Void, Never>?
  @Published var assistantVisible = false
  @Published var assistantBusy = false
  @Published var assistantAnswer = ""
  @Published var assistantHistory: [AssistantExchange] = []
  @Published var assistantSources: [Evidence] = []
  @Published var pendingWrite: AssistantReply.ProposedWrite?
  @Published var playbackTime: Double = 0
  @Published var playing = false
  @Published var waveformBins: [WaveformBin] = []
  @Published var audioExportProgress: Double?
  var audioExportTask: Task<Void, Never>?
  @Published var playbackDuration: Double = 0
  @Published var playbackLoading = false
  @Published var cloudEnabled: Bool {
    didSet { defaults.set(cloudEnabled, forKey: "cloudEnabled") }
  }
  @Published var language: String { didSet { defaults.set(language, forKey: "language") } }
  @Published var transcriptionMode: DictationTranscriptionMode {
    didSet { defaults.set(transcriptionMode.rawValue, forKey: "transcriptionMode") }
  }
  @Published var cleanupMode: CleanupMode {
    didSet { defaults.set(cleanupMode.rawValue, forKey: "cleanupMode") }
  }
  @Published var backendURL: String { didSet { defaults.set(backendURL, forKey: "backendURL") } }
  @Published var captureFallback: Bool {
    didSet { defaults.set(captureFallback, forKey: "captureFallback") }
  }
  @Published var railDock: String {
    didSet {
      defaults.set(railDock, forKey: "railDock")
      rail?.relocate()
      updateDictationIndicator()
    }
  }
  @Published var showRail: Bool {
    didSet {
      defaults.set(showRail, forKey: "showRail")
      showRail ? rail?.show() : rail?.hide()
    }
  }
  @Published var liveCaptionsEnabled: Bool {
    didSet { defaults.set(liveCaptionsEnabled, forKey: "liveCaptionsEnabled") }
  }
  @Published var meetingDetectionEnabled: Bool {
    didSet { defaults.set(meetingDetectionEnabled, forKey: "meetingDetectionEnabled") }
  }
  @Published var selectedPID: Int32 = 0
  @Published var availableApps: [NSRunningApplication] = []
  @Published var lastReceipt: MutationReceipt?
  @Published var backendToken = ""
  let devices = AudioDevices()
  @Published var microphoneUID: String = UserDefaults.standard.string(forKey: "microphoneUID") ?? ""
  { didSet {
    defaults.set(microphoneUID, forKey: "microphoneUID")
    if meetingStatus == .paused { meetingMicrophone = nil }
  } }
  var meetingMicrophone: InputDevice?
  var meetingBundleID: String?
  var remoteGapID: String?
  var remoteGapStart: Double?
  let voice = LiveConversation()
  let voiceRouter = AssistantAudioRouter()
  @Published var voiceMode = AssistantMode.privateText
  @Published var addressing = false { didSet { updateDictationIndicator() } }
  @Published var voiceScope: VoiceTurnScope? { didSet { updateDictationIndicator() } }
  var privateVoiceGap: (String, String, Double)?
  var voiceObservers = Set<AnyCancellable>()
  var voiceOutput: VoiceOutputQueue?
  var voicePlaybackAllowed = false
  var voiceUsageScopes: [UUID: String] = [:]
  var voiceUsageID: String?
  var voiceConsumerID: String?
  var addressWhenReady = false
  var voiceSessionTask: Task<Void, Never>?
  var voiceCaptureTask: Task<Void, Never>?
  var voiceIdleTask: Task<Void, Never>?
  var voiceContinuation: AsyncStream<AudioPacket>.Continuation?
  var routeContinuation: AsyncStream<AudioPacket>.Continuation?
  var routeFeed: Task<Void, Never>?
  var delegationTasks: [String: Task<Void, Never>] = [:]
  let setup = MacSetupService()
  @Published var onboardingVisible = false
  @Published var durableRequests: [DurableRequest] = []
  @Published var providerUsage: [ProviderUsage] = []
  @Published var storageBusy = false
  @Published var storageMessage: String?
  @Published var retention = RetentionPolicy()
  @Published var backupSheet = false
  var lastPrivacyCleanup = Date.distantPast
  var privacyMaintenanceTask: Task<Void, Never>?
  let shortcuts: ShortcutRegistry
  let insertion = TextInsertion()
  let root: URL
  let workspaceKeySuffix: String
  let defaults: UserDefaults
  var store: WorkspaceStore?
  var key: SymmetricKey?
  var audio: AudioOwner?
  var rail: HoverRailController?
  var detector: MeetingDetector?
  var liveStreams: [TrackKind: LiveTranscription] = [:]
  var liveFeed: Task<Void, Never>?
  var liveContinuation: AsyncStream<(TrackKind, AudioPacket)>.Continuation?
  var dictationDirectory: URL?
  var dictationConsumerID: String?
  var destination: TextInsertion.Destination?
  var editingSelection = false
  var captureTask: Task<Void, Never>?
  var liveDictationPackets: [AudioPacket] = []
  var liveDictationLastRun = 0.0
  var liveDictationBusy = false
  var liveDictationTask: Task<Void, Never>?
  var recordingEntry: DictationEntry?
  var dictationTask: Task<Void, Never>?
  var queuedDictationTargets: [String: QueuedDictationTarget] = [:]
  @Published var pendingDictations = 0
  lazy var dictationQueue: OrderedWorkQueue = {
    let queue = OrderedWorkQueue()
    queue.onChange = { [weak self] count in
      guard let self else { return }
      self.pendingDictations = count
      if self.dictationStatus != .listening {
        if count > 0 { self.dictationStatus = .processing }
        else if self.dictationStatus == .processing { self.dictationStatus = .idle }
      }
    }
    return queue
  }()
  var dictationGeneration = UUID()
  @Published var dictationReviewRequested = false
  @Published var dictationReviewActive = false
  @Published var dictationReviewText = ""
  var dictationReviewSeed = ""
  var dictationReviewSelection = NSRange(location: 0, length: 0)
  var dictationReviewAppendRequested = false
  var dictationReviewEntryID: String?
  var dictationReviewApproved = false
  var dictationReviewController: DictationReviewController?
  var meetingStarted: ContinuousClock.Instant?
  var meetingBaseElapsed: Double = 0
  var meetingTask: Task<Void, Never>?
  var meetingConsumerID: String?
  var captureStartedAt: Date?
  var hostOrigin: Double = 0
  var meetingPID: Int32 = 0
  var pausedAt: Double?
  var currentGapID: String?
  var currentGapReason = "Recording paused"
  var activeLeg: RecordingLeg?
  var timer: Timer?
  var observers: [NSObjectProtocol] = []
  let playback = MeetingPlayback()
  let dictationPlayback = MeetingPlayback(track: .microphone)
  let localSpeech = LocalSpeechService()
  let transcriptionLab = TranscriptionLab()
  var assistantTask: Task<Void, Never>?
  var assistantRequest: (meeting: String, id: String)?
  var pendingExchangeID: String?
  var pendingWriteScope: (String, Int, String)?
  var reveal: (() -> Void)?
  let isPreview: Bool
  init(preview: Bool = false) {
    defaults = preview ? UserDefaults(suiteName: "com.chup.preview." + UUID().uuidString)! : .standard
    shortcuts = ShortcutRegistry(defaults: preview ? nil : .standard)
    isPreview = preview
    let d = defaults
    workspaceKeySuffix = preview ? "" : (d.string(forKey: "workspaceKeySuffix") ?? "")
    liveCaptionsEnabled = d.bool(forKey: "liveCaptionsEnabled")
    meetingDetectionEnabled = d.object(forKey: "meetingDetectionEnabled") as? Bool ?? true
    cloudEnabled = d.bool(forKey: "cloudEnabled")
    language = d.string(forKey: "language") ?? "en"
    transcriptionMode = DictationTranscriptionMode(rawValue: d.string(forKey: "transcriptionMode") ?? "") ?? .automatic
    cleanupMode = CleanupMode(rawValue: d.string(forKey: "cleanupMode") ?? "") ?? .light
    backendURL = d.string(forKey: "backendURL") ?? "http://127.0.0.1:8787"
    captureFallback = d.bool(forKey: "captureFallback")
    railDock = d.string(forKey: "railDock") ?? "right"
    showRail = d.object(forKey: "showRail") as? Bool ?? true
    root =
      preview
      ? FileManager.default.temporaryDirectory.appendingPathComponent(
        "Chup-Design-" + UUID().uuidString)
      : d.string(forKey: "workspaceRootOverride").map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Chup", isDirectory: true)
    do {
      let databaseURL = root.appendingPathComponent("workspace.sqlite")
      let existingHeader = FileManager.default.fileExists(atPath: databaseURL.path)
        ? try FileHandle(forReadingFrom: databaseURL) : nil
      let header = try existingHeader?.read(upToCount: 16)
      try existingHeader?.close()
      let encryptedExisting = header != nil && header != Data("SQLite format 3\0".utf8)
      let databaseKey =
        preview
        ? SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        : try KeyVault.databaseKey(
          existing: encryptedExisting, account: "database-key" + workspaceKeySuffix)
      store = try WorkspaceStore(url: databaseURL, key: databaseKey)
      let hasAudio =
        FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.compactMap {
          $0 as? URL
        }.contains { $0.pathExtension == "vwj" || $0.path.contains("/VoiceReferences/") } ?? false
      key =
        preview
        ? SymmetricKey(size: .bits256)
        : try KeyVault.audioKey(existing: hasAudio, account: "audio-key" + workspaceKeySuffix)
      audio = AudioOwner(key: key!)
      if !preview {
        backendToken =
          String(data: try KeyVault.read(account: "backend-token") ?? Data(), encoding: .utf8) ?? ""
      }
      try db().indexLegacyQuestions(root: root)
      try db().recoverRequests()
      try refreshPrivacy()
      try refresh()
      for var exchange in try db().list(AssistantExchange.self, kind: "assistantExchange")
      where exchange.status == "pending" {
        exchange.status = "interrupted"
        exchange.answer = "The app closed before this answer finished. Ask again when ready."
        try db().put(
          exchange, kind: "assistantExchange", id: exchange.id, parent: exchange.meetingID)
      }
      for var entry in history where entry.status == "recording" {
        entry.status = "interrupted"
        try db().put(entry, kind: "dictation", id: entry.id, searchable: entry.text)
      }
      // Active capture cannot survive process termination; never resume microphone automatically.
      for var meeting in meetings where ["Recording", "Paused"].contains(meeting.status) {
        meeting.status = "Recovered — capture interrupted"
        try saveMeeting(meeting)
        let recoveredID = meeting.id
        if let key {
          Task {
            do {
              let report = try await RecordingRecovery().inspect(
                meetingID: recoveredID,
                legs: db().list(RecordingLeg.self, kind: "leg", parent: recoveredID), key: key)
              try db().put(report, kind: "recovery", id: recoveredID, parent: recoveredID)
              try db().put(
                CaptureGap(
                  start: report.duration, end: nil,
                  reason: "Capture interrupted at shutdown; restart interval unknown"),
                kind: "gap", id: "crash/" + recoveredID, parent: recoveredID)
              if selectedMeetingID == recoveredID { try refreshDetail() }
            } catch { notice = error.localizedDescription }
          }
        }
      }
    } catch { notice = "Workspace setup failed: \(error.localizedDescription)" }
    playback.onChange = { [weak self] time, duration, running, loading in
      self?.playbackTime = time
      self?.playbackDuration = duration
      self?.playing = running
      self?.playbackLoading = loading
    }
    playback.onWaveform = { [weak self] in self?.waveformBins = $0 }
    playback.onFailure = { [weak self] in self?.notice = $0 }
    configureDictationPlayback()
    if preview { return }
    // Warm the installed local model as soon as the app state is created. This
    // moves tokenizer/Core ML setup ahead of the first shortcut without opening
    // a microphone or blocking the workspace UI.
    localSpeech.checkInstalled()
    configureVoice()
    setup.onRefresh = { [weak self] in self?.shortcuts.enable(request: false) }
    onboardingVisible = !defaults.bool(forKey: "onboardingCompleted")
    voice.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(
      in: &voiceObservers)
    voiceRouter.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(
      in: &voiceObservers)
    shortcuts.dispatch = { [weak self] signal in self?.handle(signal) }
    shortcuts.onUserInteraction = { [weak self] in self?.insertion.noteUserInteraction() }
    insertion.interactionMonitoringAvailable = { [weak self] in self?.shortcuts.monitorsGlobalInput == true }
    audio?.onFailure = { [weak self] message in Task { @MainActor in self?.captureFailed(message) }
    }
    audio?.onRemoteFailure = { [weak self] message in
      Task { @MainActor in self?.remoteFailed(message) }
    }
    audio?.onGap = { [weak self] consumer, track, gap in
      Task { @MainActor in
        guard let self, let id = self.activeMeetingID, consumer == self.meetingConsumerID else {
          return
        }
        do {
          try self.db().put(
            CaptureGap(
              start: max(0, gap.start - self.hostOrigin),
              end: max(0, gap.end - self.hostOrigin), reason: gap.reason, track: track),
            kind: "gap", id: UUID().uuidString, parent: id)
          if self.selectedMeetingID == id { try self.refreshDetail() }
        } catch { self.notice = error.localizedDescription }
      }
    }
    devices.onChange = { [weak self] in self?.microphoneEnvironmentChanged() }
    audio?.onWaveform = { [weak self] bands, _ in
      Task { @MainActor in
        self?.micWaveform = bands
        self?.micLastPacket = Date()
      }
    }
    audio?.onLevel = { [weak self] track, level, _ in
      Task { @MainActor in
        if track == .microphone {
          if self?.dictationStatus == .listening { self?.markTrace(self?.dictationTraceID, .firstAudio) }
          self?.microphoneSignal.receive(peak: level, at: ProcessInfo.processInfo.systemUptime)
          self?.micLevel = level
          self?.micLastPacket = Date()
        }
        if track == .remote {
          self?.remoteLevel = level
          self?.remoteLastPacket = Date()
          self?.closeRemoteGap()
        }
      }
    }
    timer = MainActorTimer.repeating(every: 0.25) { [weak self] in self?.tick() }
    let center = NSWorkspace.shared.notificationCenter
    observers.append(
      center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
        [weak self] _ in
        DispatchQueue.main.async {
          self?.transcriptionLab.cancel()
          self?.stopMicrophonePreview()
          self?.endVoice()
          self?.stopAssistantRoute()
          self?.cancelDictation()
          self?.stopPlayback()
          self?.stopDictationPlayback()
          self?.shortcuts.reset()
          if self?.meetingStatus == .processing {
            self?.stopMeeting()
          } else {
            self?.pauseMeeting(reason: "Mac asleep — no audio captured")
          }
        }
      })
    observers.append(
      center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
        [weak self] _ in
        DispatchQueue.main.async {
          self?.notice = "Mac awake. Resume the meeting when you are ready; sleep was not recorded."
          self?.shortcuts.reset()
        }
      })
    observers.append(
      NotificationCenter.default.addObserver(
        // Never make the engine's notification queue wait for the main thread:
        // engine teardown on main can itself be waiting for that queue.
        forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil
      ) { [weak self] notification in
        DispatchQueue.main.async {
          guard let self, self.audio?.ownsEngine(notification.object) == true,
            self.audio?.microphoneStarting != true,
            self.audio?.microphoneConfigurationValid != true,
            self.meetingStatus == .recording || self.dictationStatus == .listening || self.microphonePreviewActive
          else { return }
          self.stopForMicrophoneIssue(
            "Microphone capture was interrupted. Audio is saved; check the input and start again."
          )
        }
      })
  }
  func focusRail() {
    if rail == nil { rail = HoverRailController(state: self) }
    rail?.focusControls()
  }
  func startShell() {
    guard !isPreview else { return }
    localSpeech.checkInstalled()
    if detector == nil { detector = MeetingDetector(state: self) }
    if rail == nil { rail = HoverRailController(state: self) }
    if dynamicIsland == nil { dynamicIsland = DynamicIslandController(state: self) }
    if dictationReviewController == nil { dictationReviewController = DictationReviewController(state: self) }
    dynamicIsland?.refresh()
    if showRail { rail?.show() }
    shortcuts.enable(request: false)
  }
  var activeMeeting: Meeting? { meetings.first { $0.id == activeMeetingID } }
  var selectedMeeting: Meeting? { meetings.first { $0.id == selectedMeetingID } }
  var statusText: String {
    if microphonePreviewBusy { return "Testing microphone · " + microphoneLabel }
    if voiceScope?.mode == .broadcast {
      return (voiceRouter.level > 0 ? "Assistant speaking in meeting" : "Broadcast armed")
        + " · Recording \(Self.time(elapsed))"
    }
    if voiceRouter.privateInput { return "Private voice · Call microphone muted" }
    if voiceScope != nil { return addressing ? "Listening to your question" : voice.status }
    if meetingStatus == .recording { return "Recording · \(Self.time(elapsed))" }
    if meetingStatus == .paused { return "Recording paused" }
    if activeMeetingID != nil && meetingStatus == .processing { return "Starting capture…" }
    switch dictationStatus {
    case .listening: return "Listening"
    case .processing: return "Processing dictation"
    case .error: return "Needs attention"
    default: return "Ready when you are"
    }
  }
  static func time(_ seconds: Double) -> String {
    let n = max(0, Int(seconds))
    return String(format: "%02d:%02d", n / 60, n % 60)
  }
  func tick() {
    checkDictationMicrophone()
    checkMicrophonePreview()
    if let last = micLastPacket, Date().timeIntervalSince(last) > 0.35,
      micWaveform.contains(where: { $0 != 0 }) {
      micEnvelope.reset()
      micWaveform = micEnvelope.bars
    }
    if !isPreview, Date().timeIntervalSince(lastPrivacyCleanup) > 3600, privacyWorkAllowed {
      lastPrivacyCleanup = Date()
      runRetention()
    }
    if let meetingStarted, activeMeetingID != nil {
      let duration = meetingStarted.duration(to: .now)
      elapsed =
        meetingBaseElapsed + Double(duration.components.seconds) + Double(
          duration.components.attoseconds) / 1e18
    }
    playback.tick()
    dictationPlayback.tick()
    if meetingStatus == .recording, let started = captureStartedAt,
      Date().timeIntervalSince(started) > 6
    {
      if Date().timeIntervalSince(micLastPacket ?? started) > 5 {
        captureFailed("Microphone packets stopped. Recording paused; source-loss gap marked.")
      }
      if meetingPID != 0, Date().timeIntervalSince(remoteLastPacket ?? started) > 8 {
        remoteFailed(
          "Call audio packets stopped. Microphone recording continues; reconnect call audio.")
      }
    }
  }
  func saveToken() {
    do {
      try KeyVault.write(Data(backendToken.utf8), account: "backend-token")
      notice = "Backend token saved to Keychain."
    } catch { notice = error.localizedDescription }
  }
  func backend(scope: String? = nil, associationID: String? = nil) throws -> BackendClient {
    guard cloudEnabled else {
      throw WorkspaceError.message(
        "Cloud processing is off. Enable it in Privacy to transcribe or ask AI; audio and notes remain saved locally."
      )
    }
    guard let url = URL(string: backendURL), !backendToken.isEmpty else {
      throw WorkspaceError.message(
        "Configure your trusted backend URL and app token in Advanced settings.")
    }
    return BackendClient(
      baseURL: url, token: backendToken, store: store,
      scope: scope ?? selectedMeetingID ?? "workspace", associationID: associationID,
      onChange: { [weak self] in try? self?.refreshPrivacy() })
  }
  func db() throws -> WorkspaceStore {
    guard let store else { throw WorkspaceError.message("Workspace storage is unavailable.") }
    return store
  }
  func refresh() throws {
    dictationTraces = try db().list(DictationTrace.self, kind: "dictationTrace").sorted { $0.created > $1.created }
    for index in dictationTraces.indices where dictationTraces[index].outcome == .running && traceOrigins[dictationTraces[index].id] == nil {
      dictationTraces[index].outcome = .interrupted
      try db().put(dictationTraces[index], kind: "dictationTrace", id: dictationTraces[index].id)
    }
    enrollments = try db().list(VoiceEnrollment.self, kind: "enrollment")
    let db = try db()
    meetings = try db.list(Meeting.self, kind: "meeting").sorted { $0.created > $1.created }
    history = try db.list(DictationEntry.self, kind: "dictation").sorted { $0.created > $1.created }
    personalization = try db.list(Personalization.self, kind: "personalization").sorted {
      $0.trigger < $1.trigger
    }
  }
  func refreshApps() {
    availableApps = NSWorkspace.shared.runningApplications.filter {
      $0.activationPolicy == .regular
        && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
  }
  func saveMeeting(_ meeting: Meeting) throws {
    try db().put(
      meeting, kind: "meeting", id: meeting.id,
      searchable: "\(meeting.title) \(meeting.participants) \(meeting.tags)")
    try refresh()
  }
  func newMeeting() {
    let meeting = Meeting(title: "Untitled meeting")
    do {
      try saveMeeting(meeting)
      selectMeeting(meeting.id)
      page = .meetings
    } catch { notice = error.localizedDescription }
  }
  func leaveMeeting() {
    cancelAssistant()
    playback.reset()
    pendingWrite = nil
    pendingWriteScope = nil
    pendingExchangeID = nil
    selectedMeetingID = nil
    assistantHistory = []
  }
  func selectMeeting(_ id: String) {
    endVoice()
    playback.reset()
    cancelAssistant()
    selectedMeetingID = id
    pendingWrite = nil
    pendingWriteScope = nil
    assistantAnswer = ""
    assistantSources = []
    pendingExchangeID = nil
    lastReceipt = nil
    lastActionReceipt = nil
    do {
      note = try db().note(id)
      noteDraft = note.text
      try refreshDetail()
      preparePlayback()
    } catch { notice = error.localizedDescription }
  }
  func refreshDetail() throws {
    guard let id = selectedMeetingID else { return }
    liveOutline = try db().list(SummaryRevision.self, kind: "liveOutline", parent: id).last
    summaryVersions = try db().list(SummaryRevision.self, kind: "summaryVersion", parent: id)
    summaryEdits = try db().list(SummaryItem.self, kind: "summaryEdit", parent: id)
    actions = try db().list(ActionRecord.self, kind: "action", parent: id)
    thoughts = try db().note("private-thoughts/" + id)
    thoughtsDraft = thoughts.text
    usageRecords = try db().list(UsageRecord.self, kind: "usage").sorted { $0.started > $1.started }
    segments = try db().list(TranscriptSegment.self, kind: "segment", parent: id).sorted {
      $0.start < $1.start
    }
    transcriptReviews = try db().list(TranscriptReview.self, kind: "transcriptReview", parent: id)
    enrollments = try db().list(VoiceEnrollment.self, kind: "enrollment")
    captureGaps = try db().list(CaptureGap.self, kind: "gap", parent: id).sorted {
      $0.start < $1.start
    }
    assistantHistory = try db().list(AssistantExchange.self, kind: "assistantExchange", parent: id)
      .sorted { $0.created < $1.created }
    summary = try db().list(MeetingSummary.self, kind: "summary", parent: id).last
    if let summary,
      (try? EvidenceValidator.validate(summary, meetingID: id, segments: segments)) == nil
    {
      self.summary = nil
    }
  }
  func saveNote(_ text: String) {
    guard let id = selectedMeetingID, text != note.text else { return }
    do {
      lastReceipt = try db().writeNote(
        meetingID: id, text: text, expectedVersion: note.version, requestID: UUID().uuidString)
      note = lastReceipt!.after
    } catch { notice = "Note not saved: \(error.localizedDescription)" }
  }
  func undoNote() {
    guard let lastReceipt else { return }
    do {
      let receipt = try db().undo(lastReceipt)
      note = receipt.after
      noteDraft = note.text
      self.lastReceipt = nil
    } catch { notice = error.localizedDescription }
  }
  func renameMeeting(_ title: String, participants: String, tags: String) {
    guard var meeting = selectedMeeting else { return }
    meeting.title = title
    meeting.participants = participants
    meeting.tags = tags
    do { try saveMeeting(meeting) } catch { notice = error.localizedDescription }
  }
  func startMeeting() {
    transcriptionLab.cancel()
    stopMicrophonePreview()
    stopDictationPlayback()
    endVoice()
    audio?.setPrivateAddress(false)
    if activeMeetingID != nil {
      if let activeMeetingID { selectMeeting(activeMeetingID) }
      page = .meetings
      reveal?()
      return
    }
    if selectedMeetingID == nil { newMeeting() }
    guard let id = selectedMeetingID else { return }
    playback.reset()
    meetingPID = selectedPID
    meetingBundleID = NSRunningApplication(processIdentifier: selectedPID)?.bundleIdentifier
    meetingMicrophone = nil
    remoteGapID = nil
    remoteGapStart = nil
    activeMeetingID = id
    meetingStatus = .processing
    elapsed = 0
    meetingBaseElapsed = 0
    meetingTask = Task {
      guard await AVCaptureDevice.requestAccess(for: .audio) else {
        if activeMeetingID == id {
          activeMeetingID = nil
          meetingStatus = .idle
          notice = "Microphone access is required to start recording."
        }
        return
      }
      guard activeMeetingID == id, !Task.isCancelled else { return }
      do {
        if let key {
          let recovered = try await RecordingRecovery().inspect(
            meetingID: id, legs: db().list(RecordingLeg.self, kind: "leg", parent: id), key: key)
          guard !Task.isCancelled else { return }
          meetingBaseElapsed = recovered.duration
          elapsed = recovered.duration
        }
      } catch {
        notice = error.localizedDescription
        stopMeeting()
        return
      }
      meetingStarted = .now
      hostOrigin = ProcessInfo.processInfo.systemUptime
      await beginLeg(id: id)
    }
  }
  func beginLeg(id: String) async {
    guard let audio else {
      notice = "Audio storage is unavailable."
      activeMeetingID = nil
      return
    }
    hostOrigin = ProcessInfo.processInfo.systemUptime - elapsed
    let directory = root.appendingPathComponent("Recordings/\(id)/\(UUID().uuidString)")
    let consumerID = "meeting:\(id)/\(UUID().uuidString)"
    meetingConsumerID = consumerID
    do {
      try Task.checkCancellation()
      let device = try devices.resolve(meetingMicrophone?.id ?? microphoneUID)
      meetingMicrophone = device
      activeMicrophone = device
      if meetingPID != 0 {
        guard let app = NSRunningApplication(processIdentifier: meetingPID), !app.isTerminated,
          app.bundleIdentifier == meetingBundleID
        else {
          throw WorkspaceError.message(
            "The selected call app exited. Stop this recording and select the reopened app; another process will not be captured automatically."
          )
        }
      }
      let leg = RecordingLeg(
        meetingID: id, directory: directory.path, offset: elapsed,
        hostStart: hostOrigin + elapsed, microphoneUID: device.id, processBundleID: meetingBundleID)
      try db().put(leg, kind: "leg", id: leg.id, parent: id)
      activeLeg = leg
      captureStartedAt = Date()
      micLastPacket = nil
      remoteLastPacket = nil
      try await audio.addConsumer(
        id: consumerID, directory: directory,
        tracks: meetingPID == 0 ? [.microphone, .assistant] : [.microphone, .remote, .assistant],
        device: device)
      try Task.checkCancellation()
      if meetingPID != 0 { try await audio.startRemote(pid: meetingPID, fallback: captureFallback) }
      guard activeMeetingID == id, !Task.isCancelled else {
        try audio.removeConsumer(id: consumerID)
        return
      }
      meetingStatus = .recording
      if meetingPID != 0 { setup.lastAudioCapture = Date() }
      if cloudEnabled && liveCaptionsEnabled { await startLiveCaptions(meetingID: id) }
      guard activeMeetingID == id, !Task.isCancelled else { return }
      if var meeting = meetings.first(where: { $0.id == id }) {
        meeting.status = "Recording"
        try saveMeeting(meeting)
      }
      if let start = pausedAt {
        let gap = CaptureGap(start: start, end: elapsed, reason: currentGapReason)
        try db().put(gap, kind: "gap", id: currentGapID ?? UUID().uuidString, parent: id)
        pausedAt = nil
        currentGapID = nil
      }
      notice = "Recording locally. Let participants know. Pause does not mute you in the call."
    } catch {
      try? audio.removeConsumer(id: consumerID)
      guard activeMeetingID == id, !Task.isCancelled else { return }
      audio.stopRemote()
      meetingStatus = .paused
      pausedAt = elapsed
      notice = "Capture could not start: \(error.localizedDescription)"
      if error is MicrophoneSelectionError { showMicrophoneMessage(error.localizedDescription) }
    }
  }
  func pauseMeeting(reason: String = "Recording paused by you") {
    guard meetingStatus == .recording, let id = activeMeetingID else { return }
    stopAssistantRoute()
    defer { audio?.stopRemote() }
    do {
      closeRemoteGap()
      stopLiveCaptions()
      if let meetingConsumerID { try audio?.removeConsumer(id: meetingConsumerID) }
      audio?.stopRemote()
      meetingStatus = .paused
      pausedAt = elapsed
      currentGapID = UUID().uuidString
      currentGapReason = reason
      try db().put(
        CaptureGap(start: elapsed, end: nil, reason: reason), kind: "gap", id: currentGapID!,
        parent: id)
      if selectedMeetingID == id { try refreshDetail() }
      if var meeting = activeMeeting {
        meeting.status = "Paused"
        try saveMeeting(meeting)
      }
    } catch {
      notice = error.localizedDescription
      meetingStatus = .error
    }
  }
  func resumeMeeting() {
    stopMicrophonePreview()
    guard let id = activeMeetingID, meetingStatus == .paused else { return }
    meetingStatus = .processing
    meetingTask = Task { await beginLeg(id: id) }
  }
  func stopMeeting() {
    guard let id = activeMeetingID else { return }
    meetingTask?.cancel()
    stopAssistantRoute()
    defer { audio?.stopRemote() }
    do {
      closeRemoteGap()
      stopLiveCaptions()
      if let meetingConsumerID { try audio?.removeConsumer(id: meetingConsumerID) }
      audio?.stopRemote()
      if var meeting = activeMeeting {
        meeting.status = "Audio saved"
        try saveMeeting(meeting)
      }
      if let start = pausedAt {
        try db().put(
          CaptureGap(start: start, end: elapsed, reason: currentGapReason), kind: "gap",
          id: currentGapID ?? UUID().uuidString, parent: id)
        pausedAt = nil
        currentGapID = nil
      }
      activeMeetingID = nil
      meetingStatus = .idle
      meetingStarted = nil
      activeLeg = nil
      notice = "Audio saved on this Mac. Transcribe when you are ready."
      if selectedMeetingID == id {
        try refreshDetail()
        preparePlayback()
      }
    } catch {
      notice = error.localizedDescription
      meetingStatus = .error
      meetingStarted = nil
    }
  }
  func remoteFailed(_ message: String) {
    guard let id = activeMeetingID, meetingStatus == .recording, remoteGapID == nil else { return }
    audio?.stopRemote()
    remoteGapID = UUID().uuidString
    remoteGapStart = elapsed
    do {
      try db().put(
        CaptureGap(start: elapsed, end: nil, reason: message, track: .remote),
        kind: "gap", id: remoteGapID!, parent: id)
      if selectedMeetingID == id { try refreshDetail() }
    } catch { notice = error.localizedDescription }
    notice = message
  }
  func closeRemoteGap() {
    guard let id = activeMeetingID, let gapID = remoteGapID, let start = remoteGapStart else {
      return
    }
    do {
      try db().put(
        CaptureGap(
          start: start, end: elapsed, reason: "Call audio source disconnected", track: .remote),
        kind: "gap", id: gapID, parent: id)
      remoteGapID = nil
      remoteGapStart = nil
      if selectedMeetingID == id { try refreshDetail() }
    } catch { notice = error.localizedDescription }
  }
  func reconnectCallAudio() {
    guard activeMeetingID != nil, meetingStatus == .recording, meetingPID != 0 else { return }
    Task {
      do {
        guard let app = NSRunningApplication(processIdentifier: meetingPID), !app.isTerminated,
          app.bundleIdentifier == meetingBundleID
        else { throw WorkspaceError.message("Reselect the reopened call app in a new recording.") }
        audio?.stopRemote()
        try await audio?.startRemote(pid: meetingPID, fallback: captureFallback)
        notice = "Waiting for call audio packets. The capture gap stays open until audio arrives."
      } catch { notice = error.localizedDescription }
    }
  }
  func inspectRecording() {
    guard let id = selectedMeetingID, id != activeMeetingID, let key else { return }
    Task {
      do {
        let report = try await RecordingRecovery().inspect(
          meetingID: id,
          legs: db().list(RecordingLeg.self, kind: "leg", parent: id), key: key)
        try db().put(report, kind: "recovery", id: id, parent: id)
        notice =
          "Recovered \(report.completePackets) authenticated packets through \(Self.time(report.duration)). \(report.truncatedFiles.count) incomplete tails; \(report.corruptFiles.count) unreadable files. Capture did not restart."
      } catch { notice = error.localizedDescription }
    }
  }
  func captureFailed(_ message: String) {
    if dictationStatus == .listening { finishTrace(dictationTraceID, .failed) }
    stopMicrophonePreview(message: message)
    endVoice()
    stopAssistantRoute()
    if meetingStatus == .processing { stopMeeting() }
    pauseMeeting(reason: message)
    if dictationStatus == .listening { cancelDictation() }
    notice = message
  }
  func beginDictation(editSelection: Bool = false, captured: TextInsertion.Destination? = nil, useCaptured: Bool = false) {
    guard dictationStatus != .listening,
      dictationStatus != .processing || pendingDictations > 0 else { return }
    transcriptionLab.cancel()
    let traceID = startDictationTrace()
    if dictationReviewActive {
      destination = nil
      dictationReviewAppendRequested = true
    } else {
      destination = useCaptured ? captured : insertion.capture()
      dictationReviewAppendRequested = false
    }
    nextDeliveryTrigger = editSelection ? "Selected-text shortcut" : "Hold-to-dictate"
    stopMicrophonePreview()
    clearDictationFeedback()
    clearMicrophoneMessage()
    dictationLiveText = ""
    liveDictationPackets = []
    liveDictationLastRun = 0
    liveDictationBusy = false
    let input: InputDevice
    do { input = try devices.resolve(audio?.microphoneUID ?? microphoneUID) }
    catch { finishTrace(traceID, .failed); showMicrophoneMessage(error.localizedDescription); return }
    activeMicrophone = input
    stopDictationPlayback()
    stopPlayback()
    dictationReady = false
    micLevel = 0
    micEnvelope.reset()
    micWaveform = micEnvelope.bars
    micLastPacket = nil
    editingSelection = editSelection
    if editSelection && (destination?.selectedText.isEmpty ?? true) {
      finishTrace(traceID, .failed)
      notice = "Select editable text in another app first, then hold the selected-text shortcut."
      return
    }
    let generation = UUID()
    dictationGeneration = generation
    let consumerID = "dictation:" + generation.uuidString
    dictationConsumerID = consumerID
    let directory = root.appendingPathComponent("Dictations/\(UUID().uuidString)")
    dictationDirectory = directory
    var entry = DictationEntry(
      text: "", original: "",
      application: destination?.application.bundleIdentifier ?? "Unknown application",
      mode: cleanupMode.rawValue, audioDirectory: directory.path)
    entry.microphoneName = input.name
    let style = personalization.last { $0.kind == "style" && $0.trigger == entry.application }
    entry.mode = style?.mode ?? cleanupMode.rawValue
    entry.language = style?.language ?? language
    entry.selection = editSelection ? destination?.selectedText : nil
    entry.preferences = personalization
    entry.status = "recording"
    do {
      try db().put(entry, kind: "dictation", id: entry.id)
      try refresh()
    } catch {
      finishTrace(traceID, .failed)
      notice = error.localizedDescription
      return
    }
    recordingEntry = entry
    dictationStatus = .listening
    captureTask = Task {
      do {
        guard let audio else { throw WorkspaceError.message("Audio is unavailable.") }
        try await audio.addConsumer(
          id: consumerID, directory: directory, tracks: [.microphone],
          device: input)
        if generation != dictationGeneration { try audio.removeConsumer(id: consumerID) }
        else {
          audio.setPacketHandler({ [weak self] track, packet in
            guard track == .microphone else { return }
            Task { @MainActor in self?.receiveLiveDictationPacket(packet) }
          }, id: consumerID)
          microphoneSignal.start(at: ProcessInfo.processInfo.systemUptime)
          dictationReady = true
        }
      } catch {
        if generation == dictationGeneration {
          stopForMicrophoneIssue(error.localizedDescription)
        }
      }
    }
  }

  func receiveLiveDictationPacket(_ packet: AudioPacket) {
    guard dictationStatus == .listening else { return }
    liveDictationPackets.append(packet)
    let duration = liveDictationPackets.reduce(0) { $0 + $1.duration }
    while liveDictationPackets.count > 80 || liveDictationPackets.reduce(0, { $0 + $1.duration }) > 12 {
      liveDictationPackets.removeFirst()
    }
    let now = ProcessInfo.processInfo.systemUptime
    guard duration >= 1.2, now - liveDictationLastRun > 1.0, !liveDictationBusy else { return }
    liveDictationLastRun = now
    liveDictationBusy = true
    let packets = liveDictationPackets
    let language = self.language
    liveDictationTask = Task { @MainActor in
      defer { liveDictationBusy = false }
      guard let text = try? await localSpeech.transcribeLive(packets: packets, language: language), !text.isEmpty else { return }
      guard dictationStatus == .listening else { return }
      dictationLiveText = text
      if dictationReviewActive, dictationReviewText == dictationReviewSeed {
        dictationReviewText = text
        dictationReviewSeed = text
      }
    }
  }
  func processDictation(_ saved: DictationEntry, traceID: String? = nil) async throws -> DictationEntry {
    var entry = saved
    entry.processingNote = nil
    // Serialize the final decode behind any provisional live decode. Whisper
    // uses one shared pipeline; starting both at once otherwise leaves a
    // valid recording saved with an empty “transcription needed” result.
    if let liveTask = liveDictationTask {
      liveTask.cancel()
      await liveTask.value
      liveDictationTask = nil
      liveDictationBusy = false
    }
    if let key, let reason = await ShortDictationFilter.inspect(directory: URL(fileURLWithPath: entry.audioDirectory), key: key) {
      try Task.checkCancellation()
      entry.status = "ignored"; entry.processingNote = reason
      try db().put(entry, kind: "dictation", id: entry.id)
      try refresh()
      finishTrace(traceID, .noSignal)
      throw DictationSignalError.unusable(reason + ". Audio kept in Show ignored clips; choose or check the microphone.")
    }
    let preferences = entry.preferences ?? personalization
    let language = entry.language ?? self.language
    let mode = transcriptionMode
    let files = try journalFiles(URL(fileURLWithPath: entry.audioDirectory))
    guard !files.isEmpty else { throw WorkspaceError.message("No saved audio was found for this dictation.") }
    var text = ""
    var cloudClient: BackendClient?
    if mode.attemptsCloud(cloudEnabled: cloudEnabled, configured: !backendToken.isEmpty) {
      markTrace(traceID, .cloudStarted)
      defer { markTrace(traceID, .cloudFinished) }
      do {
        var client = try backend(scope: "dictation/" + entry.id, associationID: entry.id)
        client.timeout = 20
        for file in files {
          try Task.checkCancellation()
          let result = try await client.transcribe(
            readWave(file), diarize: false, language: language,
            keywords: preferences.filter { $0.kind == "dictionary" && $0.language == language }.map(\.replacement))
          text += (text.isEmpty ? "" : " ") + result.text
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          throw WorkspaceError.message("Cloud transcription returned no text.")
        }
        cloudClient = client
        entry.transcriptionProvider = "OpenAI cloud"
      } catch {
        try Task.checkCancellation()
        guard mode.allowsLocal else { throw error }
        // A single sequential fallback owns the result. Partial cloud text is discarded.
        text = ""
        entry.processingNote = "Cloud unavailable · transcribed locally"
      }
    } else if !mode.allowsLocal {
      throw WorkspaceError.message("Cloud-only transcription needs cloud processing and a configured backend. Choose Local only or Cloud with local fallback in Dictation settings.")
    }
    if cloudClient == nil {
      guard let key else { throw WorkspaceError.message("Recording key unavailable.") }
      markTrace(traceID, .localStarted)
      defer { markTrace(traceID, .localFinished) }
      text = try await localSpeech.transcribe(files: files, key: key, language: language)
      entry.transcriptionProvider = "Local · Whisper large-v3-turbo"
    }
    try Task.checkCancellation()
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw WorkspaceError.message("No speech was transcribed. Audio remains available for retry.")
    }
    entry.original = text
    entry.text = text
    entry.status = "transcribed"
    try db().put(entry, kind: "dictation", id: entry.id, searchable: text)
    try refresh()
    let selection = entry.selection ?? ""
    if selection.isEmpty,
      let snippet = DictationPersonalization.snippet(text, entries: preferences, language: language) {
      entry.text = snippet
    } else {
      let cleanup = CleanupMode(rawValue: entry.mode) ?? .light
      if cleanup != .verbatim || !selection.isEmpty {
        if let client = cloudClient, cloudEnabled {
          markTrace(traceID, .cleanupStarted)
          defer { markTrace(traceID, .cleanupFinished) }
          do {
            entry.text = try await client.cleanup(text, mode: cleanup, selection: selection,
              instruction: selection.isEmpty ? "" : text,
              personalization: preferences.filter { $0.language == language }, application: entry.application)
          } catch {
            try Task.checkCancellation()
            if !selection.isEmpty { throw error }
            entry.processingNote = "Cleanup unavailable · plain transcript saved"
          }
        } else if !selection.isEmpty {
          // A spoken editing instruction is not a replacement for the selected text.
          entry.processingNote = "Editing needs cloud access · instruction saved only"
          try db().put(entry, kind: "dictation", id: entry.id, searchable: text)
          try refresh()
          throw WorkspaceError.message("Local transcription saved your instruction. Selected-text editing requires cloud processing; no replacement was inserted.")
        } else {
          entry.processingNote = "Plain local transcript · cloud cleanup not applied"
        }
      }
      entry.text = DictationPersonalization.spellings(entry.text, entries: preferences, language: language)
    }
    try Task.checkCancellation()
    entry.status = "ready"
    try db().put(entry, kind: "dictation", id: entry.id, searchable: entry.text)
    try refresh()
    return entry
  }
  func finishDictation() {
    guard dictationStatus == .listening, var entry = recordingEntry else { return }
    clearMicrophoneMessage()
    liveDictationTask?.cancel()
    captureTask?.cancel()
    if let dictationConsumerID { audio?.setPacketHandler(nil, id: dictationConsumerID) }
    do { if let dictationConsumerID { try audio?.removeConsumer(id: dictationConsumerID) } } catch {
      notice = error.localizedDescription
      return
    }
    markTrace(dictationTraceID, .captureStopped)
    let traceID = dictationTraceID
    dictationGeneration = UUID()
    dictationReady = false
    entry.status = "saved"
    do { try db().put(entry, kind: "dictation", id: entry.id); try refresh() }
    catch { notice = error.localizedDescription }
    recordingEntry = nil
    dictationConsumerID = nil
    enqueueDictation(entry, captured: destination, traceID: traceID, trigger: nextDeliveryTrigger)
    // Capture has ended; the queue may now process this clip (or wait behind
    // an earlier clip) and can safely leave the listening state.
    dictationStatus = .processing
  }

  func cancelDictation() {
    finishTrace(dictationTraceID, .cancelled)
    clearMicrophoneMessage()
    clearDictationFeedback()
    liveDictationTask?.cancel()
    liveDictationTask = nil
    dictationReady = false
    dictationGeneration = UUID()
    // Escape during a new recording cancels only that recording. Already saved
    // clips continue processing; Escape at the spinner cancels the current job.
    if dictationStatus != .listening { dictationQueue.cancelCurrent(); dictationTask?.cancel() }
    captureTask?.cancel()
    if let dictationConsumerID { audio?.setPacketHandler(nil, id: dictationConsumerID) }
    if let dictationConsumerID { try? audio?.removeConsumer(id: dictationConsumerID) }
    if var entry = recordingEntry, entry.status == "recording" {
      entry.status = "cancelled"
      // Never replace a newer raw/final transcript committed by the processing task.
      if let current = try? db().list(DictationEntry.self, kind: "dictation").first(where: {
        $0.id == entry.id
      }), current.status == "recording" {
        try? db().put(entry, kind: "dictation", id: entry.id)
        try? refresh()
      }
    }
    recordingEntry = nil
    dictationConsumerID = nil
    dictationStatus = pendingDictations > 0 ? .processing : .idle
    notice = "Voice action cancelled. Saved clips remain in history."
  }
  func toggleDictation() { dictationStatus == .listening ? finishDictation() : beginDictation() }
  func pasteLast() {
    guard let entry = history.first(where: { !$0.text.isEmpty }) else {
      notice = "No dictation is ready to paste."
      return
    }
    guard dictationStatus != .listening && dictationStatus != .processing else { return }
    let target = insertion.capture()
    clearDictationFeedback()
    dictationGeneration = UUID()
    let generation = dictationGeneration
    dictationStatus = .processing
    dictationTask = Task {
      let result = await insertion.insert(entry.text, into: target)
      guard generation == dictationGeneration, !Task.isCancelled else { return }
      showDictationFeedback(result)
      recordDelivery(result, trigger: "Paste last shortcut")
      dictationStatus = .idle
    }
  }
  func retryDictation(_ entry: DictationEntry) {
    guard dictationStatus != .processing && dictationStatus != .listening else { return }
    let traceID = startDictationTrace()
    clearDictationFeedback()
    enqueueDictation(entry, captured: nil, traceID: traceID, insertResult: false, trigger: "Retry audio")
  }

  func deleteDictation(_ entry: DictationEntry) {
    guard privacyWorkAllowed else {
      notice = "Finish capture and AI work before deleting history."
      return
    }
    do {
      if dictationPlaybackID == entry.id { stopDictationPlayback() }
      try db().finishDeletion(
        db().planItemDeletion(
          id: entry.id, kind: "dictation", directory: entry.audioDirectory, root: root), root: root)
      try refresh()
      try refreshPrivacy()
      syncBackendDeletions()
    } catch { notice = error.localizedDescription }
  }

  func journalFiles(_ directory: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "vwj" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
  }
  func journalTimestamp(_ url: URL) -> Double? {
    Double(url.deletingPathExtension().lastPathComponent.split(separator: "-").last ?? "")
  }
  func packets(_ url: URL) throws -> [AudioPacket] {
    guard let key else { throw WorkspaceError.message("Recording key unavailable.") }
    return try AudioJournal.recover(url: url, key: key).packets
  }
  func readWave(_ url: URL) throws -> Data { try AudioJournal.wave(packets: packets(url)) }
  func startLiveCaptions(meetingID: String) async {
    stopLiveCaptions()
    do {
      let client = try backend()
      for track: TrackKind in meetingPID == 0 ? [.microphone] : [.microphone, .remote] {
        let live = LiveTranscription(
          meetingID: meetingID, track: track, origin: hostOrigin,
          onSegment: { [weak self] segment in
            Task { @MainActor in
              guard let self else { return }
              do {
                try self.db().put(
                  segment, kind: "segment", id: segment.id, parent: meetingID,
                  searchable: segment.text)
                if self.selectedMeetingID == meetingID { try self.refreshDetail() }
                self.scheduleOutline(meetingID: meetingID)
              } catch {
                self.notice = "Live text could not be saved: " + error.localizedDescription
              }
            }
          }, onFailure: { [weak self] message in Task { @MainActor in self?.notice = message } },
          onUsage: { [weak self] eventID, raw in
            Task { @MainActor in
              self?.recordProviderUsage(
                id: "live-transcribe/" + eventID, category: "transcription.live",
                model: "gpt-live-transcribe", raw: raw, final: raw != "{}", scope: meetingID)
            }
          })
        liveStreams[track] = live
        await live.connect(backend: client.baseURL, token: client.token)
      }
      let stream = AsyncStream<(TrackKind, AudioPacket)>(bufferingPolicy: .bufferingNewest(64)) {
        liveContinuation = $0
      }
      let continuation = liveContinuation
      audio?.setPacketHandler { track, packet in continuation?.yield((track, packet)) }
      let streams = liveStreams
      liveFeed = Task {
        for await (track, packet) in stream {
          guard !Task.isCancelled else { break }
          await streams[track]?.append(packet)
        }
      }
    } catch { notice = "Live captions unavailable. " + error.localizedDescription }
  }
  func stopLiveCaptions() {
    audio?.setPacketHandler(nil)
    liveContinuation?.finish()
    liveContinuation = nil
    liveFeed?.cancel()
    liveFeed = nil
    for stream in liveStreams.values { Task { await stream.close() } }
    liveStreams = [:]
  }
  func cancelTranscription() { transcriptionTask?.cancel() }
  func transcribeMeeting(reprocess: Bool = false) {
    guard let id = selectedMeetingID, id != activeMeetingID, !processingMeeting, let key else {
      return
    }
    processingMeeting = true
    transcriptionTask = Task {
      defer {
        processingMeeting = false
        transcriptionProgress = ""
      }
      var activeJob: TranscriptionJob?
      do {
        let client = try backend()
        let archive = MeetingAudioArchive(key: key)
        let duration = try await archive.prepare(
          db().list(RecordingLeg.self, kind: "leg", parent: id)
        ).0
        let tracks = await archive.tracks()
        let windows = tracks.flatMap {
          TranscriptionWindow.plan(meetingID: id, track: $0, duration: duration)
        }
        guard !windows.isEmpty else { throw WorkspaceError.message("No saved audio is available.") }
        let profiles = try db().list(VoiceEnrollment.self, kind: "enrollment").filter(
          \.cloudMatching)
        guard profiles.count <= 4 else {
          throw WorkspaceError.message("Enable at most four enrolled voices for one transcription.")
        }
        let references = try profiles.map { profile -> [String: String] in
          let sealed = try AES.GCM.SealedBox(
            combined: Data(contentsOf: URL(fileURLWithPath: profile.referencePath)))
          let wave = try AES.GCM.open(sealed, using: key)
          return ["name": "voice_" + profile.id, "audio": wave.base64EncodedString()]
        }
        var previous: [TrackKind: [TranscriptSegment]] = [:]
        for (index, window) in windows.enumerated() {
          try Task.checkCancellation()
          transcriptionProgress = "Refining audio window \(index + 1) of \(windows.count)"
          let saved = try db().list(TranscriptionJob.self, kind: "transcriptionJob", parent: id)
            .first { $0.id == window.id }
          if !reprocess, let saved, saved.window == window,
            ["completed", "review"].contains(saved.status)
          {
            previous[window.track] = saved.context
            continue
          }
          var job = TranscriptionJob(window: window, status: "running")
          activeJob = job
          try db().put(job, kind: "transcriptionJob", id: job.id, parent: id)
          let wave = try await archive.wave(
            start: window.audioStart, end: window.audioEnd, track: window.track)
          let result = try await client.transcribe(
            wave, diarize: true, language: language, keywords: [],
            references: window.track == .assistant ? [] : references)
          var mapped: [TranscriptSegment] = []
          for (segmentIndex, item) in (result.segments ?? []).enumerated() {
            guard item.start.isFinite, item.end.isFinite, item.start >= 0, item.end > item.start,
              item.end <= window.audioEnd - window.audioStart + 0.2
            else {
              throw WorkspaceError.message(
                "Provider returned an invalid segment interval; this window was not committed.")
            }
            let profile = profiles.first { "voice_" + $0.id == item.speaker }
            var segment = TranscriptSegment(
              id: window.id + "/\(segmentIndex)", meetingID: id,
              start: window.audioStart + item.start, end: window.audioStart + item.end,
              text: item.text,
              speakerID: profile.map { "enrolled:" + $0.id } ?? window.id + "/" + item.speaker,
              speakerName: profile.map { $0.name + " · voice match" }, track: window.track)
            segment.attribution =
              profile == nil
              ? "request-local acoustic group" : "enrolled reference match; review identity"
            if window.track == .assistant {
              segment.speakerID = "assistant"
              segment.speakerName = "Chup! assistant"
              segment.attribution = "isolated rendered assistant output"
            }
            mapped.append(segment)
          }
          guard !mapped.isEmpty || result.text.isEmpty else {
            throw WorkspaceError.message("Speaker segments were missing.")
          }
          job.context = SpeakerContinuity.reconcile(mapped, previous: previous[window.track] ?? [])
          try Task.checkCancellation()
          _ = try db().commitWindow(job)
          previous[window.track] = job.context
          activeJob = nil
          if selectedMeetingID == id { try refreshDetail() }
        }
        for provisional in try db().list(TranscriptSegment.self, kind: "segment", parent: id)
        where provisional.provisional { try db().remove(kind: "segment", id: provisional.id) }
        if selectedMeetingID == id { try refreshDetail() }
        if autoSummaryEnabled { try await finalizeSummary(meetingID: id) }
        notice =
          "Transcript refinement saved. Review voice matches and any pending correction conflicts."
      } catch {
        if var job = activeJob {
          job.status = Task.isCancelled ? "pending" : "failed"
          job.error = error.localizedDescription
          try? db().put(job, kind: "transcriptionJob", id: job.id, parent: id)
        }
        notice =
          "Transcription paused; Retry resumes committed windows. \(error.localizedDescription)"
      }
    }
  }
  func resolveTranscriptReview(_ review: TranscriptReview, accept: Bool) {
    do {
      if accept {
        let current = try db().list(
          TranscriptSegment.self, kind: "segment", parent: review.window.meetingID
        )
        .filter { !($0.provisional) && review.window.owns($0) }
        guard Set(current.map(\.id)) == Set(review.current.map(\.id)),
          current.allSatisfy({ review.current.contains($0) })
        else { throw WorkspaceError.staleVersion }
        _ = try db().commitWindow(
          TranscriptionJob(window: review.window, context: review.incoming), acceptReview: true)
      } else {
        try db().keepTranscriptReview(review)
      }
      try refreshDetail()
    } catch { notice = error.localizedDescription }
  }
  func enrollVoice(_ segment: TranscriptSegment, name: String, consent: Bool) {
    guard consent, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !segment.provisional, segment.end - segment.start >= 2, segment.meetingID != activeMeetingID,
      let key
    else {
      notice =
        "Choose a finalized interval of at least two seconds and explicitly confirm whose voice it contains."
      return
    }
    Task {
      do {
        let all = try db().list(TranscriptSegment.self, kind: "segment", parent: segment.meetingID)
        let end = min(segment.end, segment.start + 10)
        guard
          !all.contains(where: {
            $0.id != segment.id && $0.track == segment.track && $0.start < end
              && $0.end > segment.start
          })
        else {
          throw WorkspaceError.message(
            "This interval overlaps another speaker segment. Choose a clean, single-speaker interval."
          )
        }
        let archive = MeetingAudioArchive(key: key)
        _ = try await archive.prepare(
          db().list(RecordingLeg.self, kind: "leg", parent: segment.meetingID))
        let wave = try await archive.wave(start: segment.start, end: end, track: segment.track)
        let directory = root.appendingPathComponent("VoiceReferences")
        try FileManager.default.createDirectory(
          at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = directory.appendingPathComponent(UUID().uuidString + ".sealed")
        guard let encrypted = try AES.GCM.seal(wave, using: key).combined else {
          throw WorkspaceError.corruptJournal
        }
        try encrypted.write(to: path, options: .atomic)
        let profile = VoiceEnrollment(
          name: name, meetingID: segment.meetingID, segmentID: segment.id,
          duration: end - segment.start, referencePath: path.path)
        do { try db().put(profile, kind: "enrollment", id: profile.id) } catch {
          try? FileManager.default.removeItem(at: path)
          throw error
        }
        enrollments = try db().list(VoiceEnrollment.self, kind: "enrollment")
        notice =
          "Encrypted voice reference saved. Cloud matching is off; enable it explicitly in Meetings settings."
      } catch { notice = error.localizedDescription }
    }
  }
  func saveEnrollment(_ profile: VoiceEnrollment) {
    do {
      let active = try db().list(VoiceEnrollment.self, kind: "enrollment").filter {
        $0.cloudMatching && $0.id != profile.id
      }
      guard !profile.cloudMatching || active.count < 4 else {
        throw WorkspaceError.message("At most four voices can be matched in one request.")
      }
      try db().put(profile, kind: "enrollment", id: profile.id)
      enrollments = try db().list(VoiceEnrollment.self, kind: "enrollment")
    } catch { notice = error.localizedDescription }
  }
  func deleteEnrollment(_ profile: VoiceEnrollment) { deleteEnrollmentWithPlan(profile) }

  func generateSummary() {
    guard let id = selectedMeetingID, !processingMeeting else { return }
    processingMeeting = true
    Task {
      defer { processingMeeting = false }
      do {
        try await finalizeSummary(meetingID: id)
        notice = "Summary saved with transcript sources. Your pinned edits are preserved."
      } catch { notice = error.localizedDescription }
    }
  }
  func correctSegment(
    _ original: TranscriptSegment, text: String, name: String, mergeID: String? = nil
  ) {
    do {
      var corrected = original
      corrected.text = text
      corrected.speakerName = name.isEmpty ? nil : name
      if let mergeID { corrected.speakerID = mergeID }
      try db().correct(corrected)
      try refreshDetail()
    } catch { notice = error.localizedDescription }
  }
  func renameSpeaker(_ id: String, name: String) {
    for segment in segments where segment.speakerID == id {
      correctSegment(segment, text: segment.text, name: name)
    }
  }
  func splitSpeaker(_ segment: TranscriptSegment) {
    correctSegment(
      segment, text: segment.text, name: segment.speakerName ?? "", mergeID: UUID().uuidString)
  }
  func preparePlayback() {
    guard let id = selectedMeetingID, id != activeMeetingID, let key else { return }
    do {
      playback.prepare(legs: try db().list(RecordingLeg.self, kind: "leg", parent: id), key: key)
    } catch { notice = error.localizedDescription }
  }
  func play(at offset: Double = 0) {
    stopDictationPlayback()
    guard selectedMeetingID != activeMeetingID else {
      notice = "Finish this recording before playing it back."
      return
    }
    guard !playbackLoading, playbackDuration > 0 else {
      notice = playbackLoading ? "Opening recorded audio…" : "This meeting has no recorded audio."
      return
    }
    playback.play(at: offset)
  }
  func stopPlayback() { playback.pause() }
  func seekPlayback(to time: Double) { playback.seek(to: time) }
  func cancelAssistant() {
    assistantTask?.cancel()
    assistantTask = nil
    if let request = assistantRequest {
      do {
        if var exchange = try db().list(
          AssistantExchange.self, kind: "assistantExchange", parent: request.meeting
        )
        .first(where: { $0.id == request.id && $0.status == "pending" }) {
          exchange.status = "cancelled"
          exchange.answer = "Request cancelled. This request did not write to notes."
          try db().put(
            exchange, kind: "assistantExchange", id: exchange.id, parent: exchange.meetingID)
        }
        if selectedMeetingID == request.meeting { try refreshDetail() }
      } catch { notice = error.localizedDescription }
    }
    assistantRequest = nil
    assistantBusy = false
  }
  func ask(_ question: String) {
    guard !assistantBusy, let id = selectedMeetingID,
      !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }
    let client: BackendClient
    var exchange = AssistantExchange(meetingID: id, question: question, noteVersion: note.version)
    do {
      client = try backend(scope: id, associationID: exchange.id)
      try db().put(exchange, kind: "assistantExchange", id: exchange.id, parent: id)
      try refreshDetail()
    } catch {
      notice = error.localizedDescription
      return
    }
    let scopedNote = note
    let scopedSegments = segments
    let scopedHistory = assistantHistory
    let requestID = exchange.id
    assistantBusy = true
    assistantRequest = (id, requestID)
    pendingWrite = nil
    pendingWriteScope = nil
    pendingExchangeID = nil
    assistantTask = Task {
      defer {
        if assistantRequest?.id == requestID {
          assistantBusy = false
          assistantRequest = nil
          assistantTask = nil
        }
      }
      do {
        let answer = try await client.ask(
          question, segments: scopedSegments, note: scopedNote, history: scopedHistory)
        try Task.checkCancellation()
        guard assistantRequest?.id == requestID, selectedMeetingID == id else { return }
        if !answer.sources.isEmpty {
          try EvidenceValidator.validate(
            MeetingSummary(items: [
              SummaryItem(category: "overview", text: answer.text, sources: answer.sources)
            ]), meetingID: id, segments: scopedSegments)
        }
        exchange.answer = answer.text
        exchange.sources = answer.sources
        exchange.write = answer.write
        exchange.status = "completed"
        try db().put(exchange, kind: "assistantExchange", id: requestID, parent: id)
        try refreshDetail()
        assistantAnswer = answer.text
        assistantSources = answer.sources
        pendingWrite = answer.write
        pendingWriteScope = (id, scopedNote.version, requestID + "/note")
        pendingExchangeID = requestID
      } catch {
        guard !Task.isCancelled, assistantRequest?.id == requestID, selectedMeetingID == id else {
          return
        }
        exchange.status = "failed"
        exchange.answer = "Could not complete that request: \(error.localizedDescription)"
        do {
          try db().put(exchange, kind: "assistantExchange", id: requestID, parent: id)
          try refreshDetail()
        } catch { notice = error.localizedDescription }
      }
    }
  }
  func reviewAssistantWrite(_ exchange: AssistantExchange) {
    guard exchange.meetingID == selectedMeetingID, exchange.status == "completed",
      let write = exchange.write
    else { return }
    pendingWrite = write
    pendingWriteScope = (exchange.meetingID, exchange.noteVersion, exchange.id + "/note")
    pendingExchangeID = exchange.id
  }
  func applyAssistantWrite() {
    guard let write = pendingWrite, let scope = pendingWriteScope, scope.0 == selectedMeetingID
    else { return }
    do {
      let current = try db().note(scope.0)
      guard current.version == scope.1 else { throw WorkspaceError.staleVersion }
      let text: String
      switch write.operation {
      case "create_action_item":
        let action = ActionRecord(
          id: scope.2, meetingID: scope.0, title: write.text,
          owner: write.owner, dueDate: write.dueDate, sources: write.sources ?? [],
          origin: (write.sources ?? []).isEmpty ? "user" : "transcript")
        lastActionReceipt = try db().writeAction(action, expectedVersion: 0, requestID: scope.2)
        pendingWrite = nil
        pendingWriteScope = nil
        if let pendingExchangeID,
          var exchange = assistantHistory.first(where: { $0.id == pendingExchangeID })
        {
          exchange.status = "committed"
          try db().put(exchange, kind: "assistantExchange", id: exchange.id, parent: scope.0)
        }
        pendingExchangeID = nil
        try refreshDetail()
        notice = "Action saved."
        return
      case "append_note":
        text = current.text + (current.text.isEmpty ? "" : "\n\n") + write.text
      case "update_note": text = write.text
      default: throw WorkspaceError.message("Unsupported note operation.")
      }
      let tools = MeetingTools(store: try db())
      let authorization = MeetingToolScope(
        meetingID: scope.0, addressedRequestID: scope.2, canWrite: true)
      let receipt = try tools.updateNote(text: text, expectedVersion: scope.1, scope: authorization)
      lastReceipt = receipt
      note = receipt.after
      noteDraft = note.text
      pendingWrite = nil
      pendingWriteScope = nil
      assistantAnswer += "\n\nSaved to My notes."
      if let exchangeID = pendingExchangeID,
        var exchange = assistantHistory.first(where: { $0.id == exchangeID })
      {
        exchange.status = "committed"
        try db().put(exchange, kind: "assistantExchange", id: exchange.id, parent: scope.0)
        try refreshDetail()
      }
      pendingExchangeID = nil
    } catch { notice = error.localizedDescription }
  }
  func savePersonalization(
    kind: String, trigger: String, replacement: String, language: String, mode: String? = nil
  ) {
    var item = Personalization(
      kind: kind, trigger: trigger, replacement: replacement, language: language)
    item.mode = mode
    if let existing = personalization.first(where: {
      $0.kind == kind && $0.trigger.caseInsensitiveCompare(trigger) == .orderedSame
        && (kind == "style" || $0.language == language)
    }) {
      item.id = existing.id
    }
    do {
      try db().put(
        item, kind: "personalization", id: item.id, searchable: trigger + " " + replacement)
      try refresh()
    } catch { notice = error.localizedDescription }
  }
  func deletePersonalization(_ item: Personalization) {
    do {
      try db().remove(kind: "personalization", id: item.id)
      try refresh()
    } catch { notice = error.localizedDescription }
  }
  func handle(_ signal: ShortcutSignal) {
    if signal.cancelled {
      cancelDictation()
      return
    }
    switch signal.action {
    case .holdDictation: signal.began ? beginDictation() : finishDictation()
    case .editSelection: signal.began ? beginDictation(editSelection: true) : finishDictation()
    case .toggleDictation: if signal.began { toggleDictation() }
    case .pasteLast: if signal.began { pasteLast() }
    case .meeting:
      if signal.began {
        if activeMeetingID == nil {
          page = .meetings
          reveal?()
          newMeeting()
          startMeeting()
        } else {
          startMeeting()
        }
      }
    case .assistant:
      if signal.began {
        assistantVisible = true
        reveal?()
      }
    case .focusRail: if signal.began { focusRail() }
    case .cancel:
      if rail?.dismissKeyboard() == true { return }
      endVoice()
      if signal.began {
        cancelDictation()
        stopPlayback()
      }
    }
  }
}
