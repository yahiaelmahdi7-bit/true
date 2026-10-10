import Foundation

/// Nova's switches (UserDefaults). Wake word defaults ON; the mic indicator + mute pill make that visible.
enum NovaSettings {
    static let enabledKey = "nova.enabled", wakeKey = "nova.wakeWord", hotkeyKey = "nova.hotkey", effortKey = "nova.effort", timingsKey = "nova.showTimings"
    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    static var wakeWord: Bool { UserDefaults.standard.object(forKey: wakeKey) as? Bool ?? true }
    static var hotkey: Hotkey { Hotkey(rawValue: UserDefaults.standard.string(forKey: hotkeyKey) ?? "") ?? .rightOption }
    static var effort: String { UserDefaults.standard.string(forKey: effortKey) == "medium" ? "medium" : "low" }
    static var showTimings: Bool { UserDefaults.standard.bool(forKey: timingsKey) }
}
