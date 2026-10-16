import SwiftUI

private struct PanePickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var rows: [HubRow] {
        PanePicker.order(rows: model.hub?.projects.flatMap(\.rows) ?? [], lastPaneId: UserDefaults.standard.string(forKey: "lastPaneId"))
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.hub == nil {
                    List(0..<5, id: \.self) { _ in
                        VStack(alignment: .leading) { Text("Session name"); Text("Working").font(.subheadline) }
                    }
                    .redacted(reason: .placeholder)
                } else if rows.isEmpty {
                    ContentUnavailableView("No sessions", systemImage: "terminal", description: Text("Open a pane in True on your Mac first."))
                } else {
                    List(rows) { row in
                        Button { pick(row) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name).foregroundStyle(.primary)
                                Text(row.status).font(.subheadline)
                                    .foregroundStyle(row.statusKey == "needsYou" ? AnyShapeStyle(.attention) : AnyShapeStyle(.secondary))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Message a session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func pick(_ row: HubRow) {
        guard let pane = row.pane else { return }
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            model.openPane = PaneRoute(id: pane, title: row.name, compose: true)
        }
    }
}

private struct PanePickerModifier: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .sheet(isPresented: $model.showPanePicker) { PanePickerSheet() }
            .onChange(of: model.showPanePicker) { _, shown in
                guard shown, let hub = model.hub else { return }
                let rows = PanePicker.order(rows: hub.projects.flatMap(\.rows), lastPaneId: nil)
                if rows.count == 1, let row = rows.first, let pane = row.pane {
                    model.showPanePicker = false
                    model.openPane = PaneRoute(id: pane, title: row.name, compose: true)
                }
            }
    }
}

extension View {
    func panePickerSheet() -> some View { modifier(PanePickerModifier()) }
}
