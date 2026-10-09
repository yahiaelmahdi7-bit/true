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
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

/// The floating + : a bottom-bar toolbar item, which the system draws as glass.
struct StartWorkButton: ToolbarContent {
    @Environment(AppModel.self) private var model
    var body: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            Button { model.showComposer = true } label: { Label("Start work", systemImage: "plus") }
        }
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let t = model.toast {
            Text(t).font(.subheadline.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.default, value: model.toast)
        }
    }
}
