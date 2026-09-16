import CSQLite
import CryptoKit
import Foundation

public struct BackupKeys: Codable {
  public var database: Data
  public var audio: Data
  public init(database: Data, audio: Data) {
    self.database = database
    self.audio = audio
  }
}
public struct BackupManifest: Codable {
  public var version = 1
  public var created = Date()
  public var originalRoot: String
  public var keys: BackupKeys
  public var files: [Entry]
  public struct Entry: Codable {
    var path: String
    var chunks: [String]
    var digest: Data
  }
}
public enum WorkspaceBackup {
  private struct Envelope: Codable {
    var version = 1
    var rounds = 600_000
    var salt: Data
    var sealed: Data
  }
  private static func derive(_ password: String, salt: Data) throws -> SymmetricKey {
    guard password.count >= 12, salt.count == 16 else {
      throw WorkspaceError.message("Use a backup password of at least 12 characters.")
    }
    let password = Array(password.utf8)
    var bytes = [UInt8](repeating: 0, count: 32)
    let result = password.withUnsafeBytes { pass in
      salt.withUnsafeBytes { salt in
        CCKeyDerivationPBKDF(
          CCPBKDFAlgorithm(kCCPBKDF2), pass.baseAddress!.assumingMemoryBound(to: Int8.self),
          password.count, salt.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
          CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 600_000, &bytes, bytes.count)
      }
    }
    guard result == kCCSuccess else {
      throw WorkspaceError.message("Backup key derivation failed.")
    }
    return SymmetricKey(data: bytes)
  }
  public static func create(
    snapshot: URL, destination: URL, password: String, keys: BackupKeys, originalRoot: URL
  ) throws {
    let fm = FileManager.default
    guard !fm.fileExists(atPath: destination.path) else {
      throw WorkspaceError.message("Choose a new backup folder.")
    }
    let outputPath = destination.standardizedFileURL.resolvingSymlinksInPath().path
    for input in [snapshot, originalRoot] {
      let inputPath = input.standardizedFileURL.resolvingSymlinksInPath().path
      guard outputPath != inputPath && !outputPath.hasPrefix(inputPath + "/") else {
        throw WorkspaceError.message("Save the backup outside the active workspace and snapshot folders.")
      }
    }
    let salt = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
    let key = try derive(password, salt: salt)
    let staging = destination.deletingLastPathComponent().appendingPathComponent(
      ".chup-backup-" + UUID().uuidString)
    try fm.createDirectory(
      at: staging.appendingPathComponent("blobs"), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    defer { try? fm.removeItem(at: staging) }
    var entries: [BackupManifest.Entry] = []
    guard
      let files = fm.enumerator(
        at: snapshot,
        includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    else { throw WorkspaceError.message("Cannot enumerate backup files.") }
    for case let file as URL in files {
      let attributes = try file.resourceValues(forKeys: [
        .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
      ])
      guard attributes.isSymbolicLink != true else {
        throw WorkspaceError.message("Backups do not follow symbolic links.")
      }
      guard attributes.isRegularFile == true else { continue }
      let path = try SafeWorkspacePath.relative(file, root: snapshot)
      let input = try FileHandle(forReadingFrom: file)
      var chunks: [String] = []
      var digest = SHA256()
      do {
        while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
          digest.update(data: data)
          let blob = UUID().uuidString
          let sealed = try AES.GCM.seal(data, using: key).combined!
          try sealed.write(to: staging.appendingPathComponent("blobs/" + blob), options: .atomic)
          chunks.append(blob)
        }
        try input.close()
      } catch {
        try? input.close()
        throw error
      }
      entries.append(.init(path: path, chunks: chunks, digest: Data(digest.finalize())))
    }
    let manifest = BackupManifest(originalRoot: originalRoot.path, keys: keys, files: entries)
    let sealed = try AES.GCM.seal(JSONEncoder().encode(manifest), using: key).combined!
    try JSONEncoder().encode(Envelope(salt: salt, sealed: sealed)).write(
      to: staging.appendingPathComponent("manifest.chup"), options: .atomic)
    try fm.moveItem(at: staging, to: destination)
  }
  /// Restores only to a new destination. Existing workspaces are never overwritten.
  public static func restore(archive: URL, destination: URL, password: String) throws
    -> BackupManifest
  {
    let fm = FileManager.default
    guard !fm.fileExists(atPath: destination.path) else {
      throw WorkspaceError.message("Restore requires a new, empty destination.")
    }
    let manifestURL = try SafeWorkspacePath.resolve("manifest.chup", root: archive)
    guard (try manifestURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) < 90_000_000 else {
      throw WorkspaceError.message("Recovery manifest is too large.")
    }
    let envelope = try JSONDecoder().decode(
      Envelope.self, from: Data(contentsOf: manifestURL))
    guard envelope.version == 1, envelope.rounds == 600_000, envelope.sealed.count < 64_000_000
    else { throw WorkspaceError.message("Unsupported recovery archive.") }
    let key = try derive(password, salt: envelope.salt)
    let manifest = try JSONDecoder().decode(
      BackupManifest.self,
      from: AES.GCM.open(AES.GCM.SealedBox(combined: envelope.sealed), using: key))
    guard manifest.version == 1, manifest.keys.database.count == 32,
      manifest.keys.audio.count == 32, manifest.files.count < 200_000
    else { throw WorkspaceError.message("Invalid recovery manifest.") }
    let staging = destination.deletingLastPathComponent().appendingPathComponent(
      ".chup-restore-" + UUID().uuidString)
    try fm.createDirectory(
      at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    defer { try? fm.removeItem(at: staging) }
    var paths = Set<String>()
    for entry in manifest.files {
      guard paths.insert(entry.path).inserted, entry.chunks.count < 200_000 else {
        throw WorkspaceError.message("Duplicate or oversized backup entry.")
      }
      let output = try SafeWorkspacePath.resolve(entry.path, root: staging)
      try fm.createDirectory(
        at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
      guard
        fm.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
      else { throw WorkspaceError.message("Cannot create restored file.") }
      let writer = try FileHandle(forWritingTo: output)
      var digest = SHA256()
      do {
        for name in entry.chunks {
          guard UUID(uuidString: name) != nil else {
            throw WorkspaceError.message("Invalid backup chunk.")
          }
          let blob = try SafeWorkspacePath.resolve("blobs/" + name, root: archive)
          guard (try blob.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 1_048_676
          else { throw WorkspaceError.message("Backup chunk is too large.") }
          let data = try AES.GCM.open(
            AES.GCM.SealedBox(combined: Data(contentsOf: blob)), using: key)
          digest.update(data: data)
          try writer.write(contentsOf: data)
        }
        try writer.synchronize()
        try writer.close()
      } catch {
        try? writer.close()
        throw error
      }
      guard Data(digest.finalize()) == entry.digest else { throw WorkspaceError.corruptJournal }
    }
    guard paths.contains("workspace.sqlite") else {
      throw WorkspaceError.message("Backup has no workspace database.")
    }
    do {
      let verified = try WorkspaceStore(
        url: staging.appendingPathComponent("workspace.sqlite"), key: manifest.keys.database)
      _ = try verified.maintenanceCheck()
      try verified.checkpoint()
    }
    try fm.moveItem(at: staging, to: destination)
    return manifest
  }
}
