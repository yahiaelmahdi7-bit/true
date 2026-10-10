import Foundation
import UserNotifications

/// Lock-screen notifications for panes that need you or just finished. One pipeline, fed by every hub snapshot:
/// the live poll loop (so an on-duty, locked phone notifies within one poll) and the ~15 min background refresh.
enum Notifications {
    static let needsCategory = "pane.needsYou"
    static let doneCategory = "pane.done"
    static let approve = "approve", deny = "deny", reply = "reply"

    static var onDuty: Bool { UserDefaults.standard.bool(forKey: "onDuty") }

    static func registerCategories() {
        let replyAction = UNTextInputNotificationAction(identifier: reply, title: "Reply…", options: [],
                                                        textInputButtonTitle: "Send", textInputPlaceholder: "Message")
        let needs = UNNotificationCategory(
            identifier: needsCategory,
            actions: [UNNotificationAction(identifier: approve, title: "Approve", options: []),
                      UNNotificationAction(identifier: deny, title: "Deny", options: []),
                      replyAction],
            intentIdentifiers: [], options: [])
        let done = UNNotificationCategory(identifier: doneCategory, actions: [replyAction], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([needs, done])
    }

    /// Diff a snapshot against what was already announced: post new needs-you, clear resolved, and (on duty) post finished turns.
    static func process(_ snap: HubSnapshot) async {
        let center = UNUserNotificationCenter.current()
        let plan = NeedsYouNotifier.plan(old: SharedConfig.notifiedIDs, new: snap)
        SharedConfig.notifiedIDs = snap.needsYouIDs
        if !plan.clear.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: plan.clear.map { "needs-\($0)" })
        }
        for row in plan.fire {
            let c = UNMutableNotificationContent()
            c.title = "\(row.name) needs you"
            c.body = NeedsYouNotifier.body(for: row)
            c.sound = .default
            c.interruptionLevel = .timeSensitive
            c.categoryIdentifier = needsCategory
            c.threadIdentifier = row.pane ?? row.id
            c.userInfo = userInfo(row)
            try? await center.add(UNNotificationRequest(identifier: "needs-\(row.id)", content: c, trigger: nil))
        }
        let oldWorking = SharedConfig.workingIDs
        SharedConfig.workingIDs = NeedsYouNotifier.workingIDs(snap)
        guard onDuty else { return }
        for row in NeedsYouNotifier.donePlan(oldWorking: oldWorking, new: snap) {
            let c = UNMutableNotificationContent()
            c.title = "\(row.name) finished"
            c.body = row.status
            c.sound = .default
            c.categoryIdentifier = doneCategory
            c.threadIdentifier = row.pane ?? row.id
            c.userInfo = userInfo(row)
            try? await center.add(UNNotificationRequest(identifier: "done-\(row.id)", content: c, trigger: nil))
        }
    }

    private static func userInfo(_ row: HubRow) -> [AnyHashable: Any] {
        guard let pane = row.pane else { return ["rowId": row.id] }
        return ["url": "true://pane/\(pane)", "pane": pane, "rowId": row.id]
    }

    /// Run a lock-screen button. Builds its own session: the app may have been launched cold by the action.
    static func answer(_ answer: LockScreenAnswer, pane: String) async {
        guard let url = SharedConfig.baseURL else { return }
        let session = RemoteSession(baseURL: url, store: KeychainTokenStore())
        do {
            let outcome = try await session.paneInput(id: pane, intent: answer.intent, text: answer.text)
            if let msg = LockScreenAnswer.followUp(for: outcome) { await note(msg) }
        } catch { await note("Couldn't reach the Mac") }
    }

    /// A quiet follow-up: no sound, passive.
    static func note(_ text: String) async {
        let c = UNMutableNotificationContent()
        c.title = text
        c.interruptionLevel = .passive
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "note-\(UUID().uuidString)", content: c, trigger: nil))
    }
}
