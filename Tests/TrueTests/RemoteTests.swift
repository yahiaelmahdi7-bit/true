import Testing
import Foundation
import Darwin
@testable import True

/// Client→server frame (masked, as RFC 6455 requires of browsers).
private func maskedFrame(_ op: UInt8, _ payload: [UInt8], fin: Bool = true, key: [UInt8] = [0x37, 0xfa, 0x21, 0x3d]) -> [UInt8] {
    var out: [UInt8] = [(fin ? 0x80 : 0) | op]
    let n = payload.count
    if n < 126 { out.append(0x80 | UInt8(n)) }
    else if n <= 0xFFFF { out += [0x80 | 126, UInt8(n >> 8), UInt8(n & 0xFF)] }
    else { out.append(0x80 | 127); for s in stride(from: 56, through: 0, by: -8) { out.append(UInt8((UInt64(n) >> UInt64(s)) & 0xFF)) } }
    out += key
    for (i, b) in payload.enumerated() { out.append(b ^ key[i % 4]) }
    return out
}

private func tempFile() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("true-remote-\(UUID().uuidString).json")
}

@Suite struct WebSocketTests {
    @Test func rfcSampleAcceptKey() {
        #expect(WebSocket.acceptKey(for: "dGhlIHNhbXBsZSBub25jZQ==") == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }

    @Test func serverEncodeLengths() {
        for n in [0, 5, 125, 126, 65535, 65536] {
            let f = WebSocket.encode(.binary, [UInt8](repeating: 7, count: n))
            #expect(f[0] == 0x82)
            switch n {
            case ..<126: #expect(f[1] == UInt8(n) && f.count == 2 + n)
            case ...65535: #expect(f[1] == 126 && f.count == 4 + n && Int(f[2]) << 8 | Int(f[3]) == n)
            default: #expect(f[1] == 127 && f.count == 10 + n)
            }
        }
    }

    @Test func decodeMaskedAcrossLengthBoundaries() throws {
        for n in [0, 1, 125, 126, 65535, 65536] {
            let payload = (0..<n).map { UInt8($0 & 0xFF) }
            var d = WebSocket.Decoder()
            let msgs = try d.feed(maskedFrame(2, payload))
            #expect(msgs == [WebSocket.Message(op: .binary, payload: payload)])
        }
    }

    @Test func decodeByteAtATime() throws {
        var d = WebSocket.Decoder()
        var got: [WebSocket.Message] = []
        for b in maskedFrame(1, Array("hello".utf8)) { got += try d.feed([b]) }
        #expect(got == [WebSocket.Message(op: .text, payload: Array("hello".utf8))])
    }

    @Test func fragmentationReassembles() throws {
        var d = WebSocket.Decoder()
        var out = try d.feed(maskedFrame(1, Array("hel".utf8), fin: false))
        #expect(out.isEmpty)
        out = try d.feed(maskedFrame(9, [1, 2]))                       // control frame interleaved
        #expect(out == [WebSocket.Message(op: .ping, payload: [1, 2])])
        out = try d.feed(maskedFrame(0, Array("lo".utf8)))
        #expect(out == [WebSocket.Message(op: .text, payload: Array("hello".utf8))])
    }

    @Test func rejectsUnmaskedAndOversize() {
        var d = WebSocket.Decoder()
        #expect(throws: WebSocket.Decoder.Failure.self) { _ = try d.feed([0x81, 0x01, 0x41]) }
        var small = WebSocket.Decoder(maxMessage: 10)
        #expect(throws: WebSocket.Decoder.Failure.self) { _ = try small.feed(maskedFrame(2, [UInt8](repeating: 1, count: 11))) }
    }

    @Test func backpressureRule() {
        #expect(!RemoteBackpressure.shouldSnapshot(pendingBytes: 1_048_576))
        #expect(RemoteBackpressure.shouldSnapshot(pendingBytes: 1_048_577))
        let v = RemoteViewer(pane: UUID())
        #expect(v.take() == .snapshot)                  // first delivery is a snapshot
        v.push([1, 2, 3])
        #expect(v.take() == .data([1, 2, 3]))
        v.push([UInt8](repeating: 0, count: 1_048_577))  // fell > 1 MB behind
        #expect(v.take() == .snapshot)
        #expect(v.take() == .none)
    }
}

@Suite struct HTTPParseTests {
    @Test func parsesRequestWithQueryHeadersCookies() {
        let raw = Array("GET /api/tabs?x=1&y=two HTTP/1.1\r\nHost: m.ts.net\r\nCookie: a=b; true_dev=tok\r\nTailscale-User-Login: me@x\r\n\r\n".utf8)
        guard case .request(let r, let used) = HTTPRequest.parse(raw) else { Issue.record("not parsed"); return }
        #expect(used == raw.count)
        #expect(r.method == "GET" && r.path == "/api/tabs")
        #expect(r.query == ["x": "1", "y": "two"])
        #expect(r.header("tailscale-user-login") == "me@x")
        #expect(r.cookies["true_dev"] == "tok")
        #expect(!r.isWebSocketUpgrade)
    }

