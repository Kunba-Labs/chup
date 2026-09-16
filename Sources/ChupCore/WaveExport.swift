import Foundation
import Darwin

/// PCM16 mono WAV written incrementally; incomplete exports never replace a destination.
public final class WaveFileWriter {
  private let destination: URL
  private let temporary: URL
  private let writer: FileHandle
  private let expectedFrames: Int
  private var written = 0
  private var committed = false
  public init(destination: URL, frames: Int, rate: Int = 24000) throws {
    guard frames > 0, frames <= (Int(UInt32.max) - 36) / 2, (1...384000).contains(rate),
      !FileManager.default.fileExists(atPath: destination.path) else {
      throw WorkspaceError.message("Choose a new WAV destination with a supported duration.")
    }
    self.destination = destination
    expectedFrames = frames
    temporary = destination.deletingLastPathComponent().appendingPathComponent(".chup-wave-" + UUID().uuidString)
    let fd = open(temporary.path, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR)
    guard fd >= 0 else { throw POSIXError(.EIO) }
    writer = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    var header = Data("RIFF".utf8)
    func word<T: FixedWidthInteger>(_ n: T) { var v = n.littleEndian; withUnsafeBytes(of: &v) { header.append(contentsOf: $0) } }
    word(UInt32(frames * 2 + 36)); header.append(Data("WAVEfmt ".utf8))
    word(UInt32(16)); word(UInt16(1)); word(UInt16(1)); word(UInt32(rate)); word(UInt32(rate * 2))
    word(UInt16(2)); word(UInt16(16)); header.append(Data("data".utf8)); word(UInt32(frames * 2))
    try writer.write(contentsOf: header)
  }
  public func append(_ samples: [Float]) throws {
    guard !committed, samples.count <= expectedFrames - written, samples.allSatisfy(\.isFinite) else { throw WorkspaceError.corruptJournal }
    let pcm = samples.map { Int16(max(-32767, min(32767, $0 * 32767))).littleEndian }
    try writer.write(contentsOf: pcm.withUnsafeBytes { Data($0) })
    written += samples.count
  }
  public func finish() throws {
    guard !committed, written == expectedFrames else { throw WorkspaceError.message("Audio export was incomplete.") }
    try writer.synchronize(); try writer.close()
    // link is exclusive: never replace a file created by another process during export.
    guard link(temporary.path, destination.path) == 0 else { throw POSIXError(.EEXIST) }
    committed = true
    try DurableFile.syncDirectory(destination.deletingLastPathComponent())
    try FileManager.default.removeItem(at: temporary)
  }
  deinit { try? writer.close(); try? FileManager.default.removeItem(at: temporary) }
}
public struct WaveformBin: Codable, Equatable {
  public var time: Double
  public var peak: Float
  public init(time: Double, peak: Float) { self.time = time; self.peak = peak }
}
