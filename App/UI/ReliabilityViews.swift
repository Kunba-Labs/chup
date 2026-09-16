import ChupCore
import SwiftUI

struct MicrophonePicker: View {
  @EnvironmentObject var state: WorkspaceState
  @ObservedObject var devices: AudioDevices
  var showsPreview = true
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      WorkspaceCard("Microphone", subtitle: "Choose where Chup! listens.", icon: "mic") {
        Picker("Input device", selection: $state.microphoneUID) {
          Text("Automatic · follow system input").tag("")
          ForEach(devices.inputs) { device in
            Text(
              device.name
                + (device.builtIn && devices.lidClosed == true
                  ? " · lid closed" : !device.available ? " · unavailable" : "")
            )
            .tag(device.id)
          }
          if !state.microphoneUID.isEmpty
            && !devices.inputs.contains(where: { $0.id == state.microphoneUID })
          {
            Text("Selected microphone disconnected").tag(state.microphoneUID)
          }
        }.labelsHidden().accessibilityLabel("Input device")
          .disabled(
            state.microphonePreviewBusy || state.meetingStatus == .recording
              || state.meetingStatus == .processing || state.dictationStatus == .listening
              || state.voiceScope != nil)
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 6) {
            Text("Current input").font(.caption).foregroundStyle(Palette.secondary)
            Text(state.microphoneLabel).font(.system(size: 14, weight: .medium)).fixedSize(
              horizontal: false, vertical: true)
          }
          Spacer(minLength: 0)
          Button {
            devices.refresh()
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .buttonStyle(.borderless).help("Refresh inputs").accessibilityLabel(
            "Refresh microphone inputs")
        }.insetSurface()
        if (try? devices.selection(state.microphoneUID)) == nil {
          Label("Choose an available microphone above.", systemImage: "exclamationmark.circle")
            .font(.callout).foregroundStyle(Palette.red)
        } else if devices.lidClosed == true {
          Label("Lid closed · using an external microphone", systemImage: "laptopcomputer.slash")
            .font(.caption).foregroundStyle(Palette.secondary)
        }
        DetailDisclosure(
          title: "Automatic selection & device changes",
          text:
            "Automatic follows macOS and avoids the built-in microphone when the MacBook lid is closed. A device change pauses active capture and preserves the audio already recorded."
        )
      }
      if showsPreview {
        WorkspaceCard(
          "Check your sound", subtitle: "Speak a few words and watch the waveform.",
          icon: "waveform"
        ) {
          HStack(spacing: 16) {
            Button {
              if state.microphonePreviewBusy {
                state.stopMicrophonePreview()
              } else {
                state.startMicrophonePreview()
              }
            } label: {
              Label(
                state.microphonePreviewBusy ? "Stop test" : "Test microphone",
                systemImage: state.microphonePreviewBusy ? "stop.fill" : "mic.fill")
            }.disabled(!state.microphonePreviewBusy && !state.canPreviewMicrophone)
            Spacer(minLength: 0)
            if state.microphonePreviewStarting {
              ProgressView().controlSize(.small).accessibilityLabel("Opening microphone")
            } else {
              VoiceWaveform(
                samples: state.microphonePreviewActive ? state.micWaveform : [], width: 120,
                height: 32, color: Palette.olive, barCount: 15)
            }
          }
          Text(state.microphonePreviewMessage).font(.callout).foregroundStyle(Palette.secondary)
            .fixedSize(horizontal: false, vertical: true)
          if !state.isPreview && !state.microphonePreviewBusy && !state.canPreviewMicrophone {
            InlineStatus(text: "Finish active capture before testing your microphone.")
          }
          Label("Local test · 30-second limit · nothing saved or sent", systemImage: "lock")
            .font(.caption).foregroundStyle(Palette.secondary).fixedSize(
              horizontal: false, vertical: true)
        }
      }
    }.onDisappear { if showsPreview { state.stopMicrophonePreview() } }
  }
}

struct VoiceEnrollmentSettings: View {
  @EnvironmentObject var state: WorkspaceState
  var body: some View {
    WorkspaceCard(
      "Remembered voices", subtitle: "Choose whose voice to recognize across meetings.",
      icon: "person.crop.circle.badge.checkmark"
    ) {
      DetailDisclosure(
        title: "How voice enrollment works",
        text:
          "Enroll a clean 2–10 second interval from a transcript’s correction panel. Enabling matching sends that voice sample to your configured AI service during transcription. Suggested matches need your review; attendees’ names alone are not proof of identity."
      )
      if state.enrollments.isEmpty {
        InlineStatus(text: "No voices enrolled yet.", icon: "person.crop.circle")
      }
      ForEach(state.enrollments) { profile in
        VStack(alignment: .leading, spacing: 8) {
          TextField(
            "Name",
            text: Binding(
              get: { profile.name },
              set: {
                var copy = profile
                copy.name = $0
                state.saveEnrollment(copy)
              }))
          Toggle(
            "Allow cloud matching in future meetings",
            isOn: Binding(
              get: { profile.cloudMatching },
              set: {
                var copy = profile
                copy.cloudMatching = $0
                state.saveEnrollment(copy)
              }))
          HStack {
            Text(
              "\(Int(profile.duration)) second reference · \(profile.created.formatted(date: .abbreviated, time: .omitted))"
            ).font(.caption)
            Spacer()
            Button("Delete reference", role: .destructive) { state.deleteEnrollment(profile) }
          }
        }.insetSurface()
      }
    }.disabled(state.processingMeeting)
  }
}
struct TranscriptReviewView: View {
  @EnvironmentObject var state: WorkspaceState
  let review: TranscriptReview
  @State private var expanded = false
  var body: some View {
    DisclosureGroup(isExpanded: $expanded) {
      HStack(alignment: .top, spacing: 24) {
        VStack(alignment: .leading) {
          Text("Your current transcript").font(.headline)
          ForEach(review.current) { Text($0.text).textSelection(.enabled) }
        }.frame(maxWidth: .infinity, alignment: .leading)
        VStack(alignment: .leading) {
          Text("Proposed refinement").font(.headline)
          ForEach(review.incoming) { Text($0.text).textSelection(.enabled) }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }.padding(.vertical, 12)
      HStack {
        Button("Keep my corrections") { state.resolveTranscriptReview(review, accept: false) }
        Button("Replace this interval with refinement", role: .destructive) {
          state.resolveTranscriptReview(review, accept: true)
        }
      }
    } label: {
      Label(
        "Correction review · \(WorkspaceState.time(review.window.start))–\(WorkspaceState.time(review.window.end)) · \(review.window.track.rawValue)",
        systemImage: "pencil.and.list.clipboard")
    }.padding(16).background(Palette.paper, in: RoundedRectangle(cornerRadius: 8))
  }
}