    @Test func partialAndMalformed() {
        #expect(HTTPRequest.parse(Array("GET / HTTP/1.1\r\nHost: a".utf8)) == .needMore)
        #expect(HTTPRequest.parse(Array("NONSENSE\r\n\r\n".utf8)) == .bad)
        let big = Array("POST /pair HTTP/1.1\r\nContent-Length: 999999\r\n\r\n".utf8)
        #expect(HTTPRequest.parse(big) == .bad)
    }

    @Test func bodyWaitsForContentLength() {
        let head = "POST /pair HTTP/1.1\r\nContent-Length: 6\r\n\r\n"
        #expect(HTTPRequest.parse(Array((head + "12").utf8)) == .needMore)
        guard case .request(let r, _) = HTTPRequest.parse(Array((head + "123456").utf8)) else { Issue.record("no"); return }
        #expect(r.body == Array("123456".utf8))
    }
}

@Suite struct RemoteAuthTests {
    private func decide(login: String?, allowed: String? = "me@x", valid: Bool = true, origin: String? = nil,
                        ws: Bool = false, host: String? = "mac.ts.net") -> RemoteAuth.Decision {
        RemoteAuth.decide(loginHeader: login, allowedLogin: allowed, deviceValid: valid,
                          webSocketOrigin: origin, isWebSocket: ws, host: host)
    }

    @Test func decisionTable() {
        guard case .forbidden = decide(login: nil) else { Issue.record("no header"); return }
        guard case .forbidden = decide(login: "other@x") else { Issue.record("wrong login"); return }
        guard case .forbidden = decide(login: "me@x", allowed: nil) else { Issue.record("no configured login"); return }
        #expect(decide(login: "me@x", valid: false) == .needsPairing)       // no/bad/revoked cookie
        #expect(decide(login: "ME@x") == .allow)
        #expect(decide(login: "other@x", valid: false) != .needsPairing)    // identity beats cookie
    }

    @Test func webSocketOrigin() {
        #expect(decide(login: "me@x", origin: "https://mac.ts.net:8444", ws: true) == .allow)
        guard case .forbidden = decide(login: "me@x", origin: "https://evil.com", ws: true) else { Issue.record("evil"); return }
        guard case .forbidden = decide(login: "me@x", origin: nil, ws: true) else { Issue.record("nil origin"); return }
    }

    @Test func deviceLifecycle() {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }
        let store = DeviceStore(url: url)
        let token = store.pair(label: "iPhone")
        #expect(token.count == 64)
        #expect(store.validate(token)?.label == "iPhone")
        #expect(store.validate("bad") == nil)
        #expect(store.validate(nil) == nil)
        let disk = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        #expect(!disk.contains(token))                                    // only the hash is stored
        #expect(disk.contains(RemoteAuth.sha256Hex(token)))
        #expect(DeviceStore(url: url).validate(token) != nil)             // survives restart
        store.revoke(store.all[0].id)
        #expect(store.validate(token) == nil)
    }

    @Test func sha256KnownVector() {
        #expect(RemoteAuth.sha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

@Suite struct PairingCodeTests {
    final class Clock: @unchecked Sendable { var t = Date(timeIntervalSince1970: 1_000_000) }

    @Test func codeIsSixDigitsAndSingleUse() {
        let c = Clock(); let p = PairingCodes(now: { c.t })
        let code = p.issue()
        #expect(code.count == 6 && code.allSatisfy(\.isNumber))
        #expect(p.attempt(code) == .ok)
        #expect(p.attempt(code) == .expired)
    }

    @Test func expiresAfterFiveMinutes() {
        let c = Clock(); let p = PairingCodes(now: { c.t })
        let code = p.issue()
        c.t = c.t.addingTimeInterval(301)
        #expect(p.attempt(code) == .expired)
    }

    @Test func rateLimitFivePerMinute() {
        let c = Clock(); let p = PairingCodes(now: { c.t })
        let code = p.issue()
        let wrong = code == "000000" ? "111111" : "000000"
        for _ in 0..<5 { #expect(p.attempt(wrong) == .wrong) }
        #expect(p.attempt(code) == .rateLimited)           // even the right code is refused
        c.t = c.t.addingTimeInterval(61)
        #expect(p.attempt(code) == .ok)
    }

    @Test func newCodeReplacesOld() {
        let p = PairingCodes()
        let a = p.issue(); var b = p.issue()
        while b == a { b = p.issue() }
        #expect(p.attempt(a) == .wrong)
    }
}

@Suite struct RemoteServerTests {
    @Test func bindsLoopbackOnly() {
        let a = RemoteServer.loopbackAddress()
        #expect(UInt32(bigEndian: a.sin_addr.s_addr) == 0x7F000001)
        #expect(a.sin_addr.s_addr != INADDR_ANY)
        #expect(UInt16(bigEndian: a.sin_port) == 8801)
    }

    @Test func parsesTailscaleStatus() {
        let json = #"{"Self":{"DNSName":"mac.taild56e9a.ts.net.","UserID":42},"User":{"42":{"LoginName":"me@x"}}}"#
        let r = RemoteAccess.LoginCache.parse(Data(json.utf8))
        #expect(r?.dns == "mac.taild56e9a.ts.net")
        #expect(r?.login == "me@x")
        #expect(RemoteAccess.LoginCache.parse(Data("{}".utf8)) == nil)
    }
}
