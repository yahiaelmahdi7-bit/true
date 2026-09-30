import Foundation
import AppKit
import Observation

/// The single source of truth for the window: tabs, splits, focus. Views read it; commands and
/// terminal callbacks mutate it. Every mutation autosaves, debounced (a cancelled Task, not a timer).
@MainActor
@Observable
final class WorkspaceModel {
    static let shared = WorkspaceModel()

    var state: WorkspaceState {
        didSet { if state != oldValue { scheduleSave() } }
    }
    /// Tab currently being renamed inline (double-click), if any.
    var renamingTab: UUID?

    /// Set by `AgentRegistry`: told when a pane goes away so it can forget the agent that owned it.
    @ObservationIgnored var onPaneClosed: ((UUID) -> Void)?
    /// Set by `AgentRegistry`: is this pane an agent's? Sleeping the only tab must not quit True.
    @ObservationIgnored var isAgentPane: ((UUID) -> Bool)?

    @ObservationIgnored private let store: WorkspaceStore
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(store: WorkspaceStore = WorkspaceStore()) {
        self.store = store
        self.state = store.load()
    }

    // MARK: Queries

    var selectedTab: TabState { state.tabs[state.selectedIndex] }

    private func index(of tab: UUID) -> Int? { state.tabs.firstIndex { $0.id == tab } }

    private func tabIndex(containing pane: UUID) -> Int? {
        state.tabs.firstIndex { $0.tree.contains(pane) }
    }

    // MARK: Tabs

    func newTab() {
        let cwd = selectedTab.cwds[selectedTab.focusedPane] ?? NSHomeDirectory()
        _ = state.addTab(cwd: cwd)
    }

    /// Open Project: a new pane beside the selected tab's focused pane (Split Right), in `path`, focused.
    /// The tab count and its custom name are untouched. `startupCommand` runs once in the new pane
    /// instead of a bare shell; it is never persisted.
    @discardableResult
    func openProjectBeside(path: String, startupCommand: String?) -> UUID {
        let new = split(.horizontal, cwd: path)
        if let c = startupCommand { PaneStartup.shared.set(c, for: new) }
        return new
    }

    /// An ordinary tab, named after the agent, that the registry then starts `claude` in.
    /// Returns the tab's (only) pane.
    @discardableResult
    func openAgentTab(name: String, cwd: String) -> UUID {
        let t = state.addTab(cwd: cwd)
        state.tabs[state.selectedIndex].customName = name
        return t.focusedPane
    }

    func select(tab: UUID) { if index(of: tab) != nil { state.selectedTab = tab } }
    func selectTab(number n: Int) { state.selectTab(number: n) }
    func cycleTab(by d: Int) { state.cycleTab(by: d) }
    func move(tab: UUID, onto target: UUID) { state.moveTab(tab, onto: target) }

    func rename(tab: UUID, to name: String) {
        guard let i = index(of: tab) else { return }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        state.tabs[i].customName = n.isEmpty ? nil : n
        renamingTab = nil
    }

    // MARK: Panes

    func focus(pane: UUID) {
        guard let i = tabIndex(containing: pane) else { return }
        if state.tabs[i].focusedPane != pane { state.tabs[i].focusedPane = pane }
        if state.selectedTab != state.tabs[i].id { state.selectedTab = state.tabs[i].id }
    }

    func splitFocused(_ axis: SplitTree.Axis) { split(axis, cwd: nil) }

    /// The one split path: a new leaf beside the selected tab's focused pane, focused. `cwd` nil = inherit
    /// the focused pane's current directory.
    @discardableResult
    func split(_ axis: SplitTree.Axis, cwd: String?) -> UUID {
        let i = state.selectedIndex
        let tab = state.tabs[i]
        let new = UUID()
        refreshCwd(pane: tab.focusedPane)
        let dir = cwd ?? state.tabs[i].cwds[tab.focusedPane] ?? NSHomeDirectory()
        state.tabs[i].tree = tab.tree.inserting(new, beside: tab.focusedPane, axis: axis)
        state.tabs[i].cwds[new] = dir
        state.tabs[i].focusedPane = new
        return new
    }

    func moveFocus(_ dir: SplitTree.Direction) {
        let i = state.selectedIndex
        let tab = state.tabs[i]
        if let n = tab.tree.neighbor(of: tab.focusedPane, dir) { state.tabs[i].focusedPane = n }
    }

    func closeFocusedPane() {
        let tab = selectedTab
        close(pane: tab.focusedPane)
    }

    func paneExited(_ pane: UUID) { close(pane: pane) }

    private func close(pane: UUID) {
        guard let i = tabIndex(containing: pane) else { return }
        // Putting the last agent to sleep closes the last tab; keep a plain shell so that never quits True.
        if state.tabs.count == 1, state.tabs[i].tree.leafIDs.count == 1, isAgentPane?(pane) == true {
            _ = state.addTab(cwd: NSHomeDirectory())
        }
        onPaneClosed?(pane)
        guard let i = tabIndex(containing: pane) else { return }
        if !state.closePane(pane, inTab: state.tabs[i].id) {
            saveNow()
            NSApp.terminate(nil)
        }
    }

    func setFraction(_ f: Double, split: UUID, tab: UUID) {
        guard let i = index(of: tab) else { return }
        state.tabs[i].tree = state.tabs[i].tree.settingFraction(f, forSplit: split)
    }

    /// Even out the row or column a divider belongs to (double-click on it).
    func equalize(split: UUID, tab: UUID) {
        guard let i = index(of: tab) else { return }
        state.tabs[i].tree = state.tabs[i].tree.equalizing(split: split)
    }

    // MARK: Working directories

    func updateCwd(pane: UUID, _ path: String) {
        guard let i = tabIndex(containing: pane), state.tabs[i].cwds[pane] != path else { return }
        state.tabs[i].cwds[pane] = path
    }

    func refreshCwd(pane: UUID) {
        if let p = TerminalRegistry.shared.cwd(of: pane) { updateCwd(pane: pane, p) }
    }

    func syncCwdsFromLivePids() {
        for t in state.tabs { for p in t.tree.leafIDs { refreshCwd(pane: p) } }
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.store.save(self?.state ?? .fresh())
        }
    }

    func saveNow() {
        saveTask?.cancel()
        syncCwdsFromLivePids()
        store.save(state)
    }
}
