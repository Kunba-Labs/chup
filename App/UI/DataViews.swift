import ChupCore
import SwiftUI

/// Bottom toast after a delete; Undo restores everything it moved.
struct UndoToastView: View {
  @EnvironmentObject var state: WorkspaceState
  let toast: UndoToast
  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: "trash").foregroundStyle(.white.opacity(0.7)).accessibilityHidden(true)
      Text(toast.message).lineLimit(1)
      Button("Undo") { state.restoreFromTrash(toast.ids) }
        .buttonStyle(.plain).fontWeight(.semibold).foregroundStyle(RailPalette.accent)
        .keyboardShortcut("z", modifiers: .command)
    }
    .font(.system(size: 13)).foregroundStyle(.white).padding(.horizontal, 18).padding(.vertical, 11)
    .background(RailPalette.base.opacity(0.94), in: Capsule())
    .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
  }
}

struct TrashView: View {
  @EnvironmentObject var state: WorkspaceState
  @Environment(\.dismiss) private var dismiss
  @State private var confirmEmpty = false
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Trash").font(.system(size: 24, weight: .semibold))
        Spacer()
        Button("Empty Trash…") { confirmEmpty = true }.disabled(state.trash.isEmpty)
        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
      }
      Text("Deleted meetings and dictations stay here for \(TrashEntry.retentionDays) days, then are removed for good.")
        .font(.callout).foregroundStyle(Palette.secondary)
      if state.trash.isEmpty {
        QuietEmpty(icon: "trash", title: "Trash is empty", subtitle: "Deleted meetings and dictations land here first, so you can bring them back.")
      } else {
        ScrollView {
          LazyVStack(spacing: 8) {
            ForEach(state.trash) { entry in
              HStack(spacing: 12) {
                Image(systemName: entry.kind == "meeting" ? "person.2" : "waveform")
                  .foregroundStyle(Palette.secondary).frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                  Text(entry.title.isEmpty ? "Untitled" : entry.title).lineLimit(1)
                  Text("Deleted \(entry.trashedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button("Restore") { state.restoreFromTrash([entry.id]) }
                Button("Delete forever", role: .destructive) { state.deleteForever([entry]) }
              }.padding(12).workspaceSurface()
            }
          }
        }
      }
    }
    .padding(28).frame(width: 600, height: 520).background(Palette.workspace)
    .confirmationDialog("Delete everything in the Trash for good?", isPresented: $confirmEmpty, titleVisibility: .visible) {
      Button("Delete \(state.trash.count) items forever", role: .destructive) { state.deleteForever(state.trash) }
    } message: {
      Text("Recordings, transcripts, notes and private thoughts are removed from this Mac. This cannot be undone.")
    }
  }
}

/// Tag chips with remove buttons and an add field that suggests existing tags.
struct TagEditor: View {
  @EnvironmentObject var state: WorkspaceState
  let meeting: Meeting
  @State private var adding = false
  @State private var draft = ""
  private var tags: [String] { Meeting.tagList(meeting.tags) }
  private var suggestions: [String] {
    state.allTags.filter { tag in
      !tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
        && (draft.isEmpty || tag.localizedCaseInsensitiveContains(draft))
    }.prefix(6).map { $0 }
  }
  var body: some View {
    HStack(spacing: 6) {
      ForEach(tags, id: \.self) { tag in
        HStack(spacing: 4) {
          Text(tag)
          Button {
            state.setTags(tags.filter { $0 != tag }, on: meeting)
          } label: {
            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
          }.buttonStyle(.plain).accessibilityLabel("Remove tag \(tag)")
        }
        .font(.system(size: 11, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 3)
        .background(Palette.accent.opacity(0.12), in: Capsule()).foregroundStyle(Palette.accent)
      }
      Button {
        adding = true
      } label: {
        Label("Tag", systemImage: "plus").font(.system(size: 11, weight: .medium))
      }.buttonStyle(.plain).foregroundStyle(Palette.secondary).accessibilityLabel("Add tag")
        .popover(isPresented: $adding, arrowEdge: .bottom) {
          VStack(alignment: .leading, spacing: 8) {
            TextField("New or existing tag", text: $draft).textFieldStyle(.roundedBorder)
              .onSubmit { add(draft) }
            ForEach(suggestions, id: \.self) { tag in
              Button(tag) { add(tag) }.buttonStyle(.plain)
            }
          }.padding(12).frame(width: 220)
        }
    }
  }
  private func add(_ tag: String) {
    let clean = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    state.setTags(tags + [clean], on: meeting)
    draft = ""
    adding = false
  }
}

/// Rename or delete a tag on every meeting that has it.
struct TagManagerView: View {
  @EnvironmentObject var state: WorkspaceState
  @Environment(\.dismiss) private var dismiss
  @State private var renaming: String?
  @State private var newName = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Tags").font(.system(size: 24, weight: .semibold))
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
      }
      if state.allTags.isEmpty {
        Text("No tags yet. Add one from a meeting's header.").foregroundStyle(Palette.secondary)
      }
      ScrollView {
        VStack(spacing: 6) {
          ForEach(state.allTags, id: \.self) { tag in
            HStack {
              Text(tag)
              Text("\(state.meetings.filter { Meeting.tagList($0.tags).contains(tag) }.count)")
                .font(.caption).foregroundStyle(Palette.secondary)
              Spacer()
              Button("Rename…") {
                newName = tag
                renaming = tag
              }
              Button("Delete", role: .destructive) { state.renameTag(tag, to: nil) }
            }.padding(10).workspaceSurface()
          }
        }
      }
    }
    .padding(28).frame(width: 460, height: 480).background(Palette.workspace)
    .alert("Rename tag", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
      TextField("Tag", text: $newName)
      Button("Rename") {
        let clean = newName.trimmingCharacters(in: .whitespaces)
        if let renaming, !clean.isEmpty { state.renameTag(renaming, to: clean) }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Changes the tag on every meeting that has it.")
    }
  }
}
