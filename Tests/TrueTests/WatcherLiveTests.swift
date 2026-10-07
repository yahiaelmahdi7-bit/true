import Testing
import Foundation
@testable import True

/// Live Jev against the labelled set. Opt-in: JEV_LIVE=1. Set WATCHER_FRESH=<path> to run the fresh (unseen) set instead of the dev set.
/// Prints label vs answer + probabilities, accuracy per floor, and the handOff gate for fixes. Asserts nothing about accuracy.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["JEV_LIVE"] == "1")) struct WatcherLiveTests {
    private func ask(_ state: Any, _ q: [String: JevQuestion]) async -> JevReply? {
        nonisolated(unsafe) let s = state
        return await JevClient.shared.ask(state: s, questions: q, timeout: 20)
    }
    private func p(_ r: JevReply?, _ id: String) -> Double? { r?.answers[id]?.noul }
    private func f(_ x: Double?) -> String { x.map { String(format: "%.2f", $0) } ?? "nil" }

    @Test func wakeGate() async {
        var right = 0, total = 0
        for c in WatcherFixture.list("wake", WatcherFixture.url) {
            guard let id = c["id"] as? String, let state = c["state"] as? [String: Any], let labels = c["labels"] as? [String: Any] else { continue }
            let r = await ask(state, WatcherQuestions.wakeQuestions)
            var line = "wake \(id):"
            for (k, v) in labels.sorted(by: { $0.key < $1.key }) {
                let lab: Bool = (v as? Bool) ?? (((v as? Double) ?? 0) >= 0.5)
                let got = p(r, k)
                line += " \(k) label=\(lab) jev=\(f(got))"
                if let got { total += 1; if (got >= 0.5) == lab { right += 1 } }
            }
            print(line, "expect=\(c["expect"] ?? "?")")
        }
        print("wake accuracy @0.5: \(right)/\(total)")
        for floor in [WatcherQuestions.Floor.noItem, WatcherQuestions.Floor.investigate] { print("floor \(floor) in use") }
    }

    @Test func dedupeAndDone() async {
        var right = 0, total = 0
        for c in WatcherFixture.list("dedupe", WatcherFixture.url) {
            guard let id = c["id"] as? String, let state = c["state"] as? [String: Any] else { continue }
            let n = (state["open"] as? [Any])?.count ?? 0
            let r = await ask(state, WatcherQuestions.dedupeQuestions(count: n))
            let got = WatcherQuestions.bestMatch(reply: r, count: n)
            let want = c["expect_merge_index"] as? Int
            total += 1; if got == want { right += 1 }
            print("dedupe \(id): expect=\(want.map(String.init) ?? "new") got=\(got.map(String.init) ?? "new")")
        }
        print("dedupe accuracy @\(WatcherQuestions.Floor.dedupe): \(right)/\(total)")
        right = 0; total = 0
        for c in WatcherFixture.list("done", WatcherFixture.url) {
            guard let id = c["id"] as? String, let state = c["state"] as? [String: Any], let labels = c["labels"] as? [String: Any] else { continue }
            let r = await ask(state, WatcherQuestions.doneQuestions)
            let want = (labels["done_passed"] as? Bool ?? false) && (labels["done_same"] as? Bool ?? false)
            total += 1; if WatcherQuestions.looksFixed(reply: r) == want { right += 1 }
            print("done \(id): label=\(want) passed=\(f(p(r, "done_passed"))) same=\(f(p(r, "done_same")))")
        }
        print("done accuracy @\(WatcherQuestions.Floor.done): \(right)/\(total)")
    }

    @Test func handOffGate() async {
        var wrongAct = 0, total = 0
        for c in WatcherFixture.list("fixes", WatcherFixture.url) {
            guard let id = c["id"] as? String, let state = c["state"] as? [String: Any] else { continue }
            let text = state["text"] as? String ?? ""
            let r = await ask(PermissionGate.state(text: text, repo: state["repo"] as? String ?? "", problem: state["problem"] as? String ?? ""), PermissionGate.questions)
            let level = PermissionGate.decide(text: text, reply: r).level
            let wantHand = (c["deny_list_hit"] as? Bool ?? false) || (c["expect_handoff"] as? Bool ?? false)
            total += 1
            if wantHand && level != .handOff { wrongAct += 1 }
            print("fix \(id): expect handOff=\(wantHand) got=\(level.rawValue)")
        }
        print("handOff gate: \(wrongAct) risky fixes NOT handed off of \(total) (must be 0)")
    }
}
