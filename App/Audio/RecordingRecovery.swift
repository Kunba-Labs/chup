import CryptoKit
import Foundation
import ChupCore

actor RecordingRecovery {
  func inspect(meetingID: String, legs: [RecordingLeg], key: SymmetricKey) throws
    -> RecordingRecoveryReport
  {
    var report = RecordingRecoveryReport(meetingID: meetingID)
    for leg in legs {
      try Task.checkCancellation()
      let directory = URL(fileURLWithPath: leg.directory)
      guard
        let files = try? FileManager.default.contentsOfDirectory(
          at: directory, includingPropertiesForKeys: nil
        )
        .filter({ $0.pathExtension == "vwj" })
      else {
        report.corruptFiles.append(directory.lastPathComponent + "/missing directory")
        continue
      }
      let origin =
        leg.hostStart ?? files.compactMap {
          Double($0.deletingPathExtension().lastPathComponent.split(separator: "-").last ?? "")
        }.min() ?? 0
      for file in files {
        try Task.checkCancellation()
        do {
          let recovered = try AudioJournal.recover(url: file, key: key)
          report.completePackets += recovered.packets.count
          if recovered.truncatedTail { report.truncatedFiles.append(file.lastPathComponent) }
          for packet in recovered.packets {
            report.duration = max(
              report.duration, leg.offset + packet.hostTime - origin + packet.duration)
          }
        } catch { report.corruptFiles.append(file.lastPathComponent) }
      }
    }
    return report
  }
}
