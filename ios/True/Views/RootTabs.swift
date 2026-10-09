import SwiftUI

struct RootTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Hub", systemImage: "square.stack.3d.up", value: "hub") { HubView() }
                .badge(model.needsYouCount)
            Tab("Shots", systemImage: "photo.on.rectangle", value: "shots") { ShotsView() }
            Tab("Send", systemImage: "arrow.up.arrow.down", value: "send") { SendView() }
        }
        .sheet(isPresented: $model.showComposer) {
            ComposerSheet()
        }
    }
}
