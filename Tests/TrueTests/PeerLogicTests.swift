import Testing
import Foundation
@testable import True

struct PeerLogicTests {
    static let id = "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0"
    static func body(_ patch: [String: Any] = [:], drop: [String] = []) -> Data {
        var o: [String: Any] = ["jobId": id, "title": "Fix the thing", "brief": "Please fix X.\n\tIndented.", "repo": "git@github.com:Acme/App.git",
                                "base": "main", "mode": "pane", "fromAgent": "lead", "replyToken": PeerValidate.newReplyToken(),
                                "replyURL": "https://yahia-mac.tail1234.ts.net:8444"]
        for (k, v) in patch { o[k] = v }
        for k in drop { o[k] = nil }
        return try! JSONSerialization.data(withJSONObject: o)
    }

    @Test func validJobParses() throws {
        let j = try PeerValidate.parseJob(Self.body()).get()
        #expect(j.jobId == Self.id.lowercased() && j.mode == .pane && j.base == "main")
        let d = try PeerValidate.parseJob(Self.body(drop: ["base"])).get()
        #expect(d.base == "main")
    }

    @Test func validationRejects() {
        func bad(_ p: [String: Any] = [:], drop: [String] = []) -> Bool {
            if case .failure = PeerValidate.parseJob(Self.body(p, drop: drop)) { return true }; return false
        }
        #expect(bad(["jobId": "nope"]))
        #expect(bad(["title": ""]))
        #expect(bad(["title": String(repeating: "a", count: 121)]))
        #expect(bad(["title": "two\nlines"]))
        #expect(bad(["brief": "has \u{1B}[31m escape"]))
        #expect(bad(["brief": "nul \u{0} byte"]))
        #expect(bad(["brief": String(repeating: "a", count: PeerValidate.maxBrief + 1)]))
        #expect(bad(["repo": "not a url"]))
        #expect(bad(["repo": "file:///etc/passwd"]))
        #expect(bad(["base": "--upload-pack=x"]))
        #expect(bad(["base": "a..b"]))
        #expect(bad(["mode": "shell"]))
        #expect(bad(["replyToken": "short"]))
        #expect(bad(["replyURL": "http://x.ts.net:8444"]))
        #expect(bad(["replyURL": "https://evil.example.com:8444"]))
        #expect(bad(["replyURL": "https://x.ts.net:443"]))
        #expect(bad(["replyURL": "https://x.ts.net:8444/steal"]))
        #expect(bad(drop: ["brief"]))
        #expect(!bad(["title": String(repeating: "a", count: 120)]))
        #expect(!bad(["brief": "tab\tand\nnewline"]))
    }

    @Test func repoNormalizationFixtures() {
        let want = "github.com/acme/App"
        for u in ["https://github.com/acme/App", "https://GitHub.com/acme/App.git", "git@github.com:acme/App.git",
                  "ssh://git@github.com/acme/App.git", "https://user@github.com/acme/App/", "ssh://git@github.com:22/acme/App"] {
            #expect(PeerRepo.normalize(u) == want, "\(u)")
        }
        #expect(PeerRepo.normalize("https://github.com/acme") == nil)
        #expect(PeerRepo.normalize("github.com/acme/App") == nil)
        #expect(PeerRepo.normalize("") == nil)
        #expect(PeerRepo.same("git@github.com:Acme/App.git", "https://github.com/Acme/App"))
        #expect(!PeerRepo.same("git@github.com:Acme/App.git", "https://github.com/Acme/Other"))
        #expect(PeerRepo.name("git@github.com:Acme/App.git") == "App")
    }

    @Test func repoResolutionPicksTheMatchingClone() {
        let origins = ["/r/a": "https://github.com/x/a.git", "/r/b": "git@github.com:acme/app.git"]
        #expect(PeerRepo.resolve(repo: "https://github.com/acme/app", candidates: ["/r/a", "/r/b"], originOf: { origins[$0] }) == "/r/b")
        #expect(PeerRepo.resolve(repo: "https://github.com/none/none", candidates: ["/r/a", "/r/b"], originOf: { origins[$0] }) == nil)
    }

    @Test func namingIsStable() {
        #expect(PeerNaming.shortId(Self.id) == "0f1e2d3c")
        #expect(PeerNaming.slug("Sam's Mac!") == "sam-s-mac")
        #expect(PeerNaming.slug("!!!") == "peer")
        #expect(PeerNaming.branch(label: "Sam", jobId: Self.id) == "peer/sam/0f1e2d3c")
        #expect(PeerNaming.agentName(label: "Sam", jobId: Self.id) == "peer-sam-0f1e2d3c")
        #expect(PeerNaming.worktree(clone: "/Users/f/Projects/app", jobId: Self.id) == "/Users/f/Projects/app.peers/0f1e2d3c")
        #expect(PeerNaming.fetchCommand(branch: "peer/sam/0f1e2d3c") == "git fetch origin peer/sam/0f1e2d3c && git checkout peer/sam/0f1e2d3c")
    }

