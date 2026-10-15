import Testing
import Foundation
@testable import True

/// Routes `https://<x>.ts.net:8444` to a loopback port and stamps the sender's Tailscale login, as `tailscale serve` would.
final class LoopbackTransport: PeerTransport, @unchecked Sendable {
    let ports: [String: UInt16]
    let login: String
    init(ports: [String: UInt16], login: String) { self.ports = ports; self.login = login }
    func post(baseURL: String, path: String, bearer: String?, body: Data) -> (status: Int, body: Data) {
        let host = URL(string: baseURL)?.host ?? ""
        guard let port = ports[host] else { return (0, Data()) }
        let r = PeerHTTP.send(port, "POST", path, host: "\(host):8444", login: login, bearer: bearer, body: body)
        return (r.status, Data(r.body.utf8))
    }
}

enum PeerHTTP {
    static func send(_ port: UInt16, _ method: String, _ path: String, host: String? = "b.test.ts.net:8444", login: String? = "a@x",
                     origin: String? = nil, bearer: String? = nil, body: Data = Data()) -> (status: Int, body: String) {
        var l = ["\(method) \(path) HTTP/1.1"]
        if let host { l.append("Host: \(host)") }
        if let login { l.append("Tailscale-User-Login: \(login)") }
        if let origin { l.append("Origin: \(origin)") }
        if let bearer { l.append("Authorization: Bearer \(bearer)") }
        if !body.isEmpty { l.append("Content-Type: application/json"); l.append("Content-Length: \(body.count)") }
        let raw = Array((l.joined(separator: "\r\n") + "\r\n\r\n").utf8) + Array(body)
        let fd = socket(AF_INET, SOCK_STREAM, 0); defer { close(fd) }
        var a = RemoteServer.loopbackAddress(port: port)
        _ = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        var tv = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        _ = Darwin.send(fd, raw, raw.count, 0)
        var all: [UInt8] = []; var buf = [UInt8](repeating: 0, count: 8192)
        while true { let n = recv(fd, &buf, buf.count, 0); if n <= 0 { break }; all += buf[0..<n] }
        let parts = String(decoding: all, as: UTF8.self).components(separatedBy: "\r\n\r\n")
        let status = Int(parts[0].split(separator: " ").dropFirst().first ?? "") ?? 0
        return (status, parts.dropFirst().joined(separator: "\r\n\r\n"))
    }
}

@Suite(.serialized) struct PeerEndToEndTests {
    final class Side: @unchecked Sendable {
        let root: URL, engine: PeerEngine, server: RemoteServer, launcher = FakeLauncher(), devices: DeviceStore
        init(name: String, port: UInt16, login: String, ports: [String: UInt16], senderLogin: String) {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("true-pe2e-\(UUID().uuidString)")
            devices = DeviceStore(url: root.appendingPathComponent("dev.json"))
            let codes = PairingCodes()
            engine = PeerEngine(root: root.appendingPathComponent("peers"), codes: codes, devices: devices, launcher: launcher,
                                transport: LoopbackTransport(ports: ports, login: senderLogin), inboundMode: { .bypass },
                                selfURL: { "https://\(name).test.ts.net:8444" }, ownName: name, scheduler: { _, _ in })
            server = RemoteServer(backend: RemoteEndToEndTests.FakeBackend(), codes: PairingCodes(), devices: devices,
                                  allowedLogin: { login }, dnsName: { "\(name).test.ts.net" }, wsAuthTimeout: 0.5, peerCodes: codes)
            server.peerHost = engine
            #expect(server.start(port: port))
        }
        func close() { server.stop(); try? FileManager.default.removeItem(at: root) }
    }

    func pair(_ a: Side, _ b: Side) -> PeerLink? {
        let code = b.engine.invite().code
        if case .success(let l) = a.engine.pairAsSender(url: "https://b.test.ts.net:8444", code: code, label: "Bea", myName: "Al") { return l }
        return nil
    }

