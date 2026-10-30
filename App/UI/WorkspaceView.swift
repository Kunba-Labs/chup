import ChupCore
import SwiftUI

struct WorkspaceView: View {
  @EnvironmentObject var state: WorkspaceState
  @Environment(\.openWindow) private var openWindow
  var body: some View {
    WorkspaceShell()
      .onAppear {
        if ProcessInfo.processInfo.arguments.contains("--validate-audio") { return }
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
/// Glass rail beside the floating content panel.
struct WorkspaceShell: View {
  @EnvironmentObject var state: WorkspaceState
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    HStack(spacing: 0) {
      GlassRail()
      VStack(spacing: 0) {
        if let notice = state.notice {
          HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(Palette.accent)
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
          case .today: TodayView()
          case .meetings: MeetingsView()
          case .dictation: DictationView()
          case .notebook: NotebookView()
          case .dictionary, .snippets, .styles: PersonalModuleView()
          case .settings: SettingsView()
          }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      }.background(Palette.workspace).clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
          RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.border.opacity(0.8), lineWidth: 0.5)
            .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.07), radius: 14, y: 4).padding(10)
    }.overlay {
      if state.searchOpen {
        ZStack(alignment: .top) {
          Color.black.opacity(0.18).ignoresSafeArea().onTapGesture { state.searchOpen = false }
            .accessibilityHidden(true)
          SearchPalette().padding(.top, 90)
        }
      }
    }.background {
      Button("Search") { state.searchOpen.toggle() }.keyboardShortcut("k", modifiers: .command)
        .opacity(0).accessibilityHidden(true)
    }.overlay(alignment: .bottom) {
      if let toast = state.undoToast {
        UndoToastView(toast: toast).padding(.bottom, 28).transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }.animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: state.undoToast).background(
      LinearGradient(
        colors: [Palette.sidebar, Palette.backdrop], startPoint: .topLeading,
        endPoint: .bottomTrailing)).foregroundStyle(Palette.ink).tint(Palette.accent)
  }
}
struct PageHeader: View {
  var eyebrow: String
  var title: String
  var subtitle: String
  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(eyebrow.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.8)
        .foregroundStyle(Palette.accent)
      Text(title).font(Palette.title)
      Text(subtitle).font(.system(size: 14)).foregroundStyle(Palette.secondary)
    }
  }
}
struct MeetingsView: View {
  @EnvironmentObject var state: WorkspaceState
  @AppStorage("meetingListCollapsed") private var listCollapsed = false
  @State private var showTrash = false
  @State private var showTags = false
  @State private var tagFilter: String?
  @State private var personFilter: String?
  @State private var sinceDays = 0
  @State private var deletion: Meeting?
  @State private var query = ""
  @State private var starting = false
  @State private var searchHits: [MeetingSearchHit] = []
  @State private var searchError: String?
  private func search() {
    do {
      searchHits = try state.store?.searchMeetings(query) ?? []
      searchError = nil
    } catch {
      searchError = "Search isn’t available. Try again."
      searchHits = []
    }
  }
  var filtered: [Meeting] {
    let since = Calendar.current.date(byAdding: .day, value: -sinceDays, to: Date())
    return state.meetings.filter { meeting in
      (query.isEmpty || searchHits.contains(where: { hit in hit.meetingID == meeting.id })
        || "\(meeting.title) \(meeting.participants) \(meeting.tags)"
          .localizedCaseInsensitiveContains(query))
        && (tagFilter.map { tag in Meeting.tagList(meeting.tags).contains(tag) } ?? true)
        && (personFilter.map { person in Self.people(meeting.participants).contains(person) } ?? true)
        && (sinceDays == 0 || since.map { meeting.created >= $0 } ?? true)
    }
  }
  static func people(_ participants: String) -> [String] {
    participants.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
  }
  private var filtersActive: Bool { tagFilter != nil || personFilter != nil || sinceDays != 0 }
  private var filterBar: some View {
    HStack(spacing: 10) {
      Menu(tagFilter ?? "Any tag") {
        Button("Any tag") { tagFilter = nil }
        ForEach(state.allTags, id: \.self) { tag in Button(tag) { tagFilter = tag } }
      }.fixedSize()
      Menu(personFilter ?? "Anyone") {
        Button("Anyone") { personFilter = nil }
        ForEach(Array(Set(state.meetings.flatMap { Self.people($0.participants) })).sorted(), id: \.self) {
          person in Button(person) { personFilter = person }
        }
      }.fixedSize()
      Picker("Date", selection: $sinceDays) {
        Text("Any time").tag(0)
        Text("Last 7 days").tag(7)
        Text("Last 30 days").tag(30)
        Text("Last 90 days").tag(90)
      }.labelsHidden().fixedSize()
      if filtersActive {
        Button("Clear filters") {
          tagFilter = nil
          personFilter = nil
          sinceDays = 0
        }.buttonStyle(.plain).foregroundStyle(Palette.accent)
      }
      Spacer()
    }.controlSize(.small)
  }
  var body: some View {
    if state.selectedMeetingID != nil {
      // The meeting page needs ~700 pt, so the list steps aside in narrow windows.
      GeometryReader { geometry in
        HStack(spacing: 0) {
          if !listCollapsed && geometry.size.width >= 940 {
            MeetingListColumn()
            Rectangle().fill(Palette.border).frame(width: 0.5)
          }
          MeetingDetailView(initialTab: state.meetingTab).id(state.selectedMeetingID)
        }
      }.background {
        Button("Toggle meeting list") { listCollapsed.toggle() }
          .keyboardShortcut("\\", modifiers: .command).opacity(0).accessibilityHidden(true)
      }
    } else {
      VStack(alignment: .leading, spacing: 26) {
        HStack(alignment: .top) {
          PageHeader(
            eyebrow: "Record, review, search", title: "Meetings",
            subtitle: "Record a call and get notes when it ends.")
          Spacer()
          Button("Tags") { showTags = true }.controlSize(.large)
          Button {
            showTrash = true
          } label: {
            Label(state.trash.isEmpty ? "Trash" : "Trash (\(state.trash.count))", systemImage: "trash")
          }.controlSize(.large)
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
        filterBar
        if let searchError { Text(searchError).font(.caption).foregroundStyle(Palette.red) }
        if filtered.isEmpty {
          QuietEmpty(
            icon: "person.2.wave.2", title: "No meetings yet",
            subtitle:
              "Press Record in the rail to start your first meeting."
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
                        .system(size: 26, weight: .semibold))
                      Text(meeting.created.formatted(.dateTime.month(.abbreviated))).font(.caption)
                        .textCase(.uppercase)
                    }.foregroundStyle(Palette.secondary).frame(width: 42)
                    VStack(alignment: .leading, spacing: 8) {
                      HStack(spacing: 8) {
                        if let app = state.meetingApps[meeting.id] {
                          InstalledAppIcon(bundleID: app, size: 20)
                        }
                        Text(meeting.title).font(.system(size: 21, weight: .semibold))
                      }
                      if !query.isEmpty,
                        let hit = searchHits.first(where: { $0.meetingID == meeting.id })
                      {
                        Text(hit.excerpt).font(.callout).foregroundStyle(Palette.secondary)
                          .lineLimit(2)
                      }
                      Text(
                        meeting.participants.isEmpty
                          ? "No people added" : meeting.participants
                      ).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                      if !meeting.tags.isEmpty {
                        Text(meeting.tags).font(.caption).foregroundStyle(Palette.accent)
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
                  .contextMenu {
                    Button("Move to Trash", role: .destructive) { deletion = meeting }
                      .disabled(!state.privacyWorkAllowed)
                  }
              }
            }
          }
        }
        PipelineStatus()
      }.padding(38).confirmDeleteMeeting($deletion)
        .sheet(isPresented: $showTrash) { TrashView().environmentObject(state) }
        .sheet(isPresented: $showTags) { TagManagerView().environmentObject(state) }
    }
  }
}
struct MeetingDetailView: View {
  @EnvironmentObject var state: WorkspaceState
  @State private var tab = "Notes"
  @State private var summaryEdit: SummaryItem?
  init(initialTab: String = "Notes") {
    _tab = State(initialValue: initialTab == "Summary" ? "Summary" : "Notes")
    _revealOnAppear = State(initialValue: initialTab == "Transcript")
  }
  @State private var revealOnAppear: Bool
  @AppStorage("transcriptCollapsed") private var transcriptCollapsed = false
  @AppStorage("transcriptWidth") private var transcriptWidth = 400.0
  @State private var askOpen = false
  private enum PartialDelete { case audio, transcript }
  @State private var partialDelete: PartialDelete?
  @State private var dragStartWidth: Double?
  /// Narrow windows show one pane; this asks for the transcript instead of the notes.
  @State private var narrowSide = false
  @State private var wideLayout = true
  private var transcriptVisible: Bool { !transcriptCollapsed && (wideLayout || narrowSide) }
  @State private var titleEdit: String?
  @FocusState private var titleFocused: Bool
  @State private var findQuery = ""
  @State private var findIndex = 0
  @FocusState private var findFocused: Bool
  @State private var editMetadata = false
  @State private var deletion: Meeting?
  @State private var title = ""
  @State private var people = ""
  @State private var tags = ""
  @State private var source: TranscriptSegment?
  @State private var renaming: TranscriptSegment?
  @State private var newSpeakerName = ""
  @State private var voiceSample: VoiceSample?
  @State private var captureSheet = false
  @State private var scrubbing = false
  @State private var scrubPosition: Double = 0
  @State private var resumeAfterScrub = false
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      HStack(spacing: 14) {
        if state.activeMeetingID == state.selectedMeetingID {
          Label(
            state.meetingStatus == .recording
              ? "Recording" : state.meetingStatus == .processing ? "Starting…" : "Paused",
            systemImage: state.meetingStatus == .recording
              ? "record.circle.fill" : state.meetingStatus == .processing ? "hourglass" : "pause.circle"
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
          }.accessibilityLabel("Pause or resume recording")
          Button("Stop and save") { state.stopMeeting() }
        } else {
          Label("Notes save as you type", systemImage: "checkmark.circle").font(.caption)
            .foregroundStyle(Palette.secondary)
          Spacer()
          Button {
            captureSheet = true
            state.refreshApps()
          } label: {
            Label("Record", systemImage: "record.circle")
          }.buttonStyle(.borderedProminent).disabled(state.activeMeetingID != nil)
        }
      }.font(.system(size: 12)).padding(.vertical, 8).padding(.horizontal, 14).background(
        Palette.paper, in: Capsule()
      ).padding(.top, 14).padding(.bottom, 16)
      GeometryReader { geometry in
        // The transcript pane steps aside below ~760 pt of page (about an 1100 pt window).
        let wide = geometry.size.width >= 760
        let showSide = askOpen || (!transcriptCollapsed && wide)
        Color.clear.frame(height: 0).onChange(of: wide, initial: true) { _, new in wideLayout = new }
        if !wide && (askOpen || narrowSide) {
          // Narrow window: the transcript or Ask takes the notes pane's place.
          VStack(alignment: .leading, spacing: 10) {
            Button {
              askOpen = false
              narrowSide = false
            } label: {
              Label("Back to notes", systemImage: "chevron.left")
            }.buttonStyle(.plain).foregroundStyle(Palette.secondary)
            if askOpen { AssistantView { askOpen = false } } else { transcriptBody }
          }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
        HStack(alignment: .top, spacing: 0) {
          notesPane.frame(maxWidth: .infinity, maxHeight: .infinity)
          if showSide {
            Rectangle().fill(Palette.border).frame(width: 1).padding(.horizontal, 10)
              .overlay { Color.clear.frame(width: 12).contentShape(Rectangle()).onHover { inside in
                inside ? NSCursor.resizeLeftRight.push() : NSCursor.pop()
              }.gesture(DragGesture().onChanged { drag in
                let start = dragStartWidth ?? transcriptWidth
                dragStartWidth = start
                transcriptWidth = min(640, max(300, start - drag.translation.width))
              }.onEnded { _ in dragStartWidth = nil }) }
              .accessibilityHidden(true)
            Group {
              if askOpen {
                AssistantView { askOpen = false }
              } else {
                transcriptBody
              }
            }.frame(width: min(transcriptWidth, geometry.size.width * 0.55)).frame(maxHeight: .infinity)
          }
        }
        }
      }
      timeline
    }.padding(30)
      .background {
        Button("Find in transcript") {
          revealTranscript()
          findFocused = true
        }.keyboardShortcut("f", modifiers: .command).opacity(0).accessibilityHidden(true)
      }
      .onChange(of: state.meetingTab) { _, new in
        if new == "Transcript" {
          revealTranscript()
        } else if new == "Notes" || new == "Summary" { tab = new }
      }
      .onChange(of: tab) { _, new in state.meetingTab = new }
      .onChange(of: titleFocused) { _, focused in if !focused { saveTitle() } }
      .onAppear {
        if revealOnAppear {
          revealOnAppear = false
          revealTranscript()
        }
      }
      .sheet(item: $summaryEdit) { item in SummaryEditView(item: item).environmentObject(state) }
      .sheet(isPresented: $captureSheet) { CaptureSetupView().environmentObject(state) }
      .sheet(isPresented: $editMetadata) {
        VStack(alignment: .leading, spacing: 18) {
          Text("Meeting details").font(.title2)
          TextField("Title", text: $title)
          TextField("People in the meeting", text: $people)
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
      .sheet(item: $voiceSample) { sample in VoiceSampleConfirmation(sample: sample).environmentObject(state) }
      .alert("Rename speaker", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
        TextField("Name", text: $newSpeakerName)
        Button("Rename") {
          if let renaming { state.renameSpeaker(renaming.speakerID, name: newSpeakerName.trimmingCharacters(in: .whitespaces)) }
        }
        // Enrollment needs finished audio, so it is offered once recording ends.
        if state.activeMeetingID != state.selectedMeetingID {
          Button("Rename and remember their voice…") {
            let name = newSpeakerName.trimmingCharacters(in: .whitespaces)
            if let renaming, !name.isEmpty {
              state.renameSpeaker(renaming.speakerID, name: name)
              if let sample = state.voiceSample(for: renaming.speakerID) {
                voiceSample = VoiceSample(segment: sample, name: name)
              } else {
                state.notice = "\(name) has no clean line of two seconds or more to learn their voice from."
              }
            }
          }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Changes every line from \(renaming.map { state.speakerLabel($0.speakerID) } ?? "this speaker") in this meeting. Remembering saves an encrypted voice clip on this Mac and sends it with future transcriptions so Chup! can name them.")
      }
      .confirmDeleteMeeting($deletion)
  }
  private var summaryBody: some View {
    VStack(alignment: .leading) {
      HStack {
        Text("Summary").font(.system(size: 22, weight: .semibold))
        Spacer()
        Button(state.summary == nil ? "Write summary" : "Write a new version") {
          state.generateSummary()
        }.disabled(state.segments.isEmpty || state.processingMeeting)
      }.padding(.vertical, 24)
      if !state.liveOutlines.isEmpty, state.activeMeetingID == state.selectedMeetingID {
        LiveOutlineView(outlines: state.liveOutlines)
      }
      if !state.summaryVersions.isEmpty {
        Menu("Earlier versions") {
          ForEach(state.summaryVersions) { revision in
            Button(revision.created.formatted()) { state.summary = revision.summary }
          }
        }
      }
      ForEach(state.summaryEdits) { item in
        VStack(alignment: .leading, spacing: 6) {
          Text("Your edit").font(.caption).foregroundStyle(Palette.accent)
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
                  .foregroundStyle(Palette.accent)
                Text(item.text).font(.system(size: 17)).textSelection(.enabled)
                if let owner = item.owner { Text("Owner: \(owner)").font(.caption) }
                if let due = item.dueDate { Text("Due: \(due)").font(.caption) }
                LazyVGrid(
                  columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)],
                  alignment: .leading, spacing: 10
                ) {
                  Button("Edit") { summaryEdit = item }.font(.caption)
                  if item.category == "action" {
                    Button("Save action") { state.createAction(from: item) }.font(.caption)
                  }
                  ForEach(item.sources.indices, id: \.self) { index in
                    if state.partial.transcript {
                      Label("Source deleted", systemImage: "quote.bubble").font(.caption)
                        .foregroundStyle(Palette.secondary).help("The transcript of this meeting was deleted.")
                    } else {
                    Button {
                      if let segment = state.segments.first(where: {
                        $0.id == item.sources[index].segmentID
                      }) {
                        revealTranscript()
                        state.selectedTranscriptSource = segment.id
                        if !state.partial.audio { state.play(at: segment.start) }
                      }
                    } label: {
                      Label(state.partial.audio ? "Source \(index+1) · no audio" : "Source \(index+1)", systemImage: "quote.bubble")
                    }.buttonStyle(.borderless).font(.caption)
                    }
                  }
                }
              }.padding(22).workspaceSurface()
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        QuietEmpty(
          icon: "text.alignleft", title: "No summary yet",
          subtitle:
            "Get the transcript first. Then press Write summary."
        )
      }
    }
  }
  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        Button {
          state.leaveMeeting()
        } label: {
          Image(systemName: "chevron.left").frame(width: 24, height: 24)
        }.buttonStyle(.plain).foregroundStyle(Palette.secondary).help("All meetings")
          .accessibilityLabel("All meetings")
        TextField("Untitled meeting", text: Binding(
          get: { titleEdit ?? state.selectedMeeting?.title ?? "" }, set: { titleEdit = $0 }))
          .textFieldStyle(.plain)
          .font(.system(size: 26, weight: .semibold)).focused($titleFocused).onSubmit(saveTitle)
          .accessibilityLabel("Meeting title")
        Spacer(minLength: 12)
        Menu {
          Button("Copy notes as Markdown") { state.copyNotesMarkdown() }
          Button("Draft follow-up email") { state.draftFollowup() }
        } label: {
          Label("Export", systemImage: "square.and.arrow.up")
        }.fixedSize().disabled(state.enhancedNotes?.blocks.isEmpty ?? true)
        Button {
          askOpen.toggle()
        } label: {
          Label("Ask", systemImage: "sparkle")
        }.buttonStyle(.bordered).help("Ask about this meeting")
        Button {
          if !transcriptVisible { revealTranscript() } else {
            transcriptCollapsed = true
            narrowSide = false
          }
          askOpen = false
        } label: {
          Image(systemName: "sidebar.right")
        }.buttonStyle(.plain).foregroundStyle(Palette.secondary)
          .help(transcriptVisible ? "Hide transcript" : "Show transcript")
          .accessibilityLabel(transcriptVisible ? "Hide transcript" : "Show transcript")
        Menu {
          Button("Edit details…") {
            title = state.selectedMeeting?.title ?? ""
            people = state.selectedMeeting?.participants ?? ""
            tags = state.selectedMeeting?.tags ?? ""
            editMetadata = true
          }
          Divider()
          Button("Delete audio only…") { partialDelete = .audio }
            .disabled(!state.privacyWorkAllowed || state.partial.audio)
          Button("Delete transcript only…") { partialDelete = .transcript }
            .disabled(!state.privacyWorkAllowed || state.partial.transcript)
          Button("Move to Trash", role: .destructive) { deletion = state.selectedMeeting }
            .disabled(!state.privacyWorkAllowed)
        } label: {
          Image(systemName: "ellipsis")
        }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Meeting actions")
          .confirmationDialog(
            partialDelete == .audio ? "Delete this meeting's audio?" : "Delete this meeting's transcript?",
            isPresented: Binding(get: { partialDelete != nil }, set: { if !$0 { partialDelete = nil } }),
            titleVisibility: .visible
          ) {
            Button(partialDelete == .audio ? "Delete audio" : "Delete transcript", role: .destructive) {
              if partialDelete == .audio { state.deleteSelectedAudio() } else { state.deleteSelectedTranscript() }
              partialDelete = nil
            }
          } message: {
            Text(partialDelete == .audio
              ? "The recording and its voice clips are deleted for good. Your notes and transcript stay."
              : "The transcript is deleted for good. Your notes and summary stay.")
          }
      }
      HStack(spacing: 6) {
        Text(state.selectedMeeting?.created.formatted(date: .abbreviated, time: .shortened) ?? "")
        if let people = state.selectedMeeting?.participants, !people.isEmpty {
          Text("·")
          Text(people).lineLimit(1)
        }
        if let meeting = state.selectedMeeting { TagEditor(meeting: meeting).padding(.leading, 4) }
      }.font(.caption).foregroundStyle(Palette.secondary).padding(.leading, 34)
    }
  }
  private func saveTitle() {
    // An empty title reverts to the saved one.
    defer { titleEdit = nil }
    let trimmed = (titleEdit ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard let meeting = state.selectedMeeting, !trimmed.isEmpty, trimmed != meeting.title else { return }
    state.renameMeeting(trimmed, participants: meeting.participants, tags: meeting.tags)
  }
  private var notesPane: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Picker("View", selection: $tab) {
          Text("Notes").tag("Notes")
          Text("Summary").tag("Summary")
        }.pickerStyle(.segmented).labelsHidden().frame(width: 200)
        Spacer()
        if state.processingMeetingID == state.selectedMeetingID
          || (state.notesMeetingID != nil && state.notesMeetingID == state.selectedMeetingID)
        {
          ProgressView().controlSize(.small)
          Button("Cancel") { state.cancelMeetingJobs() }.controlSize(.small)
            .help("Stop this job. Nothing half-done is saved.")
        }
      }
      if tab == "Summary" {
        summaryBody
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 26) {
            MeetingActionsView(embedded: true)
            EnhancedNotesView(showTab: { name in
              if name == "Transcript" {
                revealTranscript()
              } else { tab = name }
            }, embedded: true)
            DisclosureGroup {
              ZStack(alignment: .topLeading) {
                if state.noteDraft.isEmpty {
                  Text("Type your notes here…").foregroundStyle(
                    Palette.secondary
                  ).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                }
                TextEditor(text: $state.noteDraft).font(.system(size: 15)).scrollContentBackground(.hidden)
                  .onChange(of: state.noteDraft) { _, new in state.saveNote(new) }
              }.padding(14).frame(minHeight: 160).workspaceSurface().padding(.top, 8)
              HStack {
                Text("Version \(state.note.version) · Stored locally").font(.caption)
                  .foregroundStyle(Palette.secondary)
                Spacer()
                Button("Undo last edit") { state.undoNote() }.disabled(state.lastReceipt == nil)
              }
            } label: {
              Label("Your typed notes", systemImage: "pencil.line").font(.system(size: 15, weight: .semibold))
            }
            DisclosureGroup {
              PrivateThoughtsView(embedded: true).padding(.top, 8)
            } label: {
              Label("Private thoughts", systemImage: "lock.fill").font(.system(size: 15, weight: .semibold))
                .help("Only you see these. They never go to AI.")
            }
          }.padding(.trailing, 6).padding(.bottom, 20)
        }
      }
    }
  }
  /// Speaker lanes over the recording, then the transport row. No audio, no timeline.
  @ViewBuilder private var timeline: some View {
    if state.playbackDuration == 0 && !state.playbackLoading {
      Label(state.partial.audio ? "Audio deleted" : "No audio for this meeting", systemImage: "waveform.slash").font(.caption)
        .foregroundStyle(Palette.secondary).padding(.top, 12)
    } else {
      VStack(spacing: 6) {
        SpeakerTimeline(
          segments: state.segments, duration: state.playbackDuration, position: state.playbackTime
        ) { time in
          if !state.playbackLoading { state.seekPlayback(to: time) }
          if let segment = state.segments.last(where: { $0.start <= time }) ?? state.segments.first {
            revealTranscript()
            state.selectedTranscriptSource = segment.id
          }
        }.frame(height: 22)
          RecordingWaveform(
            bins: state.waveformBins, duration: state.playbackDuration, position: state.playbackTime
          ) { time in
            // Click to jump; the slider below is the accessible equivalent.
            if !state.playbackLoading { state.seekPlayback(to: time) }  // Resumes if it was playing.
          }
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
            Button("Show audio files") {
              NSWorkspace.shared.open(
                state.root.appendingPathComponent("Recordings/\(state.selectedMeetingID ?? "")"))
            }
          }.font(.caption).padding(.top, 4)
      }.padding(12).background(Palette.paper.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
        .padding(.top, 14)
    }
  }
  private func revealTranscript() {
    transcriptCollapsed = false
    askOpen = false
    narrowSide = true
  }
  private var refineLocked: Bool {
    state.processingMeeting || state.activeMeetingID == state.selectedMeetingID
  }
  private var findMatches: [String] {
    let query = findQuery.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else { return [] }
    return state.segments.filter { $0.text.localizedCaseInsensitiveContains(query) }.map(\.id)
  }
  private func nextMatch() {
    let matches = findMatches
    guard !matches.isEmpty else { return }
    findIndex = (findIndex + 1) % matches.count
    state.selectedTranscriptSource = matches[findIndex]
  }
  private func speakerMenu(_ segment: TranscriptSegment) -> some View {
    let label = state.speakerLabel(segment.speakerID)
    return Menu(label) {
      Button("Rename \(label) everywhere…") {
        newSpeakerName = segment.speakerName ?? ""
        renaming = segment
      }
      Menu("Move this line to") {
        ForEach(state.speakerIDs.filter { $0 != segment.speakerID }, id: \.self) { id in
          Button(state.speakerLabel(id)) { state.moveSegment(segment, to: id) }
        }
        Divider()
        Button("New speaker") { state.splitSpeaker(segment) }
      }
    }.menuStyle(.borderlessButton).fixedSize().font(.system(size: 12, weight: .semibold))
      .accessibilityLabel("Speaker \(label)").accessibilityHint("Rename this speaker or move this line")
  }
  private var transcriptBody: some View {
    VStack(alignment: .leading) {
      HStack(spacing: 8) {
        Text("Transcript").font(.system(size: 17, weight: .semibold))
        Spacer()
        Menu {
          Button("Transcribe again") { state.transcribeMeeting() }.disabled(refineLocked)
          Button("Transcribe again and review changes") { state.transcribeMeeting(reprocess: true) }
            .disabled(refineLocked)
          Divider()
          Button("Check the recording") { state.inspectRecording() }.disabled(
            state.activeMeetingID == state.selectedMeetingID)
        } label: {
          Label("Refine", systemImage: "wand.and.stars")
        }.fixedSize()
      }
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
        TextField("Find in transcript", text: $findQuery).textFieldStyle(.plain)
          .focused($findFocused).onSubmit(nextMatch)
          .onChange(of: findQuery) { _, _ in
            findIndex = -1
            nextMatch()
          }
        if !findQuery.isEmpty {
          Text(findMatches.isEmpty ? "No matches" : "\(max(0, findIndex) + 1) of \(findMatches.count)")
            .font(.caption.monospacedDigit()).foregroundStyle(Palette.secondary)
          Button { nextMatch() } label: { Image(systemName: "chevron.down") }
            .buttonStyle(.plain).disabled(findMatches.isEmpty).accessibilityLabel("Next match")
        }
      }.font(.system(size: 13)).padding(8).background(Palette.paper, in: RoundedRectangle(cornerRadius: 9))
        .padding(.bottom, 6)
      if state.processingMeetingID == state.selectedMeetingID {
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
          icon: "waveform", title: "No transcript yet",
          subtitle:
            "Record the meeting. The transcript shows here when you stop."
        )
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 25) {
            ForEach(state.segments) { segment in
              HStack(alignment: .top, spacing: 18) {
                Button(WorkspaceState.time(segment.start)) { state.play(at: segment.start) }.font(
                  .caption.monospacedDigit()
                ).buttonStyle(.plain).foregroundStyle(Palette.accent).frame(width: 48)
                VStack(alignment: .leading, spacing: 8) {
                  HStack {
                    if segment.provisional {
                      Text("Live text · speaker not known yet").font(.system(size: 12, weight: .semibold))
                    } else {
                      Circle().fill(Palette.speaker(segment.speakerID)).frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                      speakerMenu(segment)
                      if segment.speakerName == nil && state.activeMeetingID != state.selectedMeetingID {
                        Button("Who is this?") {
                          newSpeakerName = ""
                          renaming = segment
                        }.buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                          .padding(.horizontal, 8).padding(.vertical, 3)
                          .background(Palette.speaker(segment.speakerID).opacity(0.14), in: Capsule())
                          .accessibilityHint("Name this speaker everywhere in the meeting")
                      }
                    }
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
                    }.buttonStyle(.plain).accessibilityLabel("Fix this line")
                  }
                  Text(segment.text).padding(5).background(
                    state.selectedTranscriptSource == segment.id
                      ? Palette.sidebar
                      : findMatches.contains(segment.id) ? Palette.accent.opacity(0.10) : .clear,
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
      Text("Record a meeting").font(.system(size: 27, weight: .semibold))
      Text(
        "Tell everyone you’re recording. The audio stays on this Mac."
      ).foregroundStyle(Palette.secondary)
      if permissionSetup {
        Text(
          "Pick the call app to record. Nothing starts until you press Start recording."
        )
        .font(.callout).foregroundStyle(Palette.secondary)
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          MicrophonePicker(devices: state.devices, showsPreview: false)
          WorkspaceCard("Meeting audio", icon: "person.wave.2") {
            Picker("Meeting audio", selection: $state.selectedPID) {
              Label("In person · microphone only", systemImage: "person.2.wave.2").tag(Int32(0))
              ForEach(state.availableApps, id: \.processIdentifier) { app in
                Label {
                  Text(app.localizedName ?? "App \(app.processIdentifier)")
                } icon: {
                  InstalledAppIcon(image: app.icon, size: 16)
                }.tag(app.processIdentifier)
              }
            }.pickerStyle(.radioGroup)
            if state.selectedPID != 0 {
              Text(
                "Chup! records all sound from this app. In a browser, that can include other tabs."
              ).font(.caption).foregroundStyle(Palette.red)
            }
            Text("Pause stops the recording. The call can still hear you.").font(.caption)
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
      Text("Fix this line").font(.system(size: 25, weight: .semibold))
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          WorkspaceCard("Transcript", icon: "text.bubble") {
            TextEditor(text: $text).font(.system(size: 16)).scrollContentBackground(.hidden).frame(
              height: 130)
          }
          WorkspaceCard("Speaker", icon: "person.crop.circle") {
            TextField("Who said this? Leave empty if you’re not sure.", text: $name)
            DisclosureGroup("Remember this voice in future meetings") {
              Text(
                "Listen first. Only this person may speak in the clip."
              ).font(.caption)
              Button("Listen to the clip") { state.play(at: segment.start) }
              Toggle(
                "Only this person speaks in the clip",
                isOn: $enrollmentConsent)
              Button("Remember this voice") {
                state.enrollVoice(segment, name: name, consent: enrollmentConsent)
              }
              .disabled(
                !enrollmentConsent || name.isEmpty || segment.provisional
                  || segment.end - segment.start < 2)
            }
            Picker("Move to another speaker", selection: $merge) {
              Text("Keep the current speaker").tag("")
              ForEach(state.speakerIDs, id: \.self) { id in Text(state.speakerLabel(id)).tag(id) }
            }
          }
        }
      }
      Divider()
      HStack {
        Button("Make this a new speaker") {
          state.splitSpeaker(segment)
          dismiss()
        }
        Spacer()
        Button("Cancel") { dismiss() }
        Button("Save correction") {
          state.correctSegment(
            segment, text: text,
            name: merge.isEmpty ? name : state.segments.first { $0.speakerID == merge && $0.speakerName != nil }?.speakerName ?? "",
            mergeID: merge.isEmpty ? nil : merge)
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

/// What will actually happen to the next meeting: cloud AI, the backend, live notes, queued notes.
struct PipelineStatus: View {
  @EnvironmentObject var state: WorkspaceState
  @State private var backend: (ok: Bool, text: String)?
  var body: some View {
    HStack(spacing: 18) {
      item(state.cloudEnabled, state.cloudEnabled ? "Cloud AI on" : "Cloud AI off · audio stays on this Mac")
      if state.cloudEnabled {
        if state.backendToken.isEmpty {
          item(false, "Not connected · Settings → Advanced")
        } else if let backend {
          item(backend.ok, backend.text)
        } else {
          item(nil, "Checking the connection…")
        }
        item(
          state.liveCaptionsEnabled && state.liveOutlineEnabled,
          state.liveCaptionsEnabled
            ? (state.liveOutlineEnabled ? "Live notes on" : "Live captions on, live notes off")
            : "Live captions off")
      }
      if !state.notesQueue.isEmpty {
        item(nil, "\(state.notesQueue.count) waiting for notes")
      }
    }.font(.caption).foregroundStyle(Palette.secondary)
      .task(id: "\(state.backendURL)|\(state.backendToken)|\(state.cloudEnabled)") {
        backend = nil
        while state.cloudEnabled, !state.backendToken.isEmpty, !Task.isCancelled {
          backend = await probe()
          try? await Task.sleep(for: .seconds(30))
        }
      }
  }
  private func item(_ ok: Bool?, _ text: String) -> some View {
    HStack(spacing: 5) {
      Circle().fill(ok == nil ? Palette.secondary : ok! ? Palette.accent : Palette.red)
        .frame(width: 6, height: 6)
      Text(text)
    }
  }
  /// The backend answers 405 to an authorised GET and 401 to a bad token, so no model call is made.
  private func probe() async -> (Bool, String) {
    // Same rule as BackendClient: the token only goes over HTTPS or to this Mac.
    guard let url = URL(string: state.backendURL),
      url.scheme == "https" || ["localhost", "127.0.0.1", "::1"].contains(url.host ?? "")
    else { return (false, "Use an https address") }
    var request = URLRequest(url: url, timeoutInterval: 5)
    request.setValue("Bearer \(state.backendToken)", forHTTPHeaderField: "Authorization")
    guard let (_, response) = try? await URLSession.shared.data(for: request),
      let code = (response as? HTTPURLResponse)?.statusCode
    else { return (false, "Backend unreachable at \(url.host() ?? state.backendURL)") }
    switch code {
    case 405: return (true, "Connected")
    case 401: return (false, "The app token is wrong")
    default: return (false, "Backend answered HTTP \(code)")
    }
  }
}

struct VoiceSample: Identifiable {
  let segment: TranscriptSegment
  let name: String
  var id: String { segment.id }
}
/// Enrollment sends this clip with future transcriptions, so the user hears it and confirms it is one voice.
struct VoiceSampleConfirmation: View {
  @EnvironmentObject var state: WorkspaceState
  @Environment(\.dismiss) var dismiss
  let sample: VoiceSample
  @State private var confirmed = false
  var body: some View {
    content.onDisappear { state.stopPlayback() }
  }
  private var content: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Remember \(sample.name)’s voice").font(.system(size: 22, weight: .semibold))
      Text("Chup! will save this clip encrypted on this Mac and send it with future transcriptions to recognise \(sample.name).")
        .foregroundStyle(Palette.secondary)
      WorkspaceCard("Clip · \(WorkspaceState.time(sample.segment.start))", icon: "waveform") {
        Text(sample.segment.text).font(.system(size: 15)).textSelection(.enabled)
        Button("Listen to clip") { state.playVoiceSample(sample.segment) }
        Text("\(sample.segment.track == .microphone ? "Microphone" : "Call audio") only · \(Int(min(sample.segment.end - sample.segment.start, 10).rounded())) s")
          .font(.caption).foregroundStyle(Palette.secondary)
      }
      Toggle("This clip contains only \(sample.name)", isOn: $confirmed)
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
        Button("Remember voice") {
          state.enrollVoice(sample.segment, name: sample.name, consent: confirmed, matching: true)
          dismiss()
        }.buttonStyle(.borderedProminent).disabled(!confirmed)
      }
    }.padding(28).frame(width: 480).background(Palette.workspace)
  }
}