    @Test func envelopeQuotesTheBriefAndRoleCardIsShort() throws {
        let j = try PeerValidate.parseJob(Self.body()).get()
        let e = PeerText.envelope(label: "Sam", job: j, branch: "peer/sam/0f1e2d3c", worktree: "/w", resultPath: "/r/result.md")
        let begin = try #require(e.range(of: PeerText.beginMark)), end = try #require(e.range(of: PeerText.endMark))
        #expect(begin.upperBound < end.lowerBound)
        #expect(e[begin.upperBound..<end.lowerBound].contains("Please fix X."))
        #expect(e.contains("Sam's True") && e.contains("push branch peer/sam/0f1e2d3c"))
        let c = PeerText.roleCard(label: "Sam", branch: "b", worktree: "/w", resultPath: "/r")
        #expect(c.contains("SendMessage") && c.contains("Sam's True"))
        #expect(PeerText.doneLine(label: "Sam", title: "Fix", status: .done, branch: "b", resultPath: "/r")
                == "[peer Sam] \"Fix\" done — branch b — result: /r")
    }

    @Test func hookEventsMapToStatus() {
        #expect(PeerEventMap.status(.progress, resultExists: false) == .working)
        #expect(PeerEventMap.status(.need, resultExists: false) == .needsYou)
        #expect(PeerEventMap.status(.stop, resultExists: false) == .idle)
        #expect(PeerEventMap.status(.stop, resultExists: true) == .done)
        #expect(PeerEventMap.status(.error, resultExists: true) == .failed)
        #expect(PeerEventMap.status(.other, resultExists: true) == nil)
    }

    @Test func backoffDoublesToTheCap() {
        #expect((0...7).map { PeerBackoff.delay(attempt: $0) } == [30, 60, 120, 240, 480, 600, 600, 600])
        #expect(PeerBackoff.delay(attempt: 10_000) == 600 && PeerBackoff.delay(attempt: -3) == 30)
    }

    @Test func replyTokenVerification() {
        let t = PeerValidate.newReplyToken()
        #expect(PeerValidate.validReplyToken(t))
        let h = PeerToken.hash(t)
        #expect(PeerToken.verify(t, storedHash: h))
        #expect(!PeerToken.verify(PeerValidate.newReplyToken(), storedHash: h))
        #expect(!PeerToken.verify(nil, storedHash: h) && !PeerToken.verify("", storedHash: h))
    }

    @Test func inboundModeFlags() {
        #expect(PeerInboundMode.bypass.claudeFlags == ["--dangerously-skip-permissions"])
        #expect(PeerInboundMode.auto.claudeFlags == ["--permission-mode", "auto"])
        #expect(PeerInboundMode.ask.claudeFlags == ["--permission-mode", "auto"])
        #expect(PeerInboundMode.fresh == .ask)
    }

    @Test func authDecisionTable() {
        let dns = "mac.ts.net"
        func d(login: String? = "sam@x", expected: String? = "sam@x", host: String? = "mac.ts.net:8444", origin: String? = nil,
               token: Bool = true, scope: Bool = true) -> RemoteAuth.Decision {
            PeerAuth.decide(loginHeader: login, expectedLogin: expected, host: host, origin: origin, dnsName: dns,
                            tokenValid: token, scopeOK: scope)
        }
        #expect(d() == .allow)
        #expect(d(origin: nil) == .allow)                       // machine-to-machine: no Origin is fine
        #expect(d(origin: "https://mac.ts.net:8444") == .allow)
        #expect(d(origin: "https://evil.com") != .allow)        // a present Origin must be exact
        #expect(d(login: nil) != .allow)                        // missing header fails closed
        #expect(d(login: "") != .allow)
        #expect(d(login: "other@x") != .allow)                  // wrong login
        #expect(d(expected: nil) != .allow)                     // device with no recorded login (phone token)
        #expect(d(host: "evil.com") != .allow && d(host: nil) != .allow)
        #expect(d(token: false) == .needsPairing)
        #expect(d(scope: false) != .allow)                      // phone/full/dropOnly token on /api/peer/*
        #expect(d(login: "SAM@X") == .allow)                    // case-insensitive
    }
}
