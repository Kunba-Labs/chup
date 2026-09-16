import AVFoundation
import ScreenCaptureKit
import ChupCore

final class ScreenAudioCapture: NSObject, RemoteAudioCapture, SCStreamOutput, SCStreamDelegate {
  private var stream: SCStream?
  private var receive: ((AVAudioPCMBuffer, Double) -> Void)?
  private var failure: ((String) -> Void)?
  @MainActor func start(
    pid: pid_t, receive: @escaping (AVAudioPCMBuffer, Double) -> Void,
    failure: @escaping (String) -> Void
  ) async throws {
    let content = try await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: false)
    guard let app = content.applications.first(where: { $0.processID == pid }),
      let display = content.displays.first
    else {
      throw WorkspaceError.message("The selected application is not available to ScreenCaptureKit.")
    }
    self.receive = receive
    self.failure = failure
    let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
    let config = SCStreamConfiguration()
    config.capturesAudio = true
    config.excludesCurrentProcessAudio = true
    config.sampleRate = 48000
    config.channelCount = 1
    config.width = 2
    config.height = 2
    config.minimumFrameInterval = CMTime(seconds: 1, preferredTimescale: 1)
    let stream = SCStream(filter: filter, configuration: config, delegate: self)
    try stream.addStreamOutput(
      self, type: .audio,
      sampleHandlerQueue: DispatchQueue(label: "com.chup.screen-audio"))
    try await stream.startCapture()
    self.stream = stream
  }
  @MainActor func stop() {
    let previous = stream
    stream = nil
    Task { try? await previous?.stopCapture() }
  }
  func stream(_ stream: SCStream, didStopWithError error: Error) {
    failure?("Call capture stopped: \(error.localizedDescription)")
  }
  func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard type == .audio, sampleBuffer.isValid, let description = sampleBuffer.formatDescription,
      let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
      let format = AVAudioFormat(streamDescription: asbd)
    else { return }
    var block: CMBlockBuffer?
    var needed = 0
    CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer, bufferListSizeNeededOut: &needed, bufferListOut: nil, bufferListSize: 0,
      blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil)
    let pointer = UnsafeMutableRawPointer.allocate(
      byteCount: max(needed, MemoryLayout<AudioBufferList>.size),
      alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { pointer.deallocate() }
    let list = pointer.bindMemory(to: AudioBufferList.self, capacity: 1)
    guard
      CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
        sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: needed,
        blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
        flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
        blockBufferOut: &block) == noErr,
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleBuffer.numSamples))
    else { return }
    buffer.frameLength = buffer.frameCapacity
    let source = UnsafeMutableAudioBufferListPointer(list)
    let dest = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
    for i in 0..<min(source.count, dest.count) {
      if let s = source[i].mData, let d = dest[i].mData {
        memcpy(d, s, min(Int(source[i].mDataByteSize), Int(dest[i].mDataByteSize)))
      }
    }
    receive?(buffer, sampleBuffer.presentationTimeStamp.seconds)
  }
}
