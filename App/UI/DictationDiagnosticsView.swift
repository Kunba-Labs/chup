import ChupCore
import SwiftUI

struct DictationDiagnosticsView: View {
  @EnvironmentObject var state: WorkspaceState
  private let spans: [(String, DictationTrace.Stage, DictationTrace.Stage)] = [
    ("Microphone start", .requested, .firstAudio), ("Recording", .firstAudio, .captureStopped),
    ("Cloud transcription", .cloudStarted, .cloudFinished),
    ("Local transcription", .localStarted, .localFinished),
    ("Cleanup", .cleanupStarted, .cleanupFinished), ("Text delivery", .insertionStarted, .finished),
    ("After release", .captureStopped, .finished),
  ]
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      WorkspaceCard("Timing reports", icon: "timer") {
        Text(
          "Recent attempts, including failed and cancelled ones. Missing timings mean that stage did not complete. No spoken text is stored in these diagnostics."
        )
        .font(.callout).foregroundStyle(Palette.secondary)
        if state.traceStorageFailed {
          Label("Some timing data could not be saved.", systemImage: "exclamationmark.circle")
        }
        if state.dictationTraces.isEmpty {
          Text("Use dictation to capture a timing report.").foregroundStyle(Palette.secondary)
        }
      }
      ForEach(state.dictationTraces.prefix(10)) { trace in
        DisclosureGroup {
          ForEach(spans, id: \.0) { label, start, end in
            HStack {
              Text(label)
              Spacer()
              Text(trace.duration(from: start, to: end).map { "\(Int($0.rounded())) ms" } ?? "—")
                .monospacedDigit().foregroundStyle(Palette.secondary)
            }.padding(.vertical, 3)
          }
        } label: {
          HStack {
            Text(trace.created.formatted(date: .abbreviated, time: .shortened))
            Spacer()
            Text(trace.outcome.rawValue.capitalized).foregroundStyle(Palette.secondary)
          }
        }.padding(20).workspaceSurface()
      }
      WorkspaceCard("Manage reports", icon: "externaldrive") {
        HStack {
          Button("Export diagnostics…") { state.exportDiagnostics() }
          Button("Clear timing history") { state.clearDictationTraces() }
            .disabled(state.dictationStatus == .listening || state.dictationStatus == .processing)
        }
        Text(
          "Keeps the latest 50 attempts locally. Export contains timing, status and counts only."
        )
        .font(.caption).foregroundStyle(Palette.secondary)
      }
      WorkspaceCard("Paste activity", icon: "arrow.down.doc") {
        Text("Every delivery is recorded locally with its shortcut, route and safety decision. This helps explain when text was inserted, copied for recovery, or left unconfirmed.")
          .font(.callout).foregroundStyle(Palette.secondary)
        if state.deliveryDiagnostics.isEmpty {
          Text("No paste attempts yet.").foregroundStyle(Palette.secondary)
        } else {
          ForEach(state.deliveryDiagnostics.prefix(8)) { item in
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Label(item.result.title, systemImage: item.result.icon)
                Spacer()
                Text(item.date.formatted(date: .omitted, time: .shortened)).font(.caption)
              }
              Text("Trigger: \(item.trigger) · Route: \(item.route)")
                .font(.caption).foregroundStyle(Palette.secondary)
              Text(item.detail).font(.caption2).foregroundStyle(Palette.secondary)
            }.padding(.vertical, 6)
          }
        }
      }
    }
  }
}
