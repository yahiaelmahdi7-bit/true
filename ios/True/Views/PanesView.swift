import SwiftUI

struct PanesView: View {
    @Environment(AppModel.self) private var model
    @State private var tabs: [RemoteTab]?
    @State private var toasted = false
    @Namespace private var ns

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if let tabs {
                    if tabs.allSatisfy({ $0.panes.isEmpty }) {
                        ContentUnavailableView("No panes open", systemImage: "rectangle.split.2x2",
                                               description: Text("Open a terminal pane in True on your Mac and it shows up here."))
                    } else { list(tabs) }
                } else {
                    List {
                        ForEach(0..<2, id: \.self) { _ in
                            Section { ForEach(0..<3, id: \.self) { _ in PaneRowView(pane: .placeholder) } }
                        }
                    }
                    .redacted(reason: .placeholder).allowsHitTesting(false)
                }
            }
            .navigationTitle("Panes")
            .navigationDestination(item: $model.openPane) { route in
                PaneView(route: route).navigationTransition(.zoom(sourceID: route.id, in: ns))
            }
        }
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func list(_ tabs: [RemoteTab]) -> some View {
        List {
            ForEach(tabs.filter { !$0.panes.isEmpty }) { tab in
                Section {
                    ForEach(tab.panes) { pane in
                        NavigationLink(value: PaneRoute(id: pane.id, title: pane.repo ?? pane.title)) { PaneRowView(pane: pane) }
                            .matchedTransitionSource(id: pane.id, in: ns)
                    }
                } header: {
                    HStack {
                        Text(tab.title)
                        let waiting = tab.panes.filter(\.needsYou).count
                        if waiting > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "circle.fill").font(.system(size: 6))
                                Text("\(waiting)")
                            }.font(.caption).foregroundStyle(.attention).textCase(nil)
                        }
                        if tab.selected { Text("Front").font(.caption).foregroundStyle(.secondary).textCase(nil) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: PaneRoute.self) { route in
            PaneView(route: route).navigationTransition(.zoom(sourceID: route.id, in: ns))
        }
        .refreshable { await load() }
    }

    private func load() async {
        guard let session = model.session else { return }
        do {
            tabs = try await session.tabs().tabs
            toasted = false
        } catch {
            if Task.isCancelled { return }
            if !toasted { toasted = true; model.show("Couldn't load panes") }
        }
    }
}

extension RemotePane {
    static let placeholder = RemotePane(id: "x", title: "placeholder-name", cwd: "/Users/me/Projects/placeholder",
                                        agent: nil, needsYou: false, busy: false, live: true)
}

private struct PaneRowView: View {
    let pane: RemotePane

    private var cwd: String {
        let home = "/Users/"
        if pane.cwd.isEmpty { return "No directory" }
        guard pane.cwd.hasPrefix(home) else { return pane.cwd }
        let rest = pane.cwd.dropFirst(home.count)
        guard let slash = rest.firstIndex(of: "/") else { return "~" }
        return "~" + rest[slash...]
    }

    private var worktreeBadge: some View {
        Text("worktree").font(.caption2).foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(.thinMaterial, in: Capsule())
    }

    /// `repo · branch` (+ worktree capsule). Without a repo there is nothing to say beyond the title.
    private func repoLine(primary: Bool) -> some View {
        HStack(spacing: 6) {
            Text(pane.repo ?? pane.title).font(primary ? .body : .subheadline)
                .foregroundStyle(primary ? .primary : .secondary).lineLimit(1).layoutPriority(1)
            if let branch = pane.branch {
                Text("· \(branch)").font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            if pane.worktree { worktreeBadge.layoutPriority(1) }
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let agent = pane.agent {
                    Text(agent).font(.body).lineLimit(1)
                    repoLine(primary: false)
                    if let topic = pane.topic {
                        Text(topic).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    }
                } else {
                    repoLine(primary: true)
                    if let topic = pane.topic {
                        Text(topic).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    } else {
                        Text(cwd).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                    }
                }
            }
            Spacer()
            if pane.needsYou {
                HStack(spacing: 6) {
                    Image(systemName: "circle.fill").font(.system(size: 8))
                    Text("Needs you").font(.subheadline)
                }.foregroundStyle(.attention)
            } else if pane.busy {
                Text("Working").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(pane.live ? .primary : .secondary)
        .accessibilityElement(children: .combine)
    }
}
