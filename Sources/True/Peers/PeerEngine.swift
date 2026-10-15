import Foundation
import CryptoKit

/// True ↔ True peers — the engine (Run 29). Receiver: take a validated job from a paired peer, run it as a real Claude
/// session in a worktree, report status + result back. Sender: hand jobs to peers, track them, deliver one line to the
/// lead. All state in JSON files under `root`; the outbox retries only while it has items (no idle timer).
final class PeerEngine: PeerHost, @unchecked Sendable {
    let root: URL
    let codes: PairingCodes
    let devices: DeviceStore
    private let launcher: PeerLauncher
    private let transport: PeerTransport
    private let inboundMode: @Sendable () -> PeerInboundMode
    private let selfURL: @Sendable () -> String?
    private let now: @Sendable () -> Date
    private let scheduler: @Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Void
    private let ownName: String

    private let lock = NSLock()
    private let work = DispatchQueue(label: "true.peers.work")
    private let net = DispatchQueue(label: "true.peers.net")
    private var links: [PeerLink]
    private var inbound: [InboundJob]
    private var sent: [SentJob]
    private var outbox: [OutboxItem]
    private var timerAt: Date?

    init(root: URL = PeerEngine.standardRoot, codes: PairingCodes, devices: DeviceStore, launcher: PeerLauncher,
         transport: PeerTransport, inboundMode: @escaping @Sendable () -> PeerInboundMode = { PeerInboundMode.current },
         selfURL: @escaping @Sendable () -> String?, ownName: String = Host.current().localizedName ?? "True",
         now: @escaping @Sendable () -> Date = { Date() },
         scheduler: (@Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Void)? = nil) {
        self.root = root; self.codes = codes; self.devices = devices; self.launcher = launcher; self.transport = transport
        self.inboundMode = inboundMode; self.selfURL = selfURL; self.now = now; self.ownName = ownName
        let q = DispatchQueue(label: "true.peers.timer")
        self.scheduler = scheduler ?? { d, f in q.asyncAfter(deadline: .now() + d, execute: f) }
        links = PeerEngine.load(root.appendingPathComponent("peers.json")) ?? []
        inbound = PeerEngine.load(root.appendingPathComponent("inbound.json")) ?? []
        sent = PeerEngine.load(root.appendingPathComponent("sent.json")) ?? []
        outbox = PeerEngine.loadOutbox(root)
    }

