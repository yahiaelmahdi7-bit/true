import Foundation

/// What the server needs from the peers engine. Kept a protocol so the server tests run without the real engine.
protocol PeerHost: AnyObject, Sendable {
    /// Receiver: a validated job from a paired peer device. Returns the HTTP status and JSON body.
    func receiveJob(_ job: PeerJobRequest, from device: PairedDevice) -> (status: Int, body: [String: Any])
    /// Sender: who may report on this job (the peer's login + SHA-256 of the reply token we handed out).
    func sentRef(jobId: String) -> (peerLogin: String, tokenHash: String)?
    /// Sender: a status/result event for a job we sent (already authorized).
    func receiveEvent(_ event: PeerEvent) -> (status: Int, body: [String: Any])
}

struct PeerEvent: Codable, Equatable, Sendable {
    var jobId: String
    var status: PeerStatus
    var note: String
    var branch: String?
    var sha: String?
    var result: String?

    static let maxBodyBytes = 24 * 1024

    static func parse(_ data: Data) -> PeerEvent? {
        guard data.count <= maxBodyBytes,
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = o["jobId"] as? String, UUID(uuidString: id) != nil,
              let st = (o["status"] as? String).flatMap(PeerStatus.init), PeerStatus.wire.contains(st) else { return nil }
        let note = String((o["note"] as? String ?? "").prefix(PeerValidate.maxNote))
        let result = (o["result"] as? String).map { String($0.prefix(PeerValidate.maxResult)) }
        guard !PeerValidate.hasBadControl(note), result.map({ !PeerValidate.hasBadControl($0) }) ?? true else { return nil }
        func short(_ k: String) -> String? { (o[k] as? String).map { String($0.prefix(200)) } }
        return PeerEvent(jobId: id.lowercased(), status: st, note: note, branch: short("branch"), sha: short("sha"), result: result)
    }
}

extension RemoteServer {
    static func isPeerPair(_ req: HTTPRequest) -> Bool {
        (try? JSONSerialization.jsonObject(with: Data(req.body)) as? [String: Any])?["kind"] as? String == "peer"
    }

    private func deny(_ fd: Int32, _ d: RemoteAuth.Decision, _ req: HTTPRequest) {
        switch d {
        case .forbidden(let why):
            Self.peerLog("deny 403 \(req.path): \(why)")
            plain(fd, 403, "Forbidden", "Forbidden")
        case .needsPairing:
            Self.peerLog("deny 401 \(req.path)")
            plain(fd, 401, "Unauthorized", "Not paired")
        case .allow: break
        }
    }

    private static func peerLog(_ s: String) { NSLog("peers: %@", s) }

