import Foundation

public enum DictationPersonalization {
  /// "auto" transcription keeps every language's entries: the spoken language is not known
  /// until the transcript exists, and a Dutch product name is still a product name in English.
  public static func applies(_ entry: Personalization, language: String) -> Bool {
    language == "auto" || entry.language == language
  }
  /// Vocabulary hints for the transcription provider: acronyms, product names, people.
  public static func vocabulary(_ entries: [Personalization], language: String) -> [String] {
    entries.filter { $0.kind == "dictionary" && applies($0, language: language) }.map(\.replacement)
  }
  public static func snippet(_ text: String, entries: [Personalization], language: String)
    -> String?
  {
    let phrase = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    return entries.first {
      $0.kind == "snippet" && applies($0, language: language)
        && $0.trigger.compare(phrase, options: [.caseInsensitive, .diacriticInsensitive])
          == .orderedSame
    }?.replacement
  }
  public static func spellings(_ text: String, entries: [Personalization], language: String)
    -> String
  {
    var edits: [(NSRange, String)] = []
    for entry in entries.filter({
      $0.kind == "dictionary" && applies($0, language: language) && !$0.trigger.isEmpty
    })
    .sorted(by: { $0.trigger.count > $1.trigger.count }) {
      let pattern =
        "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: entry.trigger)
        + "(?![\\p{L}\\p{N}])"
      guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
        continue
      }
      for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
        guard !edits.contains(where: { NSIntersectionRange($0.0, match.range).length > 0 }) else {
          continue
        }
        edits.append((match.range, entry.replacement))
      }
    }
    let result = NSMutableString(string: text)
    for (range, replacement) in edits.sorted(by: { $0.0.location > $1.0.location }) {
      result.replaceCharacters(in: range, with: replacement)
    }
    return result as String
  }
}
