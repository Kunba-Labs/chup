import AppKit
import ChupCore
import Foundation

/// Serves read-only MCP over a 0600 Unix socket in the workspace folder, only while the user
/// has turned it on. The library stays locked to this process; `Chup! --mcp` relays stdio here.
final class MeetingMCPServer: @unchecked Sendable {
  static func socketPath(root: URL) -> String { root.appendingPathComponent("mcp.sock").path }
  private let path: String
  private var listener: Int32 = -1
  private var clients = Set<Int32>()
  private let lock = NSLock()
  private let handle: (Data) -> Data?
  init(root: URL, handle: @escaping (Data) -> Data?) {
    path = Self.socketPath(root: root)
    self.handle = handle
  }
  func start() throws {
    guard listener < 0 else { return }
    unlink(path)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    var address = Self.address(path)
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard fd >= 0, bound == 0, chmod(path, 0o600) == 0, listen(fd, 4) == 0 else {
      if fd >= 0 { close(fd) }
      throw WorkspaceError.message("Could not open the MCP socket.")
    }
    listener = fd
    Thread.detachNewThread { [weak self] in self?.acceptLoop(fd) }
  }
  /// Closes the listener and every open connection, so switching MCP off revokes access now.
  func stop() {
    guard listener >= 0 else { return }
    shutdown(listener, SHUT_RDWR)
    close(listener)
    listener = -1
    unlink(path)
    lock.withLock { clients.forEach { shutdown($0, SHUT_RDWR) } }
  }
  /// A disconnecting client must never SIGPIPE the recording app.
  static func noSigpipe(_ fd: Int32) {
    var on: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
  }
  private func acceptLoop(_ fd: Int32) {
    while true {
      let client = accept(fd, nil, nil)
      guard client >= 0 else { return }
      var uid: uid_t = 0
      var gid: gid_t = 0
      // Only this user's processes; the 0600 socket already enforces it, this is belt and braces.
      guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else {
        close(client)
        continue
      }
      Self.noSigpipe(client)
      lock.withLock { _ = clients.insert(client) }
      Thread.detachNewThread { [weak self] in self?.serve(client) }
    }
  }
  private func serve(_ client: Int32) {
    defer {
      lock.withLock { _ = clients.remove(client) }
      close(client)
    }
    var buffer = Data()
    var chunk = [UInt8](repeating: 0, count: 65536)
    while true {
      let count = read(client, &chunk, chunk.count)
      guard count > 0 else { return }
      buffer.append(contentsOf: chunk[0..<count])
      guard buffer.count < 4_000_000 else { return }
      while let newline = buffer.firstIndex(of: 10) {
        let line = buffer[buffer.startIndex..<newline]
        buffer.removeSubrange(buffer.startIndex...newline)
        guard !line.isEmpty, let reply = handle(Data(line)) else { continue }
        guard Self.writeAll(client, reply) else { return }
      }
    }
  }
  static func address(_ path: String) -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
      let bytes = Array(path.utf8.prefix(raw.count - 1))
      raw.copyBytes(from: bytes)
    }
    return address
  }
  static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
    data.withUnsafeBytes { raw in
      var offset = 0
      while offset < raw.count {
        let written = write(fd, raw.baseAddress! + offset, raw.count - offset)
        guard written > 0 else { return false }
        offset += written
      }
      return true
    }
  }
}

/// `Chup! --mcp`: what an MCP client launches. Relays stdio to the running app, opening Chup!
/// in the background if needed. Holds no key and reads no data itself.
enum MCPBridge {
  static func run() -> Never {
    let defaults = UserDefaults(suiteName: "com.chup.mac") ?? .standard
    let root =
      defaults.string(forKey: "workspaceRootOverride").map { URL(fileURLWithPath: $0) }
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Chup", isDirectory: true)
    let path = MeetingMCPServer.socketPath(root: root)
    var fd = connectSocket(path)
    if fd < 0 {
      let open = Process()
      open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
      open.arguments = ["-g", Bundle.main.bundleURL.path]
      try? open.run()
      for _ in 0..<30 where fd < 0 {
        usleep(500_000)
        fd = connectSocket(path)
      }
    }
    guard fd >= 0 else {
      FileHandle.standardError.write(
        Data("Chup! MCP is off. Turn on Settings → Privacy → Let AI tools read meetings.\n".utf8))
      exit(1)
    }
    signal(SIGPIPE, SIG_IGN)
    let socket = fd
    let replies = DispatchSemaphore(value: 0)
    Thread.detachNewThread {
      pump(from: socket, to: STDOUT_FILENO)
      replies.signal()
    }
    pump(from: STDIN_FILENO, to: socket)
    // Client closed stdin: half-close so the app finishes, then drain every queued reply.
    shutdown(socket, SHUT_WR)
    replies.wait()
    exit(0)
  }
  private static func connectSocket(_ path: String) -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    var address = MeetingMCPServer.address(path)
    let result = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    if result != 0 {
      close(fd)
      return -1
    }
    MeetingMCPServer.noSigpipe(fd)
    return fd
  }
  private static func pump(from source: Int32, to destination: Int32) {
    var chunk = [UInt8](repeating: 0, count: 65536)
    while true {
      let count = read(source, &chunk, chunk.count)
      guard count > 0, MeetingMCPServer.writeAll(destination, Data(chunk[0..<count])) else { return }
    }
  }
}
