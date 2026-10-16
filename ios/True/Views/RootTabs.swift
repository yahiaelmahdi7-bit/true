import SwiftUI

struct RootTabs: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Hub", systemImage: "square.stack.3d.up", value: "hub") { HubView() }
                .badge(model.needsYouCount)
            Tab("Panes", systemImage: "rectangle.split.2x2", value: "panes") { PanesView() }
            Tab("Shots", systemImage: "photo.on.rectangle", value: "shots") { ShotsView() }
            Tab("Send", systemImage: "arrow.up.arrow.down", value: "send") { SendView() }
            Tab("Sites", systemImage: "network", value: "sites") { SitesView() }
            Tab("Browser", systemImage: "safari", value: "browser") { BrowserView() }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.applyMacClipboard() } } }
        .sheet(isPresented: $model.showComposer) {
            ComposerSheet()
        }
    }
}
