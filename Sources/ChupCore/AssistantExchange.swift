import Foundation

public struct ProposedNoteWrite: Codable, Equatable {
  public var operation: String
  public var text: String
  public var owner: String?
  public var dueDate: String?
  public var sources: [Evidence]?
  public init(operation: String, text: String) {
    self.operation = operation
    self.text = text
  }
}

/// Durable per-meeting addressed conversation. Recorded speech never creates these requests.
public struct AssistantExchange: Codable, Identifiable, Equatable {
  public var id: String
  public var meetingID: String
  public var created: Date
  public var question: String
  public var answer: String
  public var sources: [Evidence]
  public var write: ProposedNoteWrite?
  public var noteVersion: Int
  public var status: String
  public init(id: String = UUID().uuidString, meetingID: String, question: String, noteVersion: Int)
  {
    self.id = id
    self.meetingID = meetingID
    self.question = question
    self.noteVersion = noteVersion
    created = Date()
    answer = ""
    sources = []
    write = nil
    status = "pending"
  }
}
