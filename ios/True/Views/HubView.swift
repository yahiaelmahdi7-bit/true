import SwiftUI

struct HubView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var builder: HubRow?
    @Namespace private var ns

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if model.offline {
                    ContentUnavailableView {
                        Label("Mac asleep or offline", systemImage: "wifi.slash").foregroundStyle(.attention)
                    } description: {
                        Text("Retrying. Wake the Mac or check Tailscale.")
                    }
                } else if let hub = model.hub {
                    if hub.projects.isEmpty {
                        ContentUnavailableView {
                            Label("Nothing running", systemImage: "moon.zzz")
                        } description: { Text("Seats and builders show up here.") } actions: {
                            Button("Start work") { model.showComposer = true }.buttonStyle(.borderedProminent)
                        }
                    } else { list(hub) }
                } else {
                    List {
                        ForEach(0..<2, id: \.self) { _ in
                            Section { ForEach(0..<3, id: \.self) { _ in RowView(row: .placeholder) } }
                        }
                    }
                    .redacted(reason: .placeholder).allowsHitTesting(false)
                }
            }
            .navigationTitle("Hub")
            .navigationSubtitle(model.hub?.summary ?? "")
            .navigationDestination(item: $model.openPane) { route in
                PaneView(route: route).navigationTransition(.zoom(sourceID: route.id, in: ns))
            }
            .toolbar {
                if model.failCount > 0 && !model.offline {
                    ToolbarItem(placement: .principal) {
                        Label("Reconnecting", systemImage: "arrow.triangle.2.circlepath").font(.caption.weight(.medium))
                            .symbolEffect(.rotate, options: .repeating, isActive: !reduceMotion)
                            .padding(.horizontal, 10).padding(.vertical, 4).glassEffect(.regular, in: .capsule)
                    }
                }
                StartWorkButton()
            }
            .sheet(item: $builder) { BuilderSheet(row: $0) }
            .onAppear {
                if model.uiState == "pane", model.openPane == nil {
                    Task { try? await Task.sleep(for: .seconds(1)); model.openPane = PaneRoute(id: "demo", title: "lead-true") }
                }
                if model.uiState == "builder", builder == nil {
                    Task { try? await Task.sleep(for: .seconds(1)); builder = model.hub?.projects.flatMap(\.rows).first { $0.kind == "background" } }
                }
            }
        }
    }

    private func isHot(_ r: HubRow) -> Bool { r.statusKey == "needsYou" || r.statusKey == "failed" }

    private func list(_ hub: HubSnapshot) -> some View {
        let hot = hub.projects.flatMap(\.rows).filter(isHot)
        return List {
            if hub.needsYou > 0 || !hot.isEmpty {
                Section("Needs you") { ForEach(hot) { rowLink($0) } }
            }
            ForEach(hub.projects.indices, id: \.self) { i in
                let p = hub.projects[i]
                let rows = p.rows.filter { !isHot($0) }
                if !rows.isEmpty {
                    Section {
                        ForEach(rows) { rowLink($0) }
                    } header: {
                        HStack { Text(p.title); Spacer(); Text(p.summary).foregroundStyle(.secondary).textCase(nil) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await model.refresh() }
    }

    private func toggleCommand(_ row: HubRow) -> String { row.statusKey == "asleep" ? "wake \(row.name)" : "sleep \(row.name)" }

    @ViewBuilder private func rowLink(_ row: HubRow) -> some View {
        if row.kind == "seat", let pane = row.pane {
            NavigationLink(value: PaneRoute(id: pane, title: row.name)) { RowView(row: row) }
                .matchedTransitionSource(id: pane, in: ns)
                .swipeActions(edge: .trailing) {
                    if row.statusKey == "asleep" {
                        Button { Task { await model.command(toggleCommand(row)) } } label: { Label("Wake", systemImage: "sunrise") }
                    } else {
                        Button { Task { await model.command(toggleCommand(row)) } } label: { Label("Sleep", systemImage: "moon.zzz") }.tint(.gray)
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button { model.openPane = PaneRoute(id: pane, title: row.name) } label: { Label("Open", systemImage: "terminal") }
                }
                .contextMenu {
                    Button { model.openPane = PaneRoute(id: pane, title: row.name) } label: { Label("Open", systemImage: "terminal") }
                    Button { Task { await model.command(toggleCommand(row)) } } label: {
                        row.statusKey == "asleep" ? Label("Wake", systemImage: "sunrise") : Label("Sleep", systemImage: "moon.zzz")
                    }
                    copyButtons(row)
                }
        } else if row.kind == "background" {
            Button { builder = row } label: { RowView(row: row) }.buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    if row.acked == false, let id = row.builderId {
                        Button { ack(id) } label: { Label("Ack", systemImage: "checkmark") }
                    }
                }
                .contextMenu {
                    Button { builder = row } label: { Label("Open", systemImage: "hammer") }
                    if row.acked == false, let id = row.builderId { Button { ack(id) } label: { Label("Ack", systemImage: "checkmark") } }
                    copyButtons(row)
                }
        } else { RowView(row: row) }
    }

    @ViewBuilder private func copyButtons(_ row: HubRow) -> some View {
        Button { UIPasteboard.general.string = row.name; model.show("Copied name") } label: { Label("Copy name", systemImage: "doc.on.doc") }
        if let cwd = row.cwd { Button { UIPasteboard.general.string = cwd; model.show("Copied path") } label: { Label("Copy path", systemImage: "folder") } }
    }

    private func ack(_ id: String) { Task { try? await model.session?.ackBuilder(id: id); await model.refresh() } }
}

extension HubRow {
    static let placeholder = HubRow(kind: "seat", id: "x", name: "placeholder-name", status: "Working", statusKey: "working", cwd: "~/Projects/placeholder")
}

/// Hub/Needs-you row: a TileRow with the status (dot + word, elapsed under it for Working).
struct RowView: View {
    let row: HubRow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var hot: Bool { row.statusKey == "needsYou" || row.statusKey == "failed" }
    private var failedBuilder: Bool { row.kind == "background" && row.statusKey == "failed" }
    private var symbol: String {
        failedBuilder ? "exclamationmark.circle.fill" : row.kind == "seat" ? "terminal" : row.kind == "background" ? "hammer" : "rectangle.on.rectangle"
    }
    private var detail: String? { row.kind == "background" ? (row.branch ?? row.cwd) : row.cwd }
    private var tint: AnyShapeStyle {
        hot ? AnyShapeStyle(.attention) : row.statusKey == "working" ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary)
    }

    var body: some View {
        TileRow(symbol: symbol, title: row.name, detail: detail,
                symbolStyle: failedBuilder ? AnyShapeStyle(.attention) : AnyShapeStyle(.secondary)) {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "circle.fill").font(.system(size: 8))
                        .symbolEffect(.pulse, options: .repeating, isActive: row.statusKey == "working" && !reduceMotion)
                    Text(row.status).font(.subheadline).lineLimit(1).fixedSize()
                }
                .foregroundStyle(tint)
                if row.statusKey == "working", let e = row.elapsed, !e.isEmpty {
                    Text(e).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityValue(row.status)
    }
}

struct BuilderSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let row: HubRow
    @State private var detail: BuilderDetail?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let d = detail {
                    GroupBox { Text(d.text.isEmpty ? "No output yet." : d.text).font(.footnote.monospaced()).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                        .padding()
                } else if failed {
                    ContentUnavailableView("Couldn't load", systemImage: "wifi.slash", description: Text("Mac offline?"))
                } else { ProgressView().padding(40) }
            }
            .navigationTitle(row.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                if let d = detail, d.canAck, let id = row.builderId ?? d.id {
                    Button { Task { try? await model.session?.ackBuilder(id: id); await model.refresh(); dismiss() } } label: { Text("Ack").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large).padding()
                }
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .task {
            guard let id = row.builderId else { failed = true; return }
            do { detail = try await model.session?.builderDetail(id: id) } catch { await model.handle(error); failed = true }
        }
    }
}
