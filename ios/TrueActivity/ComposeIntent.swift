import AppIntents
import Foundation

/// The lock-screen control's action. `openAppWhenRun` makes the system launch True and perform this intent IN THE APP process,
/// so this file is compiled into both the app and the widget extension (like PaneIntents.swift) — extension-only, the tap did nothing.
struct ComposeControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Message a session"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "true://compose")!))
    }
}
