import Foundation
import Darwin
import os

/// Tiny HTTP/1.1 + WebSocket server on 127.0.0.1 ONLY. `tailscale serve` terminates TLS on the tailnet
/// and proxies here, adding `Tailscale-User-Login`. Pure BSD sockets, one thread per connection
/// (a phone or two), no dependencies — same style as ``LineSocketServer``.
final class RemoteServer: @unchecked Sendable {
    static let port: UInt16 = 8801
    static let maxConnections = 16
    private static let log = Logger(subsystem: "True", category: "remote")

    /// The only address we ever bind. Tested: never 0.0.0.0.
    static func loopbackAddress(port: UInt16 = RemoteServer.port) -> sockaddr_in {
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        a.sin_family = sa_family_t(AF_INET)
        a.sin_port = port.bigEndian
        a.sin_addr.s_addr = UInt32(INADDR_LOOPBACK).bigEndian
        return a
    }

    let codes: PairingCodes
    let devices: DeviceStore
    private let backend: RemoteBackend
    private let allowedLogin: @Sendable () -> String?
    private let dnsName: @Sendable () -> String?
    private let wsAuthTimeout: TimeInterval
    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var running = false
    private var open: Set<Int32> = []
    /// Authenticated WebSocket fds → the device that authed them, so a revoke can cut live sessions.
    private var socketDevices: [Int32: UUID] = [:]

