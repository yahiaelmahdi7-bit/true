import SwiftUI

struct HubView: View {
    @Environment(AppModel.self) private var model
    @State private var builder: HubRow?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if model.offline {
                    ContentUnavailableView("Mac asleep or offline", systemImage: "wifi.slash", description: Text("Retrying. Wake the Mac or check Tailscale."))
                        .foregroundStyle(.attention)
                } else if let hub = model.hub {
                    if hub.projects.isEmpty {
                        ContentUnavailableView {
                            Label("Nothing running", systemImage: "moon.zzz")
                        } description: { Text("Seats and builders show up here.") } actions: {
                            Button("Start work") { model.showComposer = true }.buttonStyle(.borderedProminent)
                        }
                    } else { list(hub) }
                } else {
                    List { ForEach(0..<6, id: \.self) { _ in RowView(row: .placeholder) } }.redacted(reason: .placeholder)
                }
            }
            .navigationTitle("Hub")
            .navigationDestination(item: $model.openPane) { PaneView(route: $0) }
            .toolbar {
                if model.failCount > 0 && !model.offline {
                    ToolbarItem(placement: .principal) { Label("Reconnecting…", systemImage: "arrow.triangle.2.circlepath").font(.caption) }
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

    private func list(_ hub: HubSnapshot) -> some View {
        List {
            ForEach(hub.projects.indices, id: \.self) { i in
                let p = hub.projects[i]
                Section {
                    ForEach(p.rows) { row in rowLink(row) }
                } header: {
                    HStack { Text(p.title); Spacer(); Text(p.summary).foregroundStyle(.secondary).textCase(nil) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await model.refresh() }
    }

    @ViewBuilder private func rowLink(_ row: HubRow) -> some View {
        if row.kind == "seat", let pane = row.pane {
            NavigationLink(value: PaneRoute(id: pane, title: row.name)) { RowView(row: row) }
                .swipeActions(edge: .trailing) {
                    if row.statusKey == "asleep" { Button("Wake") { Task { await model.command("wake \(row.name)") } } }
                    else { Button("Sleep") { Task { await model.command("sleep \(row.name)") } }.tint(.gray) }
                }
        } else if row.kind == "background" {
            Button { builder = row } label: { RowView(row: row) }.buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    if row.acked == false, let id = row.builderId {
                        Button("Ack") { Task { try? await model.session?.ackBuilder(id: id); await model.refresh() } }
                    }
                }
        } else { RowView(row: row) }
    }
}

extension HubRow {
    static let placeholder = HubRow(kind: "seat", id: "x", name: "placeholder-name", status: "Working", statusKey: "working", cwd: "~/Projects/placeholder")
}

struct RowView: View {
    let row: HubRow
    private var hot: Bool { row.statusKey == "needsYou" || row.statusKey == "failed" }
    private var symbol: String { row.kind == "seat" ? "terminal" : row.kind == "background" ? "hammer" : "rectangle.on.rectangle" }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.secondary)
                .frame(width: 44, height: 44).background(.fill.quaternary, in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(.body.weight(.semibold)).lineLimit(1)
                if let cwd = row.cwd { Text(cwd).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Circle().frame(width: 8, height: 8)
                Text(row.status).font(.subheadline).lineLimit(1).fixedSize()
            }
            .foregroundStyle(hot ? Color.attention : Color.secondary)
        }
        .accessibilityElement(children: .combine)
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
