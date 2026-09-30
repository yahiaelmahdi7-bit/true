import AppKit
import SwiftUI

/// Which NSWindow is True's main window, by identity rather than title (a retitled main window must
/// still snapshot; another window titled "True" must not). The scene is a single-instance `Window`,
/// so there is exactly one main window and "it closed" means "True is quitting".
@MainActor
enum MainWindow {
    /// Weak: the registry never keeps a closed window alive.
    private(set) static weak var current: NSWindow?

    static func register(_ window: NSWindow) { current = window }

    /// Pure decision for the willClose observer: snapshot only when the closing window IS the main one.
    /// Sheets, popovers, Settings and any other window (whatever its title) answer false.
    /// Identities (not windows) so the notification closure can carry the value across isolation.
    nonisolated static func shouldSnapshot(closing: ObjectIdentifier?, main: ObjectIdentifier?) -> Bool {
        guard let closing, let main else { return false }
        return closing == main
    }
}

/// Zero-size probe for the main scene's root view: reports its window to ``MainWindow`` once it is in one.
struct MainWindowMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { MainWindow.register(window) }
        }
    }
}
