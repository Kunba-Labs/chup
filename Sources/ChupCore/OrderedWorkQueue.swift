import Foundation

/// Serial asynchronous work, independent of capture. Cancellation waits for the
/// active operation to unwind before starting the next (shared local model).
@MainActor public final class OrderedWorkQueue {
  private struct Job {
    let id: String
    let operation: @MainActor () async -> Void
  }
  private var jobs: [Job] = []
  private var worker: Task<Void, Never>?
  public var onChange: ((Int) -> Void)?
  public var count: Int { jobs.count }
  public init() {}
  @discardableResult public func enqueue(id: String, operation: @escaping @MainActor () async -> Void) -> Bool {
    guard !jobs.contains(where: { $0.id == id }) else { return false }
    jobs.append(Job(id: id, operation: operation))
    onChange?(count)
    startNext()
    return true
  }
  public func cancelCurrent() { worker?.cancel() }
  private func startNext() {
    guard worker == nil, let job = jobs.first else { return }
    worker = Task {
      await job.operation()
      jobs.removeFirst()
      worker = nil
      onChange?(count)
      startNext()
    }
  }
}
