import Testing
import Foundation
@testable import True

/// Run 26d regression tests (true-security re-review of 0b3c9bc). Written before the fixes.
@Suite struct NovaSecurity26dTests {
    private func tmp() throws -> String {
        let d = NSTemporaryDirectory() + "r26d-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return (try? URL(fileURLWithPath: d).resolvingSymlinksInPath().path) ?? d
    }
    private func isPark(_ p: NovaShell.Plan) -> Bool { if case .park = p { return true }; return false }
    private func isRun(_ p: NovaShell.Plan) -> Bool { if case .run = p { return true }; return false }
    private func isParkV(_ v: GateVerdict) -> Bool { if case .park = v { return true }; return false }
    private let any: (String) -> Bool = { _ in true }

    // P1
    @Test func p1_ownVoiceResidueNeverAddresses() {
        var live = NovaLiveTurn()
        let heard = "On it, Nova. Go ahead?"
        #expect(live.ingest(heard, gated: true, novaSpeaking: true) == nil)
        #expect(live.ingest(heard, gated: false, novaSpeaking: false) == nil)   // tail over, same transcript still in the stream
        #expect(live.ingest(heard + " nova go ahead", gated: false, novaSpeaking: false) == ["go", "ahead"])
    }
    // P2a
    @Test func p2a_controlCharactersNeverReachProcess() throws {
        let d = try tmp()
        let nul = NovaShell.plan("cat x\u{0}y", cwd: d, exists: any)
        #expect({ if case .refuse = nul { return true }; return false }(), "NUL must be refused, got \(nul)")
        #expect(!isRun(NovaShell.plan("cat x\u{1}y", cwd: d, exists: any)))
        #expect(!isRun(NovaShell.plan("cat x\u{7f}", cwd: d, exists: any)))
        if case .refuse = NovaGate.tool("read_file", ["path": "a\u{0}b"]) {} else { Issue.record("read_file with NUL must refuse") }
        if case .refuse = NovaGate.shell("ls\u{0}") {} else { Issue.record("gate shell with NUL must refuse") }
    }
    @Test func p2a_execSurvivesNul() async {
        let r = await NovaHands.exec("/bin/cat", ["a\u{0}b"], cwd: nil, timeout: 5, cap: 100)
        #expect(r.status == -1)
    }
    // P2b
    @Test func p2b_parkCardShowsCwd() throws {
        let d = try tmp()
        if case .park(let w) = NovaShell.plan("touch x", cwd: d, exists: any) { #expect(w.contains("touch x") && w.contains(d), "\(w)") } else { Issue.record("touch parks") }
    }
    // P2c + git content
    @Test func p2c_gitFreeOnlyInKnownProjects() throws {
        let root = try tmp(), other = try tmp()
        #expect(isPark(NovaShell.plan("git status", cwd: other, projectRoots: [root], exists: any)))
        if case .run(_, let args, _) = NovaShell.plan("git log --oneline", cwd: root, projectRoots: [root], exists: any) {
            for a in ["core.fsmonitor=", "log.showSignature=false", "diff.external=", "core.pager=cat", "--no-textconv"] { #expect(args.contains(a), "missing \(a)") }
        } else { Issue.record("git log in a known folder should run") }
    }
    @Test func p3_gitContentReadsPark() throws {
        let root = try tmp()
        func p(_ c: String) -> NovaShell.Plan { NovaShell.plan(c, cwd: root, projectRoots: [root], exists: any) }
        for c in ["git log -p", "git log --patch", "git show HEAD:secret.txt", "git diff", "git show", "git diff HEAD:x"] { #expect(!isRun(p(c)), "\(c)") }
        for c in ["git status", "git branch", "git diff --stat", "git diff --name-only", "git show --stat", "git log --oneline"] { #expect(isRun(p(c)), "\(c)") }
    }
    @Test func p3_recursiveRgExcludesSecretGlobs() throws {
        let root = try tmp()
        if case .run(_, let args, _) = NovaShell.plan("rg foo", cwd: root, exists: any) {
            #expect(args.contains("!.env") && args.contains("!*.pem") && args.contains("!id_rsa*"), "\(args)")
        } else { Issue.record("rg should run with globs") }
    }
    // P3 hidden files + hard links
    @Test func p3_hiddenFilesUnderHomePark() throws {
        let home = try tmp(), proj = home + "/proj"
        try FileManager.default.createDirectory(atPath: home + "/.config/zed", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: proj + "/.claude", withIntermediateDirectories: true)
        try "x".write(toFile: home + "/.config/zed/s.json", atomically: true, encoding: .utf8)
        try "x".write(toFile: proj + "/.claude/notes.md", atomically: true, encoding: .utf8)
        try "x".write(toFile: home + "/plain.txt", atomically: true, encoding: .utf8)
        #expect(isParkV(NovaPaths.check(home + "/.config/zed/s.json", home: home, projectRoots: [proj])))
        #expect(NovaPaths.check(home + "/plain.txt", home: home, projectRoots: [proj]) == .allow)
        #expect(NovaPaths.check(proj + "/.claude/notes.md", home: home, projectRoots: [proj]) == .allow)
        if case .refuse = NovaPaths.check(home + "/.ssh/id_rsa", home: home, projectRoots: [proj]) {} else { Issue.record("secret set stays refused") }
    }
    @Test func p3_hardLinkedFilesPark() throws {
        let home = try tmp()
        try "x".write(toFile: home + "/a.txt", atomically: true, encoding: .utf8)
        #expect(NovaPaths.check(home + "/a.txt", home: home) == .allow)
        try FileManager.default.linkItem(atPath: home + "/a.txt", toPath: home + "/b.txt")
        #expect(isParkV(NovaPaths.check(home + "/b.txt", home: home)))
    }
    // P3 approvals
    @Test func p3_spokenYesBoundToCardAndFinal() {
        let a = UUID(), b = UUID()
        #expect(NovaApproval.resolution("nova go ahead", addressed: true, final: false, cardAtStart: a, cardNow: a) == .none)
        #expect(NovaApproval.resolution("nova go ahead", addressed: true, final: true, cardAtStart: a, cardNow: a) == .approve)
        #expect(NovaApproval.resolution("nova go ahead", addressed: true, final: true, cardAtStart: a, cardNow: b) == .none)
        #expect(NovaApproval.resolution("nova go ahead", addressed: true, final: true, cardAtStart: nil, cardNow: b) == .none)
        #expect(NovaApproval.resolution("go ahead no wait", addressed: true, final: true, cardAtStart: a, cardNow: a) == .deny)
        #expect(NovaApproval.resolution("no", addressed: false, final: false, cardAtStart: nil, cardNow: a) == .deny)
    }
    // P3 de-dup message
    @Test func p3_repeatedRefusalReportsRealOutcome() async {
        let h = NovaHands(approve: { _ in false })
        let first = await h.run(name: "quit_app", input: ["name": "True"], id: "a")
        let second = await h.run(name: "quit_app", input: ["name": "True"], id: "b")
        #expect(first.isError && second.isError)
        #expect(second.text.hasPrefix("refused"), "\(second.text)")
    }
}
