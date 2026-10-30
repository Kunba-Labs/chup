import ChupCore
import SwiftUI

/// ⌘K: one query across meetings (titles, notes, transcripts), dictations and Personal
/// entries. Private thoughts, assistant exchanges and trashed items never appear.
struct SearchPalette: View {
  @EnvironmentObject var state: WorkspaceState
  @State private var query = ""
  @State private var hits: [MeetingSearchHit] = []
  @State private var lines: [MeetingSearchHit] = []
  @State private var cursor = 0
  @FocusState private var focused: Bool

  struct Result: Identifiable {
    let id: String
    let group: String
    let icon: String
    let title: String
    let detail: String
    let open: () -> Void
  }

  private var results: [Result] {
    let q = query.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return [] }
    let titles = Dictionary(state.meetings.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
    // One row per meeting for titles and notes; every matching line for transcripts.
    // A meeting whose best match is a transcript line still gets that line under Transcripts.
    let lineIDs = Set(lines.compactMap(\.segmentID))
    let extraLines = hits.filter { $0.segmentID.map { !lineIDs.contains($0) } ?? false }
    let meetings = hits.filter { $0.segmentID == nil }.compactMap { hit -> Result? in
      guard let title = titles[hit.meetingID] else { return nil }
      return Result(
        id: "m/" + hit.meetingID, group: "Meetings and notes", icon: "person.2", title: title,
        detail: hit.excerpt
      ) { open(hit) }
    } + (lines + extraLines).compactMap { hit -> Result? in
      guard let title = titles[hit.meetingID], let segment = hit.segmentID else { return nil }
      return Result(
        id: "s/" + segment, group: "Transcripts", icon: "text.quote", title: title, detail: hit.excerpt
      ) { open(hit) }
    }
    let dictations = state.history.filter { $0.text.localizedCaseInsensitiveContains(q) }.prefix(8)
      .map { entry in
        Result(
          id: "d/" + entry.id, group: "Dictations", icon: "waveform",
          title: String(entry.text.prefix(70)), detail: entry.created.formatted(date: .abbreviated, time: .shortened)
        ) {
          state.listQuery = q
          state.page = .dictation
        }
      }
    let personal = state.personalization.filter {
      $0.trigger.localizedCaseInsensitiveContains(q) || $0.replacement.localizedCaseInsensitiveContains(q)
    }.prefix(8).map { item in
      Result(
        id: "p/" + item.id, group: "Personal", icon: "character.book.closed", title: item.trigger,
        detail: item.replacement
      ) {
        state.listQuery = q
        state.page = item.kind == "dictionary" ? .dictionary : item.kind == "snippet" ? .snippets : .styles
      }
    }
    // Relevance order within each group; one heading per group.
    let order = ["Meetings and notes", "Transcripts"]
    let grouped = order.flatMap { group in meetings.filter { $0.group == group } }
    return grouped + dictations + personal
  }

  var body: some View {
    let list = results
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
        TextField("Search meetings, transcripts, dictations and Personal", text: $query)
          .textFieldStyle(.plain).font(.system(size: 17)).focused($focused)
          .onSubmit { if list.indices.contains(cursor) { choose(list[cursor]) } }
          // Arrows move through results from the field itself, where focus stays.
          .onKeyPress(.downArrow) { cursor = min(cursor + 1, max(0, list.count - 1)); return .handled }
          .onKeyPress(.upArrow) { cursor = max(cursor - 1, 0); return .handled }
          .onChange(of: query) { _, new in
            cursor = 0
            hits = (try? state.store?.searchMeetings(new)) ?? []
            lines = (try? state.store?.searchTranscriptLines(new)) ?? []
          }
        Text("esc").font(.caption).foregroundStyle(Palette.secondary)
      }.padding(16)
      Divider()
      if list.isEmpty {
        Text(query.isEmpty
          ? "Type to search. Private thoughts and the Trash are never searched."
          : "Nothing matches “\(query)”. Try fewer words.")
          .font(.callout).foregroundStyle(Palette.secondary).padding(16)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
      ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          ForEach(Array(list.enumerated()), id: \.element.id) { index, result in
            if index == 0 || list[index - 1].group != result.group {
              Text(result.group.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.2)
                .foregroundStyle(Palette.secondary).padding(.horizontal, 16).padding(.top, 12)
                .accessibilityAddTraits(.isHeader)
            }
            Button { choose(result) } label: {
              HStack(alignment: .top, spacing: 12) {
                Image(systemName: result.icon).foregroundStyle(Palette.accent).frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                  Text(result.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                  Text(result.detail).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineLimit(2)
                }
                Spacer()
              }.padding(.horizontal, 16).padding(.vertical, 8).contentShape(Rectangle())
                .background(index == cursor ? Palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).padding(.horizontal, 6).id(result.id)
          }
        }.padding(.bottom, 10)
      }.frame(maxHeight: 420)
        .onChange(of: cursor) { _, index in
          if list.indices.contains(index) { proxy.scrollTo(list[index].id) }
        }
      }
      }
    }
    .frame(width: 620).background(Palette.paper, in: RoundedRectangle(cornerRadius: 16))
    .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.border, lineWidth: 0.5) }
    .shadow(color: .black.opacity(0.2), radius: 30, y: 12)
    .onAppear { focused = true }
    .onExitCommand { state.searchOpen = false }
  }

  private func choose(_ result: Result) {
    state.searchOpen = false
    result.open()
  }
  /// Opens the meeting; a transcript hit lands on its line with the audio seeked there.
  private func open(_ hit: MeetingSearchHit) {
    state.page = .meetings
    if hit.meetingID != state.selectedMeetingID { state.selectMeeting(hit.meetingID) }
    guard let id = hit.segmentID else {
      state.meetingTab = "Notes"
      return
    }
    state.selectedTranscriptSource = id
    state.meetingTab = "Transcript"
    if let segment = state.segments.first(where: { $0.id == id }) {
      if state.playbackDuration > 0 { state.seekPlayback(to: segment.start) } else {
        state.pendingSeek = (hit.meetingID, segment.start)
      }
    }
  }
}
