import ActivityKit
import Foundation

/// Live Activities for panes that need you: one per pane, started when the row appears, updated when the question
/// changes, ended when the row resolves or after 30 minutes. At most 3, the most recent. Fed by the same hub snapshot
/// as the notifications. Silent no-op when Live Activities are off (the notifications still work).
/// Caveat: iOS only lets an app START an activity while it is in the foreground; updating and ending work in the background.
@MainActor
enum PaneActivities {
    static let maxActive = 3
    static let lifetime: TimeInterval = 30 * 60
    /// "pane|question" pairs already ended by the 30-minute limit, so a row that is still waiting is not restarted each poll.
    private static var expired: Set<String> = []

    /// Why the last start could not happen (shown once by the app), nil when fine.
    private(set) static var lastProblem: String?
    private static var reported: String?

    /// A problem the app has not shown yet, or nil.
    static func unreportedProblem() -> String? {
        guard let p = lastProblem, p != reported else { return nil }
        reported = p; return p
    }

    static func sync(_ snap: HubSnapshot) async {
        let needing = snap.projects.flatMap(\.rows).filter { $0.statusKey == "needsYou" && $0.pane != nil }
        let panes = Set(needing.compactMap(\.pane))
        expired = expired.filter { panes.contains(String($0.split(separator: "|", maxSplits: 1)[0])) }
        let now = Date()

        for a in Activity<PaneActivityAttributes>.activities {
            let key = a.attributes.paneId + "|" + a.content.state.question
            if !panes.contains(a.attributes.paneId) {
                await a.end(nil, dismissalPolicy: .immediate)
            } else if now.timeIntervalSince(a.content.state.since) > lifetime {
                expired.insert(key)
                await a.end(nil, dismissalPolicy: .immediate)
            }
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            if !needing.isEmpty { lastProblem = "Live Activities are off for True in Settings" }
            return
        }
        for row in needing {
            guard let pane = row.pane else { continue }
            let question = row.question ?? "Needs your answer"
            if let a = Activity<PaneActivityAttributes>.activities.first(where: { $0.attributes.paneId == pane }) {
                if a.content.state.question != question || a.content.state.kind != row.needKind {
                    let s = PaneActivityAttributes.ContentState(question: question, tool: row.tool, status: "needsYou", since: Date(), kind: row.needKind)
                    await a.update(ActivityContent(state: s, staleDate: nil))
                }
                continue
            }
            guard !expired.contains(pane + "|" + question) else { continue }
            let live = Activity<PaneActivityAttributes>.activities.sorted { $0.content.state.since < $1.content.state.since }
            if live.count >= maxActive, let oldest = live.first { await oldest.end(nil, dismissalPolicy: .immediate) }
            let s = PaneActivityAttributes.ContentState(question: question, tool: row.tool, status: "needsYou", since: Date(), kind: row.needKind)
            do {
                _ = try Activity.request(attributes: PaneActivityAttributes(paneId: pane, name: row.name),
                                         content: ActivityContent(state: s, staleDate: nil))
                lastProblem = nil
            } catch {
                lastProblem = "Live Activity didn't start: \(error.localizedDescription)"
            }
        }
    }
}
