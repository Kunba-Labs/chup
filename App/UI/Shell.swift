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

/// Chunky rail glyph: filled SF Symbols at a heavier weight than body icons.
/// macOS sidebar idiom: outline symbols at regular weight; the selected one fills.
struct RailIcon: View {
  let symbol: String
  var active = false
  var body: some View {
    Image(systemName: symbol).font(.system(size: 17, weight: .regular))
      .symbolVariant(active ? .fill : .none).accessibilityHidden(true)
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
            RailIcon(symbol: "magnifyingglass")
              .frame(width: 36, height: 32).contentShape(RoundedRectangle(cornerRadius: 0))
          }.buttonStyle(.plain).foregroundStyle(Palette.railIcon).help("Search  ⌘K")
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
              RailIcon(symbol: module.icon, active: active)
            }
          }
          .frame(width: 36, height: 32)
          // Bauhaus: blue selects, a full-strength block (membox --row-current-bg).
          .background(active ? Palette.accent : .clear,
            in: RoundedRectangle(cornerRadius: 0, style: .continuous))
          .contentShape(RoundedRectangle(cornerRadius: 0))
        }
        .buttonStyle(.plain).foregroundStyle(active ? Palette.onAccent : Palette.railIcon)
        .help("\(module.rawValue)  ⌘\(index + 1)")
        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
        .accessibilityLabel(module.rawValue)
        .accessibilityAddTraits(active ? .isSelected : [])
      }
      Button {
        state.handle(.init(action: .meeting, began: true))
      } label: {
        Image(systemName: state.meetingStatus == .recording ? "record.circle.fill" : "record.circle")
          .font(.heading).foregroundStyle(.white)
          .frame(width: 36, height: 36).background(Palette.record, in: Rectangle())
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
      PillSegmented(title: "Personal section", selection: $state.page, options: [WorkspacePage.dictionary, .snippets, .styles]) { $0.rawValue }
        .padding([.top, .horizontal], 38)
      PersonalizationView(page: state.page).id(state.page)
    }.pageScroll()
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
        }.font(.ui).padding(9)
          .background(Palette.paper, in: RoundedRectangle(cornerRadius: 0, style: .continuous))
        Button(selecting ? "Done" : "Select") {
          selecting.toggle()
          if !selecting { picked = [] }
        }.buttonStyle(.plain).font(.detail.weight(.medium)).foregroundStyle(Palette.accent)
          .help("Select several meetings to delete or tag")
      }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          ForEach(MeetingDays.group(meetings), id: \.title) { day in
            Text(day.title).bauhausLabel()
              .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 2).accessibilityAddTraits(.isHeader)
            ForEach(day.meetings) { meeting in row(meeting) }
          }
        }
      }
      // Keyboard focus for Delete, without a ring around the list: the selected row takes an
      // accent edge while the list has focus, so it's clear what Delete acts on.
      .focusable().focused($listFocused).focusEffectDisabled()
      .onKeyPress(keys: [.delete, .deleteForward]) { _ in
        deleteSelection()
        return .handled
      }
      if meetings.isEmpty {
        Text("No meetings match.").font(.detail).foregroundStyle(Palette.secondary)
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
            .foregroundStyle(isPicked ? Palette.accent : Palette.secondary).font(.reading)
        }
        let current = isPicked || (selected && !selecting)
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            MeetingSourceIcon(meeting: meeting, size: 14)
            Text(meeting.title).font(.ui.weight(.semibold)).lineLimit(1)
          }
          Text(meeting.created.formatted(date: .abbreviated, time: .shortened))
            .font(.detail).foregroundStyle(current ? Palette.onAccent.opacity(0.8) : Palette.secondary)
        }.foregroundStyle(current ? Palette.onAccent : Palette.ink)
      }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
        .padding(.horizontal, 10).contentShape(Rectangle())
        // Bauhaus: the current row is a blue block; grey while the list lacks focus.
        .background(
          isPicked || (selected && !selecting)
            ? (listFocused ? Palette.accent : Palette.paper) : .clear,
          in: RoundedRectangle(cornerRadius: 0, style: .continuous))
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
        Text(picked.isEmpty ? "Select meetings" : "\(picked.count) selected").font(.detail.weight(.semibold))
        Spacer()
        Button(picked.count == meetings.count ? "Select none" : "Select all") {
          picked = picked.count == meetings.count ? [] : Set(meetings.map(\.id))
        }.buttonStyle(.plain).font(.detail).foregroundStyle(Palette.accent)
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
    }.padding(10).background(Palette.paper, in: RoundedRectangle(cornerRadius: 0))
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
          Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide))).bauhausLabel()
          Text(greeting).font(.pageTitle)
        }
        HStack(spacing: 12) {
          Button {
            state.handle(.init(action: .meeting, began: true))
          } label: {
            Label("Record meeting", systemImage: "record.circle")
          }.buttonStyle(.pillPrimary)
          Button {
            state.toggleDictation()
          } label: {
            Label(state.dictationStatus == .listening ? "Finish dictation" : "Dictate",
              systemImage: "waveform")
          }.buttonStyle(.pill)
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
            }.font(.ui).foregroundStyle(Palette.secondary)
          }
        } else {
          section("Recent recordings") {
            if recent.isEmpty {
              Text("No recordings yet. Meetings and dictations show here.").foregroundStyle(Palette.secondary)
            }
            ForEach(recent, id: \.id) { item in
              Button {
                if item.meeting {
                  state.selectMeeting(item.id)
                  state.page = .meetings
                } else {
                  state.dictationFocusID = item.id
                  state.page = .dictation
                }
              } label: {
                HStack(spacing: 14) {
                  Image(systemName: item.meeting ? "person.2.fill" : "waveform")
                    .font(.detail.weight(.semibold)).foregroundStyle(Palette.accent)
                    .frame(width: 30, height: 30).background(Palette.sidebar, in: Circle())
                    .accessibilityLabel(item.meeting ? "Meeting" : "Dictation")
                  VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.heading).lineLimit(1)
                    Text(item.created.formatted(date: .abbreviated, time: .shortened))
                      .font(.detail).foregroundStyle(Palette.secondary)
                  }
                  Spacer()
                  if item.meeting, let job = state.job(for: item.id) {
                    MeetingJobBadge(job: job)
                  } else {
                    MiniWaveform(source: item.source)
                  }
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
                  Text(action.title).font(.ui)
                  Text(meetingTitle(action.meetingID) + (action.owner.map { " · \($0)" } ?? ""))
                    .font(.detail).foregroundStyle(Palette.secondary)
                }
                Spacer()
              }.padding(14).workspaceSurface()
            }
          }
        }
      }.padding(38).frame(maxWidth: 760, alignment: .leading)
        .frame(maxWidth: .infinity)  // Full-width scroll area: scrollbar at the window edge.
    }
      .background { SpaceBackdrop().ignoresSafeArea() }
      .onAppear(perform: load).onChange(of: state.meetings) { _, _ in load() }
      .onChange(of: state.actions) { _, _ in load() }
  }
  @ViewBuilder private func section(_ title: String, @ViewBuilder _ content: () -> some View)
    -> some View
  {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(.heading)
      content()
    }
  }
  private struct RecentItem {
    let id: String, title: String, created: Date, meeting: Bool, source: MiniWaveform.Source
  }
  /// Meetings and dictations together, newest first.
  private var recent: [RecentItem] {
    // The three latest meetings always stay; dictations fill in beside them.
    let meetings = state.meetings.prefix(3).map {
      RecentItem(id: $0.id, title: $0.title, created: $0.created, meeting: true, source: .meeting($0.id))
    }
    let dictations = state.history.filter { $0.status != "ignored" && $0.status != "cancelled" }.prefix(3).map {
      let line = $0.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
      return RecentItem(id: $0.id, title: line.isEmpty ? "Dictation · not transcribed yet" : line,
        created: $0.created, meeting: false, source: .dictation(id: $0.id, directory: $0.audioDirectory))
    }
    return (meetings + dictations).sorted { $0.created > $1.created }
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

/// The window's own backdrop behind the rail and the content panel: the voice gradient,
/// lavender at the top left warming to peach at the bottom right, with soft violet and coral
/// glows. Opaque, so nothing behind the window shows through (decided 2026-11-06).
struct ShellBackdrop: View {
  @Environment(\.colorScheme) private var scheme
  var body: some View {
    if scheme == .dark { Palette.sidebar } else { gradient }  // Bauhaus: one flat ground.
  }
  private var gradient: some View {
    ZStack {
      LinearGradient(colors: [Palette.sidebar, Palette.backdrop], startPoint: .topLeading, endPoint: .bottomTrailing)
      RadialGradient(colors: [Palette.violet.opacity(0.16), .clear], center: .topLeading, startRadius: 0, endRadius: 520)
      RadialGradient(colors: [Palette.coral.opacity(0.14), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 620)
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

/// Today's backdrop: a dark space image (generated with Higgsfield, 2026-11-06) that drifts very
/// slowly, with a few faint stars twinkling over it. Reduce Motion holds it still.
struct SpaceBackdrop: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// Fixed star field: (x, y in 0...1, size, phase), so stars don't jump between launches.
  private static let stars: [(CGFloat, CGFloat, CGFloat, Double)] = (0..<48).map { i in
    let h = UInt64(i + 1) &* 0x9E37_79B9_7F4A_7C15
    func unit(_ shift: UInt64) -> CGFloat { CGFloat((h >> shift) & 0xFFFF) / 65535 }
    return (unit(0), unit(16), 0.8 + unit(32) * 1.4, Double(unit(48)) * 6.28)
  }
  var body: some View {
    // ponytail: 15 fps timeline only while Today is on screen; the GPU cost is one image and 48 dots.
    TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion)) { context in
      let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
      GeometryReader { geometry in
        ZStack {
          Image("SpaceBackdrop").resizable().scaledToFill()
            .frame(width: geometry.size.width, height: geometry.size.height)
            // A slow drift: about one cycle a minute, a few points each way.
            .scaleEffect(1.06)
            .offset(x: 10 * sin(t / 9.5), y: 6 * cos(t / 11))
          Canvas { ctx, size in
            for (x, y, r, phase) in Self.stars {
              let glow = 0.25 + 0.35 * (1 + sin(t * 0.8 + phase)) / 2
              let dot = CGRect(x: x * size.width, y: y * size.height, width: r, height: r)
              ctx.fill(Path(ellipseIn: dot), with: .color(.white.opacity(glow)))
            }
          }
        }.clipped()
      }
    }.accessibilityHidden(true).allowsHitTesting(false)
  }
}
