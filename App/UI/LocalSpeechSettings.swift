import ChupCore
import SwiftUI

struct LocalSpeechSettings: View {
  @ObservedObject var service: LocalSpeechService
  @EnvironmentObject var state: WorkspaceState
  var body: some View {
    WorkspaceCard("Transcription", subtitle: "Pick where Chup! turns speech into text.", icon: "waveform")
    {
      Picker("Transcription", selection: $state.transcriptionMode) {
        ForEach(DictationTranscriptionMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }
      Divider()
      HStack {
        Label("Local speech model", systemImage: "internaldrive")
          .font(.headline)
        Spacer()
        if service.ready {
          Label("Offline ready", systemImage: "checkmark.circle.fill").foregroundStyle(
            Palette.accent)
        }
      }
      Text("Whisper large-v3-turbo · English and Dutch · 630 MB download")
        .font(.callout).foregroundStyle(Palette.secondary)
      if !service.ready { Text(service.status).font(.callout).textSelection(.enabled) }
      if let progress = service.progress {
        ProgressView(value: progress)
        Text(progress.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit().font(
          .caption)
      } else if service.working {
        ProgressView().controlSize(.small)
      }
      HStack {
        if service.working {
          Button("Cancel setup") { service.cancel() }
            .disabled(state.dictationStatus == .processing)
        } else if !service.ready {
          Button(service.installed ? "Repair / download model" : "Download model") {
            service.install()
          }
          .buttonStyle(.pillPrimary)
        }
        if (service.installed || service.partialDownload) && !service.working {
          Button(service.installed ? "Remove model" : "Remove download", role: .destructive) {
            service.remove()
          }
          .disabled(state.dictationStatus == .processing)
        }
      }
      DetailDisclosure(
        title: "What works offline?",
        text:
          "After download, dictation works without internet. AI cleanup, speakers and summaries still need the cloud."
      )
    }
  }
}
