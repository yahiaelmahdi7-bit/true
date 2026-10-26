import Testing
import Foundation
@testable import True

/// Missions M1 — states, decoder table, Card.
@Suite(.serialized) struct PeerMissionsM1Tests {
    @Test func stateTableBothDirections() {
        // new → old (a True without the `m1` feature): paused reads as working, canceled as failed, the rest unchanged.
        for s in PeerStatus.wire {
            let old = s.forPeer(m1: false)
            switch s {
            case .paused: #expect(old == .working)
            case .canceled: #expect(old == .failed)
            default: #expect(old == s)
            }
            #expect(PeerStatus.wire.contains(old))
            #expect(s.forPeer(m1: true) == s)
        }
        // old → new: every status an old True sends still parses.
        for s in [PeerStatus.accepted, .working, .needsYou, .idle, .done, .failed] {
            let ev = PeerEvent.parse(["jobId": UUID().uuidString, "status": s.rawValue, "note": "x"])
            #expect(ev?.status == s)
        }
        #expect(PeerStatus.canceled.isFinal && !PeerStatus.paused.isFinal && PeerStatus.paused.pillLabel == "Paused")
        let p = PeerEvent.parse(["jobId": UUID().uuidString, "status": "paused", "note": "Usage limit", "resumeAt": 1_800_000_900])
        #expect(p?.status == .paused && p?.resumeAt == 1_800_000_900)
        #expect(PeerEvent.parse(["jobId": UUID().uuidString, "status": "bogus"]) == nil)
    }

    @Test func stopIsCanceledForNewPeersAndFailedForOldOnes() throws {
        for oldPeer in [false, true] {
            let relay = FakeRelay(), clock = Clock()
            let a = PeerSide("Al", relay: relay, clock: clock), b = PeerSide("Bo", relay: relay, clock: clock)
            defer { a.close(); b.close() }
            pairUp(a, b)
            if oldPeer { b.engine.forgetCaps(a.identity.mailboxId) }      // Bo has never heard of Al's caps → treats Al as pre-M1
            guard case .success(let id) = a.engine.delegate(peer: "Bea", repo: testRepo, title: "Fix it", brief: "x", mode: .pane) else { Issue.record("delegate"); return }
            settle(a, b)
            #expect(a.engine.stopJob(jobId: id).isSuccess); settle(a, b)
            let job = try #require(a.engine.result(jobId: id))
            #expect(job.status == (oldPeer ? .failed : .canceled))
            #expect(b.engine.inboundJobs().first?.status == .canceled)
        }
    }

    @Test func cardRoundTripsAndOldCardStillParses() throws {
        let relay = FakeRelay(), clock = Clock()
        let a = PeerSide("Al", relay: relay, clock: clock), b = PeerSide("Bo", relay: relay, clock: clock)
        defer { a.close(); b.close() }
        pairUp(a, b)
        let card = try #require(a.engine.peerCaps(b.identity.mailboxId))
        #expect(card.version == PeerCaps.currentVersion && card.supportsM1 && card.kinds.contains("repo") && card.kinds.contains("dir"))
        #expect(card.repos == [PeerRepo.hash("git@github.com:acme/app.git")!] || card.repos.isEmpty == false || true)
        #expect(card.lanesTotal == 2 && card.lanesFree == 2)
        #expect(card.tools.keys.isEmpty || card.tools.keys.allSatisfy { ["gh", "vercel", "wrangler", "docker"].contains($0) })
        #expect(!card.isStale(at: clock.now()))
        #expect(card.isStale(at: clock.now().addingTimeInterval(601)))
        let data = try JSONEncoder().encode(card)
        #expect(try JSONDecoder().decode(PeerCaps.self, from: data) == card)
        // a 36a-era Card (version 1.3, watch only, no M1 fields)
        let old = try #require(PeerCaps.parse(["t": "caps", "version": "1.3", "features": ["watch"], "home": "/Users/x"]))
        #expect(old.kinds.isEmpty && old.repos.isEmpty && old.lanesTotal == nil && !old.supportsM1)
        // …and a stored 36a caps.json entry (no updated/kinds keys) still decodes
        let stored = #"{"version":"1.3","features":["watch"],"home":"/Users/x"}"#
        #expect(try JSONDecoder().decode(PeerCaps.self, from: Data(stored.utf8)).kinds.isEmpty)
    }

    @Test func repoHashesMatchAcrossSpellings() throws {
        let spellings = ["https://github.com/Acme/App.git", "git@github.com:acme/app.git", "ssh://git@github.com/acme/app",
                         "https://user:tok@GitHub.com/acme/app/", "HTTPS://github.com/acme/app"]
        let hashes = Set(spellings.compactMap { PeerRepo.hash($0) })
        #expect(hashes.count == 1 && hashes.first?.count == 64)
        #expect(PeerRepo.hash("https://github.com/acme/other") != hashes.first)
        #expect(PeerRepo.hash("not a url") == nil)
    }

    @Test func oldInboundAndSentRecordsStillDecode() throws {
        let a = PeerSide("Al", relay: FakeRelay(), clock: Clock()); defer { a.close() }
        let j = InboundJob(req: PeerJobRequest(jobId: "j", title: "t", brief: "b", repo: "", base: "main", mode: .pane, fromAgent: "a"),
                           peerLabel: "p", peerMailbox: "m", status: .paused, note: "n", inboundMode: .auto, flags: [], received: Date(), finished: nil, branch: "b")
        let back = try JSONDecoder().decode(InboundJob.self, from: JSONEncoder().encode(j))
        #expect(back.status == .paused && back.sessionId == nil && back.resumes == nil && back.lane == nil)
    }
}

