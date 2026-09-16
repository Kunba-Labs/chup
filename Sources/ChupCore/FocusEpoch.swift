import Foundation

/// Native focus callbacks invalidate destinations synchronously, without a
/// Swift actor assertion or an asynchronous gap before insertion revalidation.
public final class FocusEpoch: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Int = 0
  public init() {}
  public var current: Int { lock.withLock { value } }
  public func advance() { lock.withLock { value &+= 1 } }
}
