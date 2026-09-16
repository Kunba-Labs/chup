import ChupCore
import SwiftUI

struct TranscriptionLabView: View {
  @ObservedObject var lab: TranscriptionLab
  @EnvironmentObject var state: WorkspaceState
  private var captureBusy: Bool {
    state.meetingStatus == .recording || state.meetingStatus == .processing
      || state.dictationStatus == .listening
      || state.dictationStatus == .processing || state.voiceScope != nil
      || state.microphonePreviewBusy || state.storageBusy
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      WorkspaceCard(
        "Choose a recording",
        subtitle: "Both models hear the same audio. Your original stays untouched.",
        icon: "waveform"
      ) {
        Picker("Saved dictation", selection: $lab.selectedEntryID) {
          Text("Choose a recording").tag("")
          ForEach(state.history.filter { !$0.audioDirectory.isEmpty }) { entry in
            Text(
              entry.created.formatted(date: .abbreviated, time: .shortened) + " · "
                + (entry.language ?? "en")
            )
            .tag(entry.id)
          }
        }.disabled(lab.busy)
      }
      WorkspaceCard("Whisper Turbo + Parakeet v3", icon: "internaldrive") {
        Text(
          "Whisper uses the model from Dictation settings. Parakeet detects the spoken language automatically; Whisper uses the recording’s saved language."
        )
        .font(.callout).foregroundStyle(Palette.secondary)
        HStack {
          Button(
            lab.parakeetInstalled ? "Repair Parakeet" : "Download Parakeet · \(lab.downloadSize)"
          ) { lab.install() }
          if lab.parakeetInstalled {
            Button("Remove Parakeet", role: .destructive) { lab.removeModel() }
          }
        }.disabled(lab.busy || captureBusy)
        Text("Models download once. Comparisons run locally; audio is never sent to a provider.")
          .font(.caption).foregroundStyle(Palette.secondary)
      }
      WorkspaceCard("Run a comparison", icon: "play.circle") {
        HStack {
          Button("Compare models") {
            guard let entry = state.history.first(where: { $0.id == lab.selectedEntryID }),
              let key = state.key
            else { return }
            do {
              lab.run(
                entry: entry,
                journals: try state.journalFiles(URL(fileURLWithPath: entry.audioDirectory)),
                key: key)
            } catch { state.notice = error.localizedDescription }
          }.buttonStyle(.borderedProminent).disabled(
            lab.busy || captureBusy || lab.selectedEntryID.isEmpty)
          if lab.busy {
            Button("Cancel") { lab.cancel() }
            ProgressView().controlSize(.small)
          } else if !lab.results.isEmpty {
            Button("Clear results") { lab.clear() }
          }
        }
        if let progress = lab.progress { ProgressView(value: progress) }
        Text(lab.status).font(.callout).foregroundStyle(Palette.secondary).textSelection(.enabled)
        if captureBusy { Text("Finish active capture before running a comparison.").font(.caption) }
      }
      if !lab.baseline.isEmpty {
        DisclosureGroup("Original raw transcript") {
          Text(lab.baseline).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      ForEach(lab.results) { result in
        VStack(alignment: .leading, spacing: 10) {
          Text(result.model).font(.headline)
          Text(
            "Prepare \(result.preparationSeconds, specifier: "%.2f") s · Transcribe \(result.transcriptionSeconds, specifier: "%.2f") s"
          )
          .font(.caption).monospacedDigit().foregroundStyle(Palette.secondary)
          if let error = result.error {
            Label(error, systemImage: "exclamationmark.circle").font(.callout)
          }
          if !result.text.isEmpty {
            Text(result.text).font(.system(size: 16)).textSelection(.enabled)
              .fixedSize(horizontal: false, vertical: true)
            Button("Copy result") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(result.text, forType: .string)
            }
          }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(22).workspaceSurface()
      }
      DetailDisclosure(
        title: "Understanding the results",
        text:
          "Models unload between runs. Preparation includes verification, loading and a readiness check; macOS may retain compiled caches. Results have no AI cleanup or speaker labels."
      )
    }.onDisappear { lab.cancel() }
      .onChange(of: lab.selectedEntryID) { _, _ in lab.clear() }
  }
}
