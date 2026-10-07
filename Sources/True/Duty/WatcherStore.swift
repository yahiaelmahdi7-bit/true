import Foundation
import Observation

/// Where the Watcher puts things for Yahia. v1: the Hub reads the store directly; the digest is also kept as a line.
protocol InboxChannel: AnyObject {
    func deliver(item: InboxItem)
    func deliver(digest: String)
}

final class HubChannel: InboxChannel {
    var lastDigest: String?
    func deliver(item: InboxItem) {}
    func deliver(digest: String) { lastDigest = digest }
}

/// The Watcher's engine: signal -> screen -> wake gate -> dedupe -> (investigate) -> level -> Inbox.
/// Events only; no timers. Every outside effect is injected so tests run offline against temp dirs.
@Observable @MainActor
final class WatcherStore {
    static let shared = WatcherStore()
    /// Set once by the app; keeps tests and previews from touching ~/.true.
    nonisolated(unsafe) static var active = false

    struct Deps: @unchecked Sendable {
        var jev: JevClient = .shared
        var runner: Investigation.Runner = Investigation.systemRunner
        var spawn: BuilderSpawn.Runner = BuilderSpawn.systemRunner
        var git: @Sendable ([String]) -> String? = GitSignals.systemRunner
        var now: @Sendable () -> Date = { Date() }
        var root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".true/agents")
        var paths: Investigation.Paths = .standard()
        var builderBin: String = NSHomeDirectory() + "/.claude/bin/builder"
        var enabled: @Sendable () -> Bool = { UserDefaults.standard.object(forKey: "watcher.enabled") as? Bool ?? true }
    }

    private(set) var items: [InboxItem] = []
    private(set) var running: Set<String> = []
    var duty: Duty = Duty.watcherAgent().duty ?? Duty(job: Duty.watcherJob, triggers: [])
    let channel: InboxChannel
    private let d: Deps
    private let file: InboxFile
    private var home: URL { file.dir }

    init(deps: Deps = Deps(), channel: InboxChannel = HubChannel()) {
        d = deps; self.channel = channel
        file = InboxFile(dir: InboxFile.home(agent: Duty.watcherName, root: deps.root))
        file.ensureDir()
        _ = file.compactIfNeeded(now: deps.now().timeIntervalSince1970)
        items = file.items()
    }

    var enabled: Bool { d.enabled() }
    private var now: Double { d.now().timeIntervalSince1970 }

    /// What the Hub shows: open items first (needs-you), nothing hidden by default.
    var needsYou: [InboxItem] { Inbox.needsYou(items, now: now) }

    private func emit(_ e: InboxEvent) {
        file.append(e)
        items = Inbox.fold(file.events())
    }

    // MARK: logs + ledger

    private func appendLine(_ name: String, _ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return }
        let u = home.appendingPathComponent(name)
        let line = Data((s + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: u) { defer { try? h.close() }; _ = try? h.seekToEnd(); try? h.write(contentsOf: line) }
        else { try? line.write(to: u); try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: u.path) }
    }

    private func readLines(_ name: String) -> [[String: Any]] {
        guard let s = try? String(contentsOf: home.appendingPathComponent(name), encoding: .utf8) else { return [] }
        return s.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }

    static func day(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    struct Today: Equatable { var usd = 0.0; var runs = 0; var jev = 0; var perRepo: [String: Int] = [:] }

    /// Today's spend, local day; a new day starts at zero by construction.
    func today() -> Today {
        let key = Self.day(d.now())
        var t = Today()
        for l in readLines("ledger.jsonl") where (l["day"] as? String) == key {
            t.usd += (l["usd"] as? Double) ?? 0
            t.runs += (l["runs"] as? Int) ?? 0
            t.jev += (l["jev"] as? Int) ?? 0
            if let r = l["repo"] as? String, ((l["runs"] as? Int) ?? 0) > 0 { t.perRepo[r, default: 0] += 1 }
        }
        return t
    }

    private func ledger(usd: Double = 0, runs: Int = 0, jev: Int = 0, repo: String = "") {
        appendLine("ledger.jsonl", ["day": Self.day(d.now()), "at": now, "usd": usd, "runs": runs, "jev": jev, "repo": repo])
    }

    private func decision(_ what: String, _ detail: [String: Any] = [:]) {
        var o = detail; o["what"] = what; o["at"] = now
        appendLine("decisions.jsonl", o)
    }

    private func jevAsk(_ state: Any, _ q: [String: JevQuestion]) async -> JevReply? {
        let t = today()
        guard t.jev < duty.budget.jevCallsPerDay else { decision("jev-cap"); return nil }
        ledger(jev: 1)
        nonisolated(unsafe) let st = state
        return await d.jev.ask(state: st, questions: q, timeout: 8)
    }

    // MARK: pipeline

    /// One signal through the whole pipeline. Never throws; every stop is logged.
    func handle(_ s: WatcherSignal) async {
        guard enabled else { return }
        let t0 = now
        if let hit = Inbox.openItem(items, fingerprint: s.fingerprint, now: t0) {
            emit(InboxEvent(.merged, id: hit.id, at: t0, evidence: Redact.secrets(s.evidence)))
            decision("merged", ["item": hit.id]); return
        }
        if isMuted(s) { decision("muted", ["fp": s.fingerprint]); return }

        let screen = InjectionScreen.screen(s.evidence)
        let evidence = Redact.secrets(screen.text)
        if s.source == "git" { createCodeMade(s, evidence: evidence); return }

        let state: [String: Any] = ["source": s.source, "kind": s.kind, "facts": s.facts, "evidence": evidence]
        let reply = await jevAsk(state, WatcherQuestions.wakeQuestions)
        let wake = WatcherQuestions.decideWake(reply: reply, codeFact: s.codeFact, screenFlag: screen.flagged)
        appendLine("wake.jsonl", ["fp": s.fingerprint, "route": wake.route.rawValue, "worth": wake.worth ?? -1, "at": t0])
        if wake.route == .none { return }

        var item = makeItem(s, evidence: evidence)
        if wake.injection { item.note = "Contains instructions: not sent to the agent" }
        item.canInvestigate = wake.route != .none && !wake.injection

        // dedupe against the repo's open items (≤ 8)
        let open = items.filter { $0.repo == s.repo && ($0.state == .open || $0.state == .approved) }.prefix(8)
        if !open.isEmpty {
            let st: [String: Any] = ["candidate": ["title": s.title, "evidence": String(evidence.prefix(600))],
                                      "open": open.map { ["title": $0.title, "evidence": String($0.evidence.prefix(600))] }]
            let r = await jevAsk(st, WatcherQuestions.dedupeQuestions(count: open.count))
            if let i = WatcherQuestions.bestMatch(reply: r, count: open.count) {
                let target = Array(open)[i]
                emit(InboxEvent(.merged, id: target.id, at: t0, evidence: evidence))
                decision("deduped", ["into": target.id]); return
            }
        }
        emit(InboxEvent(.created, id: item.id, at: t0, item: item))
        channel.deliver(item: item)
        if wake.route == .investigate && !wake.injection { await investigate(item.id) }
    }

    private func makeItem(_ s: WatcherSignal, evidence: String) -> InboxItem {
        InboxItem(id: UUID().uuidString.prefix(8).lowercased().description, agent: Duty.watcherName, source: s.source, kind: s.kind,
                  subject: s.subject, repo: s.repo, fingerprint: s.fingerprint, title: s.title, evidence: evidence, report: nil,
                  level: nil, state: .open, seen: 1, at: now, cost: 0, note: nil, builderID: s.source == "builders" ? s.subject : nil,
                  lookedFixed: false, snoozeUntil: nil, canInvestigate: false)
    }

    /// Source 2 (git): code observed it, code writes the report. No Jev, no Claude.
    private func createCodeMade(_ s: WatcherSignal, evidence: String) {
        let item = makeItem(s, evidence: evidence)
        emit(InboxEvent(.created, id: item.id, at: now, item: item))
        let report = ItemReport(title: s.title, what: s.facts.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n"),
                                cause: "Commits were made here and never pushed.", sure: "high", evidence: [],
                                fix: .init(summary: "Review and push the branch when ready.", steps: ["Review the commits", "git push"],
                                           commands: ["git push"], files: []),
                                checked: ["git rev-list against the upstream"], unknowns: [])
        emit(InboxEvent(.reported, id: item.id, at: now, report: report, cost: 0))
        emit(InboxEvent(.levelled, id: item.id, at: now, level: PermissionGate.decide(text: report.fix.text, reply: nil).level))
        channel.deliver(item: items.first { $0.id == item.id } ?? item)
    }

    // MARK: investigation

    func investigate(_ id: String) async {
        guard enabled, let item = items.first(where: { $0.id == id }), !running.contains(id) else { return }
        let t = today()
        let hhmm = { () -> String in let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: self.d.now()) }
        let cap = min(duty.budget.perRunUSD, duty.budget.dailyUSD - t.usd)
        if cap < 0.05 || t.runs >= duty.budget.runsPerDay || (t.perRepo[item.repo] ?? 0) >= 3 || !running.isEmpty {
            emit(InboxEvent(.reported, id: id, at: now, report: item.report, note: "Budget reached at \(hhmm())"))
            decision("budget-stop", ["item": id]); return
        }
        running.insert(id); defer { running.remove(id) }
        Investigation.prepare(paths: d.paths, duty: duty, memory: memory())
        let builderDir = items.first { $0.id == id }?.builderID.flatMap { bid in
            HubStoreBuilders.dir(bid) }
        let argv = Investigation.argv(paths: d.paths, maxBudgetUSD: cap, maxTurns: duty.budget.maxTurns, addDir: builderDir)
        let sig = WatcherSignal(source: item.source, kind: item.kind, subject: item.subject, repo: item.repo, facts: [:],
                                evidence: item.evidence, codeFact: false, title: item.title)
        let prompt = Investigation.prompt(signal: sig, evidence: item.evidence, gitFacts: "")
        let (status, out) = await d.runner(argv, item.repo, prompt, ["AGENT_BURN_MAIN": "1"])
        switch Investigation.parse(status: status, output: out) {
        case let .report(rep, cost, _):
            ledger(usd: cost, runs: 1, repo: item.repo)
            let clean = rep.mapped(Redact.secrets)
            emit(InboxEvent(.reported, id: id, at: now, report: clean, cost: cost))
            let denyText = (clean.fix.commands + clean.fix.steps + clean.fix.files).joined(separator: "\n") + "\n" + clean.fix.text
            let reply = await jevAsk(PermissionGate.state(text: clean.fix.text, repo: item.repo, problem: clean.what), PermissionGate.questions)
            let pre = duty.preapproved.contains { $0.actionKind == item.kind && $0.repo == item.repo }
            let dec = PermissionGate.decide(text: clean.fix.text, denyText: denyText, reply: reply, ceiling: duty.ceiling, preapproved: pre)
            emit(InboxEvent(.levelled, id: id, at: now, level: dec.level))
            decision("level", ["item": id, "level": dec.level.rawValue, "why": dec.reasons])
        case let .stopped(why, cost):
            ledger(usd: cost, runs: 1, repo: item.repo)
            emit(InboxEvent(.reported, id: id, at: now, report: item.report, cost: cost, note: why))
        }
        if let it = items.first(where: { $0.id == id }) { channel.deliver(item: it) }
    }

    // MARK: approve / reject

    enum ApproveResult: Equatable { case started(String), handOff, refused(String) }

    func approve(_ id: String) async -> ApproveResult {
        guard let item = items.first(where: { $0.id == id }), let rep = item.report else { return .refused("Nothing to approve yet") }
        guard item.level == .askFirst else { return .handOff }
        let fixText = rep.fix.text
        let brief = fixText + "\n\nEvidence:\n" + rep.evidence.map { "\($0.path) \($0.lines): \($0.quote)" }.joined(separator: "\n")
            + "\n\nCommit on your branch only; do not push, deploy, send or delete; stop if the fix needs any of these.\n"
        let hits = DenyList.hits(fixText + "\n" + (rep.fix.commands + rep.fix.steps).joined(separator: "\n")).filter { !$0.isEmpty }
        if !hits.isEmpty { return .refused("Deny-list: \(hits.joined(separator: ", "))") }
        let dir = home.appendingPathComponent("runs/\(id)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let f = dir.appendingPathComponent("fix.md")
        try? brief.write(to: f, atomically: true, encoding: .utf8)
        let argv = [d.builderBin, "start", "--name", "fix-\(id)", "--cwd", item.repo, "--model", "sonnet",
                    "--budget", String(format: "%.2f", duty.budget.fixUSD), "--worktree", "--prompt-file", f.path]
        let (code, out) = await d.spawn(argv)
        guard code == 0, let bid = BuilderSpawn.startedID(in: out) else { return .refused("Could not start the fix builder") }
        emit(InboxEvent(.approved, id: id, at: now, cost: 0, builder: bid))
        decision("approved", ["item": id, "builder": bid])
        return .started(bid)
    }

    static let rejectReasons = ["Not a problem", "Already handled", "Wrong cause", "Not now"]

    func reject(_ id: String, reason: String) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let t = now
        switch reason {
        case "Not now":
            emit(InboxEvent(.snoozed, id: id, at: t, until: t + 24 * 3600)); return
        case "Already handled":
            emit(InboxEvent(.resolved, id: id, at: t, reason: reason))
        default:
            emit(InboxEvent(.rejected, id: id, at: t, reason: reason))
        }
        var lesson: [String: Any] = ["at": t, "reason": reason, "source": item.source, "kind": item.kind, "repo": item.repo, "title": item.title]
        if reason == "Not a problem" { lesson["muteUntil"] = t + 30 * 86400 }
        appendLine("lessons.jsonl", lesson)
        writeMemory()
    }

    private func isMuted(_ s: WatcherSignal) -> Bool {
        readLines("lessons.jsonl").contains {
            ($0["source"] as? String) == s.source && ($0["kind"] as? String) == s.kind && ($0["repo"] as? String) == s.repo
                && (($0["muteUntil"] as? Double) ?? 0) > now
        }
    }

    // MARK: memory.md (≤ 60 lines, newest first, hand-editable Preferences)

    func memory() -> String { (try? String(contentsOf: home.appendingPathComponent("memory.md"), encoding: .utf8)) ?? "" }

    func writeMemory() {
        let cur = memory()
        var prefs = "(Add things the Watcher should always know, one per line.)"
        if let a = cur.range(of: "## Preferences\n"), let b = cur.range(of: "\n## Lessons") , a.upperBound <= b.lowerBound {
            prefs = String(cur[a.upperBound..<b.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let prefLines = prefs.split(separator: "\n", omittingEmptySubsequences: false).prefix(20)
        let budget = max(0, 60 - 4 - prefLines.count)
        let lessons = readLines("lessons.jsonl").reversed().prefix(budget).map { l -> String in
            let r = (l["reason"] as? String) ?? "", t = (l["title"] as? String) ?? "", repo = ((l["repo"] as? String) ?? "") as NSString
            return "- \(r): \(t) (\(repo.lastPathComponent))"
        }
        let text = "# Watcher memory\n## Preferences\n" + prefLines.joined(separator: "\n") + "\n## Lessons\n" + lessons.joined(separator: "\n") + "\n"
        try? text.write(to: home.appendingPathComponent("memory.md"), atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: home.appendingPathComponent("memory.md").path)
    }

    // MARK: events from the app

    /// Called on WorkAwake's existing tick and on builder changes: scan builders, handle new signals, run done checks.
    func checkStuck() {
        guard enabled else { return }
        let builders = HubStore.shared.builders
        Task { @MainActor in await self.scan(builders: builders); await self.checkDone(builders: builders); await self.gitSweep(builders); self.digestIfDue() }
    }

    func scan(builders: [BuilderRecord]) async {
        let handled = Set(items.map(\.fingerprint))
        let sigs = BuilderSignals.scan(builders, now: now, handled: handled, resultText: { b in
            b.dir.flatMap { try? String(contentsOfFile: $0 + "/result.md", encoding: .utf8) } })
        for s in sigs { await handle(s) }
    }

    /// Unpushed-work check for the repos of known builders; at most hourly (events only, no timer).
    private var lastGitSweep: Date = .distantPast
    func gitSweep(_ builders: [BuilderRecord]) async {
        guard d.now().timeIntervalSince(lastGitSweep) >= 3600 else { return }
        lastGitSweep = d.now()
        for repo in Set(builders.map(\.originCwd).filter { !$0.isEmpty }) { await scanGit(repo: repo, builders: builders) }
    }

    func scanGit(repo: String, builders: [BuilderRecord]) async {
        for s in GitSignals.check(repo: repo, builders: builders, now: now, run: d.git) { await handle(s) }
    }

    func abandoned(pane: UUID, verdict: OverseerVerdict) {
        guard enabled, let s = AbandonedSignals.signal(pane: pane, verdict: verdict) else { return }
        Task { @MainActor in await self.handle(s) }
    }

    /// Quit snapshot of standing failures; replayed next launch.
    func snapshotPending(_ signals: [WatcherSignal]) {
        let u = home.appendingPathComponent("pending.jsonl")
        let text = signals.compactMap(AbandonedSignals.encode).joined(separator: "\n")
        try? text.write(to: u, atomically: true, encoding: .utf8)
    }

    func replayPending() async {
        let u = home.appendingPathComponent("pending.jsonl")
        guard let s = try? String(contentsOf: u, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: u)
        for l in s.split(separator: "\n") { if let sig = AbandonedSignals.decode(String(l)) { await handle(sig) } }
    }

    // MARK: done check

    func checkDone(builders: [BuilderRecord]) async {
        for item in items where item.state == .open && !item.lookedFixed {
            if item.source == "git" {
                let parts = item.subject.split(separator: "@", maxSplits: 1).map(String.init)
                guard parts.count == 2, let up = GitSignals.parseBranches(d.git(GitSignals.branchesArgv(repo: item.repo)) ?? "")
                        .first(where: { $0.branch == parts[1] })?.upstream else { continue }
                if GitSignals.parseAhead(d.git(GitSignals.aheadArgv(repo: item.repo, upstream: up, branch: parts[1])) ?? "").isEmpty {
                    emit(InboxEvent(.resolved, id: item.id, at: now, reason: "Pushed")); decision("done-code", ["item": item.id])
                }
            } else if item.source == "builders", let b = builders.first(where: { $0.id == item.subject }) {
                if b.acked { emit(InboxEvent(.resolved, id: item.id, at: now, reason: "Acknowledged")); continue }
                let later = builders.filter { $0.name == b.name && $0.started > b.started && $0.state == .done }
                guard let l = later.first else { continue }
                let st: [String: Any] = ["item": ["title": item.title, "evidence": String(item.evidence.prefix(600))],
                                         "later": ["name": l.name, "state": "done", "repo": l.originCwd]]
                let r = await jevAsk(st, WatcherQuestions.doneQuestions)
                if WatcherQuestions.looksFixed(reply: r) { emit(InboxEvent(.lookedFixed, id: item.id, at: now)) }
            }
        }
    }

    // MARK: digest

    func digestIfDue() {
        guard enabled else { return }
        let cal = Calendar.current
        guard cal.component(.hour, from: d.now()) >= duty.digest.notBefore else { return }
        let last = (readLines("state.jsonl").last?["lastDigest"] as? Double) ?? 0
        guard now - last >= Double(duty.digest.everyHours) * 3600 else { return }
        let open = needsYou
        guard !open.isEmpty else { return }
        appendLine("state.jsonl", ["lastDigest": now])
        channel.deliver(digest: "\(open.count) thing\(open.count == 1 ? "" : "s") waiting: " + open.prefix(3).map(\.title).joined(separator: "; "))
    }
}

/// Builder dirs for `--add-dir` (read-only access to its stream and result).
enum HubStoreBuilders {
    @MainActor static func dir(_ id: String) -> String? { HubStore.shared.builders.first { $0.id == id }?.dir }
}
