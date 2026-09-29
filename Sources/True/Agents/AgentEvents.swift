import Foundation

/// What an agent reported about itself, over `~/.true/agent-events.sock` (newline-delimited JSON:
/// `{"pane":"<uuid>","event":"stop|need|progress|…","message":"…"}`), fed by the hook forwarder.
/// Events are authoritative: status comes from what the agent SAYS, not from watching output.
enum PaneEventKind: String, Sendable {
    /// Turn over, your move (Claude's Stop).
    case stop, done
    /// Mid-turn nudge that is not a blocker.
    case notification
    /// Blocked on the user: permission prompt, question.
    case need
    /// Alive and working (a prompt was submitted, a tool is about to run).
    case progress
    /// The turn ended on an API error — deliberately not a completion.
    case error
    /// Waiting at the prompt (Claude's idle nudge).
    case idle
    /// Not a state change: the agent naming the conversation it IS (for `--resume`).
    case session
}

struct PaneEvent: Equatable, Sendable {
    let pane: UUID
    let kind: PaneEventKind
    let message: String
    let at: Date
    /// For a permission request: the tool asking and a one-line summary of what it wants to do.
    var tool: String? = nil
    var detail: String? = nil

    /// Parse one wire line. Anything malformed returns nil — the socket is a doorbell, never a crash surface.
    static func parse(line: Data, at: Date = Date()) -> PaneEvent? {
        struct Wire: Decodable {
            let pane: String
            let event: String
            let message: String?
            let tool: String?
            let input: [String: String]?
        }
        guard let w = try? JSONDecoder().decode(Wire.self, from: line),
              let pane = UUID(uuidString: w.pane), let kind = PaneEventKind(rawValue: w.event) else { return nil }
        let s = w.tool.map { ToolSummary.summarize(tool: $0, input: w.input ?? [:]) }
        return PaneEvent(pane: pane, kind: kind, message: w.message ?? "", at: at, tool: s?.tool, detail: s?.detail)
    }
}

/// One-line summary of what a permission request wants to do — the "Bash · npm test" on a
/// "Needs you" row. Pure, so the per-tool rules are unit-tested instead of living in the hook script.
enum ToolSummary {
    private static let preferredKeys = ["command", "file_path", "notebook_path", "path", "url",
                                        "query", "pattern", "description"]

    /// `tool` is the chip label; `detail` the one-liner. MCP tools (`mcp__server__tool`) read as
    /// chip "MCP" + detail "server:tool", since the raw name is noise.
    static func summarize(tool raw: String, input: [String: String]) -> (tool: String, detail: String?) {
        let name = raw.trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("mcp__") {
            let parts = name.dropFirst(5).components(separatedBy: "__")
            let label = parts.count >= 2 ? "\(parts[0]):\(parts.dropFirst().joined(separator: "__"))"
                                         : String(name.dropFirst(5))
            return ("MCP", label)
        }
        let display = name.isEmpty ? "a tool" : name
        let keys: [String]
        switch name {
        case "Bash":                                   keys = ["command"]
        case "Edit", "Write", "MultiEdit", "Read",
             "NotebookEdit":                           keys = ["file_path", "notebook_path", "path"]
        case "WebFetch":                               keys = ["url"]
        case "WebSearch":                              keys = ["query"]
        default:                                       keys = preferredKeys
        }
        for key in keys { if let v = clean(input[key]) { return (display, v) } }
        for key in input.keys.sorted() { if let v = clean(input[key]), v.count <= 120 { return (display, v) } }
        return (display, nil)
    }

    private static func clean(_ s: String?) -> String? {
        guard let s else { return nil }
        let one = s.split(whereSeparator: \.isNewline).first.map(String.init) ?? s
        let t = one.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : String(t.prefix(300))
    }
}

/// The events socket listener. Event-driven: one thread parked in `accept()` (0% CPU when idle),
/// one short-lived reader per connection. Lifted from Axon's `AgentEvents` (pure BSD sockets — no
/// dependencies, no NWListener quirks). Started once at launch; nothing else in True opens it.
final class AgentEventSocket: @unchecked Sendable {
    private let path: String
    private let handler: @Sendable (PaneEvent) -> Void
    private let lock = NSLock()
    private var started = false
    private var listenFD: Int32 = -1

    init(path: String, handler: @escaping @Sendable (PaneEvent) -> Void) {
        self.path = path
        self.handler = handler
    }

    /// Bind and accept forever. Idempotent. Returns false when the socket could not be bound.
    @discardableResult
    func start() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if started { return true }
        guard path.utf8.count < 100 else { return false }   // sun_path hard limit
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        unlink(path)                                          // a previous run's socket file
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { dst in
            _ = path.utf8CString.withUnsafeBytes { src in
                memcpy(dst.baseAddress, src.baseAddress, min(src.count, dst.count))
            }
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, Darwin.listen(fd, 16) == 0 else { close(fd); return false }
        chmod(path, 0o600)                                    // user-only: this socket flips UI state
        started = true
        listenFD = fd
        DispatchQueue.global(qos: .utility).async { [self] in acceptLoop(fd) }
        return true
    }

    /// Stop listening and remove the socket file (tests; app quit).
    func stop() {
        lock.lock(); defer { lock.unlock() }
        guard started else { return }
        started = false
        shutdown(listenFD, SHUT_RDWR)
        close(listenFD)
        unlink(path)
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let conn = accept(fd, nil, nil)
            guard conn >= 0 else {
                if errno == EINTR { continue }
                break
            }
            DispatchQueue.global(qos: .utility).async { [self] in drain(conn) }
        }
    }

    /// Read one connection to EOF, handing off each complete line — plus any unterminated remainder,
    /// so a `printf '...json...' | nc -U` without a trailing newline still lands.
    private func drain(_ conn: Int32) {
        defer { close(conn) }
        var pending = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(conn, &buf, buf.count)
            if n <= 0 { break }
            pending.append(contentsOf: buf[0..<n])
            while let nl = pending.firstIndex(of: 0x0A) {
                deliver(pending.prefix(upTo: nl))
                pending = Data(pending.suffix(from: nl + 1))
            }
            guard pending.count < 1 << 20 else { return }   // a megabyte with no newline is garbage
        }
        if !pending.isEmpty { deliver(pending) }
    }

    private func deliver(_ line: Data) {
        if let e = PaneEvent.parse(line: line) { handler(e) }
    }
}
