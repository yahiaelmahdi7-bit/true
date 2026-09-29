import AppKit
import SwiftUI

/// Empty bar space that behaves like the title bar it replaced.
///
/// `.hiddenTitleBar` + full-size content puts our toolbars where the title bar used to be, and
/// their opaque backgrounds swallow the clicks AppKit's title bar would have handled — so
/// double-clicking the top of the window did nothing, where every other Mac app zooms. This view
/// sits BEHIND a bar's controls: a click that misses every control lands here, drags the window on
/// a single click and runs the Mac's own double-click action on a double. Controls keep their
/// clicks because SwiftUI hit-tests them first.
struct WindowChromeArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ChromeView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ChromeView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                WindowChromeArea.titleBarDoubleClick(window)
            } else {
                window.performDrag(with: event)
            }
        }
    }

    /// System Settings → Desktop & Dock → "Double-click a window's title bar to". "Fill" (the
    /// macOS 15+ default, also what an unset key means) and "Maximize" both fill the usable screen;
    /// `performZoom` does that and a second double-click puts the window back, as Warp does.
    static func titleBarDoubleClick(_ window: NSWindow) {
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window.performMiniaturize(nil)
        case "None": break
        default: window.performZoom(nil)
        }
    }
}

extension View {
    /// Make this bar's empty space act like a title bar (drag, double-click). Apply it BEFORE the
    /// bar's own `.background(...)` so it sits above that fill and below the controls.
    func windowChromeArea() -> some View { background(WindowChromeArea()) }
}