    init(backend: RemoteBackend, codes: PairingCodes, devices: DeviceStore,
         allowedLogin: @escaping @Sendable () -> String?, dnsName: @escaping @Sendable () -> String?,
         wsAuthTimeout: TimeInterval = 5) {
        self.wsAuthTimeout = wsAuthTimeout
        self.backend = backend; self.codes = codes; self.devices = devices
        self.allowedLogin = allowedLogin; self.dnsName = dnsName
    }

    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    @discardableResult
    func start(port: UInt16 = RemoteServer.port) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !running else { return true }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var addr = Self.loopbackAddress(port: port)
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } == 0
        }
        guard ok, listen(fd, 16) == 0 else { close(fd); Self.log.error("bind failed on 127.0.0.1:\(port, privacy: .public)"); return false }
        listenFD = fd; running = true
        Self.log.notice("remote listening on 127.0.0.1:\(port, privacy: .public)")
        Thread.detachNewThread { [self] in acceptLoop(fd) }
        return true
    }

    func stop() {
        lock.lock()
        running = false
        let fds = open
        lock.unlock()
        for fd in fds { shutdown(fd, SHUT_RDWR) }
        Self.log.notice("remote stopped")
    }

    /// Close every live WebSocket that was authenticated by `device` (called on revoke).
    func disconnect(device: UUID) {
        lock.lock()
        let fds = socketDevices.filter { $0.value == device }.map(\.key)
        lock.unlock()
        for fd in fds { shutdown(fd, SHUT_RDWR) }
    }

    // MARK: accept

    private func acceptLoop(_ fd: Int32) {
        while isRunning {
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&p, 1, 500) > 0 else { continue }
            let c = accept(fd, nil, nil)
            if c < 0 { continue }
            lock.lock()
            let full = open.count >= Self.maxConnections
            if !full { open.insert(c) }
            lock.unlock()
            if full { close(c); continue }
            var on: Int32 = 1
            setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            var tv = timeval(tv_sec: 10, tv_usec: 0)
            setsockopt(c, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            Thread.detachNewThread { [self] in
                handle(c)
                lock.lock(); open.remove(c); lock.unlock()
                close(c)
            }
        }
        close(fd)
        lock.lock(); listenFD = -1; lock.unlock()
    }

    // MARK: socket io

    private func send(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
        var off = 0
        while off < bytes.count {
            let n = bytes[off...].withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
            if n <= 0 { return false }
            off += n
        }
        return true
    }

    enum ReadOutcome: Equatable { case request(HTTPRequest), bad, timedOut }
    static let requestDeadline: TimeInterval = 10

    /// Read until a full HTTP request parses. The deadline is for the WHOLE request, not per read, so a client
    /// dribbling one byte at a time (slowloris) is cut off; the head is capped at 16 KB by the parser.
    static func readRequest(_ fd: Int32, deadline: TimeInterval = requestDeadline) -> ReadOutcome {
        let end = Date().addingTimeInterval(deadline)
        var buf: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            switch HTTPRequest.parse(buf) {
            case .bad: return .bad
            case .request(let r, _): return .request(r)
            case .needMore: break
            }
            let ms = Int32(max(0, min(end.timeIntervalSinceNow * 1000, 10_000)))
            if ms == 0 { return .timedOut }
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let rc = poll(&p, 1, ms)
            if rc == 0 { return .timedOut }
            if rc < 0 { if errno == EINTR { continue }; return .timedOut }
            let n = recv(fd, &chunk, chunk.count, 0)
            if n <= 0 { return .timedOut }
            buf += chunk[0..<n]
        }
    }

    // MARK: request handling

    private func handle(_ fd: Int32) {
        let req: HTTPRequest
        switch Self.readRequest(fd) {
        case .timedOut: return
        case .bad: _ = send(fd, HTTPResponse.make(status: 400, reason: "Bad Request", body: Array("Bad request".utf8))); return
        case .request(let r): req = r
        }
        let isAPI = req.path.hasPrefix("/api/")
        let ws = req.isWebSocketUpgrade
        // The only request allowed to skip the bearer header is the pane WebSocket (it authenticates by first message).
        let paneSocket = ws && req.path.hasPrefix("/api/pane/")
        if ws && !paneSocket {
            _ = send(fd, HTTPResponse.make(status: 400, reason: "Bad Request", body: Array("Bad request".utf8))); return
        }
        let stateChanging = req.method != "GET" && req.method != "HEAD"
        // WebSocket auth is the first message (browsers can't set headers on a WS), so the upgrade itself needs no token.
        let needsToken = isAPI && !paneSocket
        let bearer = RemoteAuth.bearerToken(req.header("authorization"))
        let device = needsToken ? devices.validate(bearer) : nil
        let decision = RemoteAuth.decide(loginHeader: req.header(RemoteAuth.loginHeader), allowedLogin: allowedLogin(),
                                         host: req.header("host"), origin: req.header("origin"), dnsName: dnsName(),
                                         requiresOrigin: stateChanging || ws, requiresToken: needsToken,
                                         tokenValid: device != nil)
        switch decision {
        case .forbidden(let why):
            Self.log.notice("deny 403 \(req.method, privacy: .public) \(req.path, privacy: .public): \(why, privacy: .public)")
            _ = send(fd, HTTPResponse.make(status: 403, reason: "Forbidden", body: Array("Forbidden".utf8)))
        case .needsPairing:
            Self.log.notice("deny 401 \(req.path, privacy: .public): not paired")
            _ = send(fd, HTTPResponse.make(status: 401, reason: "Unauthorized", body: Array("Not paired".utf8)))
        case .allow:
            Self.log.notice("allow \(req.method, privacy: .public) \(req.path, privacy: .public) device=\(device?.label ?? "-", privacy: .public)")
            route(fd, req)
        }
    }

    private func json(_ fd: Int32, _ status: Int, _ reason: String, _ obj: [String: Any], extra: [String: String] = [:]) {
        let body = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        _ = send(fd, HTTPResponse.make(status: status, reason: reason, headers: extra, body: [UInt8](body),
                                       contentType: "application/json"))
    }

    /// POST /pair {"code":"123456"} → {"token":"…"}; the phone keeps the token in localStorage.
    private func handlePair(_ fd: Int32, _ req: HTTPRequest) {
        let code = (try? JSONSerialization.jsonObject(with: Data(req.body)) as? [String: Any])?["code"] as? String
        switch codes.attempt(code ?? "") {
        case .ok:
            let label = Self.deviceLabel(req.header("user-agent") ?? "")
            let token = devices.pair(label: label)
            Self.log.notice("paired device \(label, privacy: .public)")
            json(fd, 200, "OK", ["token": token])
        case .rateLimited:
            Self.log.notice("pair rate-limited")
            json(fd, 429, "Too Many Requests", ["error": "Too many tries. Wait a minute."], extra: ["Retry-After": "60"])
        case .burned:
            Self.log.notice("pair code burned")
            json(fd, 401, "Unauthorized", ["error": "Code burned. Show a new one on the Mac."])
        case .wrong, .expired:
            Self.log.notice("pair wrong/expired code")
            json(fd, 401, "Unauthorized", ["error": "That code didn't work. Show a fresh one on the Mac."])
        }
    }

    /// Identity, Host and (where needed) Origin/token already passed.
    private func route(_ fd: Int32, _ req: HTTPRequest) {
        if req.method == "POST" && req.path == "/pair" { handlePair(fd, req); return }
        if req.path == "/api/tabs", req.method == "GET" {
            _ = send(fd, HTTPResponse.make(status: 200, reason: "OK", body: [UInt8](backend.tabsJSON()),
                                           contentType: "application/json")); return
        }
        if req.path.hasPrefix("/api/pane/"), req.isWebSocketUpgrade {
            guard let id = UUID(uuidString: String(req.path.dropFirst("/api/pane/".count))),
                  let key = req.header("sec-websocket-key") else {
                _ = send(fd, HTTPResponse.make(status: 400, reason: "Bad Request")); return
            }
            streamPane(fd, pane: id, key: key); return
        }
        // The web app itself is not secret; all data sits behind /api/* and the token.
        if req.method == "GET", !req.path.hasPrefix("/api/"), let asset = RemoteWebAssets.asset(req.path) {
            _ = send(fd, HTTPResponse.make(status: 200, reason: "OK", body: asset.body, contentType: asset.type)); return
        }
        _ = send(fd, HTTPResponse.make(status: 404, reason: "Not Found", body: Array("Not found".utf8)))
    }

    /// First WebSocket message must be text `{"auth":"<token>"}` within 5 s, else close 4401 and no PTY bytes flow.
    private func authenticateSocket(_ fd: Int32, _ dec: inout WebSocket.Decoder, _ pending: inout [WebSocket.Message]) -> PairedDevice? {
        let end = Date().addingTimeInterval(wsAuthTimeout)
        var chunk = [UInt8](repeating: 0, count: 4096)
        while pending.isEmpty {
            let ms = Int32(max(0, end.timeIntervalSinceNow * 1000))
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard ms > 0, poll(&p, 1, ms) > 0 else { return nil }
            let n = recv(fd, &chunk, chunk.count, 0)
            guard n > 0, let msgs = try? dec.feed(Array(chunk[0..<n])) else { return nil }
            pending += msgs
        }
        let first = pending.removeFirst()
        guard first.op == .text,
              let tok = (try? JSONSerialization.jsonObject(with: Data(first.payload)) as? [String: Any])?["auth"] as? String,
              let dev = devices.validate(tok) else { return nil }
        return dev
    }

    // MARK: pane stream

    private func streamPane(_ fd: Int32, pane: UUID, key: String) {
        let head = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
            + "Sec-WebSocket-Accept: \(WebSocket.acceptKey(for: key))\r\n\r\n"
        guard send(fd, Array(head.utf8)) else { return }
        var dec = WebSocket.Decoder()
        var pending: [WebSocket.Message] = []
        guard let authed = authenticateSocket(fd, &dec, &pending) else {
            Self.log.notice("ws auth failed")
            _ = send(fd, WebSocket.encode(.close, [0x11, 0x31]))   // 4401
            return
        }
        lock.lock(); socketDevices[fd] = authed.id; lock.unlock()
        defer { lock.lock(); socketDevices[fd] = nil; lock.unlock() }
        // Revoked between validate and registration → no disconnect would ever reach this fd.
        guard devices.all.contains(where: { $0.id == authed.id }) else { return }
        guard backend.snapshot(pane: pane) != nil else {
            _ = send(fd, WebSocket.encode(.text, Array(#"{"t":"gone"}"#.utf8)))
            _ = send(fd, WebSocket.encode(.close, [0x03, 0xE8])); return
        }
        Self.log.notice("ws open pane=\(pane.uuidString.prefix(8), privacy: .public)")
        let viewer = RemoteHub.shared.subscribe(pane)
        let sendLock = NSLock()
        let alive = OSAllocatedUnfairLock(initialState: true)
        @Sendable func out(_ op: WebSocket.Opcode, _ payload: [UInt8]) -> Bool {
            sendLock.lock(); defer { sendLock.unlock() }
            return send(fd, WebSocket.encode(op, payload))
        }
        let writer = Thread { [self] in
            while alive.withLock({ $0 }) && !viewer.closed && isRunning {
                switch viewer.take() {
                case .none:
                    if viewer.wake.wait(timeout: .now() + 20) == .timedOut { _ = out(.ping, []) }
                case .data(let d):
                    if !out(.binary, d) { shutdown(fd, SHUT_RDWR); return }
                case .snapshot:
                    guard let s = backend.snapshot(pane: pane) else {
                        _ = out(.text, Array(#"{"t":"gone"}"#.utf8)); shutdown(fd, SHUT_RDWR); return
                    }
                    let hello = #"{"t":"snap","cols":\#(s.cols),"rows":\#(s.rows)}"#
                    if !out(.text, Array(hello.utf8)) || !out(.binary, s.bytes) { shutdown(fd, SHUT_RDWR); return }
                }
            }
        }
        writer.start()
        // Reader: client input → PTY. No resize message exists; the Mac stays authoritative.
        var tv = timeval(tv_sec: 0, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var chunk = [UInt8](repeating: 0, count: 8192)
        readLoop: while isRunning {
            var msgs = pending; pending = []
            if msgs.isEmpty {
                let n = recv(fd, &chunk, chunk.count, 0)
                if n <= 0 { break }
                guard let got = try? dec.feed(Array(chunk[0..<n])) else { break }
                msgs = got
            }
            for m in msgs {
                switch m.op {
                case .close: _ = out(.close, []); break readLoop
                case .ping: _ = out(.pong, m.payload)
                case .binary, .text:
                    if !backend.input(pane: pane, bytes: m.payload) { break readLoop }
                default: break
                }
            }
        }
        alive.withLock { $0 = false }
        RemoteHub.shared.unsubscribe(viewer)
        Self.log.notice("ws close pane=\(pane.uuidString.prefix(8), privacy: .public)")
    }

    // MARK: small helpers

    static func parseForm(_ body: [UInt8]) -> [String: String] {
        var out: [String: String] = [:]
        for kv in String(decoding: body, as: UTF8.self).split(separator: "&") {
            let p = kv.split(separator: "=", maxSplits: 1)
            guard p.count == 2 else { continue }
            out[String(p[0])] = String(p[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
        }
        return out
    }

    static func deviceLabel(_ ua: String) -> String {
        let kind = ua.contains("iPhone") ? "iPhone" : ua.contains("iPad") ? "iPad" : ua.contains("Android") ? "Android"
            : ua.contains("Macintosh") ? "Mac browser" : "Browser"
        let f = DateFormatter(); f.dateFormat = "d MMM HH:mm"
        return "\(kind) · paired \(f.string(from: Date()))"
    }
}
