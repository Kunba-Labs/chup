import Foundation

public struct DestinationFingerprint: Equatable {
  public var pid: Int32
  public var elementID: String
  public var selectionLocation: Int
  public var selectionLength: Int
  public var value: String
  public var focusEpoch: Int
  public var secure: Bool
  public init(
    pid: Int32, elementID: String, selectionLocation: Int, selectionLength: Int, value: String,
    focusEpoch: Int, secure: Bool
  ) {
    self.pid = pid
    self.elementID = elementID
    self.selectionLocation = selectionLocation
    self.selectionLength = selectionLength
    self.value = value
    self.focusEpoch = focusEpoch
    self.secure = secure
  }
}
public enum InsertionPolicy {
  public static func canInsert(original: DestinationFingerprint?, current: DestinationFingerprint?)
    -> Bool
  {
    guard let original, let current, !original.secure, !current.secure else { return false }
    return original == current
  }
  public static func mayRestoreClipboard(insertionChange: Int, currentChange: Int) -> Bool {
    insertionChange == currentChange
  }
}
public struct PlayedAudio: Codable, Equatable {
  public var id: String
  public var sessionID: String
  public var mode: AssistantMode
  public var generatedFrames: Int
  public var playedFrames: Int
  public var sampleRate: Int
  public var interrupted: Bool
  public init(
    id: String, sessionID: String, mode: AssistantMode, generatedFrames: Int, playedFrames: Int = 0,
    sampleRate: Int = 24000, interrupted: Bool = false
  ) {
    self.id = id
    self.sessionID = sessionID
    self.mode = mode
    self.generatedFrames = generatedFrames
    self.playedFrames = playedFrames
    self.sampleRate = sampleRate
    self.interrupted = interrupted
  }
}
/// Only the audio render callback can advance played frames. Model transcripts do not count as playback.
public struct PlaybackLedger {
  public private(set) var entries: [PlayedAudio] = []
  public init() {}
  public mutating func enqueue(_ entry: PlayedAudio) { entries.append(entry) }
  public mutating func rendered(id: String, frames: Int) {
    guard let i = entries.firstIndex(where: { $0.id == id }), frames > 0 else { return }
    entries[i].playedFrames = min(entries[i].generatedFrames, entries[i].playedFrames + frames)
  }
  public mutating func interrupt() {
    for i in entries.indices where entries[i].playedFrames < entries[i].generatedFrames {
      entries[i].interrupted = true
    }
  }
  public var broadcastSeconds: Double {
    entries.filter { $0.mode == .broadcast }.reduce(0) {
      $0 + Double($1.playedFrames) / Double($1.sampleRate)
    }
  }
}
