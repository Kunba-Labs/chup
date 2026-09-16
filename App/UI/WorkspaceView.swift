import ChupCore
import SwiftUI

struct WorkspaceView: View {
  @EnvironmentObject var state: WorkspaceState
  @Environment(\.openWindow) private var openWindow
  var body: some View {
    HStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 12) {
          WaveMark().scaleEffect(0.75).frame(width: 34)
          Text("Chup!").font(.system(size: 19, weight: .medium, design: .serif))
            .lineSpacing(0)
        }.padding(.top, 28).padding(.bottom, 38).padding(.horizontal, 24)
        Text("YOUR WORKSPACE").font(.system(size: 10, weight: .semibold)).tracking(1.7)
          .foregroundStyle(Palette.secondary).padding(.horizontal, 25).padding(.bottom, 12)
        ForEach(WorkspacePage.allCases.filter { $0 != .settings }) { page in
          Button {
            state.page = page
          } label: {
            HStack(spacing: 12) {
              if page == .dictation && state.dictationStatus == .processing {
                ProcessingCircle().frame(width: 18)
              } else if page == .dictation && state.dictationStatus == .listening {
                VoiceWaveform(samples: state.micWaveform, width: 18, height: 20, color: Palette.red)
              } else {
                Image(systemName: page.icon).frame(width: 18)
              }
              Text(page.rawValue)
              Spacer()
              if page == .dictation && state.pendingDictations > 0 {
                Text("\(state.pendingDictations)").font(.caption.monospacedDigit())
                  .foregroundStyle(Palette.secondary)
                  .accessibilityLabel("\(state.pendingDictations) dictations processing")
              }
            }.padding(.vertical, 10).padding(.horizontal, 14).contentShape(Rectangle()).background(
              state.page == page ? Palette.paper : .clear, in: RoundedRectangle(cornerRadius: 8))
          }.buttonStyle(.plain).padding(.horizontal, 12).foregroundStyle(
            state.page == page ? Palette.ink : Palette.secondary)
        }
        Spacer()
        VStack(alignment: .leading, spacing: 9) {
          HStack(spacing: 7) {
            Image(
              systemName: state.meetingStatus == .recording ? "record.circle.fill" : "lock.shield"
            ).foregroundStyle(state.meetingStatus == .recording ? Palette.red : Palette.olive)
            Text(state.meetingStatus == .recording ? "Recording locally" : "A space of your own")
              .font(.caption.weight(.medium))
          }
          Text(state.cloudEnabled ? "AI processing enabled" : "Audio & notes stay on this Mac")
            .font(.caption2).foregroundStyle(Palette.secondary)
        }.padding(20)
        Button {
          state.page = .settings
        } label: {
          Label("Settings", systemImage: "gearshape").frame(
            maxWidth: .infinity, alignment: .leading
          ).padding(16)
        }.buttonStyle(.plain).foregroundStyle(Palette.secondary)
      }.frame(width: 218).background(Palette.sidebar)
      Rectangle().fill(Palette.border).frame(width: 1)
      VStack(spacing: 0) {
        if let notice = state.notice {
          HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(Palette.olive)
            Text(notice).font(.system(size: 12))
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
            Button {
              state.notice = nil
            } label: {
              Image(systemName: "xmark")
            }.buttonStyle(.plain).accessibilityLabel("Dismiss notice")
          }.padding(13).background(Palette.paper)
        }
        Group {
          switch state.page {
          case .meetings: MeetingsView()
          case .dictation: DictationView()
          case .notebook: NotebookView()
          case .dictionary, .snippets, .styles: PersonalizationView(page: state.page).id(state.page)
          case .settings: SettingsView()
          }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      }.background(Palette.workspace)
    }.foregroundStyle(Palette.ink).tint(Palette.olive)
      .onAppear {
        if state.isPreview && ProcessInfo.processInfo.arguments.contains("--validate-audio") {
          Task {
            do {
              try await AudioValidation.run()
              exit(0)
            } catch {
              print("FAIL: " + error.localizedDescription)
              exit(1)
            }
          }
          return
        }
        if state.isPreview {
          DesignExporter.export(state: state)
          NSApp.terminate(nil)
          return
        }
        state.reveal = {
          openWindow(id: "workspace")
          NSApp.activate(ignoringOtherApps: true)
        }
        state.startShell()
      }
      .sheet(isPresented: $state.onboardingVisible) { OnboardingView().environmentObject(state) }
      .sheet(isPresented: $state.assistantVisible) {
        AssistantView().environmentObject(state).frame(width: 620, height: 580)
      }
  }
}
struct PageHeader: View {
  var eyebrow: String
  var title: String
  var subtitle: String
  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(eyebrow.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.8)
        .foregroundStyle(Palette.olive)
      Text(title).font(Palette.title)
      Text(subtitle).font(.system(size: 14)).foregroundStyle(Palette.secondary)
    }
  }
}
struct MeetingsView: View {
  @EnvironmentObject var state: WorkspaceState
  @State private var query = ""
  @State private var starting = false
  @State private var searchHits: [MeetingSearchHit] = []
  @State private var searchError: String?
  private func search() {
    do {
      searchHits = try state.store?.searchMeetings(query) ?? []
      searchError = nil
    } catch {
      searchError = "Search could not open the local index."
      searchHits = []
    }
  }
  var filtered: [Meeting] {
    state.meetings.filter { meeting in
      query.isEmpty || searchHits.contains(where: { hit in hit.meetingID == meeting.id })
        || "\(meeting.title) \(meeting.participants) \(meeting.tags)"
          .localizedCaseInsensitiveContains(query)
    }
  }
  var body: some View {
    if state.selectedMeetingID != nil {
      MeetingDetailView(initialTab: state.meetingTab)
    } else {
      VStack(alignment: .leading, spacing: 26) {
        HStack(alignment: .top) {
          PageHeader(
            eyebrow: "Be here. Keep the details.", title: "Meetings",
            subtitle: "Good conversations deserve a place to land.")
          Spacer()
          Button {
            state.newMeeting()
            starting = true
          } label: {
            Label("New meeting", systemImage: "plus")
          }.buttonStyle(.borderedProminent).controlSize(.large)
        }
        HStack {
          Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
          TextField("Search meetings, notes and transcripts", text: $query).textFieldStyle(.plain)
            .onChange(of: query) { _, _ in search() }.onAppear { search() }
          Spacer()
          Text("\(filtered.count) meetings").font(.caption).foregroundStyle(Palette.secondary)
        }.padding(13).background(Palette.paper, in: RoundedRectangle(cornerRadius: 8))
        if let searchError { Text(searchError).font(.caption).foregroundStyle(Palette.red) }
        if filtered.isEmpty {
          QuietEmpty(
            icon: "person.2.wave.2", title: "Make room for the conversation",
            subtitle:
              "Record a call or an in-person meeting. Your notes, transcript, and source-backed summary will live here."
          )
        } else {
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
              ForEach(filtered) { meeting in
                Button {
                  state.selectMeeting(meeting.id)
                  if let hit = searchHits.first(where: { $0.meetingID == meeting.id }),
                    let segment = hit.segmentID
                  {
                    state.meetingTab = "Transcript"
                    state.selectedTranscriptSource = segment
                  }
                } label: {
                  HStack(alignment: .top, spacing: 20) {
                    VStack {
                      Text(meeting.created.formatted(.dateTime.day())).font(
                        .system(size: 26, design: .serif))
                      Text(meeting.created.formatted(.dateTime.month(.abbreviated))).font(.caption)
                        .textCase(.uppercase)
                    }.foregroundStyle(Palette.secondary).frame(width: 42)
                    VStack(alignment: .leading, spacing: 8) {
                      Text(meeting.title).font(.system(size: 21, design: .serif))
                      if !query.isEmpty,
                        let hit = searchHits.first(where: { $0.meetingID == meeting.id })
                      {
                        Text(hit.excerpt).font(.callout).foregroundStyle(Palette.secondary)
                          .lineLimit(2)
                      }
                      Text(
                        meeting.participants.isEmpty
                          ? "No participants named yet" : meeting.participants
                      ).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                      if !meeting.tags.isEmpty {
                        Text(meeting.tags).font(.caption).foregroundStyle(Palette.olive)
                      }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                      Text(meeting.status).font(.caption).foregroundStyle(
                        meeting.status == "Recording" ? Palette.red : Palette.secondary)
                      Text(meeting.created.formatted(date: .omitted, time: .shortened)).font(
                        .caption
                      ).foregroundStyle(Palette.secondary)
                    }
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(
                      Palette.secondary)
                  }.padding(22).contentShape(Rectangle()).workspaceSurface()
                }.buttonStyle(.plain)
              }
            }
          }
        }
        HStack {
          Image(systemName: "lock")
          Text("Local recording first. Cloud transcription only when you enable it.")
        }.font(.caption).foregroundStyle(Palette.secondary)
      }.padding(38)
    }
  }
}
struct MeetingDetailView: View {
  @EnvironmentObject var state: WorkspaceState
  @State private var tab = "My notes"
  @State private var summaryEdit: SummaryItem?
  init(initialTab: String = "My notes") { _tab = State(initialValue: initialTab) }
  @State private var editMetadata = false
  @State private var title = ""
  @State private var people = ""
  @State private var tags = ""
  @State private var source: TranscriptSegment?
  @State private var captureSheet = false
  @State private var scrubbing = false
  @State private var scrubPosition: Double = 0
  @State private var resumeAfterScrub = false
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Button {
          state.leaveMeeting()
        } label: {
          Label("All meetings", systemImage: "arrow.left")
        }.buttonStyle(.plain).foregroundStyle(Palette.secondary)
        Spacer()
        Button {
          state.assistantVisible = true
        } label: {
          Label("Ask this meeting", systemImage: "sparkle")
        }.buttonStyle(.bordered)
      }.padding(.bottom, 25)
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 10) {
          Text(state.selectedMeeting?.title ?? "Meeting").font(Palette.title)
          HStack {
            Text(
              state.selectedMeeting?.created.formatted(date: .abbreviated, time: .shortened) ?? "")
            Text("·")
            Text(
              state.selectedMeeting?.participants.isEmpty == false
                ? state.selectedMeeting!.participants : "Participants not named")
          }.font(.caption).foregroundStyle(Palette.secondary)
        }
        Spacer()
        Button {
          title = state.selectedMeeting?.title ?? ""
          people = state.selectedMeeting?.participants ?? ""
          tags = state.selectedMeeting?.tags ?? ""
          editMetadata = true
        } label: {
          Image(systemName: "ellipsis")
        }.accessibilityLabel("Edit meeting details")
      }
      HStack(spacing: 14) {
        if state.activeMeetingID == state.selectedMeetingID {
          Label(
            state.meetingStatus == .recording ? "Recording" : "Paused",
            systemImage: state.meetingStatus == .recording ? "record.circle.fill" : "pause.circle"
          ).foregroundStyle(Palette.red)
          Text(WorkspaceState.time(state.elapsed)).monospacedDigit()
          SourceMeter(
            name: state.voiceRouter.privateInput ? "Mic omitted" : "Mic",
            level: state.voiceRouter.privateInput ? 0 : state.micLevel,
            receiving: state.micLastPacket.map { Date().timeIntervalSince($0) < 3 } ?? false)
          SourceMeter(
            name: "Call", level: state.remoteLevel,
            receiving: state.remoteLastPacket.map {
              Date().timeIntervalSince($0) < 3
            } ?? false)
          Spacer()
          Button {
            state.meetingStatus == .paused ? state.resumeMeeting() : state.pauseMeeting()
          } label: {
            Image(systemName: state.meetingStatus == .paused ? "play.fill" : "pause.fill")
          }.accessibilityLabel("Pause or resume local recording")
          Button("Stop & save") { state.stopMeeting() }
        } else {
          Label("Your notes save as you type", systemImage: "checkmark.circle").font(.caption)
            .foregroundStyle(Palette.secondary)
          Spacer()
          Button {
            captureSheet = true
            state.refreshApps()
          } label: {
            Label("Record", systemImage: "record.circle")
          }.buttonStyle(.borderedProminent).disabled(state.activeMeetingID != nil)
        }
      }.font(.system(size: 12)).padding(14).background(
        Palette.paper, in: RoundedRectangle(cornerRadius: 8)
      ).padding(.top, 26).padding(.bottom, 22)
      HStack(spacing: 25) {
        ForEach(["Summary", "My notes", "Transcript", "Actions", "Private thoughts"], id: \.self) {
          label in
          Button {
            tab = label
          } label: {
            VStack(spacing: 12) {
              Text(label).font(.system(size: 14, weight: tab == label ? .semibold : .regular))
                .foregroundStyle(tab == label ? Palette.ink : Palette.secondary)
              Rectangle().fill(tab == label ? Palette.olive : .clear).frame(height: 2)
            }.frame(width: label == "Private thoughts" ? 115 : (label == "Transcript" ? 80 : 76))
          }.buttonStyle(.plain)
        }
        Spacer()
        if state.processingMeeting { ProgressView().controlSize(.small) }
      }.overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 1) }
      Group {
        if tab == "My notes" {
          VStack(alignment: .leading, spacing: 12) {
            Text("Your side of the conversation").font(.system(size: 22, design: .serif)).padding(
              .top, 24)
            ZStack(alignment: .topLeading) {
              if state.noteDraft.isEmpty {
                Text("A thought, a question, something to come back to…").foregroundStyle(
                  Palette.secondary
                ).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
              }
              TextEditor(text: $state.noteDraft).font(.system(size: 17)).scrollContentBackground(
                .hidden
              ).onChange(of: state.noteDraft) { _, new in state.saveNote(new) }
            }.padding(16).workspaceSurface().frame(maxHeight: .infinity)
            HStack {
              Text("Version \(state.note.version) · Stored locally").font(.caption).foregroundStyle(
                Palette.secondary)
              Spacer()
              Button("Undo last edit") { state.undoNote() }.disabled(state.lastReceipt == nil)
            }
          }
        } else if tab == "Actions" {
          MeetingActionsView()
        } else if tab == "Private thoughts" {
          PrivateThoughtsView()
        } else if tab == "Summary" {
          summaryBody
        } else {
          transcriptBody
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
      RecordingWaveform(
        bins: state.waveformBins, duration: state.playbackDuration, position: state.playbackTime
      )
      .frame(height: 38).accessibilityHidden(true)
      HStack {
        Button {
          state.playing ? state.stopPlayback() : state.play(at: state.playbackTime)
        } label: {
          Image(systemName: state.playing ? "pause.fill" : "play.fill")
        }.accessibilityLabel(state.playing ? "Pause meeting audio" : "Play meeting audio")
          .disabled(state.playbackDuration == 0 || (state.playbackLoading && !state.playing))
        Text(WorkspaceState.time(state.playbackTime)).monospacedDigit().frame(width: 42)
        Slider(
          value: Binding(
            get: { scrubbing ? scrubPosition : state.playbackTime }, set: { scrubPosition = $0 }),
          in: 0...max(1, state.playbackDuration),
          onEditingChanged: { editing in
            if editing {
              scrubPosition = state.playbackTime
              resumeAfterScrub = state.playing
              scrubbing = true
              state.stopPlayback()
            } else {
              scrubbing = false
              state.seekPlayback(to: scrubPosition)
              if resumeAfterScrub { state.play(at: scrubPosition) }
            }
          }
        )
        .accessibilityLabel("Meeting audio position")
        .accessibilityValue(WorkspaceState.time(state.playbackTime))
        .disabled(state.playbackDuration == 0 || state.playbackLoading)
        Text(WorkspaceState.time(state.playbackDuration)).monospacedDigit().foregroundStyle(
          Palette.secondary)
        if state.playbackLoading { ProgressView().controlSize(.mini) }
        Text("Original audio").foregroundStyle(Palette.secondary)
        Button("Show recordings") {
          NSWorkspace.shared.open(
            state.root.appendingPathComponent("Recordings/\(state.selectedMeetingID ?? "")"))
        }
      }.font(.caption).padding(.top, 16)
    }.padding(34)
      .onChange(of: state.meetingTab) { _, new in tab = new }
      .onChange(of: tab) { _, new in state.meetingTab = new }
      .sheet(item: $summaryEdit) { item in SummaryEditView(item: item).environmentObject(state) }
      .sheet(isPresented: $captureSheet) { CaptureSetupView().environmentObject(state) }
      .sheet(isPresented: $editMetadata) {
        VStack(alignment: .leading, spacing: 18) {
          Text("Meeting details").font(.title2)
          TextField("Title", text: $title)
          TextField("Participant names (candidates, not speaker proof)", text: $people)
          TextField("Tags, separated by commas", text: $tags)
          HStack {
            Button("Cancel") { editMetadata = false }
            Spacer()
            Button("Save") {
              state.renameMeeting(title, participants: people, tags: tags)
              editMetadata = false
            }.buttonStyle(.borderedProminent)
          }
        }.padding(28).frame(width: 460)
      }
      .sheet(item: $source) { item in SegmentEditor(segment: item).environmentObject(state) }
  }
  private var summaryBody: some View {
    VStack(alignment: .leading) {
      HStack {
        Text("Grounded in the conversation").font(.system(size: 22, design: .serif))
        Spacer()
        Button(state.summary == nil ? "Generate summary" : "New summary version") {
          state.generateSummary()
        }.disabled(state.segments.isEmpty || state.processingMeeting)
      }.padding(.vertical, 24)
      if let outline = state.liveOutline, state.activeMeetingID == state.selectedMeetingID {
        LiveOutlineView(outline: outline)
      }
      if !state.summaryVersions.isEmpty {
        Menu("Saved summary versions") {
          ForEach(state.summaryVersions) { revision in
            Button(revision.created.formatted()) { state.summary = revision.summary }
          }
        }
      }
      ForEach(state.summaryEdits) { item in
        VStack(alignment: .leading, spacing: 6) {
          Text("Your pinned edit").font(.caption).foregroundStyle(Palette.olive)
          Text(item.text)
          Button("Edit") { summaryEdit = item }
        }.padding(12).background(Palette.paper, in: RoundedRectangle(cornerRadius: 8))
      }
      if let summary = state.summary {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            ForEach(summary.items) { item in
              VStack(alignment: .leading, spacing: 10) {
                Text(item.category.uppercased()).font(.caption.weight(.semibold)).tracking(1.4)
                  .foregroundStyle(Palette.olive)
                Text(item.text).font(.system(size: 17)).textSelection(.enabled)
                if let owner = item.owner { Text("Owner: \(owner)").font(.caption) }
                if let due = item.dueDate { Text("Due: \(due)").font(.caption) }
                LazyVGrid(
                  columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)],
                  alignment: .leading, spacing: 10
                ) {
                  Button("Pin an edit") { summaryEdit = item }.font(.caption)
                  if item.category == "action" {
                    Button("Save action") { state.createAction(from: item) }.font(.caption)
                  }
                  ForEach(item.sources.indices, id: \.self) { index in
                    Button {
                      if let segment = state.segments.first(where: {
                        $0.id == item.sources[index].segmentID
                      }) {
                        tab = "Transcript"
                        state.selectedTranscriptSource = segment.id
                        state.play(at: segment.start)
                      }
                    } label: {
                      Label("Source \(index+1)", systemImage: "quote.bubble")
                    }.buttonStyle(.borderless).font(.caption)
                  }
                }
              }.padding(22).workspaceSurface()
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        QuietEmpty(
          icon: "text.alignleft", title: "A clear record of what mattered",
          subtitle:
            "Transcribe the audio first, then generate an overview, decisions, actions, and open questions with evidence."
        )
      }
    }
  }
  private var transcriptBody: some View {
    VStack(alignment: .leading) {
      HStack {
        Text("Every voice, in context").font(.system(size: 22, design: .serif))
        Spacer()
        Button("Inspect recovery") { state.inspectRecording() }.disabled(
          state.activeMeetingID == state.selectedMeetingID)
        Menu("Refine transcript") {
          Button("Transcribe / retry") { state.transcribeMeeting() }
          Button("Reprocess and review corrections") { state.transcribeMeeting(reprocess: true) }
        }.disabled(
          state.processingMeeting || state.activeMeetingID == state.selectedMeetingID)
      }.padding(.vertical, 24)
      if state.processingMeeting {
        HStack {
          ProgressView().controlSize(.small)
          Text(state.transcriptionProgress)
          Button("Cancel") { state.cancelTranscription() }
        }
      }
      ForEach(state.transcriptReviews) { TranscriptReviewView(review: $0) }
      if state.meetingStatus == .recording {
        Button("Reconnect call audio") { state.reconnectCallAudio() }
      }
      if !state.captureGaps.isEmpty {
        ForEach(state.captureGaps.indices, id: \.self) { index in
          let gap = state.captureGaps[index]
          Label(
            "Capture gap at \(WorkspaceState.time(gap.start)): \(gap.reason)",
            systemImage: "waveform.slash"
          ).font(.caption).foregroundStyle(Palette.red)
        }
      }
      if state.segments.isEmpty {
        QuietEmpty(
          icon: "waveform", title: "The conversation lives here",
          subtitle:
            "Record first. Final transcription adds timing and speaker groups. People are named only when you identify them."
        )
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 25) {
            ForEach(state.segments) { segment in
              HStack(alignment: .top, spacing: 18) {
                Button(WorkspaceState.time(segment.start)) { state.play(at: segment.start) }.font(
                  .caption.monospacedDigit()
                ).buttonStyle(.plain).foregroundStyle(Palette.olive).frame(width: 48)
                VStack(alignment: .leading, spacing: 8) {
                  HStack {
                    Text(
                      segment.provisional
                        ? "Provisional · speaker unknown" : segment.speakerName ?? "Unknown speaker"
                    ).font(.system(size: 12, weight: .semibold))
                    Text(
                      segment.track == .microphone
                        ? "MIC" : (segment.track == .assistant ? "ASSISTANT" : "CALL")
                    ).font(
                      .system(size: 9, weight: .semibold)
                    ).foregroundStyle(Palette.secondary)
                    Spacer()
                    Button {
                      source = segment
                    } label: {
                      Image(systemName: "pencil")
                    }.buttonStyle(.plain).accessibilityLabel("Correct transcript or speaker")
                  }
                  Text(segment.text).padding(5).background(
                    state.selectedTranscriptSource == segment.id ? Palette.sidebar : .clear,
                    in: RoundedRectangle(cornerRadius: 5)
                  ).font(.system(size: 16)).lineSpacing(5).textSelection(.enabled)
                }
              }.padding(18).workspaceSurface()
            }
          }.scrollTargetLayout()
        }.scrollPosition(id: $state.selectedTranscriptSource, anchor: .center)
      }
    }
  }
}
struct CaptureSetupView: View {
  @EnvironmentObject var state: WorkspaceState
  @Environment(\.dismiss) var dismiss
  var permissionSetup = false
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      Text("Be present. We’ll keep the audio.").font(.system(size: 27, design: .serif))
      Text(
        "Let everyone know you’re recording. Microphone and call audio are saved separately on this Mac."
      ).foregroundStyle(Palette.secondary)
      if permissionSetup {
        Text(
          "Choose the app whose audio you want to record. Starting requests any missing macOS access and creates a new meeting recording. Nothing starts until you press Start recording."
        )
        .font(.callout).foregroundStyle(Palette.secondary)
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          MicrophonePicker(devices: state.devices, showsPreview: false)
          WorkspaceCard("Meeting audio", icon: "person.wave.2") {
            Picker("Meeting audio", selection: $state.selectedPID) {
              Text("In person · microphone only").tag(Int32(0))
              ForEach(state.availableApps, id: \.processIdentifier) { app in
                Text(app.localizedName ?? "App \(app.processIdentifier)").tag(app.processIdentifier)
              }
            }
            if state.selectedPID != 0 {
              Text(
                "App capture may include all audio from that app. Browsers can include other tabs and may use separate audio helper processes."
              ).font(.caption).foregroundStyle(Palette.red)
            }
            Text("Pausing this recorder does not mute you in the meeting.").font(.caption)
              .foregroundStyle(Palette.secondary)
          }
        }.padding(.trailing, 4)
      }
      Divider()
      HStack {
        Button("Cancel") { dismiss() }
        Spacer()
        Button("Start recording") {
          if permissionSetup { state.newMeeting() }
          state.startMeeting()
          dismiss()
        }.buttonStyle(.borderedProminent)
          .disabled(
            state.activeMeetingID != nil || state.storageBusy
              || (permissionSetup && state.selectedPID == 0))
      }
    }.padding(28).frame(width: 560, height: 720).background(Palette.workspace).onAppear {
      state.refreshApps()
    }
  }
}
struct SegmentEditor: View {
  @EnvironmentObject var state: WorkspaceState
  @Environment(\.dismiss) var dismiss
  let segment: TranscriptSegment
  @State private var text = ""
  @State private var name = ""
  @State private var merge = ""
  @State private var enrollmentConsent = false
  init(segment: TranscriptSegment) {
    self.segment = segment
    _text = State(initialValue: segment.text)
    _name = State(initialValue: segment.speakerName ?? "")
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Correct the record").font(.system(size: 25, design: .serif))
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          WorkspaceCard("Transcript", icon: "text.bubble") {
            TextEditor(text: $text).font(.system(size: 16)).scrollContentBackground(.hidden).frame(
              height: 130)
          }
          WorkspaceCard("Speaker", icon: "person.crop.circle") {
            TextField("Speaker name (leave unknown if unsure)", text: $name)
            DisclosureGroup("Remember this voice across meetings") {
              Text(
                "Listen to this interval first. It must contain only this person. The reference is saved locally and encrypted; cloud matching starts off."
              ).font(.caption)
              Button("Listen to reference interval") { state.play(at: segment.start) }
              Toggle(
                "I confirm this is a single speaker and want to enroll their voice",
                isOn: $enrollmentConsent)
              Button("Save encrypted voice reference") {
                state.enrollVoice(segment, name: name, consent: enrollmentConsent)
              }
              .disabled(
                !enrollmentConsent || name.isEmpty || segment.provisional
                  || segment.end - segment.start < 2)
            }
            Picker("Assign to existing speaker group", selection: $merge) {
              Text("Keep current assignment").tag("")
              ForEach(Array(Set(state.segments.map(\.speakerID))).sorted(), id: \.self) { id in
                Text(
                  state.segments.first(where: { $0.speakerID == id })?.speakerName
                    ?? "Unknown · \(String(id.suffix(12)))"
                ).tag(id)
              }
            }
          }
        }
      }
      Divider()
      HStack {
        Button("Split into new speaker") {
          state.splitSpeaker(segment)
          dismiss()
        }
        Spacer()
        Button("Cancel") { dismiss() }
        Button("Save correction") {
          state.correctSegment(
            segment, text: text, name: name, mergeID: merge.isEmpty ? nil : merge)
          if !name.isEmpty && merge.isEmpty { state.renameSpeaker(segment.speakerID, name: name) }
          dismiss()
        }.buttonStyle(.borderedProminent)
      }
    }.padding(28).frame(width: 580, height: 650).background(Palette.workspace).textFieldStyle(
      .roundedBorder
    ).onAppear {
      text = segment.text
      name = segment.speakerName ?? ""
    }
  }
}
