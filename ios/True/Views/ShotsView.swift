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

enum ShotDate {
    static func parse(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
    static func dayTitle(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(date: .abbreviated, time: .omitted)
    }
}

struct ShotsView: View {
    @Environment(AppModel.self) private var model
    @State private var shots: [Shot]?
    @State private var failed = false
    @State private var cache = ImageCache()
    @State private var selected: Shot?
    @Namespace private var ns
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 1), count: 3)

    /// Day groups when every timestamp parses as ISO-8601, else a single ungrouped grid.
    private func groups(_ shots: [Shot]) -> [(title: String?, shots: [Shot])] {
        let dated = shots.map { ($0, ShotDate.parse($0.created)) }
        guard dated.allSatisfy({ $0.1 != nil }) else { return [(nil, shots)] }
        let cal = Calendar.current
        let byDay = Dictionary(grouping: dated) { cal.startOfDay(for: $0.1!) }
        return byDay.keys.sorted(by: >).map { (ShotDate.dayTitle($0), byDay[$0]!.sorted { $0.1! > $1.1! }.map(\.0)) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let shots {
                    if shots.isEmpty && failed {
                        ContentUnavailableView {
                            Label("Couldn't load screenshots", systemImage: "wifi.slash")
                        } description: { Text("The Mac may be asleep or offline.") } actions: {
                            Button("Try again") { Task { await load() } }.buttonStyle(.bordered)
                        }
                    } else if shots.isEmpty {
                        ContentUnavailableView("No screenshots yet", systemImage: "camera.viewfinder", description: Text("Screenshots your seats take on the Mac appear here."))
                    } else {
                        ScrollView {
                            LazyVGrid(columns: cols, spacing: 1, pinnedViews: .sectionHeaders) {
                                ForEach(groups(shots), id: \.title) { g in
                                    Section {
                                        ForEach(g.shots) { shot in
                                            Button { selected = shot } label: { Cell(shot: shot, cache: cache) }
                                                .buttonStyle(.plain)
                                                .matchedTransitionSource(id: shot.id, in: ns)
                                        }
                                    } header: {
                                        if let t = g.title {
                                            Text(t).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.horizontal).padding(.vertical, 6).background(.bar)
                                        }
                                    }
                                }
                            }
                        }
                        .refreshable { await load() }
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: cols, spacing: 1) {
                            ForEach(0..<9, id: \.self) { _ in Color.secondary.opacity(0.15).aspectRatio(1, contentMode: .fit) }
                        }
                    }
                    .redacted(reason: .placeholder).allowsHitTesting(false)
                }
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
        do { shots = try await model.session?.shots(); failed = false }
        catch { await model.handle(error); failed = true; if shots == nil { shots = [] } }
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
                .contextMenu {
                    if let image {
                        ShareLink(item: Image(uiImage: image), preview: SharePreview("Screenshot", image: Image(uiImage: image)))
                        Button { UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil); model.show("Saved to Photos") } label: { Label("Save", systemImage: "square.and.arrow.down") }
                    }
                }
                .accessibilityLabel("Screenshot \(ShotDate.parse(shot.created)?.formatted(date: .abbreviated, time: .shortened) ?? shot.created)")
        }
    }

    struct Viewer: View {
        let shot: Shot; let cache: ImageCache
        @Environment(AppModel.self) private var model
        @State private var image: UIImage?
        @State private var chrome = true
        @State private var saved = 0

        private var caption: String {
            let when = ShotDate.parse(shot.created)?.formatted(date: .abbreviated, time: .shortened) ?? shot.created
            return "\(when) · \(shot.w)×\(shot.h)"
        }

        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image { Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("Screenshot, \(caption)") } else { ProgressView().tint(.white) }
            }
            .contentShape(.rect)
            .onTapGesture { withAnimation { chrome.toggle() } }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarVisibility(.hidden, for: .tabBar)
            .toolbarVisibility(chrome ? .visible : .hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if let image {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil); saved += 1; model.show("Saved to Photos") } label: { Label("Save", systemImage: "square.and.arrow.down") }
                        ShareLink(item: Image(uiImage: image), preview: SharePreview("Screenshot", image: Image(uiImage: image)))
                    }
                }
            }
            .sensoryFeedback(.success, trigger: saved)
            .safeAreaInset(edge: .bottom) {
                if chrome {
                    Text(caption).font(.caption.monospacedDigit()).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8).glassEffect(.regular, in: .capsule).padding(.bottom, 8)
                }
            }
            .task { image = await cache.image(shot.id, session: model.session) }
        }
    }
}
extension Shot: Hashable { public func hash(into h: inout Hasher) { h.combine(id) } }
