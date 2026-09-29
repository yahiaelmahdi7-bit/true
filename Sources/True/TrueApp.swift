import SwiftUI
import AppKit

@main
struct TrueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = WorkspaceModel.shared
    private let registry = AgentRegistry.shared

    var body: some Scene {
        Window("True", id: "main") {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    TabBar(model: model)
                    TerminalArea(model: model)
                }
                if registry.panelOpen {
                    AgentsPanel(registry: registry).transition(.move(edge: .trailing))
                }
            }
            .frame(minWidth: 480, minHeight: 300)
            .sheet(item: Bindable(registry).builder) { AgentBuilderSheet(draft: $0, registry: registry) }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") { model.newTab() }.keyboardShortcut("t")
                Button("Close Pane") { model.closeFocusedPane() }.keyboardShortcut("w")
            }
            CommandMenu("Shell") {
                Button("Split Right") { model.splitFocused(.horizontal) }.keyboardShortcut("d")
                Button("Split Down") { model.splitFocused(.vertical) }.keyboardShortcut("d", modifiers: [.command, .shift])
                Divider()
                Button("Focus Left") { model.moveFocus(.left) }.keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Button("Focus Right") { model.moveFocus(.right) }.keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                Button("Focus Up") { model.moveFocus(.up) }.keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Button("Focus Down") { model.moveFocus(.down) }.keyboardShortcut(.downArrow, modifiers: [.command, .option])
            }
            CommandMenu("Agents") {
                Button("Toggle Agents Panel") { registry.panelOpen.toggle() }.keyboardShortcut("e")
                Button("Needs You") { NeedsYouQueue.shared.trayOpen.toggle() }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                Divider()
                Button("New Agent…") { registry.panelOpen = true; registry.builder = BuilderDraft() }
            }
            CommandMenu("Tabs") {
                Button("Next Tab") { model.cycleTab(by: 1) }.keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Tab") { model.cycleTab(by: -1) }.keyboardShortcut("[", modifiers: [.command, .shift])
                Button("Next Tab (Control)") { model.cycleTab(by: 1) }.keyboardShortcut(.tab, modifiers: .control)
                Button("Previous Tab (Control)") { model.cycleTab(by: -1) }.keyboardShortcut(.tab, modifiers: [.control, .shift])
                Divider()
                ForEach(1...9, id: \.self) { n in
                    Button("Tab \(n)") { model.selectTab(number: n) }
                        .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
                }
            }
        }
        Settings { SettingsView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var agentSocket: AgentEventSocket?
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A SwiftPM executable starts with no bundle policy; without this it gets no menu bar/Dock icon.
        NSApp.setActivationPolicy(.regular)
        // The only launch-time side effect of Agents mode: a listening socket. It is event-driven
        // (blocks in accept) and costs nothing until an awake agent's hook rings it; it wakes nobody.
        agentSocket = AgentEventSocket(path: AgentPaths.standard.socketPath) { e in
            Task { @MainActor in AgentRegistry.shared.handle(e) }
        }
        _ = agentSocket?.start()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        // Final save so restored tabs carry each shell's latest cwd (not the last debounced one).
        WorkspaceModel.shared.saveNow()
        agentSocket?.stop()
    }
}
