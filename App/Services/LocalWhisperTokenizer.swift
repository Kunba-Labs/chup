import Foundation
import WhisperKit
import ArgmaxCore
import ChupCore

/// Public protocol adapter: the upstream wrapper's initializer is internal.
/// Loads only the verified local tokenizer; word-level timestamps are disabled.
struct LocalWhisperTokenizer: WhisperTokenizer {
  let base: TokenizerWrapper
  let specialTokens: SpecialTokens
  let allLanguageTokens: Set<Int>
  init(base: TokenizerWrapper) throws {
    self.base = base
    func token(_ text: String) throws -> Int {
      guard let id = base.convertTokenToId(text) else {
        throw WorkspaceError.message("Local tokenizer is missing a required speech token.")
      }
      return id
    }
    specialTokens = try SpecialTokens(
      endToken: token("<|endoftext|>"), englishToken: token("<|en|>"),
      noSpeechToken: token("<|nospeech|>"), noTimestampsToken: token("<|notimestamps|>"),
      specialTokenBegin: token("<|endoftext|>"), startOfPreviousToken: token("<|startofprev|>"),
      startOfTranscriptToken: token("<|startoftranscript|>"), timeTokenBegin: token("<|0.00|>"),
      transcribeToken: token("<|transcribe|>"), translateToken: token("<|translate|>"), whitespaceToken: 220)
    allLanguageTokens = Set((specialTokens.englishToken..<specialTokens.translateToken).filter {
      guard let value = base.convertIdToToken($0) else { return false }
      return value.range(of: "^<\\|[a-z]{2,3}\\|>$", options: .regularExpression) != nil
    })
  }
  func encode(text: String) -> [Int] { base.encode(text: text, addSpecialTokens: false) }
  func decode(tokens: [Int]) -> String { base.decode(tokens: tokens) }
  func convertTokenToId(_ token: String) -> Int? { base.convertTokenToId(token) }
  func convertIdToToken(_ id: Int) -> String? { base.convertIdToToken(id) }
  func splitToWordTokens(tokenIds: [Int]) -> (words: [String], wordTokens: [[Int]]) {
    // Preserve the complete text/token mapping without inventing word boundaries.
    (tokenIds.isEmpty ? [] : [decode(tokens: tokenIds)], tokenIds.isEmpty ? [] : [tokenIds])
  }
}
