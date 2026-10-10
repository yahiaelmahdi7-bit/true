import AppIntents
import SwiftUI
import WidgetKit

struct ComposeControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Message a session"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "true://compose")!))
    }
}

struct ComposeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "net.prismlens.true.compose") {
            ControlWidgetButton(action: ComposeControlIntent()) {
                Label("Message", systemImage: "text.bubble")
            }
        }
        .displayName("Message a session")
        .description("Open True and pick a session to send a prompt to.")
    }
}
