import Foundation
import Darwin

/// What a pane was running when True last looked, so the next launch can put it back.
enum PaneResume: Codable, Equatable, Sendable {
    /// A Claude conversation (`claude --resume <sessionID>` in `cwd`).
    case claude(sessionID: String, cwd: String)
    /// A named agent that was awake; re-woken into this same pane.
    case agent(name: String)
}

/// Finds the Claude Code process under a pane's shell. Every live Claude writes
/// `<claudeConfigDir>/sessions/<pid>.json`; the pane's Claude is a descendant of its shell, often
/// 2–3 levels down (shell → claude-burn loop → claude).
enum ClaudeSessions {
    struct Found: Equatable, Sendable { var sessionID: String; var cwd: String; var pid: pid_t }

    private struct File: Decodable { var sessionId: String?; var cwd: String?; var kind: String? }

    /// Breadth-first, so the shallowest match wins. `children` is injected so tests use a fake tree.
    static func find(under root: pid_t, sessionsDir: URL, maxDepth: Int = 5,
                     children: (pid_t) -> [pid_t]) -> Found? {
        var level = children(root)
        var seen: Set<pid_t> = [root]
        var depth = 1
        while !level.isEmpty, depth <= maxDepth {
            for pid in level where seen.insert(pid).inserted {
                if let f = read(pid, sessionsDir) { return f }
            }
            level = level.flatMap { children($0) }.filter { !seen.contains($0) }
            depth += 1
        }
        return nil
    }

    static func read(_ pid: pid_t, _ dir: URL) -> Found? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("\(pid).json")),
              let f = try? JSONDecoder().decode(File.self, from: data),
              f.kind == "interactive",
              let id = f.sessionId, !id.isEmpty, let cwd = f.cwd, !cwd.isEmpty else { return nil }
        return Found(sessionID: id, cwd: cwd, pid: pid)
    }

    /// Direct children of `pid` from the kernel.
    static func liveChildren(_ pid: pid_t) -> [pid_t] {
        var buf = [pid_t](repeating: 0, count: 256)
        _ = proc_listchildpids(pid, &buf, Int32(buf.count * MemoryLayout<pid_t>.size))
        return buf.filter { $0 > 0 }
    }
}

/// Which panes come back running what. Pure: `WorkspaceModel.init` applies the result.
enum ResumePlan {
    /// Why a `.claude` record did not come back; logged by name at launch.
    enum DropReason: String, Equatable, Sendable {
        case invalidSessionID = "session id is not a UUID"
        case transcriptMissing = "transcript missing"
    }
    struct Dropped: Equatable, Sendable { var pane: UUID; var sessionID: String; var reason: DropReason }
    /// `records` counts every resume record found (claude + agent), so "none at all" is distinguishable.
    struct Result {
        var state: WorkspaceState; var startups: [UUID: String]
        var dropped: [Dropped] = []; var records = 0
    }

    /// For each `.claude` record with a UUID id and a transcript on disk: a startup command and the
    /// pane's cwd set to the record's. Anything invalid is dropped, so the pane is a plain shell.
    /// `.agent` records are left for `AgentRegistry.restore`.
    static func apply(_ state: WorkspaceState, claudeDir: URL, settings: String) -> Result {
        var s = state
        var out: [UUID: String] = [:]
        var dropped: [Dropped] = []
        var records = 0
        for ti in s.tabs.indices {
            guard let map = s.tabs[ti].resume else { continue }
            for (pane, r) in map {
                records += 1
                guard case let .claude(id, cwd) = r else { continue }
                if let cmd = PaneStartup.resumeCommand(sessionID: id, settings: settings) {
                    if AgentLaunch.transcriptExists(id: id, cwd: cwd, claudeDir: claudeDir) {
                        out[pane] = cmd
                        s.tabs[ti].cwds[pane] = cwd
                        continue
                    }
                    dropped.append(Dropped(pane: pane, sessionID: id, reason: .transcriptMissing))
                } else {
                    dropped.append(Dropped(pane: pane, sessionID: id, reason: .invalidSessionID))
                }
                s.tabs[ti].resume?[pane] = nil
            }
            if s.tabs[ti].resume?.isEmpty == true { s.tabs[ti].resume = nil }
        }
        return Result(state: s, startups: out, dropped: dropped, records: records)
    }
}

/// Decides what to store for one pane at snapshot time.
enum SessionRecorder {
    /// - `agent`: the pane belongs to an awake agent → always `.agent`.
    /// - `alive`: the pane's view and shell still exist. A late snapshot must not wipe a good record.
    /// - `found`: the Claude under the shell, if any (only meaningful when `alive`).
    static func decide(previous: PaneResume?, agent: String?, alive: Bool,
                       found: ClaudeSessions.Found?) -> PaneResume? {
        if let a = agent { return .agent(name: a) }
        guard alive else { return previous }
        if let f = found { return .claude(sessionID: f.sessionID, cwd: f.cwd) }
        if case .claude = previous { return nil }
        return previous
    }
}
