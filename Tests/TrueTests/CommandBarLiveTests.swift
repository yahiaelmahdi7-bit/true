import Testing
import Foundation
@testable import True

/// The 39 FIXED hand-labelled routes through the real router. JEV_LIVE=1 only (the orchestrator runs it; builders never do).
/// Prints label vs route per slot + probabilities + ms and per-slot accuracy. No accuracy assertion: it is a calibration set.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["JEV_LIVE"] == "1")) struct CommandBarLiveTests {
    @Test func labelledRoutesVersusRouter() async throws {
        let url = CommandBarFixture.liveURL()
        let fx = try CommandBarFixture.load(from: url)
        var hit: [String: Int] = [:], seen: [String: Int] = [:], rows: [String] = []
        func score(_ slot: String, _ ok: Bool?) -> String {
            guard let ok else { return "-" }
            seen[slot, default: 0] += 1
            if ok { hit[slot, default: 0] += 1 }
            return ok ? "ok" : "MISS"
        }
        func p(_ x: Double?) -> String { x.map { String(format: "%.2f", $0) } ?? "-" }
        for c in fx.cases {
            let focused = fx.pane(c)
            let ctx = CommandContext(focused: focused,
                                     projects: CommandRouter.candidates(text: c.text, projects: fx.projectList, recent: []),
                                     seats: fx.barSeats, all: fx.projectList)
            let rule = CommandRules.match(c.text, projects: fx.projectList, seats: fx.barSeats)
            let t0 = Date()
            let reply = await CommandRouter.ask(text: c.text, context: ctx, rule: rule, jev: JevClient())
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            let r = CommandRouter.route(text: c.text, reply: reply, context: ctx, rule: rule)
            let e = c.expect
            let kindOK = e.kind.map { $0 == r.kind.rawValue || (c.ambiguous == true && r.twoChoice) }
            let gotProject = r.project?.name ?? focused.project
            let wantProject: String?? = e.project.map { $0 == "current" ? focused.project : ($0 == "none" ? nil : $0) }
            let projOK = wantProject.map { $0 == gotProject }
            let targetOK = e.target.map { $0 == r.target.id }
            let actionOK = e.action.map { $0 == r.action.rawValue }
            let destOK = e.destructive.map { $0 == r.isDestructive }
            rows.append("\(c.id) \"\(c.text.prefix(48))\" kind \(e.kind ?? "-")→\(r.kind.rawValue)@\(p(r.kindConfidence)) \(score("kind", kindOK))"
                + " | project \(e.project ?? "-")→\(gotProject ?? "none") \(score("project", projOK))"
                + " | target \(e.target ?? "-")→\(r.target.id) \(score("target", targetOK))"
                + " | action \(e.action ?? "-")→\(r.action.rawValue) \(score("action", actionOK))"
                + " | destructive \(e.destructive.map(String.init) ?? "-")→\(p(r.destructive))\(r.dangerTop.map { " (\($0))" } ?? "") \(score("destructive", destOK))"
                + " | model \(r.model?.rawValue ?? "-") effort \(r.effort?.rawValue ?? "-") twoChoice \(r.twoChoice) | \(ms)ms")
        }
        let acc = ["kind", "project", "target", "action", "destructive"].map { "\($0) \(hit[$0] ?? 0)/\(seen[$0] ?? 0)" }.joined(separator: "  ")
        print("\n=== Command bar live: label vs route (\(url.lastPathComponent), \(fx.cases.count) cases) ===\n" + rows.joined(separator: "\n") + "\naccuracy: \(acc)\n")
    }
}
