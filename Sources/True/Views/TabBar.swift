import SwiftUI
import UniformTypeIdentifiers

/// Liquid Glass tab strip. The empty space (and the leading traffic-light gutter) drags the
/// window; double-clicking it zooms — `windowChromeArea()` supplies both.
struct TabBar: View {
    let model: WorkspaceModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(model.state.tabs) { tab in
                TabChip(model: model, tab: tab, selected: tab.id == model.state.selectedTab)
            }
            Button { model.newTab() } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .help("New Tab (⌘T)")
            Spacer(minLength: 0)
            NeedsYouTray()
        }
        .padding(.leading, 80)   // clears the traffic lights
        .padding(.trailing, 10)
        .frame(height: 38)
        .windowChromeArea()
        .background(.clear)
        .glassEffect(.regular, in: .rect)
    }
}

private struct TabChip: View {
    let model: WorkspaceModel
    let tab: TabState
    let selected: Bool
    @State private var hovering = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            if model.renamingTab == tab.id {
                TextField("Name", text: $draft)
                    .textFieldStyle(.plain)
                    .frame(width: 110)
                    .focused($fieldFocused)
                    .onSubmit { model.rename(tab: tab.id, to: draft) }
                    .onExitCommand { model.renamingTab = nil }
                    .onAppear { draft = tab.title; fieldFocused = true }
            } else {
                Text(tab.title).lineLimit(1).frame(maxWidth: 160)
            }
            if let status = AgentRegistry.shared.tabStatus(tab) {
                Circle().fill(status.tint).frame(width: 7, height: 7).help(status.label)
            }
            if hovering || selected {
                Button { closeTab() } label: { Image(systemName: "xmark").font(.caption2) }
                    .buttonStyle(.borderless)
                    .help("Close Tab")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(selected ? Color.primary.opacity(0.14) : (hovering ? Color.primary.opacity(0.07) : .clear),
                    in: .capsule)
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { model.renamingTab = tab.id }
        .onTapGesture { model.select(tab: tab.id) }
        .draggable(tab.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let s = items.first, let src = UUID(uuidString: s) else { return false }
            model.move(tab: src, onto: tab.id)
            return true
        }
    }

    private func closeTab() {
        // Close every pane of this tab through the model so the last-tab rule applies.
        model.select(tab: tab.id)
        for p in tab.tree.leafIDs { model.paneExited(p) }
    }
}
