import AVFoundation
import IOKit
import IOKit.pwr_mgt
import Combine
import CoreAudio
import ChupCore

struct InputDevice: Identifiable, Equatable {
  let id: String
  let objectID: AudioDeviceID
  let name: String
  let sampleRate: Double
  var builtIn = false
  var physicalExternal = false
  var available = true
}

@MainActor final class AudioDevices: ObservableObject {
  @Published private(set) var inputs: [InputDevice] = []
  @Published private(set) var message: String?
  @Published private(set) var defaultInputUID: String?
  @Published private(set) var lidClosed: Bool?
  var onChange: (() -> Void)?
  private var poll: Timer?
  private var defaultAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
    mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
  private var listener: AudioObjectPropertyListenerBlock?
  private var address = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDevices,
    mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
  init() {
    refresh()
    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      Task { @MainActor in self?.refresh() }
    }
    listener = block
    AudioObjectAddPropertyListenerBlock(
      AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
    AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, .main, block)
    // Also reconcile lid, alive and rate changes when drivers omit notifications.
    poll = MainActorTimer.repeating(every: 1) { [weak self] in self?.refresh() }
  }
  func refresh() {
    let previous = inputs
    let previousDefault = defaultInputUID
    let previousLid = lidClosed
    defer {
      if previous != inputs || previousDefault != defaultInputUID || previousLid != lidClosed { onChange?() }
    }
    let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    if root != 0 {
      lidClosed = IORegistryEntryCreateCFProperty(root, kAppleClamshellStateKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
      IOObjectRelease(root)
    } else { lidClosed = nil }
    let defaultID = Self.number(AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDefaultInputDevice)
    defaultInputUID = defaultID.flatMap { Self.string($0, selector: kAudioDevicePropertyDeviceUID) }
    var size: UInt32 = 0
    guard
      AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
    else {
      message = "Audio devices could not be read."
      return
    }
    var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr
    else { return }
    inputs = devices.compactMap { device in
      var streamAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
      var bytes: UInt32 = 0
      guard AudioObjectGetPropertyDataSize(device, &streamAddress, 0, nil, &bytes) == noErr,
        bytes > 0,
        let uid = Self.string(device, selector: kAudioDevicePropertyDeviceUID),
        let name = Self.string(device, selector: kAudioObjectPropertyName)
      else { return nil }
      var rate: Double = 0
      streamAddress.mSelector = kAudioDevicePropertyNominalSampleRate
      streamAddress.mScope = kAudioObjectPropertyScopeGlobal
      bytes = UInt32(MemoryLayout<Double>.size)
      AudioObjectGetPropertyData(device, &streamAddress, 0, nil, &bytes, &rate)
      let transport = Self.number(device, selector: kAudioDevicePropertyTransportType)
      let external = [kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeBluetooth,
        kAudioDeviceTransportTypeBluetoothLE, kAudioDeviceTransportTypeThunderbolt, kAudioDeviceTransportTypeFireWire].contains(transport ?? 0)
      return InputDevice(id: uid, objectID: device, name: name, sampleRate: rate,
        builtIn: transport == kAudioDeviceTransportTypeBuiltIn, physicalExternal: external,
        available: Self.number(device, selector: kAudioDevicePropertyDeviceIsAlive) == 1 && rate > 0)
    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
  static func string(_ object: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
    var address = AudioObjectPropertyAddress(
      mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
      return nil
    }
    // CoreAudio hands back a +1 CFString; the caller owns it.
    return value?.takeRetainedValue() as String?
  }
  private static func number(_ object: AudioObjectID, selector: AudioObjectPropertySelector) -> UInt32? {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var value: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
    return value
  }
  func selection(_ uid: String) throws -> InputDevice {
    let id = try MicrophoneSelectionPolicy.choose(inputs.map {
      MicrophoneCandidate(id: $0.id, builtIn: $0.builtIn, physicalExternal: $0.physicalExternal, available: $0.available)
    }, preferred: uid, systemDefault: defaultInputUID, lidClosed: lidClosed)
    guard let device = inputs.first(where: { $0.id == id }) else { throw MicrophoneSelectionError.unavailable }
    return device
  }
  func resolve(_ uid: String) throws -> InputDevice { refresh(); return try selection(uid) }
}
