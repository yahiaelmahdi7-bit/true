import SwiftUI
import Photos

@MainActor @Observable
final class ImageCache {
    private var images: [String: UIImage] = [:]
    func image(_ id: String, session: RemoteSession?) async -> UIImage? {
        if let i = images[id] { return i }
        guard let data = try? await session?.shotData(id: id), let img = UIImage(data: data) else { return nil }
        images[id] = img; return img
    }
}

struct ShotsView: View {
    @Environment(AppModel.self) private var model
    @State private var shots: [Shot]?
    @State private var cache = ImageCache()
    @State private var selected: Shot?
    @Namespace private var ns
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 1), count: 3)

    var body: some View {
        NavigationStack {
            Group {
                if let shots {
                    if shots.isEmpty {
                        ContentUnavailableView("No screenshots", systemImage: "photo.on.rectangle", description: Text("Screenshots you take on the Mac show up here."))
                    } else {
                        ScrollView {
                            LazyVGrid(columns: cols, spacing: 1) {
                                ForEach(shots) { shot in
                                    Button { selected = shot } label: { Cell(shot: shot, cache: cache) }
                                        .buttonStyle(.plain)
                                        .matchedTransitionSource(id: shot.id, in: ns)
                                        .contextMenu {
                                            Button("Copy", systemImage: "doc.on.doc") { Task { if let i = await cache.image(shot.id, session: model.session) { UIPasteboard.general.image = i; model.show("Copied.") } } }
                                            Button("Save to Photos", systemImage: "square.and.arrow.down") { Task { if let i = await cache.image(shot.id, session: model.session) { UIImageWriteToSavedPhotosAlbum(i, nil, nil, nil); model.show("Saved.") } } }
                                        }
                                }
                            }
                        }
                        .refreshable { await load() }
                    }
                } else { ProgressView() }
            }
            .navigationTitle("Shots")
            .navigationDestination(item: $selected) { shot in
                Viewer(shot: shot, cache: cache).navigationTransition(.zoom(sourceID: shot.id, in: ns))
            }
            .toolbar { StartWorkButton() }
            .task { await load() }
        }
    }

    private func load() async {
        do { shots = try await model.session?.shots() } catch { await model.handle(error); if shots == nil { shots = [] } }
    }

    struct Cell: View {
        let shot: Shot; let cache: ImageCache
        @Environment(AppModel.self) private var model
        @State private var image: UIImage?
        var body: some View {
            Color(.secondarySystemFill).aspectRatio(1, contentMode: .fit)
                .overlay { if let image { Image(uiImage: image).resizable().scaledToFill() } }
                .clipped().contentShape(.rect)
                .task { image = await cache.image(shot.id, session: model.session) }
                .accessibilityLabel("Screenshot \(shot.created)")
        }
    }

    struct Viewer: View {
        let shot: Shot; let cache: ImageCache
        @Environment(AppModel.self) private var model
        @State private var image: UIImage?
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image { Image(uiImage: image).resizable().scaledToFit() } else { ProgressView().tint(.white) }
            }
            .navigationBarTitleDisplayMode(.inline).toolbarVisibility(.hidden, for: .tabBar)
            .toolbar {
                if let image { ToolbarItem(placement: .primaryAction) { ShareLink(item: Image(uiImage: image), preview: SharePreview("Screenshot", image: Image(uiImage: image))) } }
            }
            .task { image = await cache.image(shot.id, session: model.session) }
        }
    }
}
extension Shot: Hashable { public func hash(into h: inout Hasher) { h.combine(id) } }
