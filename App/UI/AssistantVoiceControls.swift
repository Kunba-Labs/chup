import SwiftUI
import ChupCore

struct AssistantVoiceControls: View {
  @EnvironmentObject var state: WorkspaceState
  @ObservedObject var voice: LiveConversation
  @ObservedObject var router: AssistantAudioRouter
  let mode: AssistantMode
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Image(systemName: mode == .broadcast ? "dot.radiowaves.left.and.right" : "headphones")
        Text(mode == .broadcast ? "Speak in this meeting" : "A private voice conversation").font(
          .system(size: 22, design: .serif))
      }
      Text(
        mode == .broadcast
          ? "Only this meeting’s transcript is shared. Your private questions, notes and thoughts stay out of the broadcast context."
          : "Hold to address the assistant. During a meeting, Chup! must control the call’s microphone route before private voice is available."
      )
      .font(.callout).foregroundStyle(Palette.secondary)
      Picker("Headphone output", selection: $router.monitorUID) {
        Text("Select headphones").tag("")
        ForEach(router.outputs) { output in
          Text(output.name + (output.headphones ? "" : " · unqualified")).tag(output.id)
        }
      }.disabled(state.voiceScope != nil || router.routeActive)
      if state.activeMeetingID != nil {
        DisclosureGroup("Meeting audio route") {
          Picker("Outgoing microphone", selection: $router.virtualUID) {
            Text("Chup! Mic not installed").tag("")
            ForEach(router.virtualDevices) { Text($0.name).tag($0.id) }
          }.disabled(router.routeActive)
          HStack {
            Button(router.routeActive ? "Stop outgoing route" : "Start outgoing microphone") {
              router.routeActive ? state.stopAssistantRoute() : state.enableAssistantRoute()
            }
            Button("Refresh devices") { router.refresh() }
          }
          Text(router.message).font(.caption)
          Text(
            "Select Chup! Mic in your call app. This is a routed microphone, not a separate participant. Headphones are required; speakers are not qualified."
          ).font(.caption).foregroundStyle(Palette.secondary)
        }.insetSurface()
      }
      Divider()
      HStack(spacing: 14) {
        if state.voiceScope == nil {
          Button("Connect voice") { state.connectVoice(mode: mode) }.buttonStyle(.borderedProminent)
        } else {
          Button(state.addressing ? "Finish question" : "Ask by voice") {
            state.addressing ? state.finishAddressing() : state.startAddressing()
          }.disabled(!voice.ready).buttonStyle(.borderedProminent)
          Text("Hold to address").padding(.horizontal, 12).padding(.vertical, 7)
            .background(Palette.sidebar, in: Capsule())
            .gesture(
              DragGesture(minimumDistance: 0).onChanged { _ in state.startAddressing() }.onEnded {
                _ in state.finishAddressing()
              }
            )
            .accessibilityAddTraits(.isButton).accessibilityAction { state.startAddressing() }
          Button("Stop voice") { state.endVoice() }
        }
        Spacer()
        Text(voice.status).font(.caption)
      }
      if router.privateInput {
        Label("Call microphone is muted by Chup!", systemImage: "mic.slash.fill")
          .foregroundStyle(Palette.red)
        Button("End private voice and resume call microphone") {
          state.endVoice()
          state.resumeCallMicrophone()
        }
      }
      if !voice.inputTranscript.isEmpty {
        Text(voice.inputTranscript).font(.system(size: 16)).textSelection(.enabled)
      }
      if !voice.outputTranscript.isEmpty {
        Text(voice.outputTranscript).foregroundStyle(Palette.secondary).textSelection(.enabled)
        Text("Generated voice transcript · playback may be gated or interrupted").font(.caption)
          .foregroundStyle(Palette.secondary)
      }
      TimelineView(.animation(minimumInterval: 1.0 / 24, paused: router.level == 0 || reduceMotion))
      { timeline in
        HStack(spacing: 4) {
          ForEach(0..<20, id: \.self) { i in
            Capsule().fill(mode == .broadcast ? Palette.red : Palette.olive)
              .frame(
                width: 3,
                height: 3 + CGFloat(router.level)
                  * CGFloat(
                    12 + 14 * abs(sin(timeline.date.timeIntervalSinceReferenceDate * 7 + Double(i)))
                  ))
          }
        }.frame(height: 32)
      }.accessibilityLabel(router.level > 0 ? "Assistant audio rendering" : "Assistant silent")
    }.padding(22).workspaceSurface()
  }
}
