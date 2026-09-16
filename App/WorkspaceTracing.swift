import Foundation
import ChupCore

extension WorkspaceState {
  @discardableResult func startDictationTrace() -> String {
    let trace = DictationTrace()
    dictationTraceID = trace.id
    traceOrigins[trace.id] = ProcessInfo.processInfo.systemUptime
    dictationTraces.insert(trace, at: 0)
    for old in dictationTraces.dropFirst(50) { try? db().remove(kind: "dictationTrace", id: old.id); traceOrigins[old.id] = nil }
    dictationTraces = Array(dictationTraces.prefix(50))
    markTrace(trace.id, .requested)
    return trace.id
  }
  func markTrace(_ id: String?, _ stage: DictationTrace.Stage) {
    guard let id, let origin = traceOrigins[id], let index = dictationTraces.firstIndex(where: { $0.id == id }),
      !dictationTraces[index].events.contains(where: { $0.stage == stage }) else { return }
    dictationTraces[index].mark(stage, elapsed: ProcessInfo.processInfo.systemUptime - origin)
    persistTrace(index)
  }
  func finishTrace(_ id: String?, _ outcome: DictationTrace.Outcome) {
    guard let id, let index = dictationTraces.firstIndex(where: { $0.id == id }), dictationTraces[index].outcome == .running else { return }
    markTrace(id, .finished)
    dictationTraces[index].outcome = outcome
    persistTrace(index)
    traceOrigins[id] = nil
  }
  private func persistTrace(_ index: Int) {
    do { try db().put(dictationTraces[index], kind: "dictationTrace", id: dictationTraces[index].id) }
    catch { traceStorageFailed = true }
  }
  func clearDictationTraces() {
    guard dictationStatus != .listening && dictationStatus != .processing else { return }
    do {
      for trace in dictationTraces { try db().remove(kind: "dictationTrace", id: trace.id) }
      dictationTraces = []; traceOrigins = [:]; traceStorageFailed = false
    } catch { traceStorageFailed = true; notice = "Timing history could not be fully cleared." }
  }
}
