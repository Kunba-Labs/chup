import AVFoundation
import CoreAudio
import ChupCore

struct OutputDevice: Identifiable, Equatable {
  let id: String
  let objectID: AudioDeviceID
  let name: String
  let headphones: Bool
}
@MainActor enum AssistantRouteDevices {
  static func objects(
    _ object: AudioObjectID, selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> [AudioObjectID] {
    var address = AudioObjectPropertyAddress(
      mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else {
      return []
    }
    var values = [AudioObjectID](repeating: 0, count: Int(size) / 4)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &values) == noErr else {
      return []
    }
    return values
  }
  static func scalar(_ object: AudioObjectID, selector: AudioObjectPropertySelector) -> UInt32? {
    var address = AudioObjectPropertyAddress(
      mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var value: UInt32 = 0
    var size: UInt32 = 4
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
      return nil
    }
    return value
  }
  static func outputs() -> [OutputDevice] {
    objects(AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDevices)
      .compactMap { device in
        let streams = objects(
          device, selector: kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
        guard !streams.isEmpty,
          let uid = AudioDevices.string(device, selector: kAudioDevicePropertyDeviceUID),
          let name = AudioDevices.string(device, selector: kAudioObjectPropertyName)
        else { return nil }
        let headphones = streams.contains {
          scalar($0, selector: kAudioStreamPropertyTerminalType)
            == kAudioStreamTerminalTypeHeadphones
        }
        return OutputDevice(id: uid, objectID: device, name: name, headphones: headphones)
      }
  }
  // Check every HAL input reader, including unrecognized conferencing/browser helpers.
  // An unreadable process property is unknown, never evidence of a private input route.
  static func foreignInputPIDs() -> [pid_t]? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard
      AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
    else { return nil }
    if size == 0 { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / 4)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
    else { return nil }
    var readers: [pid_t] = []
    for object in ids {
      guard let running = scalar(object, selector: kAudioProcessPropertyIsRunningInput),
        let pid = scalar(object, selector: kAudioProcessPropertyPID)
      else { return nil }
      if running != 0, pid != UInt32(ProcessInfo.processInfo.processIdentifier) {
        readers.append(pid_t(pid))
      }
    }
    return readers
  }
  static func callUsesVirtual(pid: pid_t, virtualDevice: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var process: AudioObjectID = 0
    var size: UInt32 = 4
    var pid = pid
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 4, &pid, &size, &process) == noErr,
      scalar(process, selector: kAudioProcessPropertyIsRunningInput) == 1
    else { return false }
    let devices = objects(process, selector: kAudioProcessPropertyDevices)
    let inputs = devices.filter {
      !objects($0, selector: kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeInput)
        .isEmpty
    }
    return !inputs.isEmpty && inputs.allSatisfy { $0 == virtualDevice }
  }
  static func evidence(
    microphone: InputDevice, output: OutputDevice, virtual: OutputDevice?, pid: pid_t
  ) -> RouteEvidence {
    RouteEvidence(
      microphoneUID: microphone.id, outputUID: output.id, virtualUID: virtual?.id,
      headphones: output.headphones,
      callUsesOnlyVirtualInput: virtual.map {
        callUsesVirtual(pid: pid, virtualDevice: $0.objectID)
      } ?? false)
  }
}
