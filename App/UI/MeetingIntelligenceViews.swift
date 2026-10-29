import ChupCore
import SwiftUI

struct MeetingActionsView: View {
  @EnvironmentObject var state: WorkspaceState
  @State private var title = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("What happens next").font(.system(size: 25, design: .serif)).padding(.top, 24)
      HStack {
        TextField("Add an action…", text: $title).onSubmit(add)
        Button("Add", action: add).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
      }
      ScrollView {
        ForEach(state.actions.filter { $0.status != "archived" }) { action in
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
                "Owner not assigned",
                text: Binding(
                  get: { action.owner ?? "" },
                  set: { value in
                    var copy = action
                    copy.owner = value.isEmpty ? nil : value
                    state.saveAction(copy)
                  }))
              TextField(
                "No date agreed",
                text: Binding(
                  get: { action.dueDate ?? "" },
                  set: { value in
                    var copy = action
                    copy.dueDate = value.isEmpty ? nil : value
                    state.saveAction(copy)
                  }))
            }
            ForEach(action.sources.indices, id: \.self) { index in
              Button(action.sources[index].quote) { state.revealSource(action.sources[index]) }
                .buttonStyle(.borderless).font(.caption)
            }
          }.padding(20).workspaceSurface()
        }
      }
      Button("Undo last action change") { state.undoAction() }.disabled(
        state.lastActionReceipt == nil)
    }
  }
  private func add() {
    guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    state.addAction(title)
    title = ""
  }
}
struct PrivateThoughtsView: View {
  @EnvironmentObject var state: WorkspaceState
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Just for you").font(.system(size: 25, design: .serif)).padding(.top, 24)
      Label("These thoughts are never included in AI requests or broadcasts.", systemImage: "lock")
        .font(.caption).foregroundStyle(Palette.secondary)
      TextEditor(text: $state.thoughtsDraft).font(.system(size: 17)).scrollContentBackground(
        .hidden
      )
      .padding(16).workspaceSurface()
      .onChange(of: state.thoughtsDraft) { _, text in state.saveThoughts(text) }
      Text("Saved locally · version \(state.thoughts.version)").font(.caption).foregroundStyle(
        Palette.secondary)
    }
  }
}
struct LiveOutlineView: View {
  @EnvironmentObject var state: WorkspaceState
  let outlines: [SummaryRevision]
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Live notes", systemImage: "sparkle").font(.system(size: 22, design: .serif))
      Text(
        "Written from completed live text as the meeting goes. Wording may change after final refinement."
      ).font(.caption).foregroundStyle(Palette.secondary)
      ForEach(outlines.flatMap(\.summary.items)) { item in
        VStack(alignment: .leading, spacing: 6) {
          Text(item.text)
          ForEach(item.sources.indices, id: \.self) { i in
            Button("Open source") { state.revealSource(item.sources[i]) }.buttonStyle(.borderless)
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
      Text("Keep your interpretation").font(.system(size: 25, design: .serif))
      Text(
        "This pinned edit stays separate from regenerated summaries. Its original sources are retained."
      ).foregroundStyle(Palette.secondary)
      TextEditor(text: $item.text).font(.system(size: 16)).scrollContentBackground(.hidden).padding(
        16
      ).frame(height: 180).workspaceSurface()
      HStack {
        Button("Cancel") { dismiss() }
        Spacer()
        Button("Save pinned edit") {
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
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Your notes, filled in").font(.system(size: 22, design: .serif))
        Spacer()
        if state.writingNotes || state.processingMeeting {
          ProgressView().controlSize(.small)
          Text("Writing your notes…").font(.caption).foregroundStyle(Palette.secondary)
        }
        Menu(templateName) {
          ForEach(EnhancedNotes.templates, id: \.id) { template in
            Button(template.name) { state.regenerateNotes(template: template.id) }
          }
        }.fixedSize().disabled(state.writingNotes || state.activeMeetingID == state.selectedMeetingID)
          .help("Rewrite the notes with this template")
        Menu("Share") {
          Button("Copy as Markdown") { state.copyNotesMarkdown() }
          Button("Draft follow-up email") { state.draftFollowup() }
        }.fixedSize().disabled(state.enhancedNotes?.blocks.isEmpty ?? true)
      }.padding(.top, 24)
      if let notes = state.enhancedNotes, !notes.blocks.isEmpty {
        Text("Black is what you wrote. Grey is filled in from the transcript.")
          .font(.caption).foregroundStyle(Palette.secondary)
        ScrollView {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(notes.blocks) { block in row(block) }
          }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
        }.workspaceSurface()
      } else {
        QuietEmpty(
          icon: "doc.text",
          title: state.activeMeetingID == state.selectedMeetingID
            ? "Notes are written when the meeting ends" : "No notes yet",
          subtitle:
            "Jot anything in My notes or the sidebar. When you stop, Chup! keeps your lines and fills in the rest from the transcript."
        )
        if state.activeMeetingID != state.selectedMeetingID, !state.writingNotes {
          Button("Write notes") { state.regenerateNotes(template: state.enhancedNotes?.template ?? "general") }
            .buttonStyle(.borderedProminent)
        }
      }
    }
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
          Button {
            state.revealSource(source)
            showTab("Transcript")
          } label: {
            Image(systemName: "quote.bubble")
          }.buttonStyle(.borderless).font(.caption).help(source.quote)
            .accessibilityLabel("Show source in transcript")
        }
      }
    }
  }
}
