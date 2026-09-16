import CryptoKit
import Foundation
import Darwin

public struct AudioPacket: Codable {
  public var hostTime: Double
  public var sampleRate: Double
  public var channels: Int
  public var pcm: Data
  public init(hostTime: Double, sampleRate: Double, channels: Int = 1, pcm: Data) {
    self.hostTime = hostTime
    self.sampleRate = sampleRate
    self.channels = channels
    self.pcm = pcm
  }
  public var duration: Double { Double(pcm.count) / (sampleRate * Double(channels) * 2) }
}
/// Independently authenticated records recover up to the last complete frame after a crash.
/// Call only from the audio writer's serial queue, never a realtime callback.
public final class AudioJournal {
  public let url: URL
  private let handle: FileHandle
  private let key: SymmetricKey
  private var lastSync = Date.distantPast
  public init(url: URL, key: SymmetricKey) throws {
    self.url = url
    self.key = key
    let descriptor = open(url.path, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw WorkspaceError.message("Cannot create a new audio chunk; an existing recording will not be overwritten.") }
    handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    try handle.write(contentsOf: Data("VWJ1".utf8))
    try handle.synchronize()
    try DurableFile.syncDirectory(url.deletingLastPathComponent())
  }
  public func append(_ packet: AudioPacket) throws {
    guard packet.hostTime.isFinite, packet.sampleRate.isFinite, (1...384000).contains(packet.sampleRate),
      (1...32).contains(packet.channels), packet.pcm.count <= 5_000_000,
      packet.pcm.count % (2 * packet.channels) == 0 else { throw WorkspaceError.corruptJournal }
    let clear = try JSONEncoder().encode(packet)
    let sealed = try AES.GCM.seal(clear, using: key, authenticating: Data("VWJ1".utf8)).combined!
    var count = UInt32(sealed.count).littleEndian
    var record = withUnsafeBytes(of: &count) { Data($0) }
    record.append(sealed)
    try handle.write(contentsOf: record)
    if Date().timeIntervalSince(lastSync) >= 0.5 {
      try handle.synchronize()
      lastSync = Date()
    }
  }
  public func close() throws {
    try handle.synchronize()
    try handle.close()
  }
  public static func recover(url: URL, key: SymmetricKey) throws -> (
    packets: [AudioPacket], truncatedTail: Bool
  ) {
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
    guard size <= 128_000_000 else { throw WorkspaceError.message("Audio chunk exceeds the bounded playback size.") }
    var packets: [AudioPacket] = []
    let truncated = try scan(url: url, key: key) { packets.append($0) }
    return (packets, truncated)
  }
  /// Streaming index/recovery: memory is bounded to one authenticated record.
  @discardableResult public static func scan(url: URL, key: SymmetricKey, consume: (AudioPacket) throws -> Void) throws -> Bool {
    let reader = try FileHandle(forReadingFrom: url)
    defer { try? reader.close() }
    guard try reader.read(upToCount: 4) == Data("VWJ1".utf8) else { throw WorkspaceError.corruptJournal }
    while true {
      try Task.checkCancellation()
      let header = try reader.read(upToCount: 4) ?? Data()
      if header.isEmpty { return false }
      if header.count < 4 { return true }
      let length = header.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) }
      guard length > 28, length < 8_000_000 else { throw WorkspaceError.corruptJournal }
      let data = try reader.read(upToCount: Int(length)) ?? Data()
      if data.count < Int(length) { return true }
      let packet: AudioPacket
      do {
        let clear = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key, authenticating: Data("VWJ1".utf8))
        packet = try JSONDecoder().decode(AudioPacket.self, from: clear)
      } catch { throw WorkspaceError.corruptJournal }
      guard packet.hostTime.isFinite, packet.sampleRate.isFinite, (1...384000).contains(packet.sampleRate),
        (1...32).contains(packet.channels), packet.pcm.count % (2 * packet.channels) == 0 else { throw WorkspaceError.corruptJournal }
      try consume(packet)
    }
  }
  /// One journal is bounded to 30 seconds by AudioOwner; no whole-meeting allocation.
  public static func wave(packets: [AudioPacket]) throws -> Data {
    guard let first = packets.first else {
      throw WorkspaceError.message("No recorded audio is available.")
    }
    guard packets.allSatisfy({ $0.sampleRate == first.sampleRate && $0.channels == first.channels })
    else {
      throw WorkspaceError.message("Audio format changed; export each recording leg separately.")
    }
    guard first.sampleRate.isFinite, (1...384000).contains(first.sampleRate), (1...32).contains(first.channels),
      packets.reduce(0.0, { $0 + Double($1.pcm.count) }) <= Double(UInt32.max - 36) else { throw WorkspaceError.corruptJournal }
    let pcm = packets.reduce(into: Data()) { $0.append($1.pcm) }
    var output = Data()
    func word<T: FixedWidthInteger>(_ value: T) {
      var v = value.littleEndian
      withUnsafeBytes(of: &v) { output.append(contentsOf: $0) }
    }
    output.append(Data("RIFF".utf8))
    word(UInt32(36 + pcm.count))
    output.append(Data("WAVEfmt ".utf8))
    word(UInt32(16))
    word(UInt16(1))
    word(UInt16(first.channels))
    word(UInt32(first.sampleRate))
    word(UInt32(first.sampleRate) * UInt32(first.channels) * 2)
    word(UInt16(first.channels * 2))
    word(UInt16(16))
    output.append(Data("data".utf8))
    word(UInt32(pcm.count))
    output.append(pcm)
    return output
  }
}
