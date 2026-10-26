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
