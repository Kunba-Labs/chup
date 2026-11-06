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
        .font(embedded ? .heading : .pageTitle).padding(.top, embedded ? 0 : 24)
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
              Text(action.title).font(.reading).strikethrough(action.status == "done")
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
      Text(action.title).font(.ui).strikethrough(action.status == "done")
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
      ).textFieldStyle(.plain).font(.detail).foregroundStyle(Palette.secondary).frame(width: 96)
      TextField(
        "Due",
        text: Binding(
          get: { action.dueDate ?? "" },
          set: { value in
            var copy = action
            copy.dueDate = value.isEmpty ? nil : value
            state.saveAction(copy)
          })
      ).textFieldStyle(.plain).font(.detail).foregroundStyle(Palette.secondary).frame(width: 90)
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
        Text("Just for you").font(.pageTitle).padding(.top, 24)
      }
      Label("Only you see these. They never go to AI.", systemImage: "lock")
        .font(.detail).foregroundStyle(Palette.secondary)
      TextEditor(text: $state.thoughtsDraft).font(.reading).scrollContentBackground(
        .hidden
      )
      .padding(16).frame(minHeight: embedded ? 140 : nil).workspaceSurface()
      .onChange(of: state.thoughtsDraft) { _, text in state.saveThoughts(text) }
      Text("Saved locally · version \(state.thoughts.version)").font(.detail).foregroundStyle(
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
      Label("Live notes", systemImage: "sparkle").font(.sectionTitle)
      Text(
        "Written from live text. It can change after the meeting."
      ).font(.detail).foregroundStyle(Palette.secondary)
      ForEach(LiveOutlineView.items(outlines), id: \.key) { key, item in
        VStack(alignment: .leading, spacing: 6) {
          Text(item.text)
          ForEach(item.sources.indices, id: \.self) { i in
            Button("Show in transcript") { state.revealSource(item.sources[i]) }.buttonStyle(.borderless)
              .font(.detail)
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
      Text("Your version").font(.pageTitle)
      Text(
        "Your edit stays when the summary is written again."
      ).foregroundStyle(Palette.secondary)
      TextEditor(text: $item.text).font(.reading).scrollContentBackground(.hidden).padding(
        16
      ).frame(height: 180).workspaceSurface()
      HStack {
        Button("Cancel") { dismiss() }
        Spacer()
        Button("Save edit") {
          state.saveSummaryEdit(item)
          dismiss()
        }.buttonStyle(.pillPrimary)
      }
    }.padding(28).frame(width: 560).background(Palette.workspace)
  }
}
/// Granola-style notes: the user's lines in ink, AI additions in grey with transcript sources.
/// Rewrites the filled-in notes with another template.
struct NotesTemplateMenu: View {
  @EnvironmentObject var state: WorkspaceState
  var body: some View {
    let id = state.enhancedNotes?.template ?? "general"
    let busy = state.selectedMeetingID != nil
      && (state.notesMeetingID == state.selectedMeetingID
        || state.processingMeetingID == state.selectedMeetingID)
    Menu("Template: " + (EnhancedNotes.templates.first { $0.id == id }?.name ?? "General")) {
      ForEach(EnhancedNotes.templates, id: \.id) { template in
        Button(template.name) { state.regenerateNotes(template: template.id) }
      }
    }.menuStyle(.button).buttonStyle(.pill).fixedSize()
      .disabled(busy || state.activeMeetingID == state.selectedMeetingID)
      .help("Rewrite the notes with this template")
  }
}
struct EnhancedNotesView: View {
  @EnvironmentObject var state: WorkspaceState
  var showTab: (String) -> Void = { _ in }
  var embedded = false
  /// The Summary tab puts the template picker beside its next-step field instead.
  var showsHeader = true
  /// Inside the Summary tab's own surface: no card of its own.
  var bare = false
  /// Find text from the Summary tab; matching lines are highlighted.
  var highlight = ""
  private func found(_ text: String) -> Bool {
    let query = highlight.trimmingCharacters(in: .whitespaces)
    return !query.isEmpty && text.localizedCaseInsensitiveContains(query)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if busy {
        HStack(spacing: 6) {
          ProgressView().controlSize(.small)
          Text("Writing your notes…").font(.detail).foregroundStyle(Palette.secondary)
        }
      }
      if showsHeader { HStack {
        Text("Your notes, filled in").font(embedded ? .heading : .sectionTitle)
        Spacer()
        NotesTemplateMenu()
        if !embedded {
          Menu("Share") {
            Button("Copy as Markdown") { state.copyNotesMarkdown() }
            Button("Draft follow-up email") { state.draftFollowup() }
          }.fixedSize().disabled(state.enhancedNotes?.blocks.isEmpty ?? true)
        }
      }.padding(.top, embedded ? 0 : 24) }
      if let notes = state.enhancedNotes, !notes.blocks.isEmpty {
        let lead = notes.blocks.first.flatMap { $0.kind == "ai" ? $0.id : nil }
        let names = speakerColors
        let document = VStack(alignment: .leading, spacing: 8) {
          ForEach(notes.blocks) { block in
            NoteRow(block: block, lead: block.id == lead, names: names, highlight: highlight,
              showTab: showTab).id("note-" + block.id)
          }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(bare ? 0 : 22)
          .help("Black is yours. Grey comes from the transcript.")
        if bare { document } else if embedded { document.workspaceSurface() } else {
          ScrollView { document }.workspaceSurface()
        }
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
            .buttonStyle(.pillPrimary)
        }
      }
    }
  }
  private var busy: Bool {
    state.selectedMeetingID != nil
      && (state.notesMeetingID == state.selectedMeetingID
        || state.processingMeetingID == state.selectedMeetingID)
  }
  /// Each named speaker's colour, so the notes show who said what like the transcript does.
  private var speakerColors: [(name: String, color: Color)] {
    var seen = Set<String>()
    return state.segments.compactMap { segment in
      guard let raw = segment.speakerName else { return nil }
      let name = raw.replacingOccurrences(of: " · voice match", with: "")
      guard name.count > 1, seen.insert(name).inserted else { return nil }
      return (name, Palette.speaker(segment.speakerID))
    }
  }
}
/// One line of the notes: heading, bullet or sub-bullet. The citation shows on hover or focus
/// and stays a VoiceOver action, so the page reads clean without hiding where lines came from.
private struct NoteRow: View {
  @EnvironmentObject var state: WorkspaceState
  let block: NoteBlock
  let lead: Bool
  let names: [(name: String, color: Color)]
  let highlight: String
  let showTab: (String) -> Void
  @State private var hovering = false
  @FocusState private var focused: Bool
  private var found: Bool {
    let query = highlight.trimmingCharacters(in: .whitespaces)
    return !query.isEmpty && block.text.localizedCaseInsensitiveContains(query)
  }
  /// Names in their speaker colour; the rest keeps the line's own colour.
  private var styled: AttributedString {
    var text = AttributedString(block.isHeading ? block.plainText : block.text)
    for (name, color) in names {
      var searchRange = text.startIndex..<text.endIndex
      while let range = text[searchRange].range(of: name) {
        text[range].foregroundColor = color
        searchRange = range.upperBound..<text.endIndex
      }
    }
    return text
  }
  var body: some View {
    if block.isHeading {
      Text(block.plainText).font(.heading).padding(.top, 14)
        .foregroundStyle(Palette.ink)
        .background(found ? Palette.accent.opacity(0.15) : .clear)
        .accessibilityAddTraits(.isHeader)
    } else {
      let sub = block.level == 1
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        if !lead {
          Text(sub ? "▪" : "•").font(sub ? .micro : .reading).foregroundStyle(Palette.secondary)
        }
        Text(styled).font(lead ? .reading.weight(.medium) : .reading).lineSpacing(5).textSelection(.enabled)
          .foregroundStyle(block.kind == "user" || lead ? Palette.ink : Palette.ink.opacity(0.82))
          .background(found ? Palette.accent.opacity(0.15) : .clear)
          .accessibilityLabel((block.kind == "user" ? "Your note: " : "Added: ") + block.text)
        Spacer(minLength: 0)
        citation
      }.padding(.leading, sub ? 22 : 0).padding(.bottom, lead ? 6 : 0).contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
  }
  @ViewBuilder private var citation: some View {
    if let source = block.sources.first {
      Group {
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
          }.buttonStyle(.borderless).font(.detail).focused($focused)
            .help(state.partial.audio ? source.quote + " (audio deleted)" : source.quote)
            .accessibilityLabel(state.partial.audio ? "Show source in transcript, audio deleted" : "Show source in transcript")
        }
      }.opacity(hovering || focused ? 1 : 0)  // Still focusable and announced while hidden.
    }
  }
}