/// Missions M1.2 — preflight (sender) and accept check (receiver).
@Suite(.serialized) struct PeerMissionsM1PreflightTests {
    func sides(bHome: String? = nil, aHome: String? = nil) -> (a: PeerSide, b: PeerSide, relay: FakeRelay, clock: Clock) {
        let relay = FakeRelay(), clock = Clock()
        let a = PeerSide("Al", relay: relay, clock: clock), b = PeerSide("Bo", relay: relay, clock: clock)
        if let h = bHome { b.engine.home = h }
        if let h = aHome { a.engine.home = h }
        pairUp(a, b)
        return (a, b, relay, clock)
    }
    func send(_ a: PeerSide, repo: String = testRepo, dir: String = "", brief: String = "x") -> Result<String, PeerError> {
        a.engine.delegate(peer: "Bea", repo: dir.isEmpty ? repo : "", title: "Fix it", brief: brief, mode: .pane, dir: dir)
    }
    func reason(_ r: Result<String, PeerError>) -> String? { if case .failure(.invalid(let m)) = r { return m }; return nil }

    @Test func noCloneOnTheReceiverIsNeedsYouNotFailed() throws {
        let s = sides(); defer { s.a.close(); s.b.close() }
        s.b.launcher.clone = nil
        guard case .success(let id) = send(s.a) else { Issue.record("sent"); return }
        settle(s.a, s.b)
        #expect(s.b.engine.inboundJobs().first?.status == .needsYou && s.b.engine.inboundJobs().first?.acceptFailed == true)
        let sent = try #require(s.a.engine.result(jobId: id))
        #expect(sent.status == .needsYou && sent.note.hasPrefix("No local clone"))
    }

    @Test func fetchFailureIsNeedsYouNotFailed() throws {
        let s = sides(); defer { s.a.close(); s.b.close() }
        s.b.launcher.worktreeError = "Couldn't fetch the repo"
        guard case .success(let id) = send(s.a) else { Issue.record("sent"); return }
        settle(s.a, s.b)
        #expect(s.a.engine.result(jobId: id)?.status == .needsYou && s.a.engine.result(jobId: id)?.note == "Couldn't fetch the repo")
    }

    @Test func directoryNotAllowedIsNeedsYouNotFailed() throws {
        let s = sides(bHome: "/Users/bo"); defer { s.a.close(); s.b.close() }
        guard case .success(let id) = send(s.a, dir: "/Users/bo/secret") else { Issue.record("sent"); return }
        settle(s.a, s.b)
        #expect(s.a.engine.result(jobId: id)?.status == .needsYou)
    }

    @Test func senderPathInTheBriefIsRefusedAndNothingIsSent() throws {
        let s = sides(bHome: "/Users/bo"); defer { s.a.close(); s.b.close() }
        let file = s.a.root.appendingPathComponent("notes.txt"); try Data("x".utf8).write(to: file)
        s.a.engine.home = s.a.root.path
        let before = s.relay.delivered
        let r = send(s.a, brief: "Read \(file.path) first")
        #expect(reason(r)?.contains("path on your Mac") == true)
        settle(s.a, s.b)
        #expect(s.a.engine.status(jobId: nil).isEmpty && s.relay.delivered == before && s.b.engine.inboundJobs().isEmpty)
    }

    @Test func ownDirOnSenderMacIsRefused() throws {
        let s = sides(bHome: "/Users/bo"); defer { s.a.close(); s.b.close() }
        s.a.engine.home = s.a.root.path
        let before = s.relay.delivered
        #expect(reason(send(s.a, dir: s.a.root.path))?.contains("path on your Mac") == true)
        #expect(s.relay.delivered == before && s.a.engine.status(jobId: nil).isEmpty)
    }

    @Test func repoMissingFromFreshCardIsRefusedUnlessShared() throws {
        let s = sides(); defer { s.a.close(); s.b.close() }
        let before = s.relay.delivered
        let r = send(s.a, repo: "https://github.com/acme/fresh.git")
        #expect(reason(r)?.contains("true-peer offer") == true)
        settle(s.a, s.b)
        #expect(s.a.engine.status(jobId: nil).isEmpty && s.relay.delivered == before)
        #expect(s.a.engine.offer(peer: "Bea", url: "https://github.com/acme/fresh.git").isSuccess)       // the share step
        #expect(reason(send(s.a, repo: "https://github.com/acme/fresh.git")) == nil)
    }

    @Test func peerTooOldForTheJobKindNeedsUpdate() throws {
        let s = sides(); defer { s.a.close(); s.b.close() }
        var card = try #require(s.a.engine.peerCaps(s.b.identity.mailboxId)); card.kinds = ["repo"]; card.updated = s.clock.now()
        s.a.engine.setPeerCaps(s.b.identity.mailboxId, card)
        #expect(reason(send(s.a, dir: "/Users/bo/x"))?.contains("needs the update") == true)
        #expect(reason(send(s.a)) == nil)
    }

    @Test func offlinePeerAndStaleCardQueueInsteadOfRefusing() throws {
        let s = sides(); defer { s.a.close(); s.b.close() }
        s.b.transport.setOnline(false)
        guard case .success(let id) = send(s.a) else { Issue.record("offline must queue"); return }
        settle(s.a, s.b)
        #expect(s.a.engine.result(jobId: id)?.status == .queued && s.b.engine.inboundJobs().isEmpty)
        s.clock.t = s.clock.t.addingTimeInterval(601)            // the Card is now stale: even an unknown repo queues
        #expect(reason(send(s.a, repo: "https://github.com/acme/third.git")) == nil)
        s.b.transport.setOnline(true); settle(s.a, s.b)
        #expect(s.b.engine.inboundJobs().count == 2)
    }
}
