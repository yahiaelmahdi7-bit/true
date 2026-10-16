import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var onURL: ((URL) -> Void)?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Notifications.registerCategories()
        Background.register()
        Background.schedule()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        switch response.actionIdentifier {
        case Notifications.approve, Notifications.deny:
            guard let pane = info["pane"] as? String else { return }
            await Notifications.answer(response.actionIdentifier == Notifications.approve ? .approve : .deny, pane: pane)
        case Notifications.reply:
            guard let pane = info["pane"] as? String, let r = response as? UNTextInputNotificationResponse,
                  let answer = LockScreenAnswer.reply(trimming: r.userText) else { return }
            await Notifications.answer(answer, pane: pane)
        case Notifications.open:
            if let s = info["url"] as? String, let u = URL(string: s) { await MainActor.run { onURL?(u) } }
        default:
            if let s = info["url"] as? String, let u = URL(string: s) { await MainActor.run { onURL?(u) } }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
}

@main
struct TrueApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @State private var screenshots = ScreenshotSync()
    @AppStorage("autoScreenshots") private var autoScreenshots = false
    @AppStorage("onDuty") private var onDuty = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if model.paired { RootTabs() } else { PairView() }
            }
            .environment(model)
            .onOpenURL { model.handle(url: $0) }
            .onAppear { delegate.onURL = { model.handle(url: $0) }; screenshots.attach(model); syncScreenshots(); syncDuty() }
            .environment(screenshots)
            .onChange(of: autoScreenshots) { _, _ in syncScreenshots() }
            .onChange(of: onDuty) { _, _ in syncDuty() }
            .onChange(of: model.paired) { _, _ in syncDuty() }
            .onChange(of: model.paired) { _, _ in syncScreenshots() }
            .onChange(of: scenePhase) { _, p in
                if onDuty { DutyDiag.note("scene \(p)") }
                if p == .active { syncScreenshots() }
            }
            .overlay(alignment: .top) { ToastView() .environment(model) }
        }
    }

    /// On duty only makes sense while paired; the keep-alive follows the toggle.
    private func syncDuty() {
        if onDuty && model.paired { DutyKeepAlive.shared.start() } else { DutyKeepAlive.shared.stop() }
    }

    /// Start (arm + catch up) or stop the Photos watcher to match the toggle; no new background mode.
    private func syncScreenshots() {
        if autoScreenshots && model.paired && ScreenshotSync.hasAccess { screenshots.start() } else if !autoScreenshots { screenshots.stop() }
    }
}
