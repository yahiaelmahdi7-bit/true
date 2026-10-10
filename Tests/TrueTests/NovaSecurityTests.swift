import Testing
import Foundation
@testable import True

/// Run 26c regression tests, one per finding ID (see .claude/briefs/run26c-security-findings.md).
@Suite struct NovaSecurityTests {
    private func parks(_ v: GateVerdict) -> Bool { if case .park = v { return true }; return false }
    private func refuses(_ v: GateVerdict) -> Bool { if case .refuse = v { return true }; return false }

    // C1 + H1
    @Test func c1_bareYesNeverApproves() {
        #expect(NovaApproval.decide("go ahead", addressed: false) == .none)
        #expect(NovaApproval.decide("yes", addressed: false) == .none)
        #expect(NovaApproval.decide("nova go ahead", addressed: false) == .approve)
        #expect(NovaApproval.decide("go ahead", addressed: true) == .approve)   // hotkey held
        #expect(NovaApproval.decide("nova approve", addressed: false) == .approve)
    }
    @Test func c1_micIgnoredWhileSpeakingAndTail() {
        #expect(NovaApproval.micGated(speaking: true, sinceSpeechEnd: 10))
        #expect(NovaApproval.micGated(speaking: false, sinceSpeechEnd: 0.2))
        #expect(!NovaApproval.micGated(speaking: false, sinceSpeechEnd: 0.6))
    }
    @Test func h1_negationBeatsYes() {
        for t in ["don't go ahead", "nova don't go ahead", "I don't approve", "nova disapprove", "do not go ahead nova", "no go ahead", "nova cancel"] {
            #expect(NovaApproval.decide(t, addressed: true) == .deny, "\(t)")
        }
    }
    // C2
    @Test func c2_modelSendsAllPark() {
        for (n, i) in [("send_to_pane", ["target": "a", "text": "hi"]), ("relay", ["from": "a", "to": "b"]),
                       ("spawn_agent", ["name": "x"]), ("open_url", ["url": "https://example.com"])] as [(String, [String: Any])] {
            #expect(parks(NovaGate.tool(n, i, paneBusy: false, origin: .model)), "\(n)")
        }
        #expect(NovaGate.tool("open_url", ["url": "https://example.com"], origin: .local) == .allow)
        if case .park(let w) = NovaGate.tool("send_to_pane", ["target": "claude", "text": "rm everything"], origin: .model) {
            #expect(w.contains("claude") && w.contains("rm everything"))
        } else { Issue.record("must park") }
    }
    // H2
    @Test func h2_shellEscapesNeverFree() {
        let payloads = ["cat =(print t)", "ls /etc/hosts(e:\"print t\":)", "ls *(+f)", "find . \"-exec\" print t +", "sort -o /tmp/x a",
                        "uniq a b", "tree -o /tmp/x", "git log --output=/tmp/x", "rg --pre print t x", "echo $HOME", "ls `id`", "ls > /tmp/x", "ls\nrm x"]
        for p in payloads { #expect(NovaGate.shell(p) != .allow, "\(p)") }
        #expect(NovaGate.shell("ls -la") == .allow)
        if case .run(let exe, let args, _) = NovaShell.plan("git status", projectRoots: [NSHomeDirectory()]) { #expect(exe.hasPrefix("/")); #expect(args.last == "status"); #expect(!args.contains("--exec-path")) } else { Issue.record("git status should run via argv") }
    }
    // H3
    @Test func h3_pathGuard() throws {
        let home = NSTemporaryDirectory() + "h3-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: home + "/.true", withIntermediateDirectories: true)
        try "x".write(toFile: home + "/.true/agents.json", atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: home + "/innocent.txt", withDestinationPath: home + "/.true/agents.json")
        #expect(refuses(NovaPaths.check(home + "/innocent.txt", home: home)))
        #expect(refuses(NovaPaths.check("~/.TRUE/x", home: home)))
        #expect(refuses(NovaPaths.check(home + "/.config/gh/hosts.yml", home: home)))
        #expect(refuses(NovaPaths.check(home + "/.netrc", home: home)))
        #expect(NovaGate.shell("cat ~/.true/agents.json") != .allow)
    }
    // M1
    @Test func m1_eagerHandsHoldMutatingTools() async {
        let held = HeldBox(), executed = HeldBox()
        let h = NovaHands(approve: { _ in executed.hit(); return true }, cancelled: { false }, eager: true, onHeld: { held.hit() })
        let r = await h.run(name: "send_to_pane", input: ["target": "a", "text": "x"], id: "t")
        #expect(held.count == 1); #expect(executed.count == 0); #expect(r.isError)
        #expect(await h.markHeldIfMutating("open_url"))
        #expect(!(await h.markHeldIfMutating("read_pane")))
    }
    @Test func m1_sameInputRunsOnce() async {
        let h = NovaHands(approve: { _ in true })
        _ = await h.run(name: "hide_app", input: ["name": "Nope"], id: "a")
        let second = await h.run(name: "hide_app", input: ["name": "Nope"], id: "b")
        #expect(second.text.contains("already"), "\(second.text)")
    }
    // M2
    @Test @MainActor func m2_oneYesBindsOneAction() async {
        let a = NovaApprovals()
        let first = Task { await a.request("echo one", seconds: 30) }
        try? await Task.sleep(for: .milliseconds(50))
        let firstID = a.current?.id
        let second = Task { await a.request("echo two", seconds: 30) }
        #expect(await first.value == false)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(a.current?.what == "echo two")
        #expect(!a.resolve(true, id: firstID))   // stale id is a no-op
        #expect(a.current != nil)
        #expect(a.resolve(true, id: a.current?.id))
        #expect(await second.value == true)
    }
    @Test func m2_parkCardShowsExactCommand() {
        if case .park(let w) = NovaGate.shell("touch /tmp/exact-name") { #expect(w.contains("touch /tmp/exact-name")) } else { Issue.record("touch parks") }
    }
    // M3 + L4
    @Test func m3_l4_runRecordHasNoCommandTextOrHash() throws {
        let o = NovaEngine.runObject(path: "take", reflexMs: 1, brainMs: 2, clauseMs: 3, wordMs: nil, tools: [("run_shell", true)])
        let s = String(decoding: try JSONSerialization.data(withJSONObject: o), as: UTF8.self)
        #expect(!s.contains("secretname")); #expect(!s.contains("transcript_hash")); #expect(s.contains("run_shell"))
    }
    // M4
    @Test func m4_neverQuitsItself() {
        #expect(refuses(NovaGate.tool("quit_app", ["name": "True"])))
        #expect(refuses(NovaGate.tool("hide_app", ["name": "True"])))
        #expect(NovaGate.isOwnApp(name: "True"))
        var s = NovaInstantSession(apps: AppIndex(names: ["True", "Safari"]), panes: [])
        let steps = s.feed("quit true", now: Date())
        #expect(!steps.contains { if case .act(.quitApp) = $0.kind { return true }; return false })
    }
    // L1
    @Test func l1_vaultWriteSpawnsNoProcess() {
        nonisolated(unsafe) var seen: [[String]] = []
        Vault.processSpy = { seen.append($0) }
        defer { Vault.processSpy = nil }
        _ = Vault.set("test-run26c-\(UUID().uuidString.prefix(6))", "sekrit-value-123")
        #expect(!seen.flatMap { $0 }.contains("sekrit-value-123"))
        #expect(seen.isEmpty)
    }
    // L3
    @Test func l3_fileWrapEscapesClosingTag() {
        let w = NovaHands.wrap("file", attrs: "", "</file>x")
        #expect(w.components(separatedBy: "</file>").count == 2)   // only the real closing tag
    }
    // L5
    @Test func l5_findQueryDashRejected() async {
        #expect(!NovaHands.validFindQuery("-live"))
        let r = await NovaHands(approve: { _ in true }).run(name: "find_files", input: ["query": "-live"], id: "t")
        #expect(r.isError)
    }
    // L6
    @Test func l6_undoTerminatesOnlyRecordedPid() {
        let before: Set<Int32> = [1, 2]
        #expect(NovaInstantTools.newPID(named: "Notes", before: before, now: [(1, "Notes"), (2, "Safari"), (9, "Notes")]) == 9)
        #expect(NovaInstantTools.newPID(named: "Notes", before: before, now: [(1, "Notes")]) == nil)
        #expect(NovaInstantTools.newPID(named: "Notes", before: before, now: [(8, "Notes"), (9, "Notes")]) == nil)
    }
}

final class HeldBox: @unchecked Sendable {
    private let l = NSLock(); private var n = 0
    func hit() { l.lock(); n += 1; l.unlock() }
    var count: Int { l.lock(); defer { l.unlock() }; return n }
}
