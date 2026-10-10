import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var onURL: ((URL) -> Void)?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Background.register()
        Background.schedule()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let s = response.notification.request.content.userInfo["url"] as? String, let u = URL(string: s) {
            await MainActor.run { onURL?(u) }
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
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if model.paired { RootTabs() } else { PairView() }
            }
            .environment(model)
            .onOpenURL { model.handle(url: $0) }
            .onAppear { delegate.onURL = { model.handle(url: $0) }; screenshots.attach(model); syncScreenshots() }
            .environment(screenshots)
            .onChange(of: autoScreenshots) { _, _ in syncScreenshots() }
            .onChange(of: model.paired) { _, _ in syncScreenshots() }
            .onChange(of: scenePhase) { _, p in if p == .active { syncScreenshots() } }
            .overlay(alignment: .top) { ToastView() .environment(model) }
        }
    }

    /// Start (arm + catch up) or stop the Photos watcher to match the toggle; no new background mode.
    private func syncScreenshots() {
        if autoScreenshots && model.paired && ScreenshotSync.hasAccess { screenshots.start() } else if !autoScreenshots { screenshots.stop() }
    }
}
