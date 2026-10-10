import Testing
import Foundation
@testable import True

@Suite struct NovaSecurity26f {
    let roster = ["true-cto", "true-security"]

    // 1. own-voice residue
    @Test func sameGenerationRevisionDoesNotResurrectNovaWords() {
        var live = NovaLiveTurn()
        // Nova said "... no va go ahead" (5 tokens): gated, spent.
        #expect(live.ingest("sure thing no va go ahead", gated: true, novaSpeaking: true, generation: 1) == nil)
        // a later revision merges "no va" -> "nova": fewer tokens, SAME stream: must stay dead
        #expect(live.ingest("sure thing nova go ahead", gated: false, novaSpeaking: false, generation: 1) == nil)
        #expect(live.ingest("sure thing nova go ahead", gated: false, novaSpeaking: false, generation: 1) == nil)
        // a genuinely new stream resets the floor
        #expect(live.ingest("nova go ahead", gated: false, novaSpeaking: false, generation: 2) == ["go", "ahead"])
    }
    @Test func staleGoAheadFromNovaNeverApproves() {
        var live = NovaLiveTurn()
        _ = live.ingest("I will send it nova go ahead", gated: true, novaSpeaking: true, generation: 1)
        let w = live.ingest("I will send it nova go ahead", gated: false, novaSpeaking: false, generation: 1)
        #expect(w == nil)
    }
    @Test func lateWordsInsideSpeechWindowAreSpent() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let windows = [(start: t0, end: t0.addingTimeInterval(2))]
        // 4 words; the 3rd was spoken at +1.5 s (Nova talking) but is only delivered 1 s after she stops
        let starts = [t0.addingTimeInterval(-1), t0.addingTimeInterval(0.5), t0.addingTimeInterval(1.5), t0.addingTimeInterval(2.3)]
        #expect(NovaLiveTurn.spentCount(segmentStarts: starts, windows: windows, tail: 0.4) == 4)   // +2.3 is inside the 400 ms tail
        #expect(NovaLiveTurn.spentCount(segmentStarts: starts, windows: windows, tail: 0.1) == 3)
        var live = NovaLiveTurn()
        live.spend(upTo: 3)
        #expect(live.command(in: "a nova b c", novaSpeaking: false, generation: 0) == nil)   // "nova" at index 1 is spent
        #expect(live.command(in: "a nova b c nova go", novaSpeaking: false, generation: 0) == ["go"])
    }

    // 2. a tell sentence never fires instant clauses
    @Test func tellSentenceFiresNoInstantClause() {
        var s = NovaInstantSession(apps: AppIndex(names: ["Music", "Safari"]), panes: roster)
        let steps = s.feed("tell the CTO to check the build and quit Music", now: Date())
        #expect(steps.isEmpty)
        #expect(s.tellMatched)
        var plain = NovaInstantSession(apps: AppIndex(names: ["Music", "Safari"]), panes: roster)
        #expect(!plain.feed("quit Music", now: Date()).isEmpty)
    }

    // 3. control characters at the one door
    @Test func paneDeliveryStripsEscC1AndDel() {
        let out = PaneDelivery.sanitize("a\u{1B}[201~b\u{7F}c\u{85}d\u{9B}e\u{0}f\r")
        #expect(!out.unicodeScalars.contains { $0.value < 0x20 && $0.value != 0x0A && $0.value != 0x09 || $0.value == 0x7F || (0x80...0x9F).contains($0.value) })
        #expect(out.hasPrefix("a[201~b"))
    }

    // 4. Claude Code prefixes park
    @Test func prefixedTellsPark() {
        for t in ["/clear", "  !ls", "#remember this", "  /model"] {
            if case .park = NovaGate.tool("send_to_pane", ["target": "true-cto", "text": t], origin: .user) {} else { Issue.record("\(t) must park") }
        }
        #expect(NovaGate.tool("send_to_pane", ["target": "true-cto", "text": "check the build"], origin: .user) == .allow)
    }

    // 5. only a live agent session
    @Test func shellFallbackOrUnknownStatusSendsNothing() {
        #expect(NovaTell.deliverable(awake: true, status: .idle, screen: "claude>"))
        #expect(!NovaTell.deliverable(awake: true, status: .idle, screen: "True: 'claude' was not found on PATH\n$ "))
        #expect(!NovaTell.deliverable(awake: true, status: .asleep, screen: ""))
        #expect(!NovaTell.deliverable(awake: true, status: .failed, screen: ""))
        #expect(NovaTell.deliverable(awake: false, status: .asleep, screen: ""))   // asleep seat: the existing send wakes it
    }

    // timing: still instant
    @Test func tellLatencyWithin10PercentOf26e() {
        var best = (p50: Double.infinity, p95: Double.infinity)
        for _ in 0..<3 {
            var ms: [Double] = []
            for _ in 0..<500 {
                var t = NovaTellTurn()
                let s = Date()
                if let x = t.finalize("tell the CTO to review the PR and report back", roster: roster, addressed: true, gated: false, final: true) {
                    _ = NovaGate.tool("send_to_pane", ["target": x.target, "text": x.text], origin: .user)
                    _ = NovaTell.deliverable(awake: true, status: .idle, screen: "claude>")
                }
                ms.append(Date().timeIntervalSince(s) * 1000)
            }
            ms.sort()
            if ms[475] < best.p95 { best = (ms[250], ms[475]) }
        }
        print("TELL26F-LATENCY p50=\(best.p50) ms p95=\(best.p95) ms")
        #expect(best.p50 <= 0.89 * 1.1)
        #expect(best.p95 <= 1.37 * 1.1)
    }
}