    @Test func jobTravelsFromSenderToDoneWithResult() throws {
        let ports = ["a.test.ts.net": UInt16(18890), "b.test.ts.net": UInt16(18891)]
        let a = Side(name: "a", port: 18890, login: "a@x", ports: ports, senderLogin: "a@x")
        let b = Side(name: "b", port: 18891, login: "b@x", ports: ports, senderLogin: "b@x")
        defer { a.close(); b.close() }
        // Wrong identity: A's transport stamps a@x, B stamped b@x. Pairing records a@x as A's login on B.
        let link = try #require(pair(a, b))
        #expect(link.receiverLogin == "b@x")
        #expect(b.engine.peerDevices().first?.label == "Al")

        let id: String
        switch a.engine.delegate(peer: "Bea", repo: "https://github.com/acme/app.git", title: "Fix it", brief: "do the thing") {
        case .success(let j): id = j
        case .failure(let e): Issue.record("\(e)"); return
        }
        a.engine.drain(); b.engine.drain()
        #expect(b.launcher.panes.count == 1)
        #expect(b.engine.inboundJobs().first?.req.jobId == id)
        b.engine.paneEvent(pane: b.launcher.pane, kind: .progress); b.engine.drain()
        #expect(a.engine.status(jobId: id).first?.status == .working)

        try FileManager.default.createDirectory(at: b.engine.jobDir(id), withIntermediateDirectories: true)
        try "Fixed it. Verified with tests.".write(toFile: b.engine.resultPath(id), atomically: true, encoding: .utf8)
        b.engine.paneEvent(pane: b.launcher.pane, kind: .stop); b.engine.drain()
        let sent = try #require(a.engine.result(jobId: id))
        #expect(sent.status == .done)
        #expect(sent.result?.contains("Fixed it") == true)
        #expect(a.launcher.lines.contains { $0.1.contains("[peer Bea]") && $0.1.contains("done") })

        // The agent-facing CLI sees the same thing.
        let r = PeerCLI.handle(["op": "result", "jobId": id], engine: a.engine)
        #expect(r["ok"] as? Bool == true && r["status"] as? String == "done")
        #expect((PeerCLI.handle(["op": "list"], engine: a.engine)["peers"] as? [String]) == ["Bea"])
        #expect(PeerCLI.handle(["op": "result", "jobId": "nope"], engine: a.engine)["ok"] as? Bool == false)
        #expect(PeerCLI.handle(["op": "bogus"], engine: a.engine)["ok"] as? Bool == false)
    }

    @Test func authOverHTTPFailsClosed() throws {
        let ports = ["a.test.ts.net": UInt16(18892), "b.test.ts.net": UInt16(18893)]
        let a = Side(name: "a", port: 18892, login: "a@x", ports: ports, senderLogin: "a@x")
        let b = Side(name: "b", port: 18893, login: "b@x", ports: ports, senderLogin: "a@x")
        defer { a.close(); b.close() }
        let peerTok = b.devices.pair(label: "Al", scope: .peer, login: "a@x")
        let phoneTok = b.devices.pair(label: "Phone")
        let body = Data(#"{"jobId":"x"}"#.utf8)
        func job(_ bearer: String?, login: String? = "a@x", origin: String? = nil, host: String? = "b.test.ts.net:8444") -> Int {
            PeerHTTP.send(18893, "POST", "/api/peer/job", host: host, login: login, origin: origin, bearer: bearer, body: body).status
        }
        // A bad body from a valid peer is a 400 — i.e. it got past auth, with no Origin.
        #expect(job(peerTok) == 400)
        #expect(job(phoneTok) == 403 || job(phoneTok) == 401)
        #expect(job(peerTok, login: nil) == 403)
        #expect(job(peerTok, login: "evil@x") == 403)
        #expect(job(peerTok, host: "evil.example:8444") != 400)
        #expect(job(peerTok, origin: "https://evil.example") == 403)
        #expect(job(peerTok, origin: "https://b.test.ts.net:8444") == 400)
        #expect(job(nil) == 401 || job(nil) == 403)
        // A peer token reaches nothing else.
        for path in ["/api/tabs", "/api/files", "/api/pane/\(UUID().uuidString)/input"] {
            let s = PeerHTTP.send(18893, "GET", path, login: "a@x", origin: "https://b.test.ts.net:8444", bearer: peerTok).status
            #expect(s == 403, "peer token on \(path) gave \(s)")
        }
        // Events: a real job, the wrong bearer never lands; a wrong login never lands either.
        _ = try #require(pair(a, b))
        let id: String
        switch a.engine.delegate(peer: "Bea", repo: "https://github.com/acme/app.git", title: "T", brief: "x") {
        case .success(let j): id = j
        case .failure(let e): Issue.record("\(e)"); return
        }
        let ev = Data(#"{"jobId":"\#(id)","status":"done","note":"n"}"#.utf8)
        func event(_ bearer: String, login: String) -> Int {
            PeerHTTP.send(18892, "POST", "/api/peer/event", host: "a.test.ts.net:8444", login: login, bearer: bearer, body: ev).status
        }
        #expect(event("nope", login: "b@x") == 403 || event("nope", login: "b@x") == 401)
        #expect(a.engine.status(jobId: id).first?.status != .done)
        #expect(event("nope", login: "evil@x") == 403)
    }
}
