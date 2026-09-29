import Foundation

/// Pure builders for how an awake agent starts: the role card it boots with and the exact `claude`
/// argv. Nothing here executes anything — `AgentLaunchTests` asserts on the returned strings.
enum AgentLaunch {
    /// The exact argv (argv[0] = "claude", resolved by the pane's login shell).
    static func argv(_ a: Agent, paths: AgentPaths, resumeID: String?) -> [String] {
        var v = ["claude",
                 "--name", a.name,
                 "--model", a.model.rawValue,
                 "--effort", a.effort.rawValue,
                 "--permission-mode", a.permission.rawValue,
                 "--append-system-prompt-file", paths.rolePath(a.name),
                 "--settings", paths.settingsPath(a.name)]
        if let id = resumeID, !id.isEmpty { v += ["--resume", id] }
        return v
    }

    /// POSIX single-quote: survives the pane's `sh -c` wrap untouched.
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// What the pane's login shell runs. `exec` replaces the shell with claude, so SIGTERM on the
    /// pane's pid lands on claude itself. A missing `claude` leaves a usable shell and says why,
    /// rather than a pane that flashes and vanishes.
    static func shellCommand(argv: [String]) -> String {
        "command -v claude >/dev/null 2>&1 || { echo \"True: 'claude' was not found on PATH\"; exec \"${SHELL:-/bin/zsh}\" -l; }; exec "
            + argv.map(shellQuote).joined(separator: " ")
    }

    /// Claude keeps a repo's transcripts in `<config>/projects/<cwd with / and . as ->/<id>.jsonl`.
    /// `--resume` finds a session only under the cwd it boots in, and an unknown id would fail the
    /// boot — so resume only when the id is a UUID (it goes into a shell line) AND that file exists.
    static func resumeID(for a: Agent, claudeDir: URL = claudeConfigDir) -> String? {
        guard let id = a.lastSessionID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty,
              UUID(uuidString: id) != nil else { return nil }
        let project = a.repo.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-")
        let file = claudeDir.appendingPathComponent("projects/\(project)/\(id).jsonl").path
        return FileManager.default.fileExists(atPath: file) ? id : nil
    }

    static var claudeConfigDir: URL {
        if let d = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !d.isEmpty {
            return URL(fileURLWithPath: d)
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude")
    }

    // MARK: Role card

    /// The standing brief (`--append-system-prompt-file`), rewritten on every wake so an edited
    /// charter or team reaches the agent next boot with nothing to invalidate.
    static func roleCard(_ a: Agent, all: [Agent]) -> String {
        let slug = AgentNaming.repoSlug(a.repo)
        var out: String
        switch a.role {
        case .lead:
            let helpers = a.team.isEmpty
                ? "You have no helpers configured yet — do the work yourself."
                : a.team.map { name -> String in
                    let m = all.first { $0.name == name }
                    return "- `\(name)`" + (m.map { " (\($0.model.label), \($0.effort.label) effort)" } ?? "")
                }.joined(separator: "\n")
            out = """
            # Role: Lead on \(a.repoName)

            You are `\(a.name)`, the lead agent for \(a.repoName) (\(a.repo)). The user talks to you;
            you hand bounded work to your helpers and stay accountable for the result.

            Your helpers:
            \(helpers)

            ## Protocol
            1. Split the request into bounded tasks. Each hand-off names the owner, the objective, the
               files they may touch and how you will check the result.
            2. Hand work to a helper by name with the `SendMessage` tool (`to: "<helper name>"`). A helper
               that is asleep cannot receive it — say so to the user instead of retrying.
            3. Review what comes back (diff, tests) before calling anything done. Report outcomes with
               evidence, never on a helper's word alone.
            4. If a helper is waiting on a decision only you can make, answer it before anything else.
            """
        case .helper:
            let lead = all.first { $0.role == .lead && AgentNaming.repoSlug($0.repo) == slug }?.name
                ?? AgentNaming.leadName(slug: slug)
            out = """
            # Role: Helper on \(a.repoName)

            You are `\(a.name)`, a helper agent for \(a.repoName) (\(a.repo)). Your lead is `\(lead)`.

            ## Protocol
            1. Work on what your lead assigns, inside the files they name. Do not widen scope.
            2. When done, reply to `\(lead)` with `SendMessage`: a one-line summary, what changed and the
               verification output. No "done" without evidence.
            3. If you are blocked or need a decision, message `\(lead)` with the exact question, then stop.
            """
        }
        let charter = a.charter.trimmingCharacters(in: .whitespacesAndNewlines)
        if !charter.isEmpty { out += "\n\n## Charter\n\(charter)" }
        return out + "\n"
    }
}
