import AVFoundation
import CoreAudio
import ChupCore

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
      mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var process: AudioObjectID = 0
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var processID = pid
    try check(
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size),
        &processID, &size, &process), "Find audio process")
    guard process != 0 else {
      throw WorkspaceError.message(
        "The selected app has no active audio process. Start call audio, then retry. Browser helper processes may need separate selection."
      )
    }
    let description = CATapDescription(stereoMixdownOfProcesses: [process])
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