    static var standardRoot: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".true/peers", isDirectory: true) }

    /// Tests: wait for queued work (launches, then the outbox, then anything those queued).
    func drain() { work.sync {}; net.sync {}; work.sync {}; net.sync {} }

    // MARK: files

    private static func enc() -> JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; return e }
    private static func dec() -> JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d }
    private static func load<T: Decodable>(_ url: URL) -> T? { (try? Data(contentsOf: url)).flatMap { try? dec().decode(T.self, from: $0) } }
    private static func loadOutbox(_ root: URL) -> [OutboxItem] {
        let dir = root.appendingPathComponent("outbox")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.filter { $0.hasSuffix(".json") }.compactMap { load(dir.appendingPathComponent($0)) as OutboxItem? }
            .sorted { $0.nextAt < $1.nextAt }
    }

    /// 0600 file in a 0700 directory, created with the mode (never chmod-ed after) and renamed into place.
    static func write(_ data: Data, to url: URL) {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let tmp = dir.appendingPathComponent(".\(UUID().uuidString).tmp").path
        let fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { return }
        let ok = data.withUnsafeBytes { p -> Bool in
            var off = 0
            while off < p.count { let n = Foundation.write(fd, p.baseAddress! + off, p.count - off); if n <= 0 { return false }; off += n }
            return true
        }
        close(fd)
        if ok { rename(tmp, url.path) } else { unlink(tmp) }
    }

    private func saveLinks() { Self.write((try? Self.enc().encode(links)) ?? Data(), to: root.appendingPathComponent("peers.json")) }
    private func saveInbound() { Self.write((try? Self.enc().encode(inbound)) ?? Data(), to: root.appendingPathComponent("inbound.json")) }
    private func saveSent() { Self.write((try? Self.enc().encode(sent)) ?? Data(), to: root.appendingPathComponent("sent.json")) }
    private func outboxURL(_ id: String) -> URL { root.appendingPathComponent("outbox/\(id).json") }
    private func saveOutbox(_ i: OutboxItem) { Self.write((try? Self.enc().encode(i)) ?? Data(), to: outboxURL(i.id)) }
    func jobDir(_ jobId: String) -> URL { root.appendingPathComponent("jobs/\(jobId)", isDirectory: true) }
    func resultPath(_ jobId: String) -> String { jobDir(jobId).appendingPathComponent("result.md").path }
    private func changed() { NotificationCenter.default.post(name: .peersChanged, object: nil) }

    /// One line per finished inbound job. Brief TEXT is never here — only its hash.
    private func log(_ j: InboundJob) {
        let o: [String: Any] = ["time": Int(now().timeIntervalSince1970), "jobId": j.req.jobId, "peer": j.peerLabel, "repo": j.req.repo,
                                "mode": j.req.mode.rawValue, "inboundMode": j.inboundMode.rawValue,
                                "briefSha256": SHA256.hash(data: Data(j.req.brief.utf8)).map { String(format: "%02x", $0) }.joined(),
                                "flags": j.flags, "status": j.status.rawValue]
        guard var line = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]) else { return }
        line.append(10)
        let url = root.appendingPathComponent("jobs.jsonl")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(url.path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        guard fd >= 0 else { return }
        _ = line.withUnsafeBytes { Foundation.write(fd, $0.baseAddress!, $0.count) }
        close(fd)
    }

    // MARK: views for the UI / CLI

    func peerLinks() -> [PeerLink] { lock.lock(); defer { lock.unlock() }; return links }
    func inboundJobs() -> [InboundJob] { lock.lock(); defer { lock.unlock() }; return inbound.sorted { $0.received > $1.received } }
    func sentJobs() -> [SentJob] { lock.lock(); defer { lock.unlock() }; return sent.sorted { $0.created > $1.created } }
    func peerDevices() -> [PairedDevice] { devices.all.filter { $0.scope == .peer } }
    func outboxCount() -> Int { lock.lock(); defer { lock.unlock() }; return outbox.count }

    // MARK: pairing

    /// Receiver: the URL and a fresh 6-digit code to read out to a friend.
    func invite() -> (url: String?, code: String) { (selfURL(), codes.issue()) }

    /// Sender: pair with a friend's True. `label` is what we call them; `myName` is what they will call us.
    func pairAsSender(url: String, code: String, label: String, myName: String? = nil) -> Result<PeerLink, PeerError> {
        let base = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PeerValidate.validReplyURL(base) else { return .failure(.invalid("That address should look like https://name.ts.net:8444")) }
        guard !name.isEmpty, name.count <= 40, !PeerValidate.hasBadControl(name) else { return .failure(.invalid("Give them a name")) }
        let body = try? JSONSerialization.data(withJSONObject: ["code": code.trimmingCharacters(in: .whitespaces), "kind": "peer",
                                                                "label": String((myName ?? ownName).prefix(40))])
        let r = transport.post(baseURL: base, path: "/pair", bearer: nil, body: body ?? Data())
        switch r.status {
        case 200:
            guard let o = try? JSONSerialization.jsonObject(with: r.body) as? [String: Any], let tok = o["token"] as? String,
                  let login = o["login"] as? String, !login.isEmpty else { return .failure(.invalid("Their True didn't answer properly")) }
            let link = PeerLink(label: name, url: base.hasSuffix("/") ? String(base.dropLast()) : base, token: tok, receiverLogin: login)
            lock.lock(); links.removeAll { $0.label == name }; links.append(link); saveLinks(); lock.unlock()
            changed()
            return .success(link)
        case 0: return .failure(.invalid("Couldn't reach them. Is Remote Access on, and the Mac shared on Tailscale?"))
        case 429: return .failure(.invalid("Too many tries. Wait a minute."))
        case 403: return .failure(.invalid("They turned us away. Check Tailscale sharing."))
        default: return .failure(.invalid("That code didn't work. Ask for a fresh one."))
        }
    }

    func removeLink(_ label: String) { lock.lock(); links.removeAll { $0.label == label }; saveLinks(); lock.unlock(); changed() }

    // MARK: sender

    /// Hand a job to a paired peer. `repo` is a local path or a git remote URL. Returns the jobId.
    func delegate(peer: String, repo: String, title: String, brief: String, base: String = "main", mode: PeerMode = .pane,
                  fromAgent: String = "yahia") -> Result<String, PeerError> {
        lock.lock(); let link = links.first { $0.label.lowercased() == peer.lowercased() }; lock.unlock()
        guard let link else { return .failure(.invalid("No peer named \(peer)")) }
        guard let me = selfURL() else { return .failure(.invalid("Turn Remote Access on first, so they can answer you")) }
        var remote = repo
        if repo.hasPrefix("/") || repo.hasPrefix("~") || repo.hasPrefix(".") {
            let path = (repo as NSString).expandingTildeInPath
            guard let r = launcher.remoteURL(ofRepoAt: path) else { return .failure(.invalid("That folder has no git origin")) }
            remote = r
        }
        let id = UUID().uuidString.lowercased()
        let token = PeerValidate.newReplyToken()
        let req: [String: Any] = ["jobId": id, "title": title, "brief": brief, "repo": remote, "base": base, "mode": mode.rawValue,
                                  "fromAgent": fromAgent, "replyToken": token, "replyURL": me]
        guard let body = try? JSONSerialization.data(withJSONObject: req) else { return .failure(.invalid("bad job")) }
        if case .failure(let e) = PeerValidate.parseJob(body) { return .failure(e) }
        let t = now()
        let job = SentJob(jobId: id, peerLabel: link.label, peerLogin: link.receiverLogin, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                          repo: remote, base: base, mode: mode, fromAgent: fromAgent, tokenHash: PeerToken.hash(token),
                          status: .queued, note: "Sending", branch: nil, sha: nil, result: nil, created: t, updated: t)
        lock.lock(); sent.append(job); saveSent(); lock.unlock()
        enqueue(OutboxItem(id: UUID().uuidString, kind: .job, jobId: id, peerLabel: link.label, owner: nil, baseURL: link.url,
                           path: "/api/peer/job", bearer: link.token, body: body, attempt: 0, nextAt: t))
        changed()
        return .success(id)
    }

    func status(jobId: String?) -> [SentJob] { sentJobs().filter { jobId == nil || $0.jobId == jobId } }
    func result(jobId: String) -> SentJob? { sentJobs().first { $0.jobId == jobId } }

    // PeerHost (sender)
    func sentRef(jobId: String) -> (peerLogin: String, tokenHash: String)? {
        lock.lock(); defer { lock.unlock() }
        guard let j = sent.first(where: { $0.jobId == jobId }) else { return nil }
        return (j.peerLogin, j.tokenHash)
    }

    func receiveEvent(_ ev: PeerEvent) -> (status: Int, body: [String: Any]) {
        lock.lock()
        guard let i = sent.firstIndex(where: { $0.jobId == ev.jobId }) else { lock.unlock(); return (404, ["error": "unknown job"]) }
        if !sent[i].status.isFinal {
            sent[i].status = ev.status; sent[i].note = ev.note; sent[i].updated = now()
            if let b = ev.branch { sent[i].branch = b }
            if let s = ev.sha { sent[i].sha = s }
            if let r = ev.result { sent[i].result = r }
            saveSent()
        }
        let j = sent[i]
        lock.unlock()
        changed()
        if j.status == .done || j.status == .failed, ev.status == j.status {
            let branch = j.branch ?? PeerNaming.branch(label: j.peerLabel, jobId: j.jobId)
            launcher.deliverLine(agent: j.fromAgent, line: PeerText.doneLine(label: j.peerLabel, title: j.title, status: j.status, branch: branch,
                                                                              resultPath: "true-peer result \(j.jobId)"))
        }
        return (200, ["jobId": j.jobId, "status": j.status.rawValue])
    }

    // MARK: outbox

    private func enqueue(_ item: OutboxItem) {
        lock.lock(); outbox.append(item); saveOutbox(item); lock.unlock()
        net.async { [self] in pump() }
    }

    /// Try everything due now; schedule one timer for the earliest of the rest. No items → no timer.
    func pump() {
        while true {
            lock.lock()
            let due = outbox.filter { $0.nextAt <= now() }.sorted { $0.nextAt < $1.nextAt }.first
            lock.unlock()
            guard let item = due else { break }
            let r = transport.post(baseURL: item.baseURL, path: item.path, bearer: item.bearer, body: item.body)
            lock.lock()
            guard let idx = outbox.firstIndex(where: { $0.id == item.id }) else { lock.unlock(); continue }   // revoked meanwhile
            if (200..<300).contains(r.status) {
                outbox.remove(at: idx); try? FileManager.default.removeItem(at: outboxURL(item.id))
                if item.kind == .job, let s = sent.firstIndex(where: { $0.jobId == item.jobId }), sent[s].status == .queued {
                    sent[s].note = "Delivered"; sent[s].updated = now(); saveSent()
                }
            } else if r.status == 0 || r.status == 429 || r.status >= 500 {
                outbox[idx].nextAt = now().addingTimeInterval(PeerBackoff.delay(attempt: item.attempt))
                outbox[idx].attempt += 1
                saveOutbox(outbox[idx])
            } else {     // refused for good: a 4xx won't change by retrying
                outbox.remove(at: idx); try? FileManager.default.removeItem(at: outboxURL(item.id))
                if item.kind == .job, let s = sent.firstIndex(where: { $0.jobId == item.jobId }), !sent[s].status.isFinal {
                    sent[s].status = .failed; sent[s].updated = now()
                    sent[s].note = r.status == 409 ? "They already have that job" : r.status == 403 || r.status == 401 ? "They turned this job away" : "They refused this job"
                    saveSent()
                }
            }
            lock.unlock()
            changed()
        }
        lock.lock()
        let next = outbox.map(\.nextAt).min()
        let pending = timerAt
        lock.unlock()
        guard let next else { lock.lock(); timerAt = nil; lock.unlock(); return }
        if let pending, pending <= next, pending > now() { return }
        lock.lock(); timerAt = next; lock.unlock()
        scheduler(max(1, next.timeIntervalSince(now()))) { [weak self] in
            guard let self else { return }
            self.lock.lock(); self.timerAt = nil; self.lock.unlock()
            self.net.async { self.pump() }
        }
    }

    /// Remote Access just started: anything stuck goes out now.
    func flush() {
        lock.lock()
        for i in outbox.indices { outbox[i].nextAt = now() }
        lock.unlock()
        net.async { [self] in pump() }
    }

    // MARK: receiver

    func receiveJob(_ job: PeerJobRequest, from device: PairedDevice) -> (status: Int, body: [String: Any]) {
        lock.lock()
        if let ex = inbound.first(where: { $0.req.jobId == job.jobId }) {
            lock.unlock()
            return ex.deviceId == device.id ? (202, ["jobId": ex.req.jobId, "status": ex.status.rawValue]) : (409, ["error": "job id taken"])
        }
        let mode = inboundMode()
        let screened = InjectionScreen.screen(job.title + "\n" + job.brief)
        let j = InboundJob(req: job, peerLabel: device.label, deviceId: device.id, status: mode == .ask ? .queued : .accepted,
                           note: mode == .ask ? "Waiting for you" : "Starting", inboundMode: mode, flags: screened.reasons,
                           received: now(), finished: nil, branch: PeerNaming.branch(label: device.label, jobId: job.jobId))
        inbound.append(j); saveInbound()
        lock.unlock()
        let dir = jobDir(job.jobId)
        Self.write(Data(job.brief.utf8), to: dir.appendingPathComponent("brief.md"))
        Self.write((try? Self.enc().encode(j)) ?? Data(), to: dir.appendingPathComponent("job.json"))
        changed()
        if mode == .ask {
            report(j, .needsYou, "Waiting for them to accept")
        } else {
            work.async { [self] in run(job.jobId, flags: mode.claudeFlags) }
        }
        return (202, ["jobId": job.jobId, "status": j.status.rawValue])
    }

    private func update(_ jobId: String, _ f: (inout InboundJob) -> Void) -> InboundJob? {
        lock.lock(); defer { lock.unlock() }
        guard let i = inbound.firstIndex(where: { $0.req.jobId == jobId }) else { return nil }
        f(&inbound[i]); saveInbound()
        return inbound[i]
    }

    func accept(_ jobId: String) {
        guard let j = inboundJobs().first(where: { $0.id == jobId }), j.status == .queued else { return }
        _ = update(jobId) { $0.status = .accepted; $0.note = "Starting" }
        changed()
        work.async { [self] in run(jobId, flags: PeerInboundMode.ask.claudeFlags) }
    }

    func decline(_ jobId: String) {
        guard let j = inboundJobs().first(where: { $0.id == jobId }), j.status == .queued else { return }
        end(jobId, .declined, "Declined", reportAs: .failed)
    }

    private func run(_ jobId: String, flags: [String]) {
        guard let j = inboundJobs().first(where: { $0.id == jobId }), !j.status.isFinal else { return }
        let label = j.peerLabel
        guard let clone = launcher.resolveClone(repo: j.req.repo) else {
            end(jobId, .failed, "No local clone of \(j.req.repo)", reportAs: .failed); return
        }
        let wt = PeerNaming.worktree(clone: clone, jobId: jobId)
        if let err = launcher.prepareWorktree(clone: clone, base: j.req.base, branch: j.branch, worktree: wt) {
            end(jobId, .failed, err, reportAs: .failed); return
        }
        let dir = jobDir(jobId)
        let resultP = resultPath(jobId)
        let envelope = PeerText.envelope(label: label, job: j.req, branch: j.branch, worktree: wt, resultPath: resultP)
        let role = PeerText.roleCard(label: label, branch: j.branch, worktree: wt, resultPath: resultP)
        Self.write(Data(envelope.utf8), to: dir.appendingPathComponent("envelope.md"))
        Self.write(Data(role.utf8), to: dir.appendingPathComponent("role.md"))
        let name = PeerNaming.agentName(label: label, jobId: jobId)
        var pane: UUID?, builder: String?
        switch j.req.mode {
        case .pane:
            pane = launcher.launchPane(agentName: name, label: label, cwd: wt, flags: flags, rolePath: dir.appendingPathComponent("role.md").path,
                                       firstPrompt: PeerText.firstPrompt(envelopePath: dir.appendingPathComponent("envelope.md").path))
            if pane == nil { end(jobId, .failed, "Couldn't open a tab for the job", reportAs: .failed); return }
        case .background:
            if let err = launcher.launchBackground(agentName: name, parent: PeerNaming.parentName(label: label), cwd: wt,
                                                   prompt: PeerText.firstPrompt(envelopePath: dir.appendingPathComponent("envelope.md").path)) {
                end(jobId, .failed, err, reportAs: .failed); return
            }
            builder = name
        }
        if let u = update(jobId, { $0.clone = clone; $0.worktree = wt; $0.pane = pane; $0.builder = builder; $0.note = "Started" }) {
            report(u, .accepted, "Started")
        }
        changed()
    }

    // MARK: receiver — hook events

    /// A pane hook fired. Report only when the status actually changes; final states are sticky.
    func paneEvent(pane: UUID, kind: PeerEventMap.Kind) {
        lock.lock(); let j = inbound.first { $0.pane == pane && !$0.status.isFinal }; lock.unlock()
        guard let j else { return }
        let exists = FileManager.default.fileExists(atPath: resultPath(j.id))
        guard let s = PeerEventMap.status(kind, resultExists: exists), s != j.status else { return }
        if s == .done || s == .failed { end(j.id, s, s == .done ? "Finished" : "Hit an error", reportAs: s); return }
        if let u = update(j.id, { $0.status = s; $0.note = s == .working ? "Working" : s == .needsYou ? "Needs you" : "Waiting" }) {
            report(u, s, u.note)
        }
        changed()
    }

    func paneClosed(pane: UUID) {
        lock.lock(); let j = inbound.first { $0.pane == pane && !$0.status.isFinal }; lock.unlock()
        guard let j else { return }
        if FileManager.default.fileExists(atPath: resultPath(j.id)) { end(j.id, .done, "Finished", reportAs: .done) }
        else { end(j.id, .failed, "Closed before it finished", reportAs: .failed) }
    }

    /// Builder state changed (the Hub's builder list). `running == false` means it ended.
    func builderUpdate(name: String, running: Bool) {
        lock.lock(); let j = inbound.first { $0.builder == name && !$0.status.isFinal }; lock.unlock()
        guard let j else { return }
        if running {
            guard j.status != .working else { return }
            if let u = update(j.id, { $0.status = .working; $0.note = "Working" }) { report(u, .working, "Working") }
            changed()
        } else if FileManager.default.fileExists(atPath: resultPath(j.id)) {
            end(j.id, .done, "Finished", reportAs: .done)
        } else {
            end(j.id, .failed, "Ended without a result", reportAs: .failed)
        }
    }

    // MARK: receiver — finishing

    private func end(_ jobId: String, _ status: PeerStatus, _ note: String, reportAs: PeerStatus) {
        guard let u = update(jobId, { $0.status = status; $0.note = note; $0.finished = now() }) else { return }
        var final = u
        if status == .done, let wt = u.worktree, let sha = launcher.headSHA(worktree: wt) {
            final = update(jobId) { $0.sha = sha } ?? u
        }
        log(final)
        report(final, reportAs, note)
        changed()
    }

    private func report(_ j: InboundJob, _ s: PeerStatus, _ note: String) {
        var o: [String: Any] = ["jobId": j.req.jobId, "status": s.rawValue, "note": String(note.prefix(PeerValidate.maxNote))]
        if s == .done || s == .failed { o["branch"] = j.branch }
        if s == .done {
            if let sha = j.sha { o["sha"] = sha }
            if let d = try? Data(contentsOf: URL(fileURLWithPath: resultPath(j.id))) {
                o["result"] = String(String(decoding: d.prefix(PeerValidate.maxResult * 2), as: UTF8.self).prefix(PeerValidate.maxResult))
            }
        }
        guard let body = try? JSONSerialization.data(withJSONObject: o) else { return }
        enqueue(OutboxItem(id: UUID().uuidString, kind: .event, jobId: j.req.jobId, peerLabel: j.peerLabel, owner: j.deviceId.uuidString,
                           baseURL: j.req.replyURL, path: "/api/peer/event", bearer: j.req.replyToken, body: body, attempt: 0, nextAt: now()))
    }

    // MARK: kill switches

    /// Revoke a peer: its token dies at once, its queued (unaccepted) jobs and unsent events are dropped.
    func revoke(deviceId: UUID) {
        devices.revoke(deviceId)
        lock.lock()
        let dropped = outbox.filter { $0.owner == deviceId.uuidString }
        outbox.removeAll { $0.owner == deviceId.uuidString }
        for d in dropped { try? FileManager.default.removeItem(at: outboxURL(d.id)) }
        for i in inbound.indices where inbound[i].deviceId == deviceId && inbound[i].status == .queued {
            inbound[i].status = .declined; inbound[i].note = "Peer removed"; inbound[i].finished = now(); log(inbound[i])
        }
        saveInbound()
        lock.unlock()
        changed()
    }

    /// End every running peer job cleanly (panes closed, builders stopped) and decline the waiting ones.
    func stopAll() {
        lock.lock()
        let live = inbound.filter { !$0.status.isFinal }
        lock.unlock()
        launcher.stop(panes: live.compactMap(\.pane), builders: live.compactMap(\.builder))
        for j in live { end(j.id, j.status == .queued ? .declined : .failed, "Stopped on this Mac", reportAs: .failed) }
    }
}
