import ChupCore
import SwiftUI

struct SettingsView: View {
  @EnvironmentObject var state: WorkspaceState
  @State var section = "General"
  /// Six sections; each shows one or more of the original pages, so every control keeps its home.
  let sections = ["General", "Dictation", "Meetings", "AI & Assistant", "Privacy & Data", "Advanced"]
  static let pages: [String: [String]] = [
    "General": ["General", "Permissions", "Appearance"],
    "Dictation": ["Dictation", "Shortcuts", "Audio"],
    "Meetings": ["Meetings"],
    "AI & Assistant": ["Assistant"],
    "Privacy & Data": ["Privacy"],
    "Advanced": ["Advanced", "Usage", "Recovery", "Diagnostics", "Transcription Lab"],
  ]
  /// Filled tiles: symbol on a coloured square, like System Settings.
  private static let tiles: [String: (icon: String, color: Color)] = [
    "General": ("gearshape.fill", Color(red: 0.45, green: 0.45, blue: 0.50)),
    "Dictation": ("waveform", Palette.violet),
    "Meetings": ("person.2.fill", Color(red: 0.85, green: 0.38, blue: 0.27)),
    "AI & Assistant": ("sparkles", Color(red: 0.76, green: 0.22, blue: 0.49)),
    "Privacy & Data": ("lock.fill", Color(red: 0.12, green: 0.54, blue: 0.44)),
    "Advanced": ("wrench.and.screwdriver.fill", Color(red: 0.30, green: 0.36, blue: 0.46)),
  ]
  private let descriptions = [
    "General": "Start-up, permissions and how Chup! looks.",
    "Dictation": "Shortcuts, microphone and how your words become text.",
    "Meetings": "Recording, transcripts and summaries.",
    "AI & Assistant": "Ask questions about your meetings.",
    "Privacy & Data": "Cloud AI, storage and deleting data.",
    "Advanced": "Usage, recovery, diagnostics and the transcription lab.",
  ]
  /// `section` may hold an original page name (deep links, renders); this is its section.
  private var home: String {
    sections.contains(section)
      ? section : Self.pages.first { $0.value.contains(section) }?.key ?? "General"
  }
  private var advancedPage: String {
    Self.pages["Advanced"]!.contains(section) ? section : "Advanced"
  }
  static func tile(_ name: String, size: CGFloat = 22) -> some View {
    let tile = tiles[name] ?? ("circle", .gray)
    return Image(systemName: tile.icon).font(.system(size: size * 0.5, weight: .semibold))
      .foregroundStyle(.white).frame(width: size, height: size)
      .background(tile.color, in: RoundedRectangle(cornerRadius: size * 0.27))
      .accessibilityHidden(true)
  }
  var body: some View {
    HStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 4) {
          Text("Settings").font(.system(size: 25, weight: .semibold)).padding(.horizontal, 10).padding(
            .bottom, 20)
          ForEach(sections, id: \.self) { name in
            if name == "Advanced" { Divider().padding(.vertical, 8) }
            Button {
              section = name
            } label: {
              HStack(spacing: 10) {
                Self.tile(name)
                Text(name).font(.system(size: 13))
                Spacer(minLength: 0)
              }.padding(.horizontal, 10).padding(.vertical, 10).contentShape(Rectangle())
                .background(
                  home == name ? Palette.paper : .clear, in: RoundedRectangle(cornerRadius: 9))
            }.buttonStyle(.plain).foregroundStyle(home == name ? Palette.ink : Palette.secondary)
              .accessibilityLabel(name).accessibilityAddTraits(home == name ? .isSelected : [])
          }
        }.padding(.horizontal, 12).padding(.vertical, 24)
      }.frame(width: 186).background(Palette.sidebar)
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
              Self.tile(home, size: 34)
              Text(home).font(Palette.title).accessibilityAddTraits(.isHeader)
            }
            Text(descriptions[home] ?? "").font(.system(size: 14)).foregroundStyle(
              Palette.secondary)
          }.padding(.bottom, 8)
          if home == "Advanced" {
            Picker("Advanced", selection: Binding(get: { advancedPage }, set: { section = $0 })) {
              ForEach(Self.pages["Advanced"]!, id: \.self) { name in
                Text(name == "Advanced" ? "Connection" : name).tag(name)
              }
            }.pickerStyle(.segmented).labelsHidden()
            page(advancedPage)
          } else {
            ForEach(Self.pages[home] ?? [], id: \.self) { name in
              if (Self.pages[home]?.count ?? 0) > 1 {
                Text(name).font(.system(size: 18, weight: .semibold)).padding(.top, 10)
                  .accessibilityAddTraits(.isHeader)
              }
              page(name)
            }
          }
        }.frame(maxWidth: 720, alignment: .leading).padding(28).frame(maxWidth: .infinity)
      }.background(Palette.workspace)
    }.foregroundStyle(Palette.ink).tint(Palette.accent).textFieldStyle(.roundedBorder)
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
  @ViewBuilder private func page(_ name: String) -> some View {
    switch name {
    case "General":
      WorkspaceCard("Floating rail", icon: "cursorarrow.rays") {
        SettingSwitch(
          title: "Show the floating rail",
          detail: "Keep voice controls at the edge of your screen.", isOn: $state.showRail)
      }
      WorkspaceCard("Open at login", icon: "sun.max") { LoginSettings(setup: state.setup) }
      WorkspaceCard("Setup", icon: "checkmark.shield") {
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
        "Meeting audio", subtitle: "Record what the other people say.",
        icon: "person.wave.2"
      ) {
        SettingSwitch(
          title: "Use alternative audio capture",
          detail: "Try this if your call app’s audio doesn’t record.",
          isOn: $state.captureFallback)
        DetailDisclosure(
          title: "How call audio is recorded",
          text:
            "Chup! records the call app’s sound directly. The other option needs Screen & System Audio Recording access. Neither one saves video."
        )
      }
    case "Dictation":
      LocalSpeechSettings(service: state.localSpeech)
      WorkspaceCard(
        "Writing preferences", subtitle: "How much Chup! tidies your words.",
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
        Text("Chup! doesn’t translate. Automatic picks English or Dutch for each recording.")
          .font(.callout).foregroundStyle(Palette.secondary)
      }
    case "Meetings":
      WorkspaceCard("Call alerts", icon: "bell") {
        SettingSwitch(
          title: "Suggest meeting notes",
          detail:
            "A prompt shows for 10 seconds. Recording starts only when you press Record.",
          isOn: $state.meetingDetectionEnabled)
        DetailDisclosure(
          title: "About browser calls",
          text:
            "Chup! can’t tell which browser tab is the call. Check the app before you record."
        )
      }
      WorkspaceCard("Transcripts & summaries", icon: "text.bubble") {
        SettingSwitch(
          title: "Live captions",
          detail: "Show text while you record. Uses cloud AI.",
          isOn: $state.liveCaptionsEnabled)
        Divider()
        SettingSwitch(
          title: "Live notes",
          detail: "Write notes while you record. Uses cloud AI.",
          isOn: $state.liveOutlineEnabled)
        Divider()
        SettingSwitch(
          title: "Final summary", detail: "Write a summary when the meeting ends.",
          isOn: $state.autoSummaryEnabled)
      }
      VoiceEnrollmentSettings()
    case "Assistant":
      WorkspaceCard("How to ask", icon: "sparkles") {
        Text("Choose Private text, Private voice or Speak in meeting from the assistant.").font(
          .callout
        ).foregroundStyle(Palette.secondary)
        InlineStatus(
          text:
            "The assistant acts only on questions you ask it.",
          icon: "hand.raised")
        DetailDisclosure(
          title: "Voice setup & privacy",
          text:
            "Voice questions go to GPT-Live-1. Use headphones. In a call, private voice needs the Chup! Mic."
        )
      }
      WorkspaceCard("Recent voice sessions", icon: "clock") {
        if state.usageRecords.isEmpty {
          Text("Your voice sessions show here.").foregroundStyle(Palette.secondary)
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
        Button("See usage and costs") { section = "Usage" }
      }
    case "Appearance":
      WorkspaceCard(
        "Look", subtitle: "A light window with dark floating controls.",
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
          title: "Use the Dynamic Island",
          detail:
            "On a Mac with a notch, show live text and controls under the notch. Other screens keep the rail.",
          isOn: $state.dynamicIslandEnabled)
        Picker("Dock at", selection: $state.railDock) {
          Text("Left").tag("left")
          Text("Right").tag("right")
          Text("Bottom").tag("bottom")
        }.pickerStyle(.segmented)
        Text("Drag the handle to move the rail.").font(.callout).foregroundStyle(
          Palette.secondary)
        DetailDisclosure(
          title: "Accessibility & motion",
          text:
            "Floating controls follow Reduce Motion and Reduce Transparency in macOS."
        )
      }
    case "Privacy":
      WorkspaceCard("Cloud processing", icon: "cloud") {
        SettingSwitch(
          title: "Allow cloud AI",
          detail:
            "Transcripts, summaries and questions send content to OpenAI. Recording alone sends nothing.",
          isOn: $state.cloudEnabled)
      }
      WorkspaceCard("AI tools (MCP)", icon: "point.3.connected.trianglepath.dotted") {
        SettingSwitch(
          title: "Let AI tools read meetings",
          detail:
            "Claude and other AI apps can read your meetings while Chup! is open. They can’t change anything or see private thoughts.",
          isOn: $state.mcpEnabled)
        if state.mcpEnabled {
          Text("Add to your MCP client: command \"\(Bundle.main.executablePath ?? "/Applications/Chup!.app/Contents/MacOS/Chup!")\" with argument --mcp")
            .font(.caption).textSelection(.enabled).foregroundStyle(Palette.secondary)
        }
      }
      StorageSettingsView()
    case "Permissions": PermissionCards(setup: state.setup)
    case "Usage": UsageSettingsView()
    case "Recovery": RequestRecoveryView()
    case "Diagnostics": DictationDiagnosticsView()
    case "Transcription Lab": TranscriptionLabView(lab: state.transcriptionLab)
    default:
      WorkspaceCard("AI connection", subtitle: "Your Chup! server.", icon: "network")
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
            "Set up the server with backend/.env.example. Use https for a remote server. Never paste an OpenAI key here."
        )
      }
      WorkspaceCard("Troubleshooting", icon: "stethoscope") {
        Text("\(state.runningBuild.label) · macOS 15+ · Apple silicon").font(.callout)
          .foregroundStyle(Palette.secondary)
        Button("Export diagnostics…") { state.exportDiagnostics() }
        Text(
          "Includes versions, permissions and counts. No recordings, text or passwords."
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
          "Keep Fn on your Mac keyboard. Add Control–Shift for an external keyboard."
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
              .font(.system(.callout, design: .monospaced)).foregroundStyle(Palette.accent)
          } else if assigned.isEmpty {
            Text("No shortcut assigned").font(.caption).foregroundStyle(Palette.secondary)
          }
        }.padding(20).workspaceSurface()
      }
      if registry.rebinding != nil { Button("Cancel rebinding") { registry.cancelRebind() } }
      DetailDisclosure(
        title: "How to record a shortcut",
        text:
          "Press the keys or a side mouse button, then let go. Escape cancels. Changes save at once."
      )
      WorkspaceCard(
        "Try it here", subtitle: "Press a shortcut to see if it works.",
        icon: "hand.tap"
      ) {
        Toggle(
          "Test shortcuts without performing actions",
          isOn: Binding(get: { registry.testing }, set: { registry.setTesting($0) }))
        Text(registry.lastTest).font(.system(.caption, design: .monospaced)).padding(12).frame(
          maxWidth: .infinity, alignment: .leading
        ).background(Palette.paper, in: RoundedRectangle(cornerRadius: 7))
        Text(
          "Chup! checks its own shortcuts. It can’t see every shortcut in other apps."
        ).font(.caption).foregroundStyle(Palette.secondary)
      }
    }.onDisappear {
      registry.setTesting(false)
      registry.cancelRebind()
    }
  }
}
