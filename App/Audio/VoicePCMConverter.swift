import AVFoundation
import ChupCore

final class VoicePCMConverter {
  private var converter: AVAudioConverter?
  private var sourceRate: Double = 0
  func convert(_ packet: AudioPacket) throws -> Data {
    let source = AVAudioFormat(
      commonFormat: .pcmFormatInt16, sampleRate: packet.sampleRate, channels: 1, interleaved: true)!
    let destination = AVAudioFormat(
      commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true)!
    if converter == nil || sourceRate != packet.sampleRate {
      converter = AVAudioConverter(from: source, to: destination)
      sourceRate = packet.sampleRate
    }
    guard let converter,
      let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: UInt32(packet.pcm.count / 2)),
      let output = AVAudioPCMBuffer(
        pcmFormat: destination,
        frameCapacity: UInt32(ceil(Double(packet.pcm.count / 2) * 24000 / packet.sampleRate)) + 32)
    else { throw WorkspaceError.message("Cannot convert microphone audio.") }
    input.frameLength = input.frameCapacity
    packet.pcm.withUnsafeBytes {
      if let base = $0.baseAddress { memcpy(input.int16ChannelData![0], base, packet.pcm.count) }
    }
    var supplied = false
    var error: NSError?
    converter.convert(to: output, error: &error) { _, status in
      if supplied {
        status.pointee = .noDataNow
        return nil
      }
      supplied = true
      status.pointee = .haveData
      return input
    }
    if let error { throw error }
    return Data(bytes: output.int16ChannelData![0], count: Int(output.frameLength) * 2)
  }
}
