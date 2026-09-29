import AppKit
import SwiftTerm

/// UserDefaults keys + value clamping for the few settings True has. `@AppStorage` in views and
/// plain reads in the terminal bridge share these so a key is spelled exactly once.
enum TerminalSettings {
    static let fontFamilyKey = "terminal.fontFamily"
    static let fontSizeKey = "terminal.fontSize"
    static let cursorKey = "terminal.cursor"
    static let scrollbackKey = "terminal.scrollback"

    static let systemMono = "System Mono"
    static let defaultFontSize = 13.0
    static let defaultScrollback = 10_000

    static func clampSize(_ v: Double) -> Double { min(32, max(9, v.isFinite ? v : defaultFontSize)) }
    static func clampScrollback(_ v: Int) -> Int { min(100_000, max(500, v)) }

    /// Fixed-pitch families installed on this Mac, for the picker.
    static var fixedPitchFamilies: [String] {
        let names = NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? []
        let fams = names.compactMap { NSFont(name: $0, size: 12)?.familyName }
        return Array(Set(fams)).sorted()
    }

    static func font(family: String, size: Double) -> NSFont {
        let s = CGFloat(clampSize(size))
        if family == systemMono { return NSFont.monospacedSystemFont(ofSize: s, weight: .regular) }
        return NSFont(name: family, size: s)
            ?? NSFontManager.shared.font(withFamily: family, traits: .fixedPitchFontMask, weight: 5, size: s)
            ?? NSFont.monospacedSystemFont(ofSize: s, weight: .regular)
    }

    /// Cursor choices. Default is a STEADY block: a blinking cursor is a permanent wake-up timer.
    enum Cursor: String, CaseIterable, Identifiable {
        case steadyBlock, blinkBlock, steadyBar, blinkBar, steadyUnderline, blinkUnderline
        var id: String { rawValue }
        var label: String {
            switch self {
            case .steadyBlock: "Block"
            case .blinkBlock: "Block (blinking)"
            case .steadyBar: "Bar"
            case .blinkBar: "Bar (blinking)"
            case .steadyUnderline: "Underline"
            case .blinkUnderline: "Underline (blinking)"
            }
        }
        var style: CursorStyle {
            switch self {
            case .steadyBlock: .steadyBlock
            case .blinkBlock: .blinkBlock
            case .steadyBar: .steadyBar
            case .blinkBar: .blinkBar
            case .steadyUnderline: .steadyUnderline
            case .blinkUnderline: .blinkUnderline
            }
        }
    }
}
