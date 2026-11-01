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
        .shadow(color: .black.opacity(0.07), radius: 14, y: 4)
        // The title-bar safe area already clears the traffic lights; only a hairline gap on top.
        .padding(.top, 4).padding(.bottom, 10).padding(.trailing, 10)
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
    }.animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: state.undoToast).background(ShellGlass().ignoresSafeArea()).foregroundStyle(Palette.ink).tint(Palette.accent)
      // Buttons without their own style are pills everywhere in the workspace.
      .buttonStyle(.pill)
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
  private func row(_ meeting: Meeting) -> some View {
    HStack(spacing: 12) {
      Button {
        state.selectMeeting(meeting.id)
        if let hit = searchHits.first(where: { $0.meetingID == meeting.id }), let segment = hit.segmentID {
          state.meetingTab = "Transcript"
          state.selectedTranscriptSource = segment
        }
      } label: {
        HStack(spacing: 12) {
          MeetingSourceIcon(meeting: meeting)
          VStack(alignment: .leading, spacing: 3) {
            Text(meeting.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
            HStack(spacing: 6) {
              Text(meeting.created.formatted(date: .omitted, time: .shortened))
              if let service = meeting.callService { Text("· " + service) }
              if !meeting.participants.isEmpty { Text("· " + meeting.participants).lineLimit(1) }
              ForEach(Meeting.tagList(meeting.tags).prefix(3), id: \.self) { tag in
                Text(tag).foregroundStyle(Palette.accent)
              }
            }.font(.system(size: 12)).foregroundStyle(Palette.secondary)
            if !query.isEmpty, let hit = searchHits.first(where: { $0.meetingID == meeting.id }) {
              Text(hit.excerpt).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineLimit(2)
            }
          }
          Spacer()
          if meeting.status == "Recording" {
            Label("Recording", systemImage: "record.circle.fill").font(.caption).foregroundStyle(Palette.red)
          } else if let job = state.job(for: meeting.id) {
            MeetingJobBadge(job: job)
          } else {
            MiniWaveform(source: .meeting(meeting.id), width: 60, height: 18)
          }
        }.contentShape(Rectangle())
      }.buttonStyle(.plain)
      Menu {
        Button("Open") { state.selectMeeting(meeting.id) }
        Button("Move to Trash", role: .destructive) { deletion = meeting }
          .disabled(!state.privacyWorkAllowed)
      } label: {
        Image(systemName: "ellipsis")
      }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("More options for \(meeting.title)")
    }.padding(.horizontal, 14).padding(.vertical, 10).workspaceSurface()
      .contextMenu {
        Button("Move to Trash", role: .destructive) { deletion = meeting }.disabled(!state.privacyWorkAllowed)
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
          Button { showTags = true } label: { Label("Tags", systemImage: "tag") }.buttonStyle(.pill)
          Button {
            showTrash = true
          } label: {
            Label(state.trash.isEmpty ? "Trash" : "Trash (\(state.trash.count))", systemImage: "trash")
          }.buttonStyle(.pill)
          // Creates the meeting and opens recording setup, so it says Record.
          Button {
            state.newMeeting()
            starting = true
          } label: {
            Label("Record meeting", systemImage: "record.circle")
          }.buttonStyle(.pillPrimary)
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
            icon: "person.2.wave.2", art: "VoxelMeetings", title: "No meetings yet",
            subtitle:
              "Press Record in the rail to start your first meeting."
          )
        } else {
          // Wispr-style: past notes under Today, Yesterday and date headers, one compact row each.
            LazyVStack(alignment: .leading, spacing: 4) {
              ForEach(MeetingDays.group(filtered), id: \.title) { day in
                Text(day.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.secondary)
                  .padding(.top, 14).padding(.bottom, 2).padding(.horizontal, 4)
                  .accessibilityAddTraits(.isHeader)
                ForEach(day.meetings) { meeting in row(meeting) }
              }
            }
        }
        PipelineStatus()
      }.padding(38).pageScroll().confirmDeleteMeeting($deletion)
        .sheet(isPresented: $showTrash) { TrashView().environmentObject(state) }
        .sheet(isPresented: $showTags) { TagManagerView().environmentObject(state) }
    }
  }
}
struct MeetingDetailView: View {
  @EnvironmentObject var state: WorkspaceState
  @State private var tab = "My thoughts"
  @State private var summaryEdit: SummaryItem?
  init(initialTab: String = "Notes") {
    _tab = State(initialValue: Self.tabName(initialTab))
  }
  @State private var askOpen = false
  private enum PartialDelete { case audio, transcript }
  @State private var partialDelete: PartialDelete?
  /// Narrow windows show one pane; this asks for the transcript instead of the notes.
  @State private var titleEdit: String?
  @FocusState private var titleFocused: Bool
  @State private var findQuery = ""
  @State private var replacing = false
  @State private var replaceWith = ""
  @State private var rememberSpelling = true
  @State private var findIndex = 0
  @FocusState private var findFocused: Bool
  @State private var editMetadata = false
  @State private var deletion: Meeting?
  @State private var title = ""
  @State private var people = ""
  @State private var tags = ""
  @State private var callService: String?
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
      if askOpen {
        VStack(alignment: .leading, spacing: 0) {
          header
          stickyBar
          jobCard
          AssistantView { askOpen = false }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
            .workspaceSurface().padding(.top, 14)
        }.padding([.horizontal, .top], 30).padding(.bottom, 12)
      } else {
        // One scroll area for the whole page: no boxes scrolling inside it. The title row, recording
        // bar and tabs pin to the top, so Pause, Stop, Find and Refine stay in reach.
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
              Section {
                jobCard
                activeTab.padding(.top, 14)
              } header: {
                VStack(alignment: .leading, spacing: 0) {
                  header
                  stickyBar
                }.background(Palette.workspace)
              }
            }.padding([.horizontal, .top], 30).padding(.bottom, 12)
              .frame(maxWidth: .infinity, alignment: .topLeading)
          }
          .scrollPosition($scroll)
          .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, y in
            if !restoringScroll { tabOffsets[tab] = y }
          }
          .onAppear {
            pendingSource = state.selectedTranscriptSource
            scrollToSource(proxy)
          }
          .onChange(of: state.selectedTranscriptSource) { _, id in
            pendingSource = id
            scrollToSource(proxy)
          }
          .onChange(of: tab) { _, new in
            // Each tab comes back where it was left; a pending source line wins on Transcript.
            restoringScroll = true
            DispatchQueue.main.async {
              scroll.scrollTo(y: tabOffsets[new] ?? 0)
              scrollToSource(proxy)
              DispatchQueue.main.async { restoringScroll = false }
            }
          }
          .onChange(of: summaryFindIndex) { _, index in
            let ids = summaryMatches(SummaryOutline(summary: state.summary, actions: state.actions))
            guard ids.indices.contains(index) else { return }
            // A match inside the folded notes opens them first, then scrolls once laid out.
            if ids[index].hasPrefix("note-") && !notesExpanded { notesExpanded = true }
            DispatchQueue.main.async { withAnimation { proxy.scrollTo(ids[index], anchor: .center) } }
          }
        }
      }
      askDock.padding(.horizontal, 30).padding(.bottom, 30)
    }
      .background {
        Button("Find") {
          if tab == "Summary" {
            summaryFinding = true
            summaryFindFocused = true
          } else {
            revealTranscript()
            findFocused = true
          }
        }.keyboardShortcut("f", modifiers: .command).opacity(0).accessibilityHidden(true)
      }
      .onChange(of: state.meetingTab) { _, new in
        tab = Self.tabName(new)
        askOpen = false
      }
      .onChange(of: tab) { _, new in state.meetingTab = new }
      .onChange(of: titleFocused) { _, focused in if !focused { saveTitle() } }
      .sheet(item: $summaryEdit) { item in SummaryEditView(item: item).environmentObject(state) }
      .sheet(isPresented: $captureSheet) { CaptureSetupView().environmentObject(state) }
      .sheet(isPresented: $editMetadata) {
        VStack(alignment: .leading, spacing: 18) {
          Text("Meeting details").font(.title2)
          TextField("Title", text: $title)
          TextField("People in the meeting", text: $people)
          TextField("Tags, separated by commas", text: $tags)
          Picker("Call", selection: $callService) {
            Text("The recorded app").tag(String?.none)
            ForEach(BrowserMeetingEvidence.serviceNames, id: \.self) { Text($0).tag(Optional($0)) }
          }.help("Shown on the meeting instead of the browser, when Chup! didn’t recognise the call")
          HStack {
            Button("Cancel") { editMetadata = false }
            Spacer()
            Button("Save") {
              state.renameMeeting(title, participants: people, tags: tags, callService: .some(callService))
              editMetadata = false
            }.buttonStyle(.pillPrimary)
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
  /// A transcript line asked for (source link, find, search) scrolls into view once the
  /// Transcript tab is showing.
  @State private var pendingSource: String?
  @State private var scroll = ScrollPosition()
  @State private var tabOffsets: [String: CGFloat] = [:]
  /// Set while a tab switch restores its offset, so the switch's own clamping isn't saved.
  @State private var restoringScroll = false
  private func scrollToSource(_ proxy: ScrollViewProxy) {
    guard tab == "Transcript", let id = pendingSource else { return }
    pendingSource = nil
    DispatchQueue.main.async { withAnimation { proxy.scrollTo(id, anchor: .center) } }
  }
  @ViewBuilder private var activeTab: some View {
    switch tab {
    case "Summary": summaryTab
    case "Transcript": transcriptTab
    default: thoughtsTab
    }
  }
  @ViewBuilder private var jobCard: some View {
    if let id = state.selectedMeetingID, let job = state.job(for: id) {
      MeetingJobCard(job: job, meetingID: id).padding(.top, 14)
    }
  }
  /// Recording controls and tabs: pinned while the page scrolls.
  private var stickyBar: some View {
    VStack(alignment: .leading, spacing: 0) {
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
          }.buttonStyle(.pillPrimary).disabled(state.activeMeetingID != nil)
        }
      }.font(.system(size: 12)).padding(.vertical, 8).padding(.horizontal, 14).background(
        Palette.paper, in: Capsule()
      ).padding(.top, 14).padding(.bottom, 16)
      tabBar
    }.background(Palette.workspace)
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
          .frame(minWidth: 140)
          .accessibilityLabel("Meeting title")
        Spacer(minLength: 12)
        tabActions
        Menu {
          Button("Copy as Markdown") { state.copyNotesMarkdown() }
          Button("Draft follow-up email") { state.draftFollowup() }
            .disabled(state.enhancedNotes?.blocks.isEmpty ?? true)
        } label: {
          Label("Export", systemImage: "square.and.arrow.up")
        }.menuStyle(.button).buttonStyle(.pill).fixedSize()
        Menu {
          Button("Edit details…") {
            title = state.selectedMeeting?.title ?? ""
            people = state.selectedMeeting?.participants ?? ""
            tags = state.selectedMeeting?.tags ?? ""
            callService = state.selectedMeeting?.callService
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
  /// Wispr's tabs. Old tab names from deep links and saved state map onto them.
  static func tabName(_ name: String) -> String {
    switch name {
    case "Summary": return "Summary"
    case "Transcript": return "Transcript"
    default: return "My thoughts"
    }
  }
  private func revealTranscript() {
    tab = "Transcript"
    askOpen = false
  }
  private var tabBar: some View {
    HStack(spacing: 22) {
      ForEach(["My thoughts", "Summary", "Transcript"], id: \.self) { name in
        Button {
          tab = name
          askOpen = false
        } label: {
          VStack(spacing: 8) {
            Text(name).font(.system(size: 14, weight: tab == name ? .semibold : .regular))
              .foregroundStyle(tab == name ? Palette.ink : Palette.secondary)
            Capsule().fill(tab == name ? Palette.accent : .clear).frame(height: 2)
          }.fixedSize()
        }.buttonStyle(.plain).accessibilityAddTraits(tab == name ? .isSelected : [])
      }
      Spacer()
    }.overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 1) }
  }
  /// The open tab's own actions sit in the top bar beside Export, not floating above its content.
  @ViewBuilder private var tabActions: some View {
    if tab == "Summary" {
      HStack(spacing: 8) {
        if !state.summaryVersions.isEmpty {
          Menu("Earlier versions") {
            ForEach(state.summaryVersions) { revision in
              Button(revision.created.formatted()) { state.summary = revision.summary }
            }
          }.menuStyle(.button).buttonStyle(.pill).fixedSize()
        }
        Button(state.summary == nil ? "Write summary" : "Update summary") { state.generateSummary() }
          .buttonStyle(.pill).disabled(state.segments.isEmpty || state.processingMeeting)
      }
    } else if tab == "Transcript" {
      // Narrow windows keep the title readable: a shorter find field and an icon-only Refine.
      ViewThatFits(in: .horizontal) {
        transcriptActions(findWidth: 240, labelled: true)
        transcriptActions(findWidth: 180, labelled: false)
      }
    }
  }
  private var replacePopover: some View {
    // Counted with Replace's own whole-word rule, so the number is what will change.
    let count = state.replacementLines(findQuery, with: replaceWith.isEmpty ? "\u{1}" : replaceWith).count
    return VStack(alignment: .leading, spacing: 12) {
      Text(count == 0
        ? "“\(findQuery)” isn’t a whole word in any line"
        : "Replace “\(findQuery)” in \(count) \(count == 1 ? "line" : "lines")")
        .font(.headline)
      TextField("Replace with", text: $replaceWith).textFieldStyle(.roundedBorder)
        .onSubmit(applyReplace)
      Toggle("Use this spelling in future transcripts and dictation", isOn: $rememberSpelling)
        .font(.caption)
      HStack {
        Spacer()
        Button("Cancel") { replacing = false }
        Button("Replace all", action: applyReplace).buttonStyle(.pillPrimary)
          .disabled(replaceWith.trimmingCharacters(in: .whitespaces).isEmpty || count == 0)
      }
    }.padding(16).frame(width: 340)
  }
  private func applyReplace() {
    do {
      let count = try state.replaceInTranscript(findQuery, with: replaceWith, remember: rememberSpelling)
      guard count > 0 else { return }
      state.notice = "Replaced in \(count) \(count == 1 ? "line" : "lines")."
        + (rememberSpelling ? " Saved to your dictionary." : "")
    } catch {
      state.notice = "Nothing was replaced. " + error.localizedDescription
      return
    }
    replacing = false
    findQuery = replaceWith
    replaceWith = ""
  }
  private func transcriptActions(findWidth: CGFloat, labelled: Bool) -> some View {
    HStack(spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
        TextField(labelled ? "Find in transcript" : "Find", text: $findQuery).textFieldStyle(.plain)
          .frame(minWidth: 70)
          .accessibilityLabel("Find in transcript")
          .focused($findFocused).onSubmit(nextMatch)
          .onChange(of: findQuery) { _, _ in
            findIndex = -1
            nextMatch()
          }
        if !findQuery.isEmpty {
          // The narrow field keeps its width for the query with a short status.
          Text(findMatches.isEmpty
            ? (labelled ? "No matches" : "None")
            : labelled ? "\(max(0, findIndex) + 1) of \(findMatches.count)" : "\(findMatches.count)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(findMatches.isEmpty ? Palette.red : Palette.secondary).fixedSize()
            .accessibilityLabel(findMatches.isEmpty ? "No matches" : "\(findMatches.count) matches")
          Button { nextMatch() } label: { Image(systemName: "chevron.down") }
            .buttonStyle(.plain).disabled(findMatches.isEmpty).accessibilityLabel("Next match")
          Button { replacing = true } label: { Image(systemName: "arrow.2.squarepath") }
            .buttonStyle(.plain).disabled(findMatches.isEmpty || refineLocked)
            .help("Replace in the whole transcript").accessibilityLabel("Replace")
            .popover(isPresented: $replacing, arrowEdge: .bottom) { replacePopover }
        }
      }.font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 5).frame(width: findWidth)
        .background(Palette.paper, in: Capsule())
      Menu {
        // Always a full pass: lines you edited come back for review instead of being skipped.
        Button("Transcribe again") { state.transcribeMeeting(reprocess: true) }.disabled(refineLocked)
        Divider()
        Button("Check the recording") { state.inspectRecording() }.disabled(
          state.activeMeetingID == state.selectedMeetingID)
      } label: {
        if labelled {
          Label("Refine", systemImage: "wand.and.stars")
        } else {
          Image(systemName: "wand.and.stars")
        }
      }.menuStyle(.button).buttonStyle(.pill).fixedSize().help("Refine").accessibilityLabel("Refine")
    }
  }

  // MARK: My thoughts

  private var thoughtsTab: some View {
    VStack(alignment: .leading, spacing: 10) {
      ZStack(alignment: .topLeading) {
        if state.noteDraft.isEmpty {
          Text("Type your notes here. Chup! keeps them as you wrote them.")
            .foregroundStyle(Palette.secondary).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
        }
        TextEditor(text: $state.noteDraft).font(.system(size: 16)).lineSpacing(4)
          .scrollContentBackground(.hidden)
          .onChange(of: state.noteDraft) { _, new in state.saveNote(new) }
          .accessibilityLabel("My thoughts")
      }.padding(16).frame(minHeight: 420).workspaceSurface()
      HStack {
        if state.noteSaveFailed {
          Label("Not saved. Keep typing to try again.", systemImage: "exclamationmark.triangle")
            .font(.caption).foregroundStyle(Palette.red)
        } else {
          Text("Saved on this Mac").font(.caption).foregroundStyle(Palette.secondary)
        }
        Spacer()
        Button("Undo last edit") { state.undoNote() }.disabled(state.lastReceipt == nil).controlSize(.small)
      }
      DisclosureGroup {
        PrivateThoughtsView(embedded: true).padding(.top, 6)
      } label: {
        Label("Private thoughts", systemImage: "lock.fill").font(.system(size: 13, weight: .semibold))
          .help("Only you see these. They never go to AI.")
      }
    }
  }

  // MARK: Summary

  private var summaryTab: some View {
    let outline = SummaryOutline(summary: state.summary, actions: state.actions)
    return VStack(alignment: .leading, spacing: 12) {
      if !state.liveOutlines.isEmpty, state.activeMeetingID == state.selectedMeetingID {
        LiveOutlineView(outlines: state.liveOutlines)
      }
      if summaryFinding {
        HStack(spacing: 6) {
          Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
          TextField("Find in summary", text: $summaryQuery).textFieldStyle(.plain).focused($summaryFindFocused)
            .onSubmit { nextSummaryMatch(outline) }
            .onChange(of: summaryQuery) { _, _ in summaryFindIndex = -1; nextSummaryMatch(outline) }
            .onExitCommand {
              summaryQuery = ""
              summaryFinding = false
            }
          if !summaryQuery.isEmpty {
            let count = summaryMatches(outline).count
            Text(count == 0 ? "No matches" : "\(max(0, summaryFindIndex) + 1) of \(count)")
              .font(.caption.monospacedDigit()).foregroundStyle(Palette.secondary)
            Button { nextSummaryMatch(outline) } label: { Image(systemName: "chevron.down") }
              .buttonStyle(.plain).disabled(count == 0).accessibilityLabel("Next match")
          }
          Button {
            summaryQuery = ""
            summaryFinding = false
          } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
            .foregroundStyle(Palette.secondary).accessibilityLabel("Close find")
        }.font(.system(size: 13)).padding(8).background(Palette.paper, in: RoundedRectangle(cornerRadius: 9))
      }
      if outline.isEmpty && state.summaryEdits.isEmpty, state.enhancedNotes?.blocks.isEmpty == false {
        // Notes written from the transcript when no summary was made still have a home.
        addStepField
        EnhancedNotesView(showTab: { tab = Self.tabName($0) }, embedded: true, highlight: summaryQuery).padding(4)
      } else if outline.isEmpty && state.summaryEdits.isEmpty {
        QuietEmpty(
          icon: "text.alignleft", art: "VoxelNotebook", title: "No summary yet",
          subtitle: !state.segments.isEmpty
            ? "Press Write summary to make one."
            : state.autoSummaryEnabled && state.cloudEnabled
              ? "It’s written when the meeting ends." : "After the meeting, press Write summary.")
        addStepField
      } else {
          VStack(alignment: .leading, spacing: 22) {
            if !state.summaryEdits.isEmpty {
              summarySection("Your edits") {
                ForEach(state.summaryEdits) { item in
                  bullet(item.text, sources: item.sources, edit: item, id: "edit-" + item.id)
                }
              }
            }
            if !outline.tldr.isEmpty {
              summarySection("TL;DR") {
                ForEach(outline.tldr) { item in
                  HStack(alignment: .firstTextBaseline) {
                    Text(item.text).font(.system(size: 17)).textSelection(.enabled)
                      .background(found(item.text) ? Palette.accent.opacity(0.15) : .clear)
                    sourceLinks(item.sources)
                    Spacer(minLength: 0)
                    editButton(item)
                  }.id(item.id)
                }
              }
            }
            if !outline.points.isEmpty {
              summarySection("Key points") {
                ForEach(outline.points) { item in bullet(item.text, sources: item.sources, edit: item) }
              }
            }
            if !outline.decisions.isEmpty {
              summarySection("Decisions made") {
                ForEach(outline.decisions) { item in bullet(item.text, sources: item.sources, edit: item) }
              }
            }
            summarySection("Next steps") {
              if outline.nextSteps.isEmpty {
                Text("No next steps yet.").foregroundStyle(Palette.secondary)
              }
              ForEach(outline.nextSteps, id: \.owner) { group in
                Text(group.owner).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.secondary)
                  .padding(.top, 4)
                ForEach(group.steps) { step in nextStep(step) }
              }
              addStepField.padding(.top, 4)
              if state.lastActionReceipt != nil {
                Button("Undo last change") { state.undoAction() }.controlSize(.small)
              }
            }
            if !outline.questions.isEmpty {
              summarySection("Open questions") {
                ForEach(outline.questions) { item in bullet(item.text, sources: item.sources, edit: item) }
              }
            }
            if state.enhancedNotes?.blocks.isEmpty == false {
              DisclosureGroup(isExpanded: $notesExpanded) {
                EnhancedNotesView(showTab: { tab = Self.tabName($0) }, embedded: true, highlight: summaryQuery).padding(.top, 8)
              } label: {
                Text("Notes filled in from the transcript").font(.system(size: 15, weight: .semibold))
              }
            }
          }.frame(maxWidth: .infinity, alignment: .leading).padding(22).workspaceSurface()
      }
    }
  }
  @State private var newStep = ""
  private var addStepField: some View {
    HStack {
      TextField("Add a next step…", text: $newStep).textFieldStyle(.plain).onSubmit(addStep)
        .padding(8).background(Palette.paper, in: RoundedRectangle(cornerRadius: 8))
      Button("Add", action: addStep).disabled(newStep.trimmingCharacters(in: .whitespaces).isEmpty)
    }
  }
  @State private var summaryFinding = false
  @State private var summaryQuery = ""
  @State private var summaryFindIndex = -1
  @State private var notesExpanded = false
  /// Row IDs of summary lines matching the find field, in the order they appear.
  private func summaryMatches(_ outline: SummaryOutline) -> [String] {
    var ids: [(String, String)] = state.summaryEdits.map { ("edit-" + $0.id, $0.text) }
    ids += (outline.tldr + outline.points + outline.decisions).map { ($0.id, $0.text) }
    ids += outline.nextSteps.flatMap(\.steps).map { ($0.id, $0.text) }
    ids += outline.questions.map { ($0.id, $0.text) }
    ids += (state.enhancedNotes?.blocks ?? []).map { ("note-" + $0.id, $0.text) }
    return ids.filter { found($0.1) }.map(\.0)
  }
  private func nextSummaryMatch(_ outline: SummaryOutline) {
    let count = summaryMatches(outline).count
    summaryFindIndex = count == 0 ? -1 : (summaryFindIndex + 1) % count
  }
  @FocusState private var summaryFindFocused: Bool
  /// Summary lines matching the find field get a highlight.
  private func found(_ text: String) -> Bool {
    let query = summaryQuery.trimmingCharacters(in: .whitespaces)
    return !query.isEmpty && text.localizedCaseInsensitiveContains(query)
  }
  private func addStep() {
    let text = newStep.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return }
    state.addAction(text)
    newStep = ""
  }
  private func summarySection(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.system(size: 15, weight: .semibold)).accessibilityAddTraits(.isHeader)
      content()
    }
  }
  private func bullet(_ text: String, sources: [Evidence], edit: SummaryItem?, id: String? = nil) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text("•").foregroundStyle(Palette.secondary)
      Text(text).font(.system(size: 15)).textSelection(.enabled)
        .background(found(text) ? Palette.accent.opacity(0.15) : .clear)
      sourceLinks(sources)
      Spacer(minLength: 0)
      if let edit { editButton(edit) }
    }.id(id ?? edit?.id ?? text)
  }
  private func editButton(_ item: SummaryItem) -> some View {
    Button { summaryEdit = item } label: { Image(systemName: "pencil") }
      .buttonStyle(.plain).foregroundStyle(Palette.secondary).help("Edit this line")
      .accessibilityLabel("Edit this line")
  }
  @ViewBuilder private func sourceLinks(_ sources: [Evidence]) -> some View {
    ForEach(sources.indices, id: \.self) { index in
      SourceLink(source: sources[index], number: sources.count > 1 ? index + 1 : nil)
    }
  }
  private func nextStep(_ step: SummaryOutline.Step) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Toggle("", isOn: Binding(get: { step.done }, set: { done in
        if var action = step.action {
          action.status = done ? "done" : "open"
          state.saveAction(action)
        } else if var item = step.item {
          item.status = done ? "done" : "open"
          state.createAction(from: item)
        }
      })).labelsHidden().toggleStyle(.checkbox).accessibilityLabel("Done: " + step.text)
      Text(step.text).font(.system(size: 15)).strikethrough(step.done)
        .background(found(step.text) ? Palette.accent.opacity(0.15) : .clear)
        .foregroundStyle(step.done ? Palette.secondary : Palette.ink)
      if let action = step.action {
        // Saved steps keep their owner and due date editable inline.
        // Committed on Return or when focus leaves: saving per keystroke would regroup the
        // list by owner mid-typing and drop the field.
        CommitField(placeholder: "Owner", value: action.owner ?? "", label: "Owner of " + step.text) { value in
          var copy = action
          copy.owner = value.isEmpty ? nil : value
          return state.saveAction(copy)
        }.frame(width: 90)
        CommitField(placeholder: "Due", value: action.dueDate ?? "", label: "Due date of " + step.text) { value in
          var copy = action
          copy.dueDate = value.isEmpty ? nil : value
          return state.saveAction(copy)
        }.frame(width: 80)
      } else if let due = step.dueDate {
        Text("due \(due)").font(.caption).foregroundStyle(Palette.secondary)
      }
      sourceLinks(step.sources)
      Spacer(minLength: 0)
      if let item = step.item { editButton(item) }
    }.id(step.id)
  }

  // MARK: Transcript

  private var transcriptTab: some View {
    VStack(alignment: .leading, spacing: 12) {
      timeline
      transcriptBody
    }
  }
  /// Speaker lanes over the recording, then the transport row. No audio, no timeline.
  @ViewBuilder private var timeline: some View {
    if state.playbackDuration == 0 && !state.playbackLoading {
      Label(state.partial.audio ? "Audio deleted" : "No audio for this meeting", systemImage: "waveform.slash")
        .font(.caption).foregroundStyle(Palette.secondary)
    } else {
      VStack(spacing: 6) {
        SpeakerTimeline(
          segments: state.segments, duration: state.playbackDuration, position: state.playbackTime
        ) { time in
          if !state.playbackLoading { state.seekPlayback(to: time) }
          if let segment = state.segments.last(where: { $0.start <= time }) ?? state.segments.first {
            state.selectedTranscriptSource = segment.id
          }
        }.frame(height: 18)
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
          Text(WorkspaceState.time(state.playbackDuration)).monospacedDigit().foregroundStyle(Palette.secondary)
          if state.playbackLoading { ProgressView().controlSize(.mini) }
          Button("Show audio files") {
            NSWorkspace.shared.open(state.root.appendingPathComponent("Recordings/\(state.selectedMeetingID ?? "")"))
          }
        }.font(.caption)
      }.padding(12).background(Palette.paper.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
    }
  }

  // MARK: Ask

  /// Wispr's "Ask anything": a bar at the bottom that opens the conversation above it.
  @ViewBuilder private var askDock: some View {
    if !askOpen {
      Button {
        askOpen = true
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "sparkle").foregroundStyle(Palette.accent)
          Text("Ask anything about this meeting").foregroundStyle(Palette.secondary)
          Spacer()
          if !state.assistantHistory.isEmpty {
            Text("\(state.assistantHistory.count) earlier").font(.caption).foregroundStyle(Palette.secondary)
          }
        }.font(.system(size: 14)).padding(.horizontal, 16).padding(.vertical, 12)
          .background(Palette.paper, in: Capsule())
          .overlay { Capsule().strokeBorder(Palette.border) }
          .contentShape(Capsule())
      }.buttonStyle(.plain).padding(.top, 12).accessibilityLabel("Ask anything about this meeting")
    }
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
  /// Consecutive lines from one speaker on one track, in order.
  private var transcriptGroups: [[TranscriptSegment]] {
    var groups: [[TranscriptSegment]] = []
    for segment in state.segments {
      if let last = groups.last?.last, last.speakerID == segment.speakerID, last.track == segment.track,
        last.provisional == segment.provisional
      {
        groups[groups.count - 1].append(segment)
      } else {
        groups.append([segment])
      }
    }
    return groups
  }
  private var transcriptBody: some View {
    VStack(alignment: .leading) {
      TranscriptReviewGroup(reviews: state.transcriptReviews)
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
          icon: "waveform", art: "VoxelDictation", title: "No transcript yet",
          subtitle:
            "Record the meeting. The transcript shows here when you stop."
        )
      } else {
          // One flowing document: back-to-back lines from the same speaker share one heading.
          LazyVStack(alignment: .leading, spacing: 22) {
            ForEach(transcriptGroups, id: \.first!.id) { group in
              let segment = group[0]
              HStack(alignment: .top, spacing: 18) {
                Button(WorkspaceState.time(segment.start)) { state.play(at: segment.start) }.font(
                  .caption.monospacedDigit()
                ).buttonStyle(.plain).foregroundStyle(Palette.accent).frame(width: 48).padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
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
                  }
                  ForEach(group) { line in
                    TranscriptLine(
                      text: line.text, time: WorkspaceState.time(line.start),
                      play: { state.play(at: line.start) },
                      highlight: state.selectedTranscriptSource == line.id
                        ? Palette.sidebar
                        : findMatches.contains(line.id) ? Palette.accent.opacity(0.10) : .clear
                    ) { source = line }.id(line.id)
                  }
                }
              }
            }
          }.padding(22).workspaceSurface()
      }
    }
  }
}
/// One transcript line inside a speaker's block; its edit button shows on hover and stays
/// reachable by keyboard and VoiceOver.
private struct TranscriptLine: View {
  let text: String
  let time: String
  let play: () -> Void
  let highlight: Color
  let edit: () -> Void
  @State private var hovering = false
  @FocusState private var focused: Int?
  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(text).font(.system(size: 16)).lineSpacing(5).textSelection(.enabled)
        .padding(.horizontal, 4).padding(.vertical, 1)
        .background(highlight, in: RoundedRectangle(cornerRadius: 5))
      Spacer(minLength: 0)
      // Shown on hover or keyboard focus; always reachable by keyboard and VoiceOver.
      HStack(spacing: 10) {
        Button(time, action: play).font(.caption.monospacedDigit()).foregroundStyle(Palette.accent)
          .accessibilityLabel("Play from \(time)").focused($focused, equals: 0)
        Button(action: edit) { Image(systemName: "pencil") }.foregroundStyle(Palette.secondary)
          .accessibilityLabel("Fix this line").focused($focused, equals: 1)
      }.buttonStyle(.plain).opacity(hovering || focused != nil ? 1 : 0)
    }.contentShape(Rectangle()).onHover { hovering = $0 }
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
        }.buttonStyle(.pillPrimary)
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
        }.buttonStyle(.pillPrimary)
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
        }.buttonStyle(.pillPrimary).disabled(!confirmed)
      }
    }.padding(28).frame(width: 480).background(Palette.workspace)
  }
}