    /// POST /pair {"code","kind":"peer","label"} → {"token","login"}. The caller is another tailnet user: their login
    /// header is REQUIRED (fail closed) and recorded on the device; later requests must carry the same one.
    func handlePeerPair(_ fd: Int32, _ req: HTTPRequest) {
        guard peerHost != nil else { plain(fd, 404, "Not Found", "Not found"); return }
        guard let login = req.header(RemoteAuth.loginHeader)?.lowercased(), !login.isEmpty,
              RemoteAuth.hostMatches(host: req.header("host"), dnsName: dnsName()),
              req.header("origin") == nil || RemoteAuth.originMatches(origin: req.header("origin"), dnsName: dnsName()) else {
            Self.peerLog("deny 403 /pair peer: identity/host"); plain(fd, 403, "Forbidden", "Forbidden"); return
        }
        let o = (try? JSONSerialization.jsonObject(with: Data(req.body)) as? [String: Any]) ?? [:]
        let label = String(((o["label"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !label.isEmpty, !PeerValidate.hasBadControl(label), !label.contains("\n") else {
            json(fd, 400, "Bad Request", ["error": "Need a label"]); return
        }
        switch peerCodes.attempt((o["code"] as? String) ?? "") {
        case .ok:
            let token = devices.pair(label: label, scope: .peer, login: login)
            Self.peerLog("paired peer \(label)")
            json(fd, 200, "OK", ["token": token, "login": allowedLogin() ?? ""])
        case .rateLimited:
            json(fd, 429, "Too Many Requests", ["error": "Too many tries. Wait a minute."], extra: ["Retry-After": "60"])
        case .burned:
            json(fd, 401, "Unauthorized", ["error": "Code burned. Show a new one."])
        case .wrong, .expired:
            json(fd, 401, "Unauthorized", ["error": "That code didn't work. Show a fresh one."])
        }
    }

    /// Streamed JSON body, capped; nil after a 4xx/408 has been sent.
    private func peerBody(_ fd: Int32, _ req: HTTPRequest, max: Int) -> Data? {
        let len = req.declaredLength
        guard len > 0 else { plain(fd, 400, "Bad Request", "Send JSON"); return nil }
        guard len <= max else { plain(fd, 413, "Payload Too Large", "Too large"); return nil }
        var body = Array(req.body.prefix(len))
        if DropReceiver.pump(fd, have: body.count, total: len, deadline: HTTPRequest.bodyDeadline, sink: { body += $0; return true }) != .ok {
            plain(fd, 408, "Request Timeout", "Too slow"); return nil
        }
        return Data(body)
    }

    /// /api/peer/job (peer device token) and /api/peer/event (the job's reply token). No Origin is fine; a present one
    /// must be exact. A phone/full/dropOnly token is 403 here, a peer token is 403 everywhere else.
    func handlePeer(_ fd: Int32, _ req: HTTPRequest) {
        guard let host = peerHost, req.method == "POST", req.path == "/api/peer/job" || req.path == "/api/peer/event" else {
            plain(fd, 404, "Not Found", "Not found"); return
        }
        let bearer = RemoteAuth.bearerToken(req.header("authorization"))
        let login = req.header(RemoteAuth.loginHeader)
        if req.path == "/api/peer/job" {
            let device = devices.validate(bearer)
            let d = PeerAuth.decide(loginHeader: login, expectedLogin: device?.login, host: req.header("host"),
                                    origin: req.header("origin"), dnsName: dnsName(), tokenValid: device != nil,
                                    scopeOK: device?.scope == .peer)
            guard d == .allow, let device else { deny(fd, d, req); return }
            guard let data = peerBody(fd, req, max: PeerValidate.maxBodyBytes) else { return }
            switch PeerValidate.parseJob(data) {
            case .failure(.invalid(let why)): json(fd, 400, "Bad Request", ["error": why])
            case .success(let job):
                let r = host.receiveJob(job, from: device)
                json(fd, r.status, r.status == 202 ? "Accepted" : "Error", r.body)
            }
            return
        }
        // Event: the bearer is the per-job reply token, so the job is named in the body before we can check it.
        guard login?.isEmpty == false, RemoteAuth.hostMatches(host: req.header("host"), dnsName: dnsName()),
              req.header("origin") == nil || RemoteAuth.originMatches(origin: req.header("origin"), dnsName: dnsName()) else {
            deny(fd, .forbidden("identity/host"), req); return
        }
        guard bearer != nil else { deny(fd, .needsPairing, req); return }
        guard let data = peerBody(fd, req, max: PeerEvent.maxBodyBytes) else { return }
        guard let ev = PeerEvent.parse(data) else { json(fd, 400, "Bad Request", ["error": "bad event"]); return }
        let ref = host.sentRef(jobId: ev.jobId)
        let d = PeerAuth.decide(loginHeader: login, expectedLogin: ref?.peerLogin, host: req.header("host"),
                                origin: req.header("origin"), dnsName: dnsName(),
                                tokenValid: ref.map { PeerToken.verify(bearer, storedHash: $0.tokenHash) } ?? false, scopeOK: true)
        guard d == .allow else { deny(fd, ref == nil ? .forbidden("unknown job") : d, req); return }
        let r = host.receiveEvent(ev)
        json(fd, r.status, r.status == 200 ? "OK" : "Error", r.body)
    }
}
