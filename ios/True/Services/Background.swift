import Foundation
import BackgroundTasks
import UserNotifications

/// Needs-you notifications: no server push exists, so the system wakes the app ~every 15 min and it asks the Mac.
enum Background {
    static let identifier = "net.prismlens.true.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            schedule()
            let work = Task {
                await check()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let req = BGAppRefreshTaskRequest(identifier: identifier)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func check() async {
        guard let url = SharedConfig.baseURL else { return }
        let session = RemoteSession(baseURL: url, store: KeychainTokenStore())
        guard let snap = try? await session.hub() else { return }
        let old = SharedConfig.notifiedIDs
        let fresh = snap.needsYouIDs.subtracting(old)
        SharedConfig.notifiedIDs = snap.needsYouIDs
        for row in snap.projects.flatMap(\.rows) where fresh.contains(row.id) {
            let c = UNMutableNotificationContent()
            c.title = "\(row.name) needs you"
            c.body = row.cwd ?? "Tap to open"
            c.sound = .default
            c.interruptionLevel = .timeSensitive
            if let pane = row.pane { c.userInfo = ["url": "true://pane/\(pane)"] }
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "needs-\(row.id)", content: c, trigger: nil))
        }
    }
}
