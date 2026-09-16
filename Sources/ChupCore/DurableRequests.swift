import CryptoKit
import Foundation

public struct DurableRequest: Codable, Identifiable {
  public var id = UUID().uuidString
  public var created = Date()
  public var scope: String
  public var associationID: String?
  public var route: String
  public var body: Data
  public var fingerprint: String
  public var status = "queued"
  public var error: String?
  public var response: Data?
  public var applied = false
  public init(scope: String, associationID: String? = nil, route: String, body: Data) {
    self.scope = scope
    self.associationID = associationID
    self.route = route
    self.body = body
    fingerprint = SHA256.hash(data: Data((scope + "/" + route).utf8) + body).map {
      String(format: "%02x", $0)
    }.joined()
  }
}
public struct ProviderUsage: Codable, Identifiable, Equatable {
  public var id: String
  public var category: String
  public var model: String
  public var created: Date = Date()
  public var inputTokens: Double?
  public var cachedTokens: Double?
  public var outputTokens: Double?
  public var seconds: Double?
  public var confirmed: Bool
  public var raw: String
  public init(
    id: String, category: String, model: String, inputTokens: Double? = nil,
    cachedTokens: Double? = nil, outputTokens: Double? = nil, seconds: Double? = nil,
    confirmed: Bool, raw: String
  ) {
    self.id = id
    self.category = category
    self.model = model
    self.inputTokens = inputTokens
    self.cachedTokens = cachedTokens
    self.outputTokens = outputTokens
    self.seconds = seconds
    self.confirmed = confirmed
    self.raw = raw
  }
}
public struct UsageRates: Codable, Equatable {
  public var inputPerMillion: Double?
  public var cachedPerMillion: Double?
  public var outputPerMillion: Double?
  public var perMinute: Double?
  public init(
    inputPerMillion: Double? = nil, cachedPerMillion: Double? = nil,
    outputPerMillion: Double? = nil, perMinute: Double? = nil
  ) {
    self.inputPerMillion = inputPerMillion
    self.cachedPerMillion = cachedPerMillion
    self.outputPerMillion = outputPerMillion
    self.perMinute = perMinute
  }
  public func estimate(_ item: ProviderUsage) -> Double? {
    let values = [item.inputTokens, item.cachedTokens, item.outputTokens, item.seconds,
      inputPerMillion, cachedPerMillion, outputPerMillion, perMinute].compactMap { $0 }
    guard item.confirmed, values.allSatisfy({ $0.isFinite && $0 >= 0 }),
      (item.cachedTokens ?? 0) <= (item.inputTokens ?? 0) else { return nil }
    if let seconds = item.seconds, item.inputTokens == nil, let rate = perMinute, rate >= 0 {
      let result = seconds * rate / 60
      return result.isFinite ? result : nil
    }
    guard let input = item.inputTokens, let output = item.outputTokens, let ir = inputPerMillion,
      let or = outputPerMillion, ir >= 0, or >= 0
    else { return nil }
    let cached = item.cachedTokens ?? 0
    guard cached == 0 || cachedPerMillion != nil else { return nil }
    let result = (max(0, input - cached) * ir + cached * (cachedPerMillion ?? 0) + output * or)
      / 1_000_000
    return result.isFinite ? result : nil
  }
}
extension WorkspaceStore {
  public func request(id: String) throws -> DurableRequest? {
    guard let row = try rows("SELECT json FROM objects WHERE kind='request' AND id=?", [id]).first
    else { return nil }
    return try decoder.decode(DurableRequest.self, from: Data(row[0].utf8))
  }
  public func requestListings() throws -> [DurableRequest] {
    try rows(
      "SELECT json_set(json,'$.body','', '$.response', CASE WHEN json_extract(json,'$.response') IS NULL THEN NULL ELSE '' END) FROM objects WHERE kind='request' ORDER BY rowid DESC"
    ).map { try decoder.decode(DurableRequest.self, from: Data($0[0].utf8)) }
  }
  public func saveRequest(_ job: DurableRequest) throws {
    let previous = try request(id: job.id)
    if let previous, previous.fingerprint != job.fingerprint || previous.scope != job.scope || previous.route != job.route
    {
      throw WorkspaceError.requestCollision
    }
    let erasedCompletedAudio = job.body.isEmpty && job.status == "completed" && job.response != nil
      && ["transcribe", "dictation"].contains(job.route) && previous?.fingerprint == job.fingerprint
    guard erasedCompletedAudio || DurableRequest(scope: job.scope, route: job.route, body: job.body).fingerprint == job.fingerprint else {
      throw WorkspaceError.requestCollision
    }
    try put(job, kind: "request", id: job.id, parent: job.scope)
  }
  public func recoverRequests() throws {
    for var job in try list(DurableRequest.self, kind: "request")
    where ["running", "queued"].contains(job.status) {
      job.status = "interrupted"
      job.error =
        "Chup! closed before the response was reconciled. Resume checks the same request ID before retrying."
      try saveRequest(job)
    }
  }
  public func saveProviderUsage(_ item: ProviderUsage, scope: String) throws {
    if let previous = try list(ProviderUsage.self, kind: "providerUsage").first(where: {
      $0.id == item.id
    }), previous.confirmed && !item.confirmed {
      return
    }
    try put(item, kind: "providerUsage", id: item.id, parent: scope)
  }
}