/// A small text field that saves once, on Return or when focus leaves.
struct CommitField: View {
  let placeholder: String
  let value: String
  let label: String
  /// Returns whether the save worked; on failure the draft stays for another try.
  let commit: (String) -> Bool
  @State private var draft: String?
  @FocusState private var focused: Bool
  var body: some View {
    TextField(placeholder, text: Binding(get: { draft ?? value }, set: { draft = $0 }))
      .textFieldStyle(.plain).font(.caption).foregroundStyle(Palette.secondary)
      .focused($focused).accessibilityLabel(label)
      .onSubmit(save)
      .onChange(of: focused) { _, now in if !now { save() } }
  }
  private func save() {
    guard let draft else { return }
    let trimmed = draft.trimmingCharacters(in: .whitespaces)
    if trimmed == value || commit(trimmed) { self.draft = nil }
  }
}

/// What is running on one meeting: the refine pipeline (transcript, summary, notes) or a single
/// summary or notes pass. One source for the detail page's progress card and the list rows.
struct MeetingJob {
  enum Step: String { case transcript = "Transcript", summary = "Summary", notes = "Notes" }
  var step: Step
  var steps: [Step]
  /// Transcription only: share of audio parts done.
  var fraction: Double?
  var parts: (done: Int, total: Int)?
  var title: String {
    switch step {
    case .transcript: parts == nil ? "Preparing the recording" : "Transcribing the recording"
    case .summary: "Writing the summary"
    case .notes: "Writing notes"
    }
  }
  var short: String {
    switch step {
    case .transcript: fraction.map { "Transcribing " + $0.formatted(.percent.precision(.fractionLength(0))) } ?? "Preparing"
    case .summary: "Summarizing"
    case .notes: "Writing notes"
    }
  }
}
extension WorkspaceState {
  func job(for id: String?) -> MeetingJob? {
    guard let id else { return nil }
    let phase = processingMeetingID == id ? refinePhase : nil
    let steps: [MeetingJob.Step] = autoSummaryEnabled ? [.transcript, .summary, .notes] : [.transcript, .notes]
    if notesMeetingID == id { return MeetingJob(step: .notes, steps: phase == nil ? [.notes] : steps) }
    guard processingMeetingID == id else { return nil }
    // No refine phase: a summary written on its own.
    guard let phase else { return MeetingJob(step: .summary, steps: [.summary]) }
    let progress = transcriptionProgress
    if phase == .transcript, progress.total > 0 {
      return MeetingJob(
        step: .transcript, steps: steps, fraction: Double(progress.done) / Double(progress.total),
        parts: (min(progress.done + 1, progress.total), progress.total))
    }
    return MeetingJob(step: phase, steps: steps)  // .transcript here: still planning the audio.
  }
}
/// The one progress display on a meeting page: what is happening, how far, which step is next.
struct MeetingJobCard: View {
  @EnvironmentObject var state: WorkspaceState
  let job: MeetingJob
  let meetingID: String
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(job.title).font(.system(size: 14, weight: .semibold))
        if let fraction = job.fraction {
          Text(fraction.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit()
            .foregroundStyle(Palette.secondary)
        }
        Spacer()
        Button("Cancel") { state.cancelJobs(for: meetingID) }.controlSize(.small)
          .help("Stop now. Finished parts are kept, and Refine picks up where it stopped.")
      }
      Group {
        if let fraction = job.fraction { ProgressView(value: fraction) } else { ProgressView().progressViewStyle(.linear) }
      }.tint(Palette.accent).accessibilityLabel(job.title)
      HStack(spacing: 10) {
        if job.steps.count > 1 {
          let current = job.steps.firstIndex(of: job.step) ?? 0
          ForEach(Array(job.steps.enumerated()), id: \.offset) { index, step in
            Label(
              step.rawValue,
              systemImage: index < current ? "checkmark.circle.fill" : index == current ? "circle.inset.filled" : "circle"
            ).foregroundStyle(index <= current ? Palette.accent : Palette.secondary)
              .fontWeight(index == current ? .semibold : .regular)
          }
        }
        Spacer()
        if let parts = job.parts {
          Text("Part \(parts.done) of \(parts.total)").monospacedDigit()
        }
      }.font(.caption).foregroundStyle(Palette.secondary)
    }.padding(14).workspaceSurface()
  }
}
/// A list row's status: busy meetings say so instead of showing their waveform.
struct MeetingJobBadge: View {
  let job: MeetingJob
  var body: some View {
    HStack(spacing: 6) {
      ProgressView().controlSize(.mini)
      Text(job.short).monospacedDigit()
    }.font(.caption.weight(.medium)).foregroundStyle(Palette.accent)
      .padding(.horizontal, 9).padding(.vertical, 4).background(Palette.accent.opacity(0.10), in: Capsule())
      .accessibilityElement(children: .combine)
  }
}
/// The call app's icon, or the call service's logo for a browser tab (Google Meet in Safari).
struct MeetingSourceIcon: View {
  @EnvironmentObject var state: WorkspaceState
  /// Services with a Mac app show its icon when it is installed; Meet ships its own logo.
  static let desktopApps = [
    "Zoom": "us.zoom.xos", "Microsoft Teams": "com.microsoft.teams2",
    "Slack": "com.tinyspeck.slackmacgap", "Discord": "com.hnc.Discord", "Webex": "Cisco-Systems.Spark",
  ]
  let meeting: Meeting
  var size: CGFloat = 22
  var body: some View {
    if let service = meeting.callService {
      Group {
        if service == "Google Meet" {
          Image("GoogleMeet").resizable().scaledToFit().padding(size * 0.08)
        } else if let app = Self.desktopApps[service], let icon = InstalledAppIcon.icon(app) {
          Image(nsImage: icon).resizable()
        } else {
          Image(systemName: "video.fill").font(.system(size: size * 0.45)).foregroundStyle(Palette.accent)
            .background(Palette.accent.opacity(0.12), in: Circle().size(width: size, height: size))
        }
      }.frame(width: size, height: size).help(service).accessibilityLabel(service)
    } else if let app = state.meetingApps[meeting.id] {
      InstalledAppIcon(bundleID: app, size: size)
    } else if size >= 20 {
      // In person, or no call app recorded.
      Image(systemName: "person.2.fill").font(.system(size: size / 2)).foregroundStyle(Palette.secondary)
        .frame(width: size, height: size).background(Palette.sidebar, in: Circle()).accessibilityHidden(true)
    }
  }
}