/// A citation that opens its transcript line, or says why it can't: the transcript was
/// deleted ("source deleted", not clickable) or only the audio was ("no audio", no seek).
struct SourceLink: View {
  @EnvironmentObject var state: WorkspaceState
  let source: Evidence
  var label: String?
  /// Set when a line has several sources, so VoiceOver can tell them apart.
  var number: Int?
  private var name: String { number.map { "Source \($0)" } ?? "Source" }
  var body: some View {
    if state.partial.transcript {
      Group {
        if let label { Label("Source deleted · " + label, systemImage: "quote.bubble") } else {
          Image(systemName: "quote.bubble")
        }
      }.font(.detail).foregroundStyle(Palette.secondary.opacity(0.6))
        .help("Source deleted: the transcript of this meeting was deleted.")
        .accessibilityLabel(name + " deleted")
    } else {
      Button {
        state.revealSource(source)
      } label: {
        if let label { Text(state.partial.audio ? label + " · no audio" : label) } else {
          Image(systemName: state.partial.audio ? "quote.bubble.fill" : "quote.bubble")
        }
      }.buttonStyle(.borderless).font(.detail)
        .help(state.partial.audio ? source.quote + " (audio deleted)" : source.quote)
        .accessibilityLabel(state.partial.audio ? "Show \(name.lowercased()) in transcript, audio deleted" : "Show \(name.lowercased()) in transcript")
        .accessibilityHint(source.quote)
    }
  }
}
