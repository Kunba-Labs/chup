import CryptoKit
import XCTest

@testable import ChupCore

final class PrivacyStorageTests: XCTestCase {
  func directory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "Chup-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
  func testEncryptedDatabaseAndWALHideNotesAndSearchAndRejectWrongKey() throws {
    let root = try directory()
    let url = root.appendingPathComponent("workspace.sqlite")
    let key = Data(repeating: 42, count: 32)
    var store: WorkspaceStore? = try WorkspaceStore(url: url, key: key)
    try store!.writeNote(
      meetingID: "m", text: "Sensitive capybara negation", expectedVersion: 0, requestID: "r")
    XCTAssertTrue(store!.encrypted)
    XCTAssertEqual(try store!.search("capybara", kind: "note"), ["m"])
    for file in try FileManager.default.contentsOfDirectory(
      at: root, includingPropertiesForKeys: nil) where !file.path.hasSuffix("lock")
    {
      XCTAssertNil(try Data(contentsOf: file).range(of: Data("capybara".utf8)))
    }
    store = nil
    let bytes = try Data(contentsOf: url)
    XCTAssertThrowsError(try WorkspaceStore(url: url, key: Data(repeating: 43, count: 32)))
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    let reopened = try WorkspaceStore(url: url, key: key)
    XCTAssertEqual(try reopened.note("m").text, "Sensitive capybara negation")
    XCTAssertEqual(
      try reopened.writeNote(
        meetingID: "m", text: "Sensitive capybara negation", expectedVersion: 0, requestID: "r"
      ).after.version, 1)
  }
  func testPlaintextMigrationPreservesWALContentFTSAndReceiptsAndReplacesOrphanStage() throws {
    let root = try directory()
    let url = root.appendingPathComponent("workspace.sqlite")
    let original = root.appendingPathComponent("original.sqlite")
    let plain = try WorkspaceStore(url: original)
    try plain.writeNote(
      meetingID: "m", text: "Do not ship Friday", expectedVersion: 0, requestID: "r")
    // Snapshot an idle connection while its committed note still lives in WAL.
    try FileManager.default.copyItem(at: original, to: url)
    try FileManager.default.copyItem(at: URL(fileURLWithPath: original.path + "-wal"),
      to: URL(fileURLWithPath: url.path + "-wal"))
    withExtendedLifetime(plain) {}
    try Data("interrupted staging data".utf8).write(to: url.appendingPathExtension("encrypting"))
    let encrypted = try WorkspaceStore(url: url, key: Data(repeating: 4, count: 32))
    XCTAssertTrue(encrypted.migratedPlaintext)
    XCTAssertEqual(try encrypted.note("m").text, "Do not ship Friday")
    XCTAssertEqual(try encrypted.search("Friday", kind: "note"), ["m"])
    XCTAssertEqual(try encrypted.receipt(requestID: "r")?.after.version, 1)
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: url.appendingPathExtension("encrypting").path))
    XCTAssertTrue(try encrypted.maintenanceCheck().contains("passed"))
  }
  func testFailedMigrationLeavesOriginalReadable() throws {
    let root = try directory()
    let url = root.appendingPathComponent("workspace.sqlite")
    do {
      let store = try WorkspaceStore(url: url)
      try store.writeNote(meetingID: "m", text: "Keep me", expectedVersion: 0, requestID: "r")
    }
    XCTAssertThrowsError(try WorkspaceStore(url: url, key: Data([1])))
    XCTAssertEqual(try WorkspaceStore(url: url).note("m").text, "Keep me")
  }
  func testDeletionResumesAndCascadesPrivateDataRejectingLateWrites() throws {
    let root = try directory()
    let store = try WorkspaceStore(url: root.appendingPathComponent("workspace.sqlite"))
    let audio = root.appendingPathComponent("Recordings/m/leg")
    try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
    try Data([1, 2, 3]).write(to: audio.appendingPathComponent("audio.vwj"))
    try store.put(Meeting(id: "m", title: "Delete me"), kind: "meeting", id: "m")
    try store.put(
      RecordingLeg(meetingID: "m", directory: audio.path, offset: 0), kind: "leg", id: "leg",
      parent: "m")
    try store.writeNote(meetingID: "m", text: "Meeting note", expectedVersion: 0, requestID: "a")
    try store.writeNote(
      meetingID: "private-thoughts/m", text: "Private thought", expectedVersion: 0, requestID: "p")
    let request = DurableRequest(scope: "m", route: "ask", body: Data("private request".utf8))
    try store.saveRequest(request)
    let plan = try store.planMeetingDeletion("m", root: root)
    XCTAssertThrowsError(
      try store.writeNote(
        meetingID: "m", text: "Late callback", expectedVersion: 1, requestID: "late"))
    try store.finishDeletion(plan, root: root)
    try store.finishDeletion(plan, root: root)
    XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
    XCTAssertEqual(try store.note("m"), Note())
    XCTAssertEqual(try store.note("private-thoughts/m"), Note())
    XCTAssertNil(try store.receipt(requestID: "p"))
    XCTAssertTrue(try store.list(DurableRequest.self, kind: "request").isEmpty)
    XCTAssertEqual(try store.pendingBackendDeletions().first?.requests, [request.id])
    XCTAssertThrowsError(
      try store.put(Meeting(id: "m", title: "Resurrected"), kind: "meeting", id: "m"))
  }
  func testDeletingOriginMeetingPurgesEnrolledReferenceRequestsAcrossMeetings() throws {
    let root = try directory()
    let store = try WorkspaceStore(url: root.appendingPathComponent("w.sqlite"))
    let file = root.appendingPathComponent("voice-reference")
    try Data([1]).write(to: file)
    let profile = VoiceEnrollment(id: "enrolled", name: "Person", meetingID: "origin", segmentID: "s", duration: 5, referencePath: file.path)
    try store.put(profile, kind: "enrollment", id: profile.id)
    let crossMeeting = DurableRequest(scope: "other", route: "transcribe", body: Data(#"{"references":[{"name":"voice_enrolled","url":"data:audio/wav;base64,AA=="}]}"#.utf8))
    let unrelated = DurableRequest(scope: "other", route: "summary", body: Data("[]".utf8))
    try store.saveRequest(crossMeeting)
    try store.saveRequest(unrelated)
    let plan = try store.planMeetingDeletion("origin", root: root)
    XCTAssertEqual(plan.requestIDs, [crossMeeting.id])
    try store.finishDeletion(plan, root: root)
    XCTAssertNil(try store.request(id: crossMeeting.id))
    XCTAssertNotNil(try store.request(id: unrelated.id))
    XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    XCTAssertThrowsError(try store.saveSegments([], meetingID: "origin", revisionID: "late"))
  }
  func testReadableExportExcludesPrivateMaterialByDefault() throws {
    let root = try directory()
    let store = try WorkspaceStore(url: root.appendingPathComponent("w.sqlite"))
    try store.put(Meeting(id: "m", title: "Meeting"), kind: "meeting", id: "m")
    try store.writeNote(
      meetingID: "private-thoughts/m", text: "PRIVATESECRET", expectedVersion: 0, requestID: "p")
    XCTAssertFalse(
      String(decoding: try store.exportMeeting("m"), as: UTF8.self).contains("PRIVATESECRET"))
    XCTAssertTrue(
      String(decoding: try store.exportMeeting("m", includePrivate: true), as: UTF8.self).contains(
        "PRIVATESECRET"))
  }
  func testRecoveryArchiveRoundTripRejectsWrongPasswordTamperingAndExistingDestination() throws {
    let root = try directory()
    let snapshot = root.appendingPathComponent("snapshot")
    let archive = root.appendingPathComponent("backup")
    try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
    let keys = BackupKeys(
      database: Data(repeating: 8, count: 32), audio: Data(repeating: 9, count: 32))
    do {
      let store = try WorkspaceStore(
        url: snapshot.appendingPathComponent("workspace.sqlite"), key: keys.database)
      try store.writeNote(meetingID: "m", text: "Backup secret", expectedVersion: 0, requestID: "r")
      try store.checkpoint()
    }
    let largeFixture = Data(repeating: 73, count: 2_200_001)
    try largeFixture.write(to: snapshot.appendingPathComponent("fixture.vwj"))
    XCTAssertThrowsError(try WorkspaceBackup.create(
      snapshot: snapshot, destination: snapshot.appendingPathComponent("nested-backup"),
      password: "a long backup password", keys: keys, originalRoot: snapshot))
    try WorkspaceBackup.create(
      snapshot: snapshot, destination: archive, password: "a long backup password", keys: keys,
      originalRoot: snapshot)
    XCTAssertThrowsError(
      try WorkspaceBackup.restore(
        archive: archive, destination: root.appendingPathComponent("wrong"),
        password: "wrong long password"))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: root.appendingPathComponent("wrong").path))
    let destination = root.appendingPathComponent("restored")
    let manifest = try WorkspaceBackup.restore(
      archive: archive, destination: destination, password: "a long backup password")
    XCTAssertEqual(manifest.keys.audio, keys.audio)
    XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("fixture.vwj")), largeFixture)
    XCTAssertEqual(
      try WorkspaceStore(
        url: destination.appendingPathComponent("workspace.sqlite"), key: keys.database
      ).note("m").text, "Backup secret")
    XCTAssertThrowsError(
      try WorkspaceBackup.restore(
        archive: archive, destination: destination, password: "a long backup password"))
    let blob = try XCTUnwrap(
      FileManager.default.contentsOfDirectory(
        at: archive.appendingPathComponent("blobs"), includingPropertiesForKeys: nil
      ).first)
    var bytes = try Data(contentsOf: blob)
    bytes[bytes.count - 1] ^= 1
    try bytes.write(to: blob)
    XCTAssertThrowsError(
      try WorkspaceBackup.restore(
        archive: archive, destination: root.appendingPathComponent("tampered"),
        password: "a long backup password"))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: root.appendingPathComponent("tampered").path))
  }
  func testPathsCannotTraverseOrFollowLinksOutsideWorkspace() throws {
    let root = try directory()
    let outside = try directory()
    XCTAssertThrowsError(try SafeWorkspacePath.resolve("../outside", root: root))
    XCTAssertThrowsError(try SafeWorkspacePath.resolve("/absolute", root: root))
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("link"), withDestinationURL: outside)
    XCTAssertThrowsError(try SafeWorkspacePath.resolve("link/file", root: root))
  }
  func testDurableRequestRecoveryAndUsageSnapshotsAreIdempotent() throws {
    let root = try directory()
    let store = try WorkspaceStore(url: root.appendingPathComponent("w.sqlite"))
    var job = DurableRequest(scope: "m", route: "summary", body: Data("[]".utf8))
    job.status = "running"
    try store.saveRequest(job)
    var changed = job
    changed.body = Data("different payload".utf8)
    XCTAssertThrowsError(try store.saveRequest(changed))
    changed = job
    changed.scope = "other"
    XCTAssertThrowsError(try store.saveRequest(changed))
    try store.recoverRequests()
    XCTAssertEqual(
      try store.list(DurableRequest.self, kind: "request").first?.status, "interrupted")
    let partial = ProviderUsage(
      id: "voice", category: "voice", model: "gpt-live-1", seconds: 5, confirmed: false, raw: "{}")
    let final = ProviderUsage(
      id: "voice", category: "voice", model: "gpt-live-1", seconds: 8, confirmed: true, raw: "{}")
    try store.saveProviderUsage(partial, scope: "m")
    try store.saveProviderUsage(final, scope: "m")
    try store.saveProviderUsage(partial, scope: "m")
    XCTAssertEqual(try store.list(ProviderUsage.self, kind: "providerUsage"), [final])
    XCTAssertNil(UsageRates(perMinute: 1).estimate(partial))
    XCTAssertEqual(UsageRates(perMinute: 1).estimate(final)!, 8.0 / 60, accuracy: 0.00001)
  }
  func testSetupAndRetentionStartConservatively() {
    var choices = SetupChoices()
    choices.dictation = false
    choices.meetings = false
    XCTAssertTrue(choices.permissions.isEmpty)
    choices.meetings = true
    XCTAssertEqual(choices.permissions, [.microphone, .systemAudio])
    choices.screenFallback = true
    XCTAssertTrue(choices.permissions.contains(.screenCapture))
    let policy = RetentionPolicy()
    XCTAssertFalse(policy.expired(.distantPast, days: policy.meetingDays))
    XCTAssertTrue(policy.expired(Date().addingTimeInterval(-31 * 86400), days: 30))
  }
}
