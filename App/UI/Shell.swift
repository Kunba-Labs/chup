import ChupCore
import SwiftUI

/// The modules the glass rail switches between. Personal groups the three
/// dictation-personalisation pages behind one rail entry.
enum RailModule: String, CaseIterable, Identifiable {
  case today = "Today", meetings = "Meetings", dictation = "Dictation", notebook = "Notebook",
    personal = "Personal", settings = "Settings"
  var id: String { rawValue }
  var icon: String {
    switch self {
    case .today: return "sun.max"
    case .meetings: return "person.2"
    case .dictation: return "waveform"
    case .notebook: return "book.closed"
    case .personal: return "character.book.closed"
    case .settings: return "gearshape"
    }
  }
  var page: WorkspacePage {
    switch self {
    case .today: return .today
    case .meetings: return .meetings
    case .dictation: return .dictation
    case .notebook: return .notebook
    case .personal: return .dictionary
    case .settings: return .settings
    }
  }
  static func of(_ page: WorkspacePage) -> RailModule {
    switch page {
    case .today: return .today
    case .meetings: return .meetings
    case .dictation: return .dictation
    case .notebook: return .notebook
    case .dictionary, .snippets, .styles: return .personal
    case .settings: return .settings
    }
  }
}

/// Translucent icon rail (the inbox2-style glass), solid under Reduce Transparency.
struct GlassRail: View {
  @EnvironmentObject var state: WorkspaceState
  var body: some View {
    VStack(spacing: 6) {
      WaveMark().scaleEffect(0.62).frame(height: 34).padding(.top, 34).padding(.bottom, 14)
      ForEach(Array(RailModule.allCases.enumerated()), id: \.element) { index, module in
        if module == .settings {
          Button {
            state.searchOpen = true
          } label: {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium))
              .frame(width: 40, height: 40).contentShape(RoundedRectangle(cornerRadius: 12))
          }.buttonStyle(.plain).foregroundStyle(Palette.secondary).help("Search  ⌘K")
            .accessibilityLabel("Search")
          Spacer()
        }
        let active = RailModule.of(state.page) == module
        Button {
          state.page = module.page
        } label: {
          ZStack {
            if module == .dictation && state.dictationStatus == .listening {
              VoiceWaveform(samples: state.micWaveform, width: 18, height: 18)
            } else if module == .dictation && state.dictationStatus == .processing {
              ProcessingCircle().frame(width: 18)
            } else {
              Image(systemName: module.icon).font(.system(size: 15, weight: .medium))
            }
          }
          .frame(width: 40, height: 40)
          .background(active ? Palette.paper : .clear, in: RoundedRectangle(cornerRadius: 12))
          .shadow(color: .black.opacity(active ? 0.08 : 0), radius: 4, y: 1)
          .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).foregroundStyle(active ? Palette.ink : Palette.secondary)
        .help("\(module.rawValue)  ⌘\(index + 1)")
        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
        .accessibilityLabel(module.rawValue)
        .accessibilityAddTraits(active ? .isSelected : [])
      }
      Button {
        state.handle(.init(action: .meeting, began: true))
      } label: {
        Image(systemName: state.meetingStatus == .recording ? "record.circle.fill" : "record.circle")
          .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
          .frame(width: 40, height: 40).background(Palette.gradient, in: Circle())
      }
      .buttonStyle(.plain).padding(.vertical, 14)
      .help(state.activeMeetingID == nil ? "Record a meeting" : "Show the recording meeting")
      .accessibilityLabel(state.activeMeetingID == nil ? "Record meeting" : "Show recording meeting")
    }
    // Transparent: the shell's behind-window glass shows through, so the rail and the
    // gutter around the panel read as one glass surface.
    .frame(width: 60).frame(maxHeight: .infinity)
  }
}

/// Personal: dictionary, snippets and styles behind one module.
struct PersonalModuleView: View {
  @EnvironmentObject var state: WorkspaceState
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Picker("Personal", selection: $state.page) {
        ForEach([WorkspacePage.dictionary, .snippets, .styles]) { Text($0.rawValue).tag($0) }
      }.pickerStyle(.segmented).labelsHidden().frame(width: 320).padding([.top, .horizontal], 38)
      PersonalizationView(page: state.page).id(state.page)
    }
  }
}

