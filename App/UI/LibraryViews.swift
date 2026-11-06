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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    ScrollViewReader { proxy in
    VStack(alignment: .leading, spacing: 28) {
      HStack(alignment: .top) {
        PageHeader(
          eyebrow: "Talk instead of typing", title: "Dictation",
          subtitle: "Hold your shortcut and talk. Your words go where you type.")
        Spacer()
        VStack(alignment: .trailing, spacing: 8) {
          HStack(spacing: 10) {
            Picker("Writing mode", selection: $state.cleanupMode) {
              ForEach(CleanupMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.labelsHidden().fixedSize().help("Writing mode")
            TextField("Search dictation history", text: $search).textFieldStyle(.roundedBorder)
              .frame(width: 220)
            Button {
              showTrash = true
            } label: {
              Label(state.trash.isEmpty ? "Trash" : "Trash (\(state.trash.count))", systemImage: "trash")
            }.buttonStyle(.pill)
          }
          if state.history.contains(where: { $0.status == "ignored" }) {
            Toggle("Show ignored clips", isOn: $showIgnored).toggleStyle(.checkbox)
              .font(.detail).foregroundStyle(Palette.secondary)
          }
        }
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
            .font(.sectionTitle)
            Text("Use your shortcut in the app you’re typing in.")
              .font(
                .caption
              ).foregroundStyle(Palette.secondary)
          }
          Spacer()
          Button(state.dictationStatus == .listening ? "Finish" : "test") {
            state.toggleDictation()
          }.buttonStyle(.pillPrimary)
          if state.dictationStatus == .listening { Button("Cancel") { state.cancelDictation(reason: "Dictation page Cancel") } }
        }
        Divider()
        HStack {
          Label("Input: " + state.microphoneLabel, systemImage: "mic")
            .font(.detail).foregroundStyle(Palette.secondary)
          Button("Change microphone") { state.openMicrophoneSettings() }.buttonStyle(.plain)
          Spacer()
        }
      }
      if state.history.isEmpty {
        QuietEmpty(
          icon: "text.cursor", title: "No dictations yet",
          subtitle:
            "Your dictations show here. Copy or retry any of them."
        )
      } else {
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
                  if !(state.dictationStatus == .listening && state.recordingEntry?.id == entry.id) {
                    MiniWaveform(source: .dictation(id: entry.id, directory: entry.audioDirectory), width: 60, height: 16)
                  }
                  Text(entry.application)
                }.font(.detail).foregroundStyle(Palette.secondary)
                Text(
                  entry.status == "ignored"
                    ? "No speech heard"
                    : (entry.text.isEmpty ? "Audio saved · not transcribed yet" : entry.text)
                ).font(
                  .reading
                ).lineSpacing(5).textSelection(.enabled)
                // Statuses side by side as small tags; a warning is a yellow mark.
                HStack(spacing: 6) {
                  if let microphone = entry.microphoneName { StatusTag(text: microphone, icon: "mic") }
                  if let provider = entry.transcriptionProvider {
                    StatusTag(text: provider, icon: provider.hasPrefix("Local") ? "internaldrive" : "cloud")
                  }
                  // Older entries saved this as a note; it is the normal local result, not a warning.
                  if let note = entry.processingNote, note != "Plain local transcript · cloud cleanup not applied" {
                    StatusTag(text: note, icon: "exclamationmark.triangle.fill", warning: true)
                  }
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
                }.buttonStyle(.pill).controlSize(.small)
                if state.dictationPlaybackID == entry.id {
                  HStack(spacing: 12) {
                    if state.dictationPlaybackLoading && state.dictationPlaybackDuration == 0 {
                      ProgressView().controlSize(.small)
                      Text("Opening recording…").font(.detail)
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
                  }.font(.detail).foregroundStyle(Palette.secondary)
                }
              }.padding(22).workspaceSurface()
                .overlay {
                  if state.dictationFocusID == entry.id {
                    RoundedRectangle(cornerRadius: 0).strokeBorder(Palette.accent, lineWidth: 2)
                  }
                }
                .id(entry.id)
            }
          }
      }
    }.padding(38).pageScroll()
      // Opened from Today: scroll to that clip and outline it.
      .onChange(of: state.dictationFocusID, initial: true) { _, id in
        guard let id else { return }
        search = ""
        if state.history.first(where: { $0.id == id })?.status == "ignored" { showIgnored = true }
        DispatchQueue.main.async {
          withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(id, anchor: .center) }
        }
      }
      .onDisappear { state.dictationFocusID = nil }
    }
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
                  Text(meeting.title).font(.sectionTitle)
                  Text(meeting.created.formatted(date: .abbreviated, time: .omitted)).font(.detail)
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
    }.padding(38).pageScroll().confirmDeleteMeeting($deletion)
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
          ).font(.detail).foregroundStyle(Palette.secondary)
          TextField(page == .styles ? "e.g. com.apple.mail" : "What you say", text: $trigger)
        }
        VStack(alignment: .leading, spacing: 7) {
          Text(
            page == .styles
              ? "Writing style" : page == .dictionary ? "Preferred spelling" : "Expanded text"
          ).font(.detail).foregroundStyle(Palette.secondary)
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
                  Text(item.trigger).font(.ui.weight(.semibold))
                  Text(item.replacement).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Text(item.language.uppercased()).font(.detail)
                Button("Edit") {
                  trigger = item.trigger
                  replacement = item.replacement
                  language = item.language
                  mode = CleanupMode(rawValue: item.mode ?? "") ?? .light
                }.buttonStyle(.pill).controlSize(.small)
                Button {
                  state.deletePersonalization(item)
                } label: {
                  Image(systemName: "trash")
                }.buttonStyle(.plain).accessibilityLabel("Delete \(item.trigger)")
              }.padding(18).workspaceSurface()
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
        Text("Ask about this meeting").font(.pageTitle)
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
      PillSegmented(title: "Conversation mode", selection: $state.voiceMode, options: AssistantMode.allCases) { $0.rawValue }
        .onChange(of: mode) { _, _ in state.endVoice() }
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if let notice = state.notice {
            Label(notice, systemImage: "info.circle").font(.detail).foregroundStyle(
              Palette.secondary
            ).textSelection(.enabled)
          }
          if mode != .privateText {
            AssistantVoiceControls(voice: state.voice, router: state.voiceRouter, mode: mode)
          }
          if state.assistantHistory.isEmpty {
            Text("What did we decide?\nWhat should happen next?").font(
              .pageTitle
            )
            .foregroundStyle(Palette.secondary)
            Text(
              "Ask a question, or ask Chup! to add to your notes."
            )
            .font(.detail).foregroundStyle(Palette.secondary)
          }
          ForEach(state.assistantHistory) { exchange in
            VStack(alignment: .leading, spacing: 12) {
              Text(exchange.question).font(.sectionTitle).textSelection(
                .enabled)
              if exchange.status == "pending" {
                Label("Searching the meeting…", systemImage: "ellipsis").foregroundStyle(
                  Palette.secondary)
              } else {
                Text(exchange.answer).font(.reading).lineSpacing(4).textSelection(.enabled)
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
                .buttonStyle(.borderless).font(.detail)
              }
              if exchange.status == "committed" {
                Label(
                  exchange.write?.operation == "create_action_item"
                    ? "Action saved" : "Saved to My notes", systemImage: "checkmark.circle"
                ).font(.detail)
                  .foregroundStyle(Palette.accent)
              } else if exchange.write != nil && exchange.status == "completed" {
                Button(
                  exchange.write?.operation == "create_action_item"
                    ? "Review action" : "Review note change"
                ) { state.reviewAssistantWrite(exchange) }.font(.detail)
              }
            }.padding(20).workspaceSurface()
          }
          if let write = state.pendingWrite {
            VStack(alignment: .leading, spacing: 12) {
              Text(
                write.operation == "create_action_item" ? "Proposed action" : "Proposed note change"
              ).font(.ui.weight(.semibold))
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
        .font(.detail).foregroundStyle(Palette.secondary)
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
    }.padding(11).background(Palette.paper, in: RoundedRectangle(cornerRadius: 0))
  }
}

/// A compact status chip: icon and short text in a ruled block; warnings are yellow marks.
struct StatusTag: View {
  let text: String
  let icon: String
  var warning = false
  var body: some View {
    Label(text, systemImage: icon).labelStyle(TagLabelStyle()).font(.detail.weight(.medium)).lineLimit(1)
      .padding(.horizontal, 7).padding(.vertical, 3)
      .foregroundStyle(warning ? Palette.onStar : Palette.secondary)
      .background(warning ? Palette.star : Palette.paper)
      .overlay { if !warning { Rectangle().strokeBorder(Palette.border) } }
      .help(text)
  }
}
private struct TagLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 5) { configuration.icon.imageScale(.small); configuration.title }
  }
}
