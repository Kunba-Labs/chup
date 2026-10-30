import Foundation

/// The summary laid out the way Wispr Flow's Flow Summaries read: a TL;DR, key points,
/// Decisions Made and Next Steps grouped by owner. Saved action items win over the summary's
/// own action lines, so ticking one off shows everywhere.
public struct SummaryOutline: Equatable {
  /// One next step: a saved action item, or a summary action line not saved yet.
  public struct Step: Identifiable, Equatable {
    public var id: String
    public var text: String
    public var done: Bool
    public var dueDate: String?
    public var sources: [Evidence]
    public var action: ActionRecord?
    public var item: SummaryItem?
    public var owner: String?
  }
  public var tldr: [SummaryItem] = []
  public var points: [SummaryItem] = []
  public var decisions: [SummaryItem] = []
  public var questions: [SummaryItem] = []
  public var nextSteps: [(owner: String, steps: [Step])] = []

  public init(summary: MeetingSummary?, actions: [ActionRecord]) {
    let items = summary?.items ?? []
    tldr = items.filter { $0.category == "overview" }
    points = items.filter { $0.category == "topic" }
    decisions = items.filter { $0.category == "decision" }
    questions = items.filter { $0.category == "question" || $0.category == "risk" }
    let saved = actions.filter { $0.status != "archived" }
    var steps = saved.map {
      Step(id: $0.id, text: $0.title, done: $0.status == "done", dueDate: $0.dueDate, sources: $0.sources,
        action: $0, item: nil, owner: $0.owner)
    }
    let savedTitles = Set(saved.map { $0.title.lowercased() })
    for item in items where item.category == "action" && !savedTitles.contains(item.text.lowercased()) {
      steps.append(
        Step(id: item.id, text: item.text, done: item.status == "done", dueDate: item.dueDate,
          sources: item.sources, action: nil, item: item, owner: item.owner))
    }
    var order: [String] = []
    var groups: [String: [Step]] = [:]
    for step in steps {
      let owner = step.owner?.trimmingCharacters(in: .whitespaces).isEmpty == false ? step.owner! : "No owner"
      if groups[owner] == nil { order.append(owner) }
      groups[owner, default: []].append(step)
    }
    // Named owners first in order of appearance; unassigned steps last.
    order.sort { ($0 == "No owner" ? 1 : 0) < ($1 == "No owner" ? 1 : 0) }
    nextSteps = order.map { ($0, groups[$0]!) }
  }

  public var isEmpty: Bool {
    tldr.isEmpty && points.isEmpty && decisions.isEmpty && questions.isEmpty && nextSteps.isEmpty
  }

  public static func == (a: SummaryOutline, b: SummaryOutline) -> Bool {
    a.tldr == b.tldr && a.points == b.points && a.decisions == b.decisions && a.questions == b.questions
      && a.nextSteps.map(\.owner) == b.nextSteps.map(\.owner)
      && a.nextSteps.map(\.steps) == b.nextSteps.map(\.steps)
  }

  /// Markdown for Copy and Export: title, the user's own notes, then the summary.
  public func markdown(title: String, thoughts: String) -> String {
    var out = ["# " + title]
    let mine = thoughts.trimmingCharacters(in: .whitespacesAndNewlines)
    if !mine.isEmpty { out += ["", "## My thoughts", mine] }
    func section(_ name: String, _ lines: [String]) {
      if !lines.isEmpty { out += ["", "## " + name] + lines }
    }
    section("TL;DR", tldr.map(\.text))
    section("Key points", points.map { "- " + $0.text })
    section("Decisions made", decisions.map { "- " + $0.text })
    if !nextSteps.isEmpty {
      out += ["", "## Next steps"]
      for group in nextSteps {
        out.append("**\(group.owner)**")
        out += group.steps.map { "- [\($0.done ? "x" : " ")] " + $0.text + ($0.dueDate.map { " (due \($0))" } ?? "") }
      }
    }
    section("Open questions", questions.map { "- " + $0.text })
    return out.joined(separator: "\n") + "\n"
  }
}
