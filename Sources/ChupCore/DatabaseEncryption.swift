import CSQLite
import Darwin
import Foundation

/// SQLCipher page encryption, including the WAL and FTS. Plaintext migration never creates a
/// plaintext backup: it verifies an encrypted sibling before atomically replacing the old file.
public enum DatabaseEncryption {
  static func keyText(_ key: Data) throws -> String {
    guard key.count == 32 else {
      throw WorkspaceError.message("A 256-bit database key is required.")
    }
    return "x'" + key.map { String(format: "%02x", $0) }.joined() + "'"
  }
  static func apply(_ key: Data, to db: OpaquePointer?) throws {
    let text = try keyText(key)
    guard text.withCString({ sqlite3_key(db, $0, Int32(text.utf8.count)) }) == SQLITE_OK else {
      throw WorkspaceError.message("Could not unlock the encrypted workspace.")
    }
    _ = try sql(db, "SELECT count(*) FROM sqlite_master")
  }
  @discardableResult static func sql(_ db: OpaquePointer?, _ query: String, _ values: [String] = [])
    throws -> [[String]]
  {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
      throw WorkspaceError.message(
        "Database operation failed: " + String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_finalize(statement) }
    for (index, value) in values.enumerated() {
      sqlite3_bind_text(
        statement, Int32(index + 1), value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
    var rows: [[String]] = []
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { return rows }
      guard code == SQLITE_ROW else {
        throw WorkspaceError.message(
          "Database operation failed: " + String(cString: sqlite3_errmsg(db)))
      }
      rows.append(
        (0..<sqlite3_column_count(statement)).map {
          sqlite3_column_text(statement, $0).map { String(cString: $0) } ?? ""
        })
    }
  }
  public static func migratePlaintext(at url: URL, key: Data) throws -> Bool {
    let files = FileManager.default
    guard files.fileExists(atPath: url.path) else { return false }
    let reader = try FileHandle(forReadingFrom: url)
    let header = try reader.read(upToCount: 16)
    try reader.close()
    guard header == Data("SQLite format 3\0".utf8) else { return false }
    let sibling = url.appendingPathExtension("encrypting")
    if files.fileExists(atPath: sibling.path) { try files.removeItem(at: sibling) }
    var db: OpaquePointer?
    guard
      sqlite3_open_v2(
        url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        == SQLITE_OK
    else {
      sqlite3_close(db)
      throw WorkspaceError.message("Cannot open the previous workspace for encryption.")
    }
    do {
      let checkpoint = try sql(db, "PRAGMA wal_checkpoint(TRUNCATE)")
      guard checkpoint.first?.first != "1" else {
        throw WorkspaceError.message("Close other workspace connections before migration.")
      }
      _ = try sql(db, "PRAGMA journal_mode=DELETE")
      try sql(db, "ATTACH DATABASE ? AS encrypted KEY ?", [sibling.path, keyText(key)])
      try sql(db, "SELECT sqlcipher_export('encrypted')")
      let version = try sql(db, "PRAGMA user_version").first?.first ?? "0"
      guard Int(version) != nil else { throw WorkspaceError.corruptJournal }
      try sql(db, "PRAGMA encrypted.user_version=" + version)
      try sql(db, "DETACH DATABASE encrypted")
      sqlite3_close(db)
      db = nil
      var checked: OpaquePointer?
      guard sqlite3_open_v2(sibling.path, &checked, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
        sqlite3_close(checked)
        throw WorkspaceError.message("Encrypted migration could not be reopened.")
      }
      do {
        try apply(key, to: checked)
        guard try sql(checked, "PRAGMA integrity_check") == [["ok"]],
          try sql(checked, "PRAGMA cipher_integrity_check").isEmpty
        else {
          throw WorkspaceError.message("Encrypted migration failed integrity validation.")
        }
      } catch {
        sqlite3_close(checked)
        throw error
      }
      sqlite3_close(checked)
      let handle = try FileHandle(forWritingTo: sibling)
      try handle.synchronize()
      try handle.close()
      guard rename(sibling.path, url.path) == 0 else {
        throw WorkspaceError.message(
          "Could not replace the previous database; it remains available.")
      }
      let directory = open(url.deletingLastPathComponent().path, O_RDONLY)
      if directory >= 0 {
        _ = fsync(directory)
        close(directory)
      }
      return true
    } catch {
      sqlite3_close(db)
      try? files.removeItem(at: sibling)
      throw error
    }
  }
}
