import Foundation
import BackgroundTasks
import UserNotifications

/// Needs-you notifications (the diff and posting live in Notifications): no server push exists, so the system wakes the app ~every 15 min and it asks the Mac.
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
        await Notifications.process(snap)
    }
}
