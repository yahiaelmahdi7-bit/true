import Testing
import Foundation
@testable import True

private let apps = AppIndex(names: ["Safari", "Google Chrome", "Music", "Music Memos", "Notes", "Visual Studio Code", "System Settings"])
private func session(wait: TimeInterval = 0.25) -> NovaInstantSession { NovaInstantSession(apps: apps, panes: ["Atlas", "Orion"], prefixWait: wait) }
private func acts(_ steps: [NovaInstantSession.Step]) -> [InstantVerb] { steps.compactMap { if case .act(let v) = $0.kind { return v } else { return nil } } }

@Suite struct NovaInstantLaneTests {
    @Test func aliasesResolve() {
        #expect(apps.resolve("chrome")?.name == "Google Chrome")
        #expect(apps.resolve("vs code")?.name == "Visual Studio Code")
        #expect(apps.resolve("settings")?.name == "System Settings")
        #expect(apps.resolve("safar") == nil)
    }
    @Test func prefixWaitsThenFires() {
        var s = session(); let t0 = Date()
        #expect(acts(s.feed("open music", now: t0)).isEmpty)                       // "Music" is a prefix of "Music Memos"
        #expect(acts(s.feed("open music", now: t0.addingTimeInterval(0.1))).isEmpty)
        #expect(acts(s.feed("open music", now: t0.addingTimeInterval(0.3))) == [.openApp("Music")])
        var s2 = session(); _ = s2.feed("open music", now: t0)
        #expect(acts(s2.feed("open music memos", now: t0.addingTimeInterval(0.05))) == [.openApp("Music Memos")])
    }
    @Test func clausesSplitAcrossRevisions() {
        var s = session(); let t = Date()
        let partials = ["open", "open saf", "open safari", "open safari and", "open safari and then vol", "open safari and then volume up", "open safari and then volume up"]
        var all: [InstantVerb] = []
        for (i, p) in partials.enumerated() { all += acts(s.feed(p, now: t.addingTimeInterval(Double(i) * 0.1))) }
        #expect(all == [.openApp("Safari"), .volumeUp])         // each exactly once, in order — no double dispatch
    }
    @Test func noDoubleDispatchOnRepeatedFeeds() {
        var s = session(); let t = Date()
        var n = 0
        for i in 0..<10 { n += acts(s.feed("open safari", now: t.addingTimeInterval(Double(i) * 0.05))).count }
        #expect(n == 1)
    }
    @Test func correctionUndoesThenRedoes() {
        var s = session(); let t = Date()
        var kinds: [String] = []
        for (i, p) in ["open safari", "open safari no", "open safari no chrome", "open safari no chrome"].enumerated() {
            for st in s.feed(p, now: t.addingTimeInterval(Double(i) * 0.1)) {
                switch st.kind { case .act(let v): kinds.append("act:\(v.spoken)"); case .undo: kinds.append("undo") }
            }
        }
        #expect(kinds == ["act:opened Safari", "undo", "act:opened Google Chrome"])
    }
    @Test func noWithoutLiveActIsOrdinaryWords() {
        var s = session()
        #expect(s.feed("no", now: Date()).isEmpty)
    }
    @Test func unhandledRemainderIsExposed() {
        var s = session(); let t = Date()
        _ = s.feed("open safari and then summarize the build log", now: t)
        #expect(s.unhandled.contains("summarize"))
        #expect(!s.unhandled.contains("safari"))
    }
    @Test func quitIsGracefulTool() {
        #expect(NovaInstantRunner.tool(for: .quitApp("Notes")).0 == "quit_graceful")
    }
}

@Suite struct NovaLiveTurnTests {
    @Test func ambientNeverFires() {
        var t = NovaLiveTurn()
        #expect(t.command(in: "open safari the tv is saying", novaSpeaking: false) == nil)
    }
    @Test func commandIsWordsAfterLastName() {
        var t = NovaLiveTurn()
        #expect(t.command(in: "blah blah Nova open Safari", novaSpeaking: false) == ["open", "Safari"])
        #expect(t.command(in: "blah blah Nova open Safari and then nova volume up", novaSpeaking: false) == ["volume", "up"])
    }
    @Test func novaOwnSpeechIgnoredButStopBargesIn() {
        var t = NovaLiveTurn()
        #expect(t.command(in: "nova open safari", novaSpeaking: true) == nil)
        #expect(NovaLiveTurn.isBargeIn("nova stop"))
        #expect(!NovaLiveTurn.isBargeIn("nova open safari"))
    }
    @Test func spentTurnDoesNotRefire() {
        var t = NovaLiveTurn()
        let text = "nova open safari"
        _ = t.command(in: text, novaSpeaking: false)
        t.endTurn(wordCount: NovaLiveTurn.tokens(text).count)
        #expect(t.command(in: text, novaSpeaking: false) == nil)
        #expect(t.command(in: text + " nova mute", novaSpeaking: false) == ["mute"])
    }
    @Test func hotkeyTakesWordsFromPress() {
        var t = NovaLiveTurn()
        t.pressHotkey(wordCount: 2)
        #expect(t.command(in: "one two open safari", novaSpeaking: false) == ["open", "safari"])
    }
}

@Suite struct NovaEagerTests {
    @Test func startsAfterQuietAndCapsRestarts() {
        var e = NovaEagerTurn(); var now = Date(); var starts = 0
        for i in 0..<8 {
            now = now.addingTimeInterval(0.1)
            _ = e.observe(unhandled: "words \(i)", now: now)                  // new words (cancels a running one)
            now = now.addingTimeInterval(0.3)
            if case .start = e.observe(unhandled: "words \(i)", now: now) { starts += 1 }
        }
        #expect(starts == NovaEagerTurn.maxRestarts + 1)                       // first run + 3 restarts, then no more
    }
    @Test func newWordsCancelRunningEager() {
        var e = NovaEagerTurn(); let t = Date()
        _ = e.observe(unhandled: "a", now: t)
        #expect(e.observe(unhandled: "a", now: t.addingTimeInterval(0.3)) == .start("a"))
        #expect(e.observe(unhandled: "a b", now: t.addingTimeInterval(0.4)) == .cancel)
    }
}

@Suite struct NovaLatencyTests {
    @Test func handStartsWithin30msOfCompletingPartial() {
        var ms: [Double] = []
        let commands = ["open safari", "volume up", "mute", "hide notes", "scroll down"]
        var n = 0
        while n < 50 {
            var s = session(); let words = commands[n % commands.count].split(separator: " ").map(String.init)
            for k in 1...words.count {
                let t0 = Date()
                let steps = s.feed(words[0..<k].joined(separator: " "), now: t0)
                for _ in steps { ms.append(Date().timeIntervalSince(t0) * 1000) }   // fake hand: starts when the step arrives
            }
            n += 1
        }
        ms.sort()
        let p50 = ms[ms.count / 2], p95 = ms[Int(Double(ms.count) * 0.95)]
        print("INSTANT-LATENCY n=\(ms.count) p50=\(String(format: "%.3f", p50)) ms p95=\(String(format: "%.3f", p95)) ms")
        #expect(ms.count >= 50)
        #expect(p95 <= 30)
    }
}