/// Compact meeting list beside an open meeting; ⌘\ hides it.
struct MeetingListColumn: View {
  @EnvironmentObject var state: WorkspaceState
  @State private var query = ""
  /// Select mode, ⌘-click and ⇧-click build a selection for bulk Delete and Tag.
  @State private var selecting = false
  @State private var picked: Set<String> = []
  @State private var anchor: String?
  @State private var tagging = false
  @State private var bulkTag = ""
  @FocusState private var listFocused: Bool
  private var meetings: [Meeting] {
    query.isEmpty
      ? state.meetings
      : state.meetings.filter {
        "\($0.title) \($0.participants) \($0.tags)".localizedCaseInsensitiveContains(query)
      }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        HStack(spacing: 6) {
          Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
          TextField("Filter meetings", text: $query).textFieldStyle(.plain)
            // A selection never includes meetings the filter hides.
            .onChange(of: query) { _, _ in picked.formIntersection(meetings.map(\.id)) }
        }.font(.system(size: 13)).padding(9)
          .background(Palette.paper, in: RoundedRectangle(cornerRadius: 9))
        Button(selecting ? "Done" : "Select") {
          selecting.toggle()
          if !selecting { picked = [] }
        }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent)
          .help("Select several meetings to delete or tag")
      }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          ForEach(MeetingDays.group(meetings), id: \.title) { day in
            Text(day.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.secondary)
              .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 2).accessibilityAddTraits(.isHeader)
            ForEach(day.meetings) { meeting in row(meeting) }
          }
        }
      }
      .focusable().focused($listFocused).focusEffectDisabled()
      // Our own focus ring, so it's clear when Delete acts on the list.
      .overlay {
        RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.accent.opacity(listFocused ? 0.6 : 0), lineWidth: 2)
          .allowsHitTesting(false)
      }
      .onKeyPress(keys: [.delete, .deleteForward]) { _ in
        deleteSelection()
        return .handled
      }
      if meetings.isEmpty {
        Text("No meetings match.").font(.caption).foregroundStyle(Palette.secondary)
      }
      if selecting || picked.count > 1 { bulkBar }
    }.padding(14).frame(width: 236).background(Palette.sidebar.opacity(0.5))

  }

  private func row(_ meeting: Meeting) -> some View {
    let selected = meeting.id == state.selectedMeetingID
    let isPicked = picked.contains(meeting.id)
    return Button {
      click(meeting)
    } label: {
      HStack(spacing: 8) {
        if selecting {
          Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(isPicked ? Palette.accent : Palette.secondary).font(.system(size: 15))
        }
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            if let app = state.meetingApps[meeting.id] { InstalledAppIcon(bundleID: app, size: 14) }
            Text(meeting.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
          }
          Text(meeting.created.formatted(date: .abbreviated, time: .shortened))
            .font(.system(size: 11)).foregroundStyle(Palette.secondary)
        }
      }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
        .padding(.horizontal, 10).contentShape(Rectangle())
        .background(
          isPicked ? Palette.accent.opacity(0.14) : selected && !selecting ? Palette.paper : .clear,
          in: RoundedRectangle(cornerRadius: 9))
    }.buttonStyle(.plain)
      .accessibilityAddTraits((selecting ? isPicked : selected || isPicked) ? .isSelected : [])
      .accessibilityHint(selecting ? "Selects this meeting" : "Opens this meeting")
      .contextMenu {
        Button("Select") {
          selecting = true
          picked.insert(meeting.id)
        }
        Button("Move to Trash", role: .destructive) { state.trashMeetings([meeting]) }
          .disabled(!state.privacyWorkAllowed)
      }
  }

  private var bulkBar: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(picked.isEmpty ? "Select meetings" : "\(picked.count) selected").font(.caption.weight(.semibold))
        Spacer()
        Button(picked.count == meetings.count ? "Select none" : "Select all") {
          picked = picked.count == meetings.count ? [] : Set(meetings.map(\.id))
        }.buttonStyle(.plain).font(.caption).foregroundStyle(Palette.accent)
      }
      HStack(spacing: 8) {
        Button("Tag…") { tagging = true }.controlSize(.small).disabled(picked.isEmpty)
          .popover(isPresented: $tagging) {
            TextField("Tag", text: $bulkTag).textFieldStyle(.roundedBorder).frame(width: 180)
              .padding(12).onSubmit {
                let tag = bulkTag.trimmingCharacters(in: .whitespaces)
                if !tag.isEmpty { state.addTag(tag, to: chosen) }
                bulkTag = ""
                tagging = false
              }
          }
        Spacer()
        Button("Delete", role: .destructive) { deleteSelection() }
          .controlSize(.small).disabled(picked.isEmpty || !state.privacyWorkAllowed)
      }
    }.padding(10).background(Palette.paper, in: RoundedRectangle(cornerRadius: 10))
  }
}

