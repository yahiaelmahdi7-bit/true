import Testing
import Foundation
@testable import True

@Suite struct NovaTell26e {
    let roster = ["true-cto", "true-security", "true-swift-engineer"]

    @Test func verbatimSendRunsUnparkedAndKeepsTextByteForByte() {
        let spoken = "review the PR, and don't touch main!"
        let t = NovaTell.parse("tell the CTO to " + spoken, roster: roster)
        #expect(t == NovaTell.Tell(target: "true-cto", text: spoken))
        #expect(NovaGate.tool("send_to_pane", ["target": "true-cto", "text": spoken], origin: .user) == .allow)
    }
    @Test func verbsAndAliases() {
        #expect(NovaTell.parse("ask security whether the key leaked", roster: roster)?.target == "true-security")
        #expect(NovaTell.parse("message swift engineer fix the build", roster: roster)?.text == "fix the build")
        #expect(NovaTell.parse("tell true-cto go", roster: roster)?.target == "true-cto")
    }
    @Test func modelSendWithSameTargetStillParks() async {
        if case .park = NovaGate.tool("send_to_pane", ["target": "true-cto", "text": "hi"], origin: .model) {} else { Issue.record("model send must park") }
        let hands = NovaHands(approve: { _ in false })
        let r = await hands.run(name: "send_to_pane", input: ["target": "zzz", "text": "hi"], id: "1")
        #expect(r.text.contains("did not approve"))
        let u = await hands.runUser(name: "send_to_pane", input: ["target": "zzz", "text": "hi"])
        #expect(u.text.contains("no agent named zzz"))
    }
    @Test func ambientNeverSends() {
        var t = NovaTellTurn()
        #expect(t.finalize("tell the CTO hi", roster: roster, addressed: false, gated: false, final: true) == nil)
    }
    @Test func ambiguousOrUnknownFallsThrough() {
        #expect(NovaTell.parse("tell the CTO hi", roster: ["true-cto", "CTO"]) == nil)
        #expect(NovaTell.parse("tell nobody hi", roster: roster) == nil)
        #expect(NovaTell.parse("tell the CTO", roster: roster) == nil)
        #expect(NovaTell.parse("open Safari", roster: roster) == nil)
    }
    @Test func eagerNeverSendsOnlyFinalDoes() {
        var t = NovaTellTurn()
        #expect(t.finalize("tell the CTO hi", roster: roster, addressed: true, gated: false, final: false) == nil)
        #expect(t.finalize("tell the CTO hi", roster: roster, addressed: true, gated: false, final: true) != nil)
    }
    @Test func atMostOncePerTurn() {
        var t = NovaTellTurn()
        #expect(t.finalize("tell the CTO hi", roster: roster, addressed: true, gated: false, final: true) != nil)
        #expect(t.finalize("tell the CTO hi", roster: roster, addressed: true, gated: false, final: true) == nil)
        t.reset()
        #expect(t.finalize("tell the CTO hi", roster: roster, addressed: true, gated: false, final: true) != nil)
    }
    @Test func ignoredWhileNovaSpeaks() {
        var t = NovaTellTurn()
        #expect(t.finalize("tell the CTO hi", roster: roster, addressed: true, gated: true, final: true) == nil)
    }
    @Test func denyListAndControlCharsRefused() {
        if case .refuse = NovaGate.tool("send_to_pane", ["target": "true-cto", "text": "run git push now"], origin: .user) {} else { Issue.record("deny-list text must be refused") }
        if case .refuse = NovaGate.tool("send_to_pane", ["target": "true-cto", "text": "hi\u{1B}[2J"], origin: .user) {} else { Issue.record("control char must be refused") }
    }
    @Test func busyPaneStillParksForUser() {
        if case .park = NovaGate.tool("send_to_pane", ["target": "true-cto", "text": "hi"], paneBusy: true, origin: .user) {} else { Issue.record("busy pane must park") }
    }
    @Test func finalToSendLatencyUnder30ms() {
        var ms: [Double] = []
        for _ in 0..<500 {
            var t = NovaTellTurn()
            let s = Date()
            if let x = t.finalize("tell the CTO to review the PR and report back", roster: roster, addressed: true, gated: false, final: true) {
                _ = NovaGate.tool("send_to_pane", ["target": x.target, "text": x.text], origin: .user)
            }
            ms.append(Date().timeIntervalSince(s) * 1000)
        }
        ms.sort()
        let p50 = ms[250], p95 = ms[475]
        print("TELL-LATENCY p50=\(p50) ms p95=\(p95) ms")
        #expect(p95 <= 30)
        #expect(ms.count == 500 && p50 < 30)
    }
}
