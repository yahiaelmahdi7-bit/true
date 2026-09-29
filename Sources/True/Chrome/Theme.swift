import AppKit
import CoreImage
import SwiftUI

/// True's whole palette. Black, no chrome: every surface is the terminal's own black, and the only
/// lines are hairlines between panes. Views and the terminal bridge read these, never literals.
enum Theme {
    static let background = Color.black
    static let hairline = Color.white.opacity(0.10)
    static let text = Color.white.opacity(0.88)
    static let dimText = Color.white.opacity(0.38)

    static let nsBackground = NSColor.black
    static let nsText = NSColor(white: 0.88, alpha: 1)

    /// The soft aura around terminal text. A fresh instance per call: NSShadow is mutable and
    /// each view keeps the one it's handed.
    static var textGlow: NSShadow {
        let s = NSShadow()
        s.shadowColor = NSColor(white: 1, alpha: 0.45)
        s.shadowBlurRadius = 4
        s.shadowOffset = .zero
        return s
    }

    /// Drains all colour from what a terminal draws (see `TrueTerminalView.applyThemeColors`).
    static var monochrome: [CIFilter] {
        guard let f = CIFilter(name: "CIColorControls") else { return [] }
        f.setValue(0, forKey: kCIInputSaturationKey)
        return [f]
    }

    /// Breathing room between a pane's edge and its first/last character.
    static let paneInsets = EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 10)
}