extension MeetingListColumn {
  private var chosen: [Meeting] { state.meetings.filter { picked.contains($0.id) } }
  /// Delete key (list focused) and the bar: the selection if there is one, otherwise the open
  /// meeting. A window-wide ⌘⌫ would also fire while typing notes, so there isn't one.
  /// Everything goes to the Trash with an Undo toast.
  private func deleteSelection() {
    // In Select mode only ticked meetings are deleted; otherwise an empty selection means the
    // open meeting.
    // Only meetings the filter shows can be deleted from here.
    let targets = picked.isEmpty && !selecting
      ? meetings.filter { $0.id == state.selectedMeetingID } : chosen
    guard !targets.isEmpty else { return }
    state.trashMeetings(targets)
    picked = []
    selecting = false
  }
  private func click(_ meeting: Meeting) {
    listFocused = true
    let flags = NSEvent.modifierFlags
    if flags.contains(.shift), let anchor,
      let from = meetings.firstIndex(where: { $0.id == anchor }),
      let to = meetings.firstIndex(where: { $0.id == meeting.id })
    {
      picked = Set(meetings[min(from, to)...max(from, to)].map(\.id))
    } else if selecting || flags.contains(.command) {
      // ⌘-click starts the selection with the open meeting, so it adds a second one.
      if picked.isEmpty, !selecting, let open = state.selectedMeetingID,
        meetings.contains(where: { $0.id == open })
      { picked.insert(open) }
      if picked.contains(meeting.id) { picked.remove(meeting.id) } else { picked.insert(meeting.id) }
      anchor = meeting.id
    } else {
      picked = []
      anchor = meeting.id
      if meeting.id != state.selectedMeetingID { state.selectMeeting(meeting.id) }
    }
  }
}

