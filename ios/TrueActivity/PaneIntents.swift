import ActivityKit
import AppIntents

/// Lock-screen Approve / Deny. LiveActivityIntents run in the app's process (even when the phone is locked),
/// so they reach the Mac through the same RemoteSession + Keychain token the app uses.
struct ApprovePaneIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Approve"
    @Parameter(title: "Pane") var paneId: String
    init() {}
    init(paneId: String) { self.paneId = paneId }
    func perform() async throws -> some IntentResult {
        await PaneActivityAnswer.send(.approve, pane: paneId)
        return .result()
    }
}

struct DenyPaneIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Deny"
    @Parameter(title: "Pane") var paneId: String
    init() {}
    init(paneId: String) { self.paneId = paneId }
    func perform() async throws -> some IntentResult {
        await PaneActivityAnswer.send(.deny, pane: paneId)
        return .result()
    }
}

enum PaneActivityAnswer {
    /// Mark the activity "sent" first so a second tap finds no buttons, then ask the Mac. A failure puts the buttons back.
    static func send(_ answer: LockScreenAnswer, pane: String) async {
        let before = await setStatus("sent", pane: pane)
        guard let url = SharedConfig.baseURL else { _ = await setStatus(before, pane: pane); return }
        let session = RemoteSession(baseURL: url, store: KeychainTokenStore())
        do {
            let outcome = try await session.paneInput(id: pane, intent: answer.intent, text: answer.text)
            switch outcome {
            case .promptGone, .noPane:
                // Nothing left to answer on the Mac: say so instead of offering Approve again.
                _ = await setStatus("gone", pane: pane)
            default:
                if LockScreenAnswer.followUp(for: outcome) != nil { _ = await setStatus(before, pane: pane) }
            }
        } catch { _ = await setStatus(before, pane: pane) }
    }

    /// Returns the status it replaced (so a failure can restore it); nil when there is no such activity.
    @discardableResult
    static func setStatus(_ status: String?, pane: String) async -> String? {
        guard let status,
              let activity = Activity<PaneActivityAttributes>.activities.first(where: { $0.attributes.paneId == pane })
        else { return nil }
        var state = activity.content.state
        let old = state.status
        guard old != status else { return old }
        state.status = status
        await activity.update(ActivityContent(state: state, staleDate: nil))
        return old
    }
}
