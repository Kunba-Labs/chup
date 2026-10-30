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
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  var body: some View {
    VStack(spacing: 6) {
      WaveMark().scaleEffect(0.62).frame(height: 34).padding(.top, 34).padding(.bottom, 14)
      ForEach(Array(RailModule.allCases.enumerated()), id: \.element) { index, module in
        if module == .settings { Spacer() }
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
    .frame(width: 60).frame(maxHeight: .infinity)
    .background {
      if reduceTransparency { Palette.sidebar } else { Rectangle().fill(.ultraThinMaterial) }
    }
    .overlay(alignment: .trailing) { Rectangle().fill(Palette.border.opacity(0.7)).frame(width: 0.5) }
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
  private var meetings: [Meeting] {
    query.isEmpty
      ? state.meetings
      : state.meetings.filter {
        "\($0.title) \($0.participants) \($0.tags)".localizedCaseInsensitiveContains(query)
      }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
        TextField("Filter meetings", text: $query).textFieldStyle(.plain)
      }.font(.system(size: 13)).padding(9)
        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 9))
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          ForEach(meetings) { meeting in
            let selected = meeting.id == state.selectedMeetingID
            Button {
              if !selected { state.selectMeeting(meeting.id) }
            } label: {
              VStack(alignment: .leading, spacing: 3) {
                Text(meeting.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(meeting.created.formatted(date: .abbreviated, time: .shortened))
                  .font(.system(size: 11)).foregroundStyle(Palette.secondary)
              }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                .padding(.horizontal, 10).contentShape(Rectangle())
                .background(selected ? Palette.paper : .clear, in: RoundedRectangle(cornerRadius: 9))
            }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
          }
        }
      }
      if meetings.isEmpty {
        Text("No meetings match.").font(.caption).foregroundStyle(Palette.secondary)
      }
    }.padding(14).frame(width: 236).background(Palette.sidebar.opacity(0.5))
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
            "Start here", subtitle: "Nothing is recorded yet. Three ways to begin:", icon: "sparkles"
          ) {
            VStack(alignment: .leading, spacing: 10) {
              Label("Record a meeting. Chup! keeps the audio and writes notes when you stop.",
                systemImage: "1.circle")
              Label("Hold your dictation shortcut anywhere and talk. The text lands where you type.",
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
              Text("Nothing open. Actions from your meetings show up here.")
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
