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
  let outline: SummaryRevision
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Provisional live outline", systemImage: "sparkle").font(
        .system(size: 22, design: .serif))
      Text(
        "Based on completed live text through the most recent ten minutes. Timing and wording may change after final refinement."
      ).font(.caption).foregroundStyle(Palette.secondary)
      ForEach(outline.summary.items) { item in
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
