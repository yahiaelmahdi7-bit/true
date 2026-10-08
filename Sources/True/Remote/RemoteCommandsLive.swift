import Foundation
import AppKit

/// Panes opened from the phone, so the Mac can tag them "from iPhone" for 10 minutes.
final class RemoteOrigin: @unchecked Sendable {
    static let shared = RemoteOrigin()
    static let window: TimeInterval = 600
    private let lock = NSLock()
    private var panes: [UUID: Date] = [:]

    func mark(_ pane: UUID, now: Date = Date()) {
        lock.lock(); panes[pane] = now; lock.unlock()
    }

    func isRecent(_ pane: UUID, now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let t = panes[pane] else { return false }
        if now.timeIntervalSince(t) >= Self.window { panes[pane] = nil; return false }
        return true
    }
}

/// The Hub as JSON, from the Mac Hub's own groups (HubModel.build): same grouping, order, counts and status labels.
enum RemoteHubJSON {
    static func make(groups: [HubProjectGroup], seatStatus: (String) -> AgentStatus, seatPane: (String) -> UUID?,
                     now: Double) -> [String: Any] {
        let projects: [[String: Any]] = groups.map { g in
            var rows: [[String: Any]] = g.seats.map { a in
                let st = seatStatus(a.name)
                var r: [String: Any] = ["kind": "seat", "id": "seat-\(a.name)", "name": a.name, "status": st.label,
                                        "statusKey": st.rawValue, "model": a.model.rawValue]
                if let p = seatPane(a.name) { r["pane"] = p.uuidString }
                return r
            }
            rows += g.background.map { b in
                ["kind": "background", "id": "builder-\(b.id)", "name": b.name, "status": b.statusLabel,
                 "statusKey": b.status.rawValue, "builderId": b.id, "acked": b.acked, "model": b.model,
                 "elapsed": b.elapsed(now: now), "branch": b.branch ?? NSNull()] as [String: Any]
            }
            rows += g.others.map { p in
                let st: AgentStatus = p.busy ? .working : .idle
                return ["kind": "other", "id": "peer-\(p.pid)", "name": p.displayName, "status": st.label,
                        "statusKey": st.rawValue, "cwd": p.cwd, "updated": p.updatedAt] as [String: Any]
            }
            return ["key": g.key, "title": g.title, "summary": g.summary, "working": g.working, "needsYou": g.needsYou,
                    "failed": g.failed, "rows": rows]
        }
        let w = groups.reduce(0) { $0 + $1.working }, n = groups.reduce(0) { $0 + $1.needsYou }
        let f = groups.reduce(0) { $0 + $1.failed }
        var parts: [String] = []
        if w > 0 { parts.append("\(w) working") }
        if n > 0 { parts.append("\(n) needs you") }
        if f > 0 { parts.append("\(f) failed") }
        return ["now": now, "working": w, "needsYou": n, "failed": f, "summary": parts.joined(separator: " · "),
                "projects": projects]
    }

    /// A builder id is a folder name under ~/.claude/builders: plain characters only, and it must be one the Hub knows.
    static func isValidBuilderID(_ id: String, known: [BuilderRecord]) -> Bool {
        guard !id.isEmpty, id.utf8.count <= 80,
              id.unicodeScalars.allSatisfy({ ($0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0))) || $0 == "-" || $0 == "_" })
        else { return false }
        return known.contains { $0.id == id }
    }

    /// Mark a builder acknowledged: the same `acked: true` the builder CLI writes into meta.json. Id must be known.
    static func ack(id: String, known: [BuilderRecord]) -> Bool {
        guard isValidBuilderID(id, known: known), let dir = known.first(where: { $0.id == id })?.dir else { return false }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: url),
              var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        obj["acked"] = true
        guard let out = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return false }
        return (try? out.write(to: url, options: .atomic)) != nil
    }
}

private final class JevBox: @unchecked Sendable { var reply: JevReply? }

