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
                TerminalArea(model: model)
                if registry.panelOpen {
                    Theme.hairline.frame(width: 1)
                    HubPanel(registry: registry).transition(.move(edge: .trailing))
                }
            }
            // Content stays below the title-bar zone: on macOS 26 SwiftUI lays views out there under
            // `.ignoresSafeArea` but never paints them (a red test strip never reached the screen).
            // The tab numbers live in that zone as an AppKit-hosted view instead (`installTabs`).
            .background { Theme.background.ignoresSafeArea(); WindowConfigurator().frame(width: 0, height: 0) }
            .preferredColorScheme(.dark)
            .frame(minWidth: 480, minHeight: 300)
            .overlay { ProjectPaletteHost() }
            .sheet(item: Bindable(registry).builder) { AgentBuilderSheet(draft: $0, registry: registry) }
            .sheet(isPresented: Bindable(ContextCleaner.shared).isOpen) { CleanerSheet(cleaner: ContextCleaner.shared) }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") { model.newTab() }.keyboardShortcut("t")
                Button("Open Project…") { ProjectPalette.shared.toggle() }.keyboardShortcut("o")
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
                Divider()
                Button("Screenshots…") { ScreenshotWatcher.shared.trayOpen.toggle() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Paste Latest Screenshot") { ScreenshotWatcher.shared.pasteLatest() }
                    .keyboardShortcut("v", modifiers: [.command, .option])
            }
            CommandMenu("Hub") {
                Button("Toggle Hub") { registry.panelOpen.toggle() }.keyboardShortcut("e")
                Button("Needs You") { NeedsYouQueue.shared.trayOpen.toggle() }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                Divider()
                Button("New Agent…") { registry.panelOpen = true; registry.builder = BuilderDraft() }
                Button("Context Cleaner…") { ContextCleaner.shared.isOpen = true }
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
    private var controlSocket: AgentControlSocket?
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A SwiftPM executable starts with no bundle policy; without this it gets no menu bar/Dock icon.
        NSApp.setActivationPolicy(.regular)
        // Launch side effect: paint the live Dock tile with the bare cursive T. The bundle icon alone gets
        // boxed into a grey tile by macOS 26; a runtime image is drawn as-is. One-shot, no ongoing cost.
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        // Closing the main window quits True, and its views may be dismantled before applicationShouldTerminate.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil,
                                               queue: .main) { n in
            guard let w = n.object as? NSWindow, w.title == "True" else { return }
            MainActor.assumeIsolated { SessionSnapshot.atQuit() }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil,
                                               queue: .main) { n in
            guard let w = n.object as? NSWindow else { return }
            Task { @MainActor in WindowChrome.hideButtons(w) }
        }
        // The only launch-time side effect of Agents mode: a listening socket. It is event-driven
        // (blocks in accept) and costs nothing until an awake agent's hook rings it; it wakes nobody.
        agentSocket = AgentEventSocket(path: AgentPaths.standard.socketPath) { e in
            Task { @MainActor in AgentRegistry.shared.handle(e) }
        }
        _ = agentSocket?.start()
        // Same kind of side effect, for `truectl`: one more thread parked in accept() — 0% idle, nothing
        // polls. It only acts when an awake agent runs `truectl summon`, and the reply says who was woken.
        controlSocket = AgentControlSocket(path: AgentPaths.standard.controlSocketPath, registry: AgentRegistry.shared)
        _ = controlSocket?.start()
        AgentHooks.installClient(paths: AgentPaths.standard)   // the door's client, before any agent wakes
        AgentHooks.installPaneHooks(paths: AgentPaths.standard)  // two small files, rewritten only if stale
        // The Hub's data: one directory scan plus a few kqueue watches on ~/.claude/sessions and
        // ~/.claude/builders — event-driven, 0% CPU when idle, no timer. Read-only; never opens *.key.
        HubStore.shared.start()
        // The screen stays on (so it never locks) only while agents work (IdleGate); 120 s after everything
        // is idle it is released and the Mac follows its normal sleep timers. Event-driven; the exit drops it.
        WorkAwake.shared.start()
        // One kqueue watch on the screenshot folder: 0% CPU when idle, and it is what makes "fresh" possible.
        ScreenshotWatcher.shared.start()
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Before any view is torn down: the shells are still alive, so their Claude children can be found.
        SessionSnapshot.atQuit()
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        // Final save so restored tabs carry each shell's latest cwd (not the last debounced one).
        WorkspaceModel.shared.saveNow()
        agentSocket?.stop()
        controlSocket?.stop()
    }
}
