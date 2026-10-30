import ChupCore
import SwiftUI

struct DictationView: View {
  @EnvironmentObject var state: WorkspaceState
  private func takeListQuery() {
    if let query = state.listQuery {
      search = query
      state.listQuery = nil
    }
  }
  @State private var showTrash = false
  @State private var search = ""
  @State private var showIgnored = false
  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      HStack(alignment: .top) {
        PageHeader(
          eyebrow: "Talk instead of typing", title: "Dictation",
          subtitle: "Hold your shortcut and talk. Your words go where you type.")
        Spacer()
        Button {
          showTrash = true
        } label: {
          Label(state.trash.isEmpty ? "Trash" : "Trash (\(state.trash.count))", systemImage: "trash")
        }.buttonStyle(.pill)
      }.sheet(isPresented: $showTrash) { TrashView().environmentObject(state) }
      .onAppear(perform: takeListQuery).onChange(of: state.listQuery) { _, _ in takeListQuery() }
      WorkspaceCard {
        HStack(spacing: 22) {
          if state.dictationStatus == .listening {
            VoiceWaveform(samples: state.micWaveform, width: 46, height: 38)
          } else {
            WaveMark()
          }
          VStack(alignment: .leading, spacing: 8) {
            Text(
              state.dictationStatus == .listening ? "Listening to you…" : "Hold your shortcut to talk"
            )
            .font(.system(size: 23, weight: .semibold))
            Text("Use your shortcut in the app you’re typing in.")
              .font(
                .caption
              ).foregroundStyle(Palette.secondary)
          }
          Spacer()
          Button(state.dictationStatus == .listening ? "Finish" : "test") {
            state.toggleDictation()
          }.buttonStyle(.pillPrimary)
          if state.dictationStatus == .listening { Button("Cancel") { state.cancelDictation() } }
        }
        Divider()
        HStack {
          Label("Input: " + state.microphoneLabel, systemImage: "mic")
            .font(.callout).foregroundStyle(Palette.secondary)
          Button("Change microphone") { state.openMicrophoneSettings() }.buttonStyle(.plain)
          Spacer()
        }
      }
      HStack {
        Picker("Writing mode", selection: $state.cleanupMode) {
          ForEach(CleanupMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.frame(width: 250)
        Spacer()
        TextField("Search dictation history", text: $search).textFieldStyle(.roundedBorder).frame(
          width: 240)
      }
      if state.history.contains(where: { $0.status == "ignored" }) {
        Toggle("Show ignored clips", isOn: $showIgnored).toggleStyle(.checkbox)
          .font(.caption).foregroundStyle(Palette.secondary)
      }
      if state.history.isEmpty {
        QuietEmpty(
          icon: "text.cursor", title: "No dictations yet",
          subtitle:
            "Your dictations show here. Copy or retry any of them."
        )
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(
              state.history.filter {
                (showIgnored || $0.status != "ignored")
                  && (search.isEmpty || $0.text.localizedCaseInsensitiveContains(search))
              }
            ) { entry in
              VStack(alignment: .leading, spacing: 13) {
                HStack {
                  Text(entry.created.formatted(date: .abbreviated, time: .shortened))
                  Text("· \(entry.mode)")
                  Spacer()
                  Text(entry.application)
                }.font(.caption).foregroundStyle(Palette.secondary)
                Text(
                  entry.status == "ignored"
                    ? "No speech heard"
                    : (entry.text.isEmpty ? "Audio saved · not transcribed yet" : entry.text)
                ).font(
                  .system(size: 16)
                ).lineSpacing(5).textSelection(.enabled)
                if let microphone = entry.microphoneName {
                  Label(microphone, systemImage: "mic").font(.caption).foregroundStyle(
                    Palette.secondary)
                }
                if let provider = entry.transcriptionProvider {
                  Label(
                    provider, systemImage: provider.hasPrefix("Local") ? "internaldrive" : "cloud"
                  )
                  .font(.caption).foregroundStyle(Palette.secondary)
                }
                if let note = entry.processingNote {
                  Text(note).font(.caption).foregroundStyle(Palette.secondary)
                }
                HStack {
                  Button {
                    state.playDictation(entry)
                  } label: {
                    Label(
                      state.dictationPlaybackID == entry.id && state.dictationPlaying
                        ? "Pause" : "Play recording",
                      systemImage: state.dictationPlaybackID == entry.id && state.dictationPlaying
                        ? "pause.fill" : "play.fill")
                  }.disabled(
                    !state.canPlayDictation
                      || (state.dictationStatus == .listening
                        && state.recordingEntry?.id == entry.id)
                  )
                  .help("Play the saved audio")
                  Button("Copy") { TextInsertion.copy(entry.text) }.disabled(entry.text.isEmpty)
                  Button("Retry audio") { state.retryDictation(entry) }
                  Spacer()
                  Button("Delete", role: .destructive) { state.trashDictations([entry]) }
                }.font(.caption)
                if state.dictationPlaybackID == entry.id {
                  HStack(spacing: 12) {
                    if state.dictationPlaybackLoading && state.dictationPlaybackDuration == 0 {
                      ProgressView().controlSize(.small)
                      Text("Opening recording…").font(.caption)
                    } else {
                      Text(WorkspaceState.time(state.dictationPlaybackTime)).monospacedDigit()
                      Slider(
                        value: Binding(
                          get: { state.dictationPlaybackTime },
                          set: { state.dictationPlayback.seek(to: $0) }),
                        in: 0...max(0.01, state.dictationPlaybackDuration)
                      )
                      .accessibilityLabel("Dictation playback position")
                      Text(WorkspaceState.time(state.dictationPlaybackDuration)).monospacedDigit()
                    }
                  }.font(.caption).foregroundStyle(Palette.secondary)
                }
              }.padding(22).workspaceSurface()
            }
          }
        }
      }
    }.padding(38)
  }
}
struct NotebookView: View {
  @EnvironmentObject var state: WorkspaceState
  @State private var deletion: Meeting?
  @State private var query = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      HStack {
        PageHeader(
          eyebrow: "Your notes", title: "Notebook",
          subtitle: "Notes you write yourself, for any meeting.")
        Spacer()
        Button { state.newMeeting() } label: { Label("New note", systemImage: "square.and.pencil") }
          .buttonStyle(.pillPrimary)
      }
      ListSearchField(placeholder: "Search notebook", text: $query)
      if state.meetings.isEmpty {
        QuietEmpty(
          icon: "book.closed", title: "No notes yet",
          subtitle:
            "Press New note to start one.")
      } else {
        ScrollView {
          LazyVStack(spacing: 14) {
            if !query.isEmpty && !state.meetings.contains(where: {
              "\($0.title) \($0.participants) \($0.tags)".localizedCaseInsensitiveContains(query)
            }) {
              Text("Nothing in your notebook matches “\(query)”.").foregroundStyle(Palette.secondary)
            }
            ForEach(state.meetings.filter {
              query.isEmpty || "\($0.title) \($0.participants) \($0.tags)".localizedCaseInsensitiveContains(query)
            }) { meeting in
              Button {
                state.selectMeeting(meeting.id)
                state.page = .meetings
              } label: {
                VStack(alignment: .leading, spacing: 8) {
                  Text(meeting.title).font(.system(size: 21, weight: .semibold))
                  Text(meeting.created.formatted(date: .abbreviated, time: .omitted)).font(.caption)
                    .foregroundStyle(Palette.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(22).workspaceSurface()
              }.buttonStyle(.plain)
                .contextMenu {
                  Button("Move to Trash", role: .destructive) { deletion = meeting }
                    .disabled(!state.privacyWorkAllowed)
                }
            }
          }
        }
      }
    }.padding(38).confirmDeleteMeeting($deletion)
  }
}
struct PersonalizationView: View {
  @EnvironmentObject var state: WorkspaceState
  let page: WorkspacePage
  @State private var trigger = ""
  @State private var replacement = ""
  @State private var language = "en"
  @State private var mode = CleanupMode.light
  @State private var query = ""
  private func takeListQuery() {
    if let handed = state.listQuery {
      query = handed
      state.listQuery = nil
    }
  }
  var kind: String { page == .dictionary ? "dictionary" : page == .snippets ? "snippet" : "style" }
  var body: some View {
    VStack(alignment: .leading, spacing: 26) {
      PageHeader(
        eyebrow: "Your words", title: page.rawValue,
        subtitle: page == .dictionary
          ? "Names and words Chup! should spell your way."
          : page == .snippets
            ? "Say a short phrase to type something you write often."
            : "How you write in each app.")
      WorkspaceCard(
        page == .styles ? "Add an application style" : "Add a personal entry",
        icon: page == .styles ? "textformat" : "plus.circle"
      ) {
        VStack(alignment: .leading, spacing: 7) {
          Text(
            page == .styles
              ? "Application" : page == .dictionary ? "Spoken alias" : "Spoken trigger"
          ).font(.caption).foregroundStyle(Palette.secondary)
          TextField(page == .styles ? "e.g. com.apple.mail" : "What you say", text: $trigger)
        }
        VStack(alignment: .leading, spacing: 7) {
          Text(
            page == .styles
              ? "Writing style" : page == .dictionary ? "Preferred spelling" : "Expanded text"
          ).font(.caption).foregroundStyle(Palette.secondary)
          TextField(
            page == .styles ? "How you want to sound" : "What Chup! should write",
            text: $replacement, axis: .vertical
          ).lineLimit(1...4)
        }
        HStack {
          Picker("Language", selection: $language) {
            Text("English").tag("en")
            Text("Nederlands").tag("nl")
          }.frame(width: 200)
          if page == .styles {
            Picker("Cleanup", selection: $mode) {
              ForEach(CleanupMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
          }
          Spacer()
          Button("Add entry") {
            state.savePersonalization(
              kind: kind, trigger: trigger, replacement: replacement, language: language,
              mode: page == .styles ? mode.rawValue : nil)
            trigger = ""
            replacement = ""
          }.buttonStyle(.pillPrimary).disabled(trigger.isEmpty || replacement.isEmpty)
        }
      }.textFieldStyle(.roundedBorder)
      ListSearchField(placeholder: "Search \(page.rawValue.lowercased())", text: $query)
        .onAppear(perform: takeListQuery).onChange(of: state.listQuery) { _, _ in takeListQuery() }
      if !state.personalization.contains(where: { $0.kind == kind }) {
        QuietEmpty(
          icon: page.icon, title: "Nothing here yet",
          subtitle: "Add your first entry above.")
      } else {
        ScrollView {
          LazyVStack(spacing: 12) {
            if !query.isEmpty && !state.personalization.contains(where: {
              $0.kind == kind && "\($0.trigger) \($0.replacement)".localizedCaseInsensitiveContains(query)
            }) {
              Text("No entries match “\(query)”.").foregroundStyle(Palette.secondary)
            }
            ForEach(state.personalization.filter {
              $0.kind == kind
                && (query.isEmpty || "\($0.trigger) \($0.replacement)".localizedCaseInsensitiveContains(query))
            }) { item in
              HStack {
                VStack(alignment: .leading, spacing: 8) {
                  Text(item.trigger).font(.headline)
                  Text(item.replacement).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Text(item.language.uppercased()).font(.caption)
                Button("Edit") {
                  trigger = item.trigger
                  replacement = item.replacement
                  language = item.language
                  mode = CleanupMode(rawValue: item.mode ?? "") ?? .light
                }.buttonStyle(.borderless)
                Button {
                  state.deletePersonalization(item)
                } label: {
                  Image(systemName: "trash")
                }.buttonStyle(.plain).accessibilityLabel("Delete \(item.trigger)")
              }.padding(18).workspaceSurface()
            }
          }
        }
      }
    }.padding(38)
  }
}
struct AssistantView: View {
  @EnvironmentObject var state: WorkspaceState
  @Environment(\.dismiss) private var dismissSheet
  @State private var question = ""
  /// Set when shown as the meeting page's side panel instead of a sheet.
  var onClose: (() -> Void)?
  private func dismiss() { onClose.map { $0() } ?? dismissSheet() }
  private var mode: AssistantMode { state.voiceMode }
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        Text("Ask about this meeting").font(.system(size: 29, weight: .semibold))
        Spacer()
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
        }.buttonStyle(.plain).accessibilityLabel("Close assistant")
      }
      Text(state.selectedMeeting?.title ?? "Open a meeting first.").font(
        .caption
      ).foregroundStyle(Palette.secondary)
      Picker("Conversation mode", selection: $state.voiceMode) {
        ForEach(AssistantMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }.pickerStyle(.segmented).onChange(of: mode) { _, _ in state.endVoice() }
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if let notice = state.notice {
            Label(notice, systemImage: "info.circle").font(.caption).foregroundStyle(
              Palette.secondary
            ).textSelection(.enabled)
          }
          if mode != .privateText {
            AssistantVoiceControls(voice: state.voice, router: state.voiceRouter, mode: mode)
          }
          if state.assistantHistory.isEmpty {
            Text("What did we decide?\nWhat should happen next?").font(
              .system(size: 25, weight: .semibold)
            )
            .foregroundStyle(Palette.secondary)
            Text(
              "Ask a question, or ask Chup! to add to your notes."
            )
            .font(.callout).foregroundStyle(Palette.secondary)
          }
          ForEach(state.assistantHistory) { exchange in
            VStack(alignment: .leading, spacing: 12) {
              Text(exchange.question).font(.system(size: 19, weight: .semibold)).textSelection(
                .enabled)
              if exchange.status == "pending" {
                Label("Searching the meeting…", systemImage: "ellipsis").foregroundStyle(
                  Palette.secondary)
              } else {
                Text(exchange.answer).font(.system(size: 15)).lineSpacing(4).textSelection(.enabled)
                  .foregroundStyle(exchange.status == "failed" ? Palette.red : Palette.ink)
              }
              ForEach(exchange.sources.indices, id: \.self) { index in
                let source = exchange.sources[index]
                Button {
                  if let segment = state.segments.first(where: { $0.id == source.segmentID }) {
                    state.play(at: segment.start)
                  }
                } label: {
                  Label(source.quote, systemImage: "quote.bubble")
                }
                .buttonStyle(.borderless).font(.caption)
              }
              if exchange.status == "committed" {
                Label(
                  exchange.write?.operation == "create_action_item"
                    ? "Action saved" : "Saved to My notes", systemImage: "checkmark.circle"
                ).font(.caption)
                  .foregroundStyle(Palette.accent)
              } else if exchange.write != nil && exchange.status == "completed" {
                Button(
                  exchange.write?.operation == "create_action_item"
                    ? "Review action" : "Review note change"
                ) { state.reviewAssistantWrite(exchange) }.font(.caption)
              }
            }.padding(20).workspaceSurface()
          }
          if let write = state.pendingWrite {
            VStack(alignment: .leading, spacing: 12) {
              Text(
                write.operation == "create_action_item" ? "Proposed action" : "Proposed note change"
              ).font(.headline)
              Text(write.text).textSelection(.enabled)
              Button(write.operation == "create_action_item" ? "Save action" : "Save to My notes") {
                state.applyAssistantWrite()
              }.buttonStyle(
                .borderedProminent)
            }.padding(20).workspaceSurface()
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
      HStack {
        TextField("Ask this meeting…", text: $question).textFieldStyle(.roundedBorder).onSubmit(
          send)
        if state.assistantBusy {
          ProgressView().controlSize(.small)
          Button("Cancel") { state.cancelAssistant() }
        }
        Button("Ask", action: send).buttonStyle(.pillPrimary).disabled(
          state.assistantBusy || question.isEmpty || mode != .privateText)
      }
      Label("Only this meeting goes to AI.", systemImage: "lock")
        .font(.caption).foregroundStyle(Palette.secondary)
    }.padding(30).background(Palette.workspace).foregroundStyle(Palette.ink).tint(Palette.accent)
  }
  func send() {
    guard mode == .privateText, !question.isEmpty, !state.assistantBusy else { return }
    state.ask(question)
    if state.assistantBusy { question = "" }
  }
}

/// The filter field every module list shares.
struct ListSearchField: View {
  let placeholder: String
  @Binding var text: String
  var body: some View {
    HStack {
      Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
      TextField(placeholder, text: $text).textFieldStyle(.plain)
      if !text.isEmpty {
        Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
          .buttonStyle(.plain).foregroundStyle(Palette.secondary).accessibilityLabel("Clear search")
      }
    }.padding(11).background(Palette.paper, in: RoundedRectangle(cornerRadius: 8))
  }
}