struct RemoteCommandsLive: RemoteCommands {
    private static func onMain<T: Sendable>(_ f: @MainActor () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated { f() } }
        return DispatchQueue.main.sync { MainActor.assumeIsolated { f() } }
    }

    private var logURL: URL { CommandBarLog.standard.dir.appendingPathComponent("remote.jsonl") }

    func environment() -> BarEnvironment { Self.onMain { BarEnvironmentProvider.live() } }
    func isExecutable(_ name: String) -> Bool { BarEnvironmentProvider.onPath(name) }
    var jevEnabled: Bool { TerminalSettings.jevRouting }

    func jev(text: String, context: CommandContext, rule: RuleMatch?) -> JevReply? {
        let box = JevBox(), sem = DispatchSemaphore(value: 0)
        Task.detached {
            box.reply = await CommandRouter.ask(text: text, context: context, rule: rule, jev: .shared,
                                                isExecutable: { BarEnvironmentProvider.onPath($0) })
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + CommandRouter.timeout + 1)
        return box.reply
    }

    func launch(_ plan: Plan, route r: Route) -> RemoteLaunch {
        let rec = CommandBarLog.Record(event: .run, text: plan.argv.last ?? r.text, latencyMs: nil, route: r,
                                       door: String(describing: plan.door), background: false)
        CommandBarLog.standard.append(rec)
        return Self.onMain {
            let ws = WorkspaceModel.shared
            var pane: UUID?
            switch plan.door {
            case .newClaudePane(let cwd):
                let cmd = CommandExecutor.startupCommand(argv: plan.argv, settings: AgentPaths.standard.paneSettingsPath)
                pane = ws.openProjectBeside(path: cwd ?? NSHomeDirectory(), startupCommand: cmd)
            case .newShellSplit(let cwd):
                let text = plan.argv.last ?? ""
                let new = ws.split(.horizontal, cwd: cwd ?? NSHomeDirectory())
                if plan.autoSubmit { PaneStartup.shared.set("\(text); exec \"${SHELL:-/bin/zsh}\" -l", for: new) }
                else {
                    Task { @MainActor in
                        for _ in 0..<20 {
                            try? await Task.sleep(for: .milliseconds(100))
                            if let v = TerminalRegistry.shared.view(for: new) { v.send(txt: text); return }
                        }
                    }
                }
                pane = new
            case .background(let name, _, _):
                CommandExecutor.run(plan, route: r, onBackground: { result in
                    if case .failure(let e) = result { CommandBarLog.logger.error("remote background spawn failed: \(e.message, privacy: .public)") }
                })
                return .background(name)
            case .seat(let n):
                CommandExecutor.run(plan, route: r)
                pane = AgentRegistry.shared.panes[n]
            case .trueAction:
                CommandExecutor.run(plan, route: r)
                pane = ws.selectedTab.focusedPane
            default:
                return .failed("not allowed from the phone")
            }
            guard let p = pane else { return .done }
            RemoteOrigin.shared.mark(p)
            return .pane(p)
        }
    }

    func history() -> [String] { CommandBarLog.standard.loadHistory() }
    func pushHistory(_ text: String) {
        let log = CommandBarLog.standard
        log.saveHistory(CommandBarLog.pushed(text, onto: log.loadHistory()))
    }

    func hubJSON() -> Data {
        return Self.onMain {
            let reg = AgentRegistry.shared, hub = HubStore.shared
            let now = Date().timeIntervalSince1970
            let groups = HubModel.build(seats: reg.crew, seatStatus: { reg.statusOf($0) }, seatAwake: { reg.isAwake($0) },
                                        peers: hub.peers, builders: hub.builders, now: now)
            let obj: [String: Any] = RemoteHubJSON.make(groups: groups, seatStatus: { reg.statusOf($0) }, seatPane: { reg.panes[$0] }, now: now)
            return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        }
    }

    func builderDetail(id: String) -> Data? {
        let builders = Self.onMain { HubStore.shared.builders }
        guard RemoteHubJSON.isValidBuilderID(id, known: builders), let b = builders.first(where: { $0.id == id }) else { return nil }
        let obj: [String: Any] = ["id": b.id, "name": b.name, "status": b.statusLabel, "acked": b.acked,
                                  "canAck": b.state != .running, "text": String(HubScanner.detail(of: b).prefix(20_000))]
        return try? JSONSerialization.data(withJSONObject: obj)
    }

    func ackBuilder(id: String) -> Bool {
        let builders = Self.onMain { HubStore.shared.builders }
        let ok = RemoteHubJSON.ack(id: id, known: builders)
        if ok { Task { @MainActor in await HubStore.shared.reload() } }
        return ok
    }

    func record(_ line: [String: Any]) {
        let fm = FileManager.default
        let dir = CommandBarLog.standard.dir
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard var data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) else { return }
        data.append(10)
        if !fm.fileExists(atPath: logURL.path) { fm.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
        if let h = try? FileHandle(forWritingTo: logURL) {
            _ = try? h.seekToEnd(); try? h.write(contentsOf: data); try? h.close()
        }
    }
}
