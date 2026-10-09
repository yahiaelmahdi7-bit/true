import SwiftUI

/// The floating + : a toolbar item (a .bottomBar item is hidden behind the TabView's tab bar), which the system draws as glass.
struct StartWorkButton: ToolbarContent {
    @Environment(AppModel.self) private var model
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { model.showComposer = true } label: { Label("Start work", systemImage: "plus") }
        }
    }
}
