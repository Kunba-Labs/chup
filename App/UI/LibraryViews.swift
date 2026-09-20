import ChupCore
import SwiftUI

struct DictationView: View {
  @EnvironmentObject var state: WorkspaceState
  @State private var search = ""
  @State private var showIgnored = false
  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      PageHeader(
        eyebrow: "From thought to words", title: "Dictation",
        subtitle: "Speak naturally. Keep your voice in what you write.")
      WorkspaceCard {
        HStack(spacing: 22) {
          if state.dictationStatus == .listening {
            VoiceWaveform(samples: state.micWaveform, width: 46, height: 38, color: Palette.red)
          } else {
            WaveMark(color: Palette.olive)
          }
          VStack(alignment: .leading, spacing: 8) {
            Text(
              state.dictationStatus == .listening ? "Listening to you…" : "A little less typing."
            )
            .font(.system(size: 23, design: .serif))
            Text("Use your global shortcut in another app to preserve the intended text field.")
              .font(
                .caption
              ).foregroundStyle(Palette.secondary)
          }
          Spacer()
          Button(state.dictationStatus == .listening ? "Finish" : "test") {
            state.toggleDictation()
          }.buttonStyle(.borderedProminent)
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
          icon: "text.cursor", title: "Your words, safely kept",
          subtitle:
            "Completed dictations and recoverable audio appear here. Copy, retry, or paste your last result with a shortcut."
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
                    ? "Not transcribed · no usable speech"
                    : (entry.text.isEmpty ? "Audio saved · transcription needed" : entry.text)
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
                  .help("Listen to the saved audio without transcription or cloud access")
                  Button("Copy") { TextInsertion.copy(entry.text) }.disabled(entry.text.isEmpty)
                  Button("Retry audio") { state.retryDictation(entry) }
                  Spacer()
                  Button("Delete", role: .destructive) { state.deleteDictation(entry) }
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
  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      HStack {
        PageHeader(
          eyebrow: "Things worth keeping", title: "Notebook",
          subtitle: "Your own words, separate from every generated summary.")
        Spacer()
        Button("New note") { state.newMeeting() }
      }
      if state.meetings.isEmpty {
        QuietEmpty(
          icon: "book.closed", title: "A place for your thinking",
          subtitle:
            "Create a meeting note and write freely, before, during, or after a conversation.")
      } else {
        ScrollView {
          LazyVStack(spacing: 14) {
            ForEach(state.meetings) { meeting in
              Button {
                state.selectMeeting(meeting.id)
                state.page = .meetings
              } label: {
                VStack(alignment: .leading, spacing: 8) {
                  Text(meeting.title).font(.system(size: 21, design: .serif))
                  Text(meeting.created.formatted(date: .abbreviated, time: .omitted)).font(.caption)
                    .foregroundStyle(Palette.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(22).workspaceSurface()
              }.buttonStyle(.plain)
            }
          }
        }
      }
    }.padding(38)
  }
}
struct PersonalizationView: View {
  @EnvironmentObject var state: WorkspaceState
  let page: WorkspacePage
  @State private var trigger = ""
  @State private var replacement = ""
  @State private var language = "en"
  @State private var mode = CleanupMode.light
  var kind: String { page == .dictionary ? "dictionary" : page == .snippets ? "snippet" : "style" }
  var body: some View {
    VStack(alignment: .leading, spacing: 26) {
      PageHeader(
        eyebrow: "Make it sound like you", title: page.rawValue,
        subtitle: page == .dictionary
          ? "Names, acronyms, product names and preferred spellings. Used for dictation and meeting transcripts."
          : page == .snippets
            ? "A short spoken phrase for something you write often."
            : "Writing preferences for each application and language.")
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
          }.buttonStyle(.borderedProminent).disabled(trigger.isEmpty || replacement.isEmpty)
        }
      }.textFieldStyle(.roundedBorder)
      if !state.personalization.contains(where: { $0.kind == kind }) {
        QuietEmpty(
          icon: page.icon, title: "Make this space yours",
          subtitle: "Add your first entry above. Your preferences will appear here.")
      } else {
        ScrollView {
          LazyVStack(spacing: 12) {
            ForEach(state.personalization.filter { $0.kind == kind }) { item in
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
  @Environment(\.dismiss) var dismiss
  @State private var question = ""
  private var mode: AssistantMode { state.voiceMode }
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        Text("A thought partner").font(.system(size: 29, design: .serif))
        Spacer()
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
        }.buttonStyle(.plain).accessibilityLabel("Close assistant")
      }
      Text(state.selectedMeeting?.title ?? "Open a meeting to give the assistant context.").font(
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
              .system(size: 25, design: .serif)
            )
            .foregroundStyle(Palette.secondary)
            Text(
              "Ask about this meeting, or ask to add something to My notes. Your conversation is saved locally with this meeting."
            )
            .font(.callout).foregroundStyle(Palette.secondary)
          }
          ForEach(state.assistantHistory) { exchange in
            VStack(alignment: .leading, spacing: 12) {
              Text(exchange.question).font(.system(size: 19, design: .serif)).textSelection(
                .enabled)
              if exchange.status == "pending" {
                Label("Looking through this meeting…", systemImage: "ellipsis").foregroundStyle(
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
                  .foregroundStyle(Palette.olive)
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
        Button("Ask", action: send).buttonStyle(.borderedProminent).disabled(
          state.assistantBusy || question.isEmpty || mode != .privateText)
      }
      Label("Only this meeting is shared with your configured AI backend.", systemImage: "lock")
        .font(.caption).foregroundStyle(Palette.secondary)
    }.padding(30).background(Palette.workspace).foregroundStyle(Palette.ink).tint(Palette.olive)
  }
  func send() {
    guard mode == .privateText, !question.isEmpty, !state.assistantBusy else { return }
    state.ask(question)
    if state.assistantBusy { question = "" }
  }
}
