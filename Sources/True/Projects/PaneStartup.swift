import Foundation

/// A one-shot "run this instead of a bare shell" for a pane about to be created. Consumed by
/// `EmbeddedTerminal.makeNSView` and never persisted. A restored pane is a plain shell unless the
/// workspace recorded a Claude conversation for it, in which case `WorkspaceModel.init` registers a
/// `--resume` command here before any view exists. (Not an agent: no `launchSpecs`, no `TRUE_AGENT`, never counted by `isAgentPane`.)
@MainActor
final class PaneStartup {
    static let shared = PaneStartup()
    private var commands: [UUID: String] = [:]

    func set(_ command: String, for pane: UUID) { commands[pane] = command }

    /// Returns the command once; a second call (or a pane that never had one) gets nil.
    func take(_ pane: UUID) -> String? { commands.removeValue(forKey: pane) }

    /// Login + interactive so the user's `claude` alias (claude-burn) and PATH apply. When claude exits,
    /// the pane becomes a normal login shell in the repo instead of closing. `--settings` adds True's
    /// hook layer (on top of the user's own settings) so the session reports Working/Needs you/Done.
    nonisolated static func claudeCommand(settings: String) -> String {
        "claude --settings \(AgentLaunch.shellQuote(settings)); exec \"${SHELL:-/bin/zsh}\" -l"
    }

    /// Resume a recorded conversation in its pane; nil unless `sessionID` is a UUID (it goes into a shell line).
    /// `prompt` (interrupted sessions only) rides as the final positional argument: the session's first message.
    nonisolated static func resumeCommand(sessionID: String, settings: String, prompt: String? = nil) -> String? {
        guard UUID(uuidString: sessionID) != nil else { return nil }
        let tail = prompt.map { " " + AgentLaunch.shellQuote($0) } ?? ""
        return "claude --resume \(sessionID) --settings \(AgentLaunch.shellQuote(settings))\(tail); exec \"${SHELL:-/bin/zsh}\" -l"
    }

    /// The shell argv that runs `command`.
    nonisolated static func shellArgs(for command: String) -> [String] { ["-l", "-i", "-c", command] }
}
