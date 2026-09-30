import Foundation

/// A one-shot "run this instead of a bare shell" for a pane about to be created. Consumed by
/// `EmbeddedTerminal.makeNSView` and never persisted, so a restored tab is always a plain shell.
/// (Not an agent: no `launchSpecs`, no `TRUE_AGENT`, never counted by `isAgentPane`.)
@MainActor
final class PaneStartup {
    static let shared = PaneStartup()
    private var commands: [UUID: String] = [:]

    func set(_ command: String, for pane: UUID) { commands[pane] = command }

    /// Returns the command once; a second call (or a pane that never had one) gets nil.
    func take(_ pane: UUID) -> String? { commands.removeValue(forKey: pane) }

    /// Login + interactive so the user's `claude` alias (claude-burn) and PATH apply. When claude exits,
    /// the pane becomes a normal login shell in the repo instead of closing.
    nonisolated static let claudeCommand = #"claude; exec "$SHELL" -l"#

    /// The shell argv that runs `command`.
    nonisolated static func shellArgs(for command: String) -> [String] { ["-l", "-i", "-c", command] }
}
