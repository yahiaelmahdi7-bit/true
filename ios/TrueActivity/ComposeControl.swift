import AppIntents
import SwiftUI
import WidgetKit

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
