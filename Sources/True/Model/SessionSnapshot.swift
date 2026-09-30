import Foundation
import AppKit

/// Glue between the live terminals and the workspace's resume records. All calls are event-driven:
/// quit, window close, a one-shot after Return, and a Claude `session` hook.
@MainActor
enum SessionSnapshot {
    static var sessionsDir: URL { AgentLaunch.claudeConfigDir.appendingPathComponent("sessions") }

    /// Look at the pane's live shell: alive?, and which interactive Claude runs beneath it.
    static func probe(_ pane: UUID) -> (alive: Bool, found: ClaudeSessions.Found?) {
        guard let v = TerminalRegistry.shared.view(for: pane), v.process.running, v.process.shellPid > 0 else {
            return (false, nil)
        }
        let found = ClaudeSessions.find(under: v.process.shellPid, sessionsDir: sessionsDir,
                                        children: ClaudeSessions.liveChildren)
        return (true, found)
    }

    static func record(_ model: WorkspaceModel = .shared) { model.recordResume(probe: probe) }

    /// Quit or window close: record, save, then stop reacting to the shells dying.
    static func atQuit(_ model: WorkspaceModel = .shared) {
        model.freeze { record(model) }
    }

    private static var pending: [UUID: Task<Void, Never>] = [:]

    /// ~2.5 s after Return in `pane` (debounced per pane): the crash / force-quit safety net.
    static func scheduleAfterReturn(pane: UUID) {
        pending[pane]?.cancel()
        pending[pane] = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2500))
            guard !Task.isCancelled else { return }
            pending[pane] = nil
            let (alive, found) = probe(pane)
            let m = WorkspaceModel.shared
            guard let t = m.state.tabs.first(where: { $0.tree.contains(pane) }) else { return }
            m.setResume(SessionRecorder.decide(previous: t.resume?[pane], agent: m.agentName?(pane),
                                               alive: alive, found: found), pane: pane)
        }
    }
}
