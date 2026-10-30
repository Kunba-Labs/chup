import ChupCore
import SwiftUI

struct MeetingActionsView: View {
  @EnvironmentObject var state: WorkspaceState
  @State private var title = ""
  /// Inside the Notes pane: no own scroll view, smaller heading.
  var embedded = false
  var body: some View {
    VStack(alignment: .leading, spacing: embedded ? 10 : 18) {
      Text(embedded ? "Action items" : "What happens next")
        .font(.system(size: embedded ? 17 : 25, weight: .semibold)).padding(.top, embedded ? 0 : 24)
      HStack {
        TextField("Add an action…", text: $title).onSubmit(add)
        Button("Add", action: add).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
      }
      scrollable {
        ForEach(state.actions.filter { $0.status != "archived" }) { action in
          if embedded { compactRow(action) } else {
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Toggle(
                "",
                isOn: Binding(
                  get: { action.status == "done" },
                  set: { value in
                    var copy = action
                    copy.status = value ? "done" : "open"
                    state.saveAction(copy)
                  })
              ).labelsHidden().accessibilityLabel("Complete " + action.title)
              Text(action.title).font(.system(size: 17)).strikethrough(action.status == "done")
              Spacer()
            }
            HStack {
              TextField(
                "No owner",
                text: Binding(
                  get: { action.owner ?? "" },
                  set: { value in
                    var copy = action
                    copy.owner = value.isEmpty ? nil : value
                    state.saveAction(copy)
                  }))
              TextField(
                "No due date",
                text: Binding(
                  get: { action.dueDate ?? "" },
                  set: { value in
                    var copy = action
                    copy.dueDate = value.isEmpty ? nil : value
                    state.saveAction(copy)
                  }))
            }
            ForEach(action.sources.indices, id: \.self) { index in
              SourceLink(source: action.sources[index], label: action.sources[index].quote)
            }
          }.padding(20).workspaceSurface()
          }
        }
      }
      Button("Undo") { state.undoAction() }.disabled(
        state.lastActionReceipt == nil)
    }
  }
  /// One checklist line: tick, title, owner and date inline, first source as a link.
  private func compactRow(_ action: ActionRecord) -> some View {
    HStack(spacing: 10) {
      Toggle(
        "",
        isOn: Binding(
          get: { action.status == "done" },
          set: { value in
            var copy = action
            copy.status = value ? "done" : "open"
            state.saveAction(copy)
          })
      ).labelsHidden().accessibilityLabel("Complete " + action.title)
      Text(action.title).font(.system(size: 14)).strikethrough(action.status == "done")
        .foregroundStyle(action.status == "done" ? Palette.secondary : Palette.ink)
      Spacer(minLength: 8)
      TextField(
        "Owner",
        text: Binding(
          get: { action.owner ?? "" },
          set: { value in
            var copy = action
            copy.owner = value.isEmpty ? nil : value
            state.saveAction(copy)
          })
      ).textFieldStyle(.plain).font(.caption).foregroundStyle(Palette.secondary).frame(width: 96)
      TextField(
        "Due",
        text: Binding(
          get: { action.dueDate ?? "" },
          set: { value in
            var copy = action
            copy.dueDate = value.isEmpty ? nil : value
            state.saveAction(copy)
          })
      ).textFieldStyle(.plain).font(.caption).foregroundStyle(Palette.secondary).frame(width: 90)
      if let source = action.sources.first { SourceLink(source: source) }
    }.padding(.vertical, 8).padding(.horizontal, 12).workspaceSurface()
  }
  @ViewBuilder private func scrollable(@ViewBuilder _ content: () -> some View) -> some View {
    if embedded { VStack(spacing: 8) { content() } } else { ScrollView { content() } }
  }
  private func add() {
    guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    state.addAction(title)
    title = ""
  }
}
struct PrivateThoughtsView: View {
  @EnvironmentObject var state: WorkspaceState
  var embedded = false
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if !embedded {
        Text("Just for you").font(.system(size: 25, weight: .semibold)).padding(.top, 24)
      }
      Label("Only you see these. They never go to AI.", systemImage: "lock")
        .font(.caption).foregroundStyle(Palette.secondary)
      TextEditor(text: $state.thoughtsDraft).font(.system(size: 17)).scrollContentBackground(
        .hidden
      )
      .padding(16).frame(minHeight: embedded ? 140 : nil).workspaceSurface()
      .onChange(of: state.thoughtsDraft) { _, text in state.saveThoughts(text) }
      Text("Saved locally · version \(state.thoughts.version)").font(.caption).foregroundStyle(
        Palette.secondary)
    }
  }
}
struct LiveOutlineView: View {
  @EnvironmentObject var state: WorkspaceState
  let outlines: [SummaryRevision]
  /// Model item IDs repeat across passes; key each by its revision too.
  static func items(_ outlines: [SummaryRevision]) -> [(key: String, item: SummaryItem)] {
    outlines.flatMap { revision in revision.summary.items.map { (revision.id + "/" + $0.id, $0) } }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Live notes", systemImage: "sparkle").font(.system(size: 22, weight: .semibold))
      Text(
        "Written from live text. It can change after the meeting."
      ).font(.caption).foregroundStyle(Palette.secondary)
      ForEach(LiveOutlineView.items(outlines), id: \.key) { key, item in
        VStack(alignment: .leading, spacing: 6) {
          Text(item.text)
          ForEach(item.sources.indices, id: \.self) { i in
            Button("Show in transcript") { state.revealSource(item.sources[i]) }.buttonStyle(.borderless)
              .font(.caption)
          }
        }
      }
    }.padding(22).workspaceSurface()
  }
}
struct SummaryEditView: View {
  @EnvironmentObject var state: WorkspaceState
  @Environment(\.dismiss) var dismiss
  @State var item: SummaryItem
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Your version").font(.system(size: 25, weight: .semibold))
      Text(
        "Your edit stays when the summary is written again."
      ).foregroundStyle(Palette.secondary)
      TextEditor(text: $item.text).font(.system(size: 16)).scrollContentBackground(.hidden).padding(
        16
      ).frame(height: 180).workspaceSurface()
      HStack {
        Button("Cancel") { dismiss() }
        Spacer()
        Button("Save edit") {
          state.saveSummaryEdit(item)
          dismiss()
        }.buttonStyle(.borderedProminent)
      }
    }.padding(28).frame(width: 560).background(Palette.workspace)
  }
}
/// Granola-style notes: the user's lines in ink, AI additions in grey with transcript sources.
struct EnhancedNotesView: View {
  @EnvironmentObject var state: WorkspaceState
  var showTab: (String) -> Void = { _ in }
  var embedded = false
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Your notes, filled in").font(.system(size: embedded ? 17 : 22, weight: .semibold))
        Spacer()
        if busy {
          ProgressView().controlSize(.small)
          Text("Writing your notes…").font(.caption).foregroundStyle(Palette.secondary)
        }
        Menu(templateName) {
          ForEach(EnhancedNotes.templates, id: \.id) { template in
            Button(template.name) { state.regenerateNotes(template: template.id) }
          }
        }.fixedSize().disabled(busy || state.activeMeetingID == state.selectedMeetingID)
          .help("Rewrite the notes with this template")
        if !embedded {
          Menu("Share") {
            Button("Copy as Markdown") { state.copyNotesMarkdown() }
            Button("Draft follow-up email") { state.draftFollowup() }
          }.fixedSize().disabled(state.enhancedNotes?.blocks.isEmpty ?? true)
        }
      }.padding(.top, embedded ? 0 : 24)
      if let notes = state.enhancedNotes, !notes.blocks.isEmpty {
        Text("Black is yours. Grey comes from the transcript.")
          .font(.caption).foregroundStyle(Palette.secondary)
        let document = VStack(alignment: .leading, spacing: 8) {
          ForEach(notes.blocks) { block in row(block) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
        if embedded { document.workspaceSurface() } else { ScrollView { document }.workspaceSurface() }
      } else {
        QuietEmpty(
          icon: "doc.text",
          title: state.activeMeetingID == state.selectedMeetingID
            ? "Notes come when the meeting ends" : "No notes yet",
          subtitle:
            "Type notes during the meeting. Chup! adds the rest when you stop."
        )
        if state.activeMeetingID != state.selectedMeetingID, !busy {
          Button("Write notes") { state.regenerateNotes(template: state.enhancedNotes?.template ?? "general") }
            .buttonStyle(.borderedProminent)
        }
      }
    }
  }
  private var busy: Bool {
    state.selectedMeetingID != nil
      && (state.notesMeetingID == state.selectedMeetingID
        || state.processingMeetingID == state.selectedMeetingID)
  }
  private var templateName: String {
    let id = state.enhancedNotes?.template ?? "general"
    return "Template: " + (EnhancedNotes.templates.first { $0.id == id }?.name ?? "General")
  }
  @ViewBuilder private func row(_ block: NoteBlock) -> some View {
    if block.isHeading {
      Text(block.plainText).font(.system(size: 18, weight: .semibold)).padding(.top, 10)
        .foregroundStyle(block.kind == "user" ? Palette.ink : Palette.secondary)
        .accessibilityAddTraits(.isHeader)
    } else {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("•").foregroundStyle(Palette.secondary)
        Text(block.text).font(.system(size: 16)).textSelection(.enabled)
          .foregroundStyle(block.kind == "user" ? Palette.ink : Palette.secondary)
          .accessibilityLabel((block.kind == "user" ? "Your note: " : "Added: ") + block.text)
        if let source = block.sources.first {
          if state.partial.transcript {
            Image(systemName: "quote.bubble").font(.caption).foregroundStyle(Palette.secondary.opacity(0.5))
              .help("Source deleted: the transcript of this meeting was deleted.")
              .accessibilityLabel("Source deleted")
          } else {
            Button {
              state.revealSource(source)
              showTab("Transcript")
            } label: {
              Image(systemName: state.partial.audio ? "quote.bubble.fill" : "quote.bubble")
            }.buttonStyle(.borderless).font(.caption)
              .help(state.partial.audio ? source.quote + " (audio deleted)" : source.quote)
              .accessibilityLabel(state.partial.audio ? "Show source in transcript, audio deleted" : "Show source in transcript")
          }
        }
      }
    }
  }
}

/// A citation that opens its transcript line, or says why it can't: the transcript was
/// deleted ("source deleted", not clickable) or only the audio was ("no audio", no seek).
struct SourceLink: View {
  @EnvironmentObject var state: WorkspaceState
  let source: Evidence
  var label: String?
  var body: some View {
    if state.partial.transcript {
      Group {
        if let label { Label("Source deleted · " + label, systemImage: "quote.bubble") } else {
          Image(systemName: "quote.bubble")
        }
      }.font(.caption).foregroundStyle(Palette.secondary.opacity(0.6))
        .help("Source deleted: the transcript of this meeting was deleted.")
        .accessibilityLabel("Source deleted")
    } else {
      Button {
        state.revealSource(source)
      } label: {
        if let label { Text(state.partial.audio ? label + " · no audio" : label) } else {
          Image(systemName: state.partial.audio ? "quote.bubble.fill" : "quote.bubble")
        }
      }.buttonStyle(.borderless).font(.caption)
        .help(state.partial.audio ? source.quote + " (audio deleted)" : source.quote)
        .accessibilityLabel(state.partial.audio ? "Show source in transcript, audio deleted" : "Show source in transcript")
    }
  }
}
