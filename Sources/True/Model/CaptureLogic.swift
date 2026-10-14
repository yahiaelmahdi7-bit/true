import Carbon.HIToolbox
import CoreGraphics
import SwiftUI

/// The one place the capture shortcut is defined (⌃⌥⌘A): the Carbon registration, the menu item and its
/// displayed shortcut all follow. Not ⇧⌘3/4/5 (macOS), not ⌃⌥⌘S / ⌃⌥⌘F / ⇧⌘S / ⌥⌘V (True).
enum CaptureHotKey {
    static let letter: Character = "a"
    static let carbonKeyCode = UInt32(kVK_ANSI_A)
    static let carbonModifiers = UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey)
    static var keyEquivalent: KeyEquivalent { KeyEquivalent(letter) }
    static let eventModifiers: SwiftUI.EventModifiers = [.control, .option, .command]
}

/// Pure geometry for the capture overlay (view points, top-left origin) — testable without a window.
enum CaptureLogic {
    /// The rectangle dragged from `a` to `b`; `square` (Shift) makes it the larger side on both axes, growing
    /// toward the cursor. Always clamped to `bounds`.
    static func dragRect(from a: CGPoint, to b: CGPoint, square: Bool, bounds: CGRect) -> CGRect {
        var dx = b.x - a.x, dy = b.y - a.y
        if square {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side; dy = dy < 0 ? -side : side
        }
        var r = CGRect(x: min(a.x, a.x + dx), y: min(a.y, a.y + dy), width: abs(dx), height: abs(dy))
        r = r.intersection(bounds)
        return r.isNull ? .zero : r
    }

    /// Move a rectangle by `d`, keeping it fully inside `bounds` and the same size.
    static func moved(_ r: CGRect, by d: CGSize, within bounds: CGRect) -> CGRect {
        CGRect(x: max(bounds.minX, min(r.minX + d.width, bounds.maxX - r.width)),
               y: max(bounds.minY, min(r.minY + d.height, bounds.maxY - r.height)),
               width: r.width, height: r.height)
    }

    /// The frontmost window under `p`. `windows` are ordered front to back; tiny ones are never snap targets.
    static func windowRect(at p: CGPoint, in windows: [CGRect]) -> CGRect? {
        windows.first { $0.width >= 40 && $0.height >= 40 && $0.contains(p) }
    }

    /// Selection (view points) → pixel rect in the frozen image, snapped to whole pixels.
    static func pixelRect(_ r: CGRect, viewSize: CGSize, imageSize: CGSize) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let sx = imageSize.width / viewSize.width, sy = imageSize.height / viewSize.height
        let px = CGRect(x: r.minX * sx, y: r.minY * sy, width: r.width * sx, height: r.height * sy).integral
        return px.intersection(CGRect(origin: .zero, size: imageSize))
    }

    /// "1280 × 720" — the live size readout (in pixels, what will be saved).
    static func sizeLabel(_ px: CGRect) -> String { "\(Int(px.width)) × \(Int(px.height))" }

    /// Where the loupe sits: below-right of the cursor, flipping to the other side near an edge.
    static func loupeOrigin(cursor: CGPoint, size: CGFloat, in bounds: CGRect, gap: CGFloat = 22) -> CGPoint {
        var x = cursor.x + gap, y = cursor.y + gap
        if x + size > bounds.maxX { x = cursor.x - gap - size }
        if y + size > bounds.maxY { y = cursor.y - gap - size }
        return CGPoint(x: max(bounds.minX, x), y: max(bounds.minY, y))
    }

    /// Toolbar frame under the selection (or above when there is no room), centred and kept on screen.
    static func toolbarOrigin(selection: CGRect, toolbar: CGSize, in bounds: CGRect, gap: CGFloat = 10) -> CGPoint {
        var y = selection.maxY + gap
        if y + toolbar.height > bounds.maxY - 8 { y = selection.minY - gap - toolbar.height }
        if y < bounds.minY + 8 { y = max(bounds.minY + 8, bounds.maxY - toolbar.height - 8) }   // selection fills the screen: float inside
        let x = max(bounds.minX + 8, min(selection.midX - toolbar.width / 2, bounds.maxX - toolbar.width - 8))
        return CGPoint(x: x, y: y)
    }
}
