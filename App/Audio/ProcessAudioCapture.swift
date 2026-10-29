import AppKit
import AVFoundation
import CoreAudio
import ChupCore

/// CoreAudio process objects attributed to the app responsible for them. Browsers and Electron
/// apps do audio in helpers (com.apple.WebKit.GPU, com.google.Chrome.helper), so a helper's own
/// bundle ID never names the meeting app.
enum AudioProcesses {
  struct Entry {
    var object: AudioObjectID
    var appPID: pid_t
    var input: Bool
  }
  // ponytail: private libsystem call (used by OverSight-style tools); falls back to the
  // helper's own PID if Apple removes it, which degrades to the old per-process behaviour.
  private typealias Responsible = @convention(c) (pid_t) -> pid_t
  private static let responsible: Responsible? = dlsym(
    UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid"
  ).map { unsafeBitCast($0, to: Responsible.self) }

  static func list() -> [Entry] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard
      AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
    else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
    else { return [] }
    return ids.compactMap { id in
      var pid: pid_t = 0
      address.mSelector = kAudioProcessPropertyPID
      size = UInt32(MemoryLayout<pid_t>.size)
      guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &pid) == noErr else {
        return nil
      }
      var running: UInt32 = 0
      address.mSelector = kAudioProcessPropertyIsRunningInput
      size = UInt32(MemoryLayout<UInt32>.size)
      _ = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &running)
      // Regular apps keep their own PID; one launched from Terminal is "responsible" to Terminal.
      let isApp = NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
      let owner = isApp ? pid : responsible?(pid) ?? pid
      return Entry(object: id, appPID: owner > 0 ? owner : pid, input: running != 0)
    }
  }
}

final class ProcessAudioCapture: RemoteAudioCapture {
  private var tap: AudioObjectID = 0
  private var device: AudioObjectID = 0
  private var callback: AudioDeviceIOProcID?
  private var formatListener: AudioObjectPropertyListenerBlock?
  private var formatAddress = AudioObjectPropertyAddress(
    mSelector: kAudioTapPropertyFormat,
    mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
  @MainActor func start(
    pid: pid_t, receive: @escaping (AVAudioPCMBuffer, Double) -> Void,
    failure: @escaping (String) -> Void
  ) async throws {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioTapPropertyFormat,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    // ponytail: helpers that first appear after start aren't tapped; re-tap on process-list
    // change if a call app spawns its audio helper mid-call.
    let processes = AudioProcesses.list().filter { $0.appPID == pid }.map(\.object)
    guard !processes.isEmpty else {
      throw WorkspaceError.message(
        "The selected app has no active audio process. Start call audio, then retry."
      )
    }
    let description = CATapDescription(stereoMixdownOfProcesses: processes)
    description.name = "Chup! call capture"
    description.isPrivate = true
    description.muteBehavior = .unmuted
    do {
      try check(AudioHardwareCreateProcessTap(description, &tap), "Create process tap")
      var asbd = AudioStreamBasicDescription()
      address.mSelector = kAudioTapPropertyFormat
      size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
      try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &asbd), "Read tap format")
      guard let format = AVAudioFormat(streamDescription: &asbd) else {
        throw WorkspaceError.message("The call audio format is unsupported.")
      }
      let listener: AudioObjectPropertyListenerBlock = { _, _ in
        failure(
          "Call audio format changed. Microphone capture continues; reconnect call audio to use its new format."
        )
      }
      try check(
        AudioObjectAddPropertyListenerBlock(tap, &formatAddress, .main, listener),
        "Watch call format")
      formatListener = listener
      let aggregate: [String: Any] = [
        kAudioAggregateDeviceNameKey: "Chup! Private Capture",
        kAudioAggregateDeviceUIDKey: UUID().uuidString,
        kAudioAggregateDeviceIsPrivateKey: true, kAudioAggregateDeviceIsStackedKey: false,
        kAudioAggregateDeviceTapAutoStartKey: true,
        kAudioAggregateDeviceTapListKey: [
          [kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]
        ],
      ]
      try check(
        AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device),
        "Create private capture device")
      try check(
        AudioDeviceCreateIOProcIDWithBlock(&callback, device, nil) { _, input, inputTime, _, _ in
          let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
          guard let first = list.first, first.mDataByteSize > 0 else { return }
          let frames = first.mDataByteSize / max(1, asbd.mBytesPerFrame)
          guard frames <= 32768, list.count == (format.isInterleaved ? 1 : Int(format.channelCount))
          else {
            failure(
              "Call audio buffer format changed or exceeded its safe limit. Reconnect call audio.")
            return
          }
          guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            return
          }
          buffer.frameLength = frames
          let dest = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
          for i in 0..<min(dest.count, list.count) {
            if let src = list[i].mData, let out = dest[i].mData {
              memcpy(out, src, min(Int(dest[i].mDataByteSize), Int(list[i].mDataByteSize)))
            }
          }
          receive(buffer, AVAudioTime.seconds(forHostTime: inputTime.pointee.mHostTime))
        }, "Register capture callback")
      try check(AudioDeviceStart(device, callback), "Start call capture")
    } catch {
      stop()
      throw error
    }
  }
  @MainActor func stop() {
    if device != 0 {
      AudioDeviceStop(device, callback)
      if let callback { AudioDeviceDestroyIOProcID(device, callback) }
      AudioHardwareDestroyAggregateDevice(device)
    }
    if tap != 0 {
      if let formatListener {
        AudioObjectRemovePropertyListenerBlock(tap, &formatAddress, .main, formatListener)
      }
      AudioHardwareDestroyProcessTap(tap)
    }
    formatListener = nil
    callback = nil
    device = 0
    tap = 0
  }
  private func check(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else {
      throw WorkspaceError.message(
        "\(operation) failed (\(status)). Check System Audio Recording permission, or explicitly select ScreenCaptureKit in Settings."
      )
    }
  }
}