struct TodayView: View {
  @EnvironmentObject var state: WorkspaceState
  @State private var open: [ActionRecord] = []
  private var greeting: String {
    switch Calendar.current.component(.hour, from: Date()) {
    case 5..<12: return "Good morning"
    case 12..<18: return "Good afternoon"
    default: return "Good evening"
    }
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        VStack(alignment: .leading, spacing: 8) {
          Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
            .font(.system(size: 11, weight: .semibold)).tracking(1.6).foregroundStyle(Palette.accent)
          Text(greeting).font(.system(size: 34, weight: .semibold))
        }
        HStack(spacing: 12) {
          Button {
            state.handle(.init(action: .meeting, began: true))
          } label: {
            Label("Record meeting", systemImage: "record.circle").padding(.horizontal, 6)
          }.buttonStyle(.borderedProminent).controlSize(.large)
          Button {
            state.toggleDictation()
          } label: {
            Label(state.dictationStatus == .listening ? "Finish dictation" : "Dictate",
              systemImage: "waveform").padding(.horizontal, 6)
          }.buttonStyle(.bordered).controlSize(.large)
        }
        if state.meetings.isEmpty && state.history.isEmpty {
          WorkspaceCard(
            "Start here", subtitle: "Three ways to start:", icon: "sparkles"
          ) {
            VStack(alignment: .leading, spacing: 10) {
              Label("Record a meeting. You get notes when you stop.",
                systemImage: "1.circle")
              Label("Hold your shortcut and talk. Your words go where you type.",
                systemImage: "2.circle")
              Label("Add names and terms under Personal so transcripts spell them right.",
                systemImage: "3.circle")
            }.font(.system(size: 14)).foregroundStyle(Palette.secondary)
          }
        } else {
          section("Recent meetings") {
            if state.meetings.isEmpty {
              Text("No meetings yet.").foregroundStyle(Palette.secondary)
            }
            ForEach(state.meetings.prefix(3)) { meeting in
              Button {
                state.selectMeeting(meeting.id)
                state.page = .meetings
              } label: {
                HStack {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title).font(.system(size: 15, weight: .semibold))
                    Text(meeting.created.formatted(date: .abbreviated, time: .shortened))
                      .font(.caption).foregroundStyle(Palette.secondary)
                  }
                  Spacer()
                  Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.secondary)
                }.padding(16).contentShape(Rectangle()).workspaceSurface()
              }.buttonStyle(.plain)
            }
          }
          section("Open action items") {
            if open.isEmpty {
              Text("No open actions. New ones from your meetings show here.")
                .foregroundStyle(Palette.secondary)
            }
            ForEach(open) { action in
              HStack(spacing: 12) {
                Toggle("", isOn: Binding(get: { false }, set: { _ in complete(action) }))
                  .labelsHidden().accessibilityLabel("Complete " + action.title)
                VStack(alignment: .leading, spacing: 3) {
                  Text(action.title).font(.system(size: 14))
                  Text(meetingTitle(action.meetingID) + (action.owner.map { " · \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(Palette.secondary)
                }
                Spacer()
              }.padding(14).workspaceSurface()
            }
          }
        }
      }.padding(38).frame(maxWidth: 760, alignment: .leading)
    }.onAppear(perform: load).onChange(of: state.meetings) { _, _ in load() }
      .onChange(of: state.actions) { _, _ in load() }
  }
  @ViewBuilder private func section(_ title: String, @ViewBuilder _ content: () -> some View)
    -> some View
  {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(.system(size: 18, weight: .semibold))
      content()
    }
  }
  private func meetingTitle(_ id: String) -> String {
    state.meetings.first { $0.id == id }?.title ?? "Meeting"
  }
  private func load() {
    let live = Set(state.meetings.map(\.id))
    open = ((try? state.store?.list(ActionRecord.self, kind: "action")) ?? [])
      .filter { $0.status == "open" && live.contains($0.meetingID) }
  }
  private func complete(_ action: ActionRecord) {
    var done = action
    done.status = "done"
    do {
      _ = try state.store?.writeAction(
        done, expectedVersion: action.version, requestID: UUID().uuidString)
      if action.meetingID == state.selectedMeetingID { try state.refreshDetail() }
    } catch { state.notice = error.localizedDescription }
    load()
  }
}

/// The window's own material (set on the scene with containerBackground) shows through here;
/// this adds inbox2's sheen and a light lavender tint. Reduce Transparency gets a solid fill.
struct ShellGlass: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  var body: some View {
    if reduceTransparency {
      Palette.sidebar
    } else {
      ZStack {
        LinearGradient(
          stops: [.init(color: .white.opacity(0.22), location: 0), .init(color: .white.opacity(0.05), location: 0.35),
                  .init(color: .clear, location: 0.6)],
          startPoint: .top, endPoint: .bottom)
        Palette.sidebar.opacity(0.12)
      }
    }
  }
}

/// Meetings grouped by calendar day, newest first, titled Today, Yesterday or the date.
enum MeetingDays {
  static func group(_ meetings: [Meeting], now: Date = Date()) -> [(title: String, meetings: [Meeting])] {
    let calendar = Calendar.current
    var order: [Date] = []
    var days: [Date: [Meeting]] = [:]
    for meeting in meetings.sorted(by: { $0.created > $1.created }) {
      let day = calendar.startOfDay(for: meeting.created)
      if days[day] == nil { order.append(day) }
      days[day, default: []].append(meeting)
    }
    return order.map { day in
      let title =
        calendar.isDate(day, inSameDayAs: now) ? "Today"
        : calendar.isDate(day, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: now) ?? now) ? "Yesterday"
        : day.formatted(.dateTime.weekday(.wide).day().month(.wide)
            .year(calendar.isDate(day, equalTo: now, toGranularity: .year) ? .omitted : .defaultDigits))
      return (title, days[day]!)
    }
  }
}
