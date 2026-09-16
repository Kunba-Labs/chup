import Foundation
import Darwin

/// Publish a complete local file only after its contents are on disk.
public enum DurableFile {
  public static func syncDirectory(_ directory: URL) throws {
    let fd = open(directory.path, O_RDONLY)
    guard fd >= 0 else { throw POSIXError(.EIO) }
    defer { close(fd) }
    guard fsync(fd) == 0 else { throw POSIXError(.EIO) }
  }
  public static func write(_ data: Data, to destination: URL) throws {
    let temporary = destination.deletingLastPathComponent().appendingPathComponent(".chup-write-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let fd = open(temporary.path, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR)
    guard fd >= 0 else { throw POSIXError(.EIO) }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    do { try handle.write(contentsOf: data); try handle.synchronize(); try handle.close() }
    catch { try? handle.close(); throw error }
    guard rename(temporary.path, destination.path) == 0 else { throw POSIXError(.EIO) }
    try syncDirectory(destination.deletingLastPathComponent())
  }
}
