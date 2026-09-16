import Foundation

public enum ShortDictationPolicy {
  /// Conservative: uncertain input and longer clips always remain available for transcription.
  public static func ignore(duration: Double, peak: Float, speechConfidence: Double?, noiseConfidence: Double?) -> Bool {
    guard duration.isFinite, peak.isFinite, duration >= 0, duration <= 2 else { return false }
    if peak <= 0.0001 { return true }
    guard let speechConfidence, let noiseConfidence,
      (0...1).contains(speechConfidence), (0...1).contains(noiseConfidence) else { return false }
    // Non-speech labels divide probability among many noise classes. Require very low
    // vocal confidence as well as a positive non-speech classification, not duration alone.
    return speechConfidence < 0.01 && noiseConfidence >= 0.4
  }
}
