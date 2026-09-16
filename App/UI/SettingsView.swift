import ChupCore
import SwiftUI

struct SettingsView: View {
  @EnvironmentObject var state: WorkspaceState
  @State var section = "General"
  let sections = [
    "General", "Shortcuts", "Audio", "Dictation", "Meetings", "Assistant", "Appearance", "Privacy",
    "Permissions", "Usage", "Recovery", "Diagnostics", "Transcription Lab", "Advanced",
  ]
  private let icons = [
    "General": "slider.horizontal.3", "Shortcuts": "keyboard", "Audio": "mic",
    "Dictation": "waveform", "Meetings": "person.2", "Assistant": "sparkles",
    "Appearance": "paintpalette",
    "Privacy": "lock.shield", "Permissions": "checkmark.shield", "Usage": "clock",
    "Recovery": "arrow.counterclockwise",
    "Diagnostics": "stethoscope", "Transcription Lab": "flask", "Advanced": "gearshape.2",
  ]
  private let descriptions = [
    "General": "Make Chup! part of your day.",
    "Shortcuts": "Your voice, one familiar gesture away.",
    "Audio": "Choose your input. Make sure you sound like you.",
    "Dictation": "Decide how your spoken words become text.",
    "Meetings": "Capture the conversation, keep what matters.",
    "Assistant": "A thought partner with clear boundaries.",
    "Appearance": "A quiet workspace, wherever you work.",
    "Privacy": "Your words and how they are kept.",
    "Permissions": "Give each feature the access it needs.",
    "Usage": "Understand your AI activity and estimates.",
    "Recovery": "Pick up work that was interrupted.",
    "Diagnostics": "See where a dictation spent its time.",
    "Transcription Lab": "Find the local model that hears you best.",
    "Advanced": "Connections and troubleshooting.",
  ]
  var body: some View {
    HStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 4) {
          Text("Settings").font(.system(size: 25, design: .serif)).padding(.horizontal, 10).padding(
            .bottom, 20)
          ForEach(sections, id: \.self) { name in
            Button {
              section = name
            } label: {
              HStack(spacing: 10) {
                Image(systemName: icons[name] ?? "circle").frame(width: 17).accessibilityHidden(
                  true)
                Text(name).font(.system(size: 13))
                Spacer(minLength: 0)
              }.padding(.horizontal, 10).padding(.vertical, 10).contentShape(Rectangle())
                .background(
                  section == name ? Palette.paper : .clear, in: RoundedRectangle(cornerRadius: 9))
            }.buttonStyle(.plain).foregroundStyle(section == name ? Palette.ink : Palette.secondary)
              .accessibilityAddTraits(section == name ? .isSelected : [])
          }
        }.padding(.horizontal, 12).padding(.vertical, 24)
      }.frame(width: 186).background(Palette.sidebar)
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          VStack(alignment: .leading, spacing: 8) {
            Text(section).font(Palette.title).accessibilityAddTraits(.isHeader)
            Text(descriptions[section] ?? "").font(.system(size: 14)).foregroundStyle(
              Palette.secondary)
          }.padding(.bottom, 8)
          selectedContent
        }.frame(maxWidth: 720, alignment: .leading).padding(28).frame(maxWidth: .infinity)
      }.background(Palette.workspace)
    }.foregroundStyle(Palette.ink).tint(Palette.olive).textFieldStyle(.roundedBorder)
      .onAppear {
        if state.microphoneSettingsRequested {
          section = "Audio"
          state.microphoneSettingsRequested = false
        }
        state.setup.refresh()
        try? state.refreshPrivacy()
      }
      .onChange(of: state.microphoneSettingsRequested) { _, requested in
        if requested {
          section = "Audio"
          state.microphoneSettingsRequested = false
        }
      }
      .sheet(isPresented: $state.backupSheet) { BackupSettingsView().environmentObject(state) }
  }
  @ViewBuilder private var selectedContent: some View {
    switch section {
    case "General":
      WorkspaceCard("At your fingertips", icon: "cursorarrow.rays") {
        SettingSwitch(
          title: "Show the floating rail",
          detail: "Keep voice controls at the edge of your screen.", isOn: $state.showRail)
      }
      WorkspaceCard("Start with your Mac", icon: "sun.max") { LoginSettings(setup: state.setup) }
      WorkspaceCard("Set up your workspace", icon: "checkmark.shield") {
        HStack {
          Button("Run setup again") {
            state.onboardingVisible = true
            state.reveal?()
          }
          Button("Review permissions") { section = "Permissions" }
        }
      }
      DisclosureGroup("About this installation") {
        VStack(alignment: .leading, spacing: 8) {
          Text(state.runningBuild.label).font(.headline)
          Text(state.runningBuild.appPath).font(.caption).foregroundStyle(Palette.secondary)
        }.textSelection(.enabled).padding(.top, 8)
      }.font(.callout).foregroundStyle(Palette.secondary)
    case "Shortcuts": ShortcutSettingsView(registry: state.shortcuts)
    case "Audio":
      MicrophonePicker(devices: state.devices)
      WorkspaceCard(
        "Meeting audio", subtitle: "Capture the other side of the conversation.",
        icon: "person.wave.2"
      ) {
        SettingSwitch(
          title: "Use alternative audio capture",
          detail: "Try this if the standard capture route does not work with your call app.",
          isOn: $state.captureFallback)
        DetailDisclosure(
          title: "How capture and permissions work",
          text:
            "Core Audio process taps are the default. The ScreenCaptureKit fallback requests Screen & System Audio Recording access. Neither route needs a virtual microphone; no screen video is saved."
        )
      }
    case "Dictation":
      LocalSpeechSettings(service: state.localSpeech)
      WorkspaceCard(
        "Writing preferences", subtitle: "A little cleanup, while keeping your meaning.",
        icon: "textformat"
      ) {
        Picker("Cleanup", selection: $state.cleanupMode) {
          ForEach(CleanupMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        Picker("Language", selection: $state.language) {
          Text("Automatic (English / Nederlands)").tag("auto")
          Text("English").tag("en")
          Text("Nederlands").tag("nl")
        }
        Text("Transcription is explicit; Chup! does not translate. Automatic detects English or Nederlands from each recording.")
          .font(.callout).foregroundStyle(Palette.secondary)
      }
    case "Meetings":
      WorkspaceCard("When a call begins", icon: "bell") {
        SettingSwitch(
          title: "Suggest meeting notes",
          detail:
            "A gentle prompt that disappears after 10 seconds. Recording always needs your action.",
          isOn: $state.meetingDetectionEnabled)
        DetailDisclosure(
          title: "About browser calls",
          text:
            "Browser activity cannot prove which tab is a meeting. Review the selected application before recording."
        )
      }
      WorkspaceCard("Transcripts & summaries", icon: "text.bubble") {
        SettingSwitch(
          title: "Live captions",
          detail: "Show provisional text while recording. Uses cloud processing.",
          isOn: $state.liveCaptionsEnabled)
        Divider()
        SettingSwitch(
          title: "Live outline",
          detail: "Build a provisional outline from completed text. Uses cloud processing.",
          isOn: $state.liveOutlineEnabled)
        Divider()
        SettingSwitch(
          title: "Final summary", detail: "Generate a summary after the transcript is refined.",
          isOn: $state.autoSummaryEnabled)
      }
      VoiceEnrollmentSettings()
    case "Assistant":
      WorkspaceCard("A conversation, on your terms", icon: "sparkles") {
        Text("Choose Private text, Private voice or Speak in meeting from the assistant.").font(
          .callout
        ).foregroundStyle(Palette.secondary)
        InlineStatus(
          text:
            "Only questions you explicitly address to the assistant can trigger retrieval or note changes.",
          icon: "hand.raised")
        DetailDisclosure(
          title: "Voice setup & privacy",
          text:
            "GPT-Live-1 receives addressed voice. Headphones must be identified by macOS. Private voice in a meeting requires control of the call’s microphone through the separately built Chup! Mic prototype; headphones alone do not make your spoken question private. After a voice failure, the outgoing microphone stays muted until you resume it."
        )
      }
      WorkspaceCard("Recent voice sessions", icon: "clock") {
        if state.usageRecords.isEmpty {
          Text("Your voice sessions will appear here.").foregroundStyle(Palette.secondary)
        }
        ForEach(state.usageRecords.prefix(12)) { item in
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text(item.category).font(.headline)
              Spacer()
              Text(item.status).font(.caption).foregroundStyle(Palette.secondary)
            }
            if let end = item.ended {
              Text("\(Int(end.timeIntervalSince(item.started))) seconds · measured locally").font(
                .caption
              ).foregroundStyle(Palette.secondary)
            }
          }.padding(.vertical, 4)
        }
        Button("View usage & estimates") { section = "Usage" }
      }
    case "Appearance":
      WorkspaceCard(
        "Paper & glass", subtitle: "A light reading space with dark floating controls.",
        icon: "paintpalette"
      ) {
        HStack(spacing: 16) {
          RoundedRectangle(cornerRadius: 12).fill(Palette.workspace).overlay {
            WaveMark().scaleEffect(0.7)
          }.frame(height: 78)
          RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.13)).overlay {
            WaveMark(color: .white).scaleEffect(0.7)
          }.frame(height: 78)
        }.accessibilityLabel("Light workspace and dark rail appearance samples")
      }
      WorkspaceCard("Floating controls", icon: "sidebar.right") {
        SettingSwitch(
          title: "Show Dynamic Island transcript",
          detail: "Show a dark top-center pill while dictation is listening or processing.",
          isOn: $state.dynamicIslandEnabled)
        Picker("Dock at", selection: $state.railDock) {
          Text("Left").tag("left")
          Text("Right").tag("right")
          Text("Bottom").tag("bottom")
        }.pickerStyle(.segmented)
        Text("Drag the handle to adjust its position on a display.").font(.callout).foregroundStyle(
          Palette.secondary)
        DetailDisclosure(
          title: "Accessibility & motion",
          text:
            "Floating controls follow macOS Reduce Motion and Reduce Transparency settings. The workspace stays light and the rail stays dark."
        )
      }
    case "Privacy":
      WorkspaceCard("Cloud processing", icon: "cloud") {
        SettingSwitch(
          title: "Allow cloud AI",
          detail:
            "Transcription, summaries and questions send the required content through your backend to OpenAI. Recording itself stays local.",
          isOn: $state.cloudEnabled)
      }
      StorageSettingsView()
    case "Permissions": PermissionCards(setup: state.setup)
    case "Usage": UsageSettingsView()
    case "Recovery": RequestRecoveryView()
    case "Diagnostics": DictationDiagnosticsView()
    case "Transcription Lab": TranscriptionLabView(lab: state.transcriptionLab)
    default:
      WorkspaceCard("AI connection", subtitle: "Connect to your trusted backend.", icon: "network")
      {
        VStack(alignment: .leading, spacing: 6) {
          Text("Backend URL").font(.caption)
          TextField("https://your-backend.example", text: $state.backendURL).accessibilityLabel(
            "Backend URL")
        }
        VStack(alignment: .leading, spacing: 6) {
          Text("App authentication token").font(.caption)
          SecureField("Stored in Keychain", text: $state.backendToken).accessibilityLabel(
            "App authentication token")
        }
        Button("Save token in Keychain") { state.saveToken() }
        DetailDisclosure(
          title: "Backend setup",
          text:
            "Use backend/.env.example to configure the included backend. Use HTTPS for a remote deployment. This token is for the app connection; never enter an OpenAI project secret here."
        )
      }
      WorkspaceCard("Troubleshooting", icon: "stethoscope") {
        Text("\(state.runningBuild.label) · macOS 15+ · Apple silicon").font(.callout)
          .foregroundStyle(Palette.secondary)
        Button("Export diagnostics…") { state.exportDiagnostics() }
        Text(
          "Exports versions, permissions, timing and counts. Recordings, transcripts, notes and credentials are excluded."
        ).font(.caption).foregroundStyle(Palette.secondary)
      }
    }
  }
}
struct ShortcutSettingsView: View {
  @ObservedObject var registry: ShortcutRegistry
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      WorkspaceCard("Choose your shortcuts", icon: "keyboard") {
        HStack {
          Button("Default preset") { registry.preset(false) }
          Button("No-Fn preset") { registry.preset(true) }
        }
        Text(registry.registrationStatus).font(.caption).foregroundStyle(Palette.secondary)
        Button("Enable / retry registration") { registry.enable() }
        Divider()
        Text(
          "Keep Fn for your Mac keyboard and add Control–Shift for an external keyboard. Every shortcut below stays active."
        )
        .font(.callout).foregroundStyle(Palette.secondary)
        if !registry.bindings.contains(where: {
          $0.action == .holdDictation && $0.modifiers == [.control, .shift] && $0.modifierOnly
        }) {
          Button("Add Control–Shift for dictation") { registry.addControlShift() }
            .disabled(registry.rebinding != nil)
        }
      }
      ForEach(ShortcutAction.allCases) { action in
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text(action.title).font(.headline)
            Spacer()
            Button {
              registry.beginRebind(action)
            } label: {
              Label("Add shortcut", systemImage: "plus")
            }.buttonStyle(.borderless).disabled(registry.rebinding != nil)
              .accessibilityLabel("Add shortcut for \(action.title)")
          }
          let assigned = registry.bindings.filter { $0.action == action }
          ForEach(assigned) { binding in
            VStack(alignment: .leading, spacing: 5) {
              HStack(spacing: 12) {
                Button(
                  registry.rebindingID == binding.id ? "Press keys, then release…" : binding.label
                ) {
                  registry.beginRebind(action, bindingID: binding.id)
                }.font(.system(.body, design: .monospaced))
                  .disabled(registry.rebinding != nil && registry.rebindingID != binding.id)
                  .accessibilityLabel("Edit \(binding.label) for \(action.title)")
                Text(binding.hold ? "Hold" : "Press").font(.caption).foregroundStyle(
                  Palette.secondary)
                Spacer()
                Button {
                  registry.remove(binding.id)
                } label: {
                  Image(systemName: "minus.circle")
                }.buttonStyle(.borderless).disabled(registry.rebinding != nil)
                  .accessibilityLabel("Remove \(binding.label) from \(action.title)")
                  .help("Remove only this shortcut")
              }
              if let error = registry.registrationFailures[binding.id] {
                Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(
                  Palette.red)
              }
            }
          }
          if registry.rebinding == action && registry.rebindingID == nil {
            Label("Press keys, then release…", systemImage: "keyboard")
              .font(.system(.callout, design: .monospaced)).foregroundStyle(Palette.olive)
          } else if assigned.isEmpty {
            Text("No shortcut assigned").font(.caption).foregroundStyle(Palette.secondary)
          }
        }.padding(20).workspaceSurface()
      }
      if registry.rebinding != nil { Button("Cancel rebinding") { registry.cancelRebind() } }
      DetailDisclosure(
        title: "How to record a shortcut",
        text:
          "Press modifiers alone (such as Control–Shift), a key with modifiers, or a side mouse button, then release all keys. Escape cancels, except when assigning Cancel voice action. Changes apply immediately and remain active when Settings closes."
      )
      WorkspaceCard(
        "Try it here", subtitle: "Check a shortcut without starting a voice action.",
        icon: "hand.tap"
      ) {
        Toggle(
          "Test shortcuts without performing actions",
          isOn: Binding(get: { registry.testing }, set: { registry.setTesting($0) }))
        Text(registry.lastTest).font(.system(.caption, design: .monospaced)).padding(12).frame(
          maxWidth: .infinity, alignment: .leading
        ).background(Palette.paper, in: RoundedRectangle(cornerRadius: 7))
        Text(
          "Internal and known system conflicts are checked. Other apps’ shortcut assignments cannot be exhaustively detected. Registered ordinary chords are reserved by macOS. Fn, modifier-only and mouse gestures are monitored without suppressing their system behavior."
        ).font(.caption).foregroundStyle(Palette.secondary)
      }
    }.onDisappear {
      registry.setTesting(false)
      registry.cancelRebind()
    }
  }
}
