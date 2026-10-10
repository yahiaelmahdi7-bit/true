import AppKit
import Foundation

/// The GATE: deterministic code in front of every hand, whatever the model wants. Fixed word lists are RULES, not
/// judgment, so they stay code (brief). Screen text, pane output, file contents and web pages are DATA — the gate
/// never reads them to decide anything; it looks only at the tool name and the arguments about to run.
enum GateVerdict: Equatable {
    case allow
    case park(String)      // wait for a spoken "go ahead" (30 s) or the HUD Approve button
    case refuse(String)    // spoken with the reason; never runs
}

enum NovaGate {
    static let parkSeconds: TimeInterval = 30

    /// Where a tool call comes from. `.local` = the user's own words matched by the instant lane / reflex tables.
    enum Origin { case model, local }
    /// The app Nova lives in: it may never quit, hide or terminate it.
    static let ownBundleIDs: Set<String> = Set(["net.prismlens.true"] + (Bundle.main.bundleIdentifier.map { [$0] } ?? []))
    static func isOwnApp(name: String) -> Bool {
        let n = name.lowercased().trimmingCharacters(in: .whitespaces)
        var own: Set<String> = ["true", "true app", "true.app"]
        if let b = Bundle.main.infoDictionary?["CFBundleName"] as? String { own.insert(b.lowercased()) }
        return own.contains(n)
    }
    static func isOwnApp(_ app: NSRunningApplication) -> Bool {
        if let id = app.bundleIdentifier, ownBundleIDs.contains(id) { return true }
        return app.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    /// Free path = read-only and provably so (see `NovaShell`). DenyList first; everything else parks with the EXACT command.
    static func shell(_ command: String, cwd: String = "") -> GateVerdict {
        let c = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else { return .refuse("empty command") }
        if c.unicodeScalars.contains(where: { $0.value == 0 }) || cwd.unicodeScalars.contains(where: { $0.value == 0 }) { return .refuse("bad characters in the command") }
        if DenyList.isHit(c) { return .refuse("blocked by the deny-list: \(DenyList.hits(c).joined(separator: ", "))") }
        switch NovaShell.plan(c, cwd: cwd) {
        case .run: return .allow
        case .park(let what): return .park(what)
        case .refuse(let why): return .refuse(why)
        }
    }

    /// Files Nova must never read, whatever the model asks (symlinks resolved, case-insensitive).
    static func readableFile(_ path: String, home: String = NSHomeDirectory()) -> GateVerdict { NovaPaths.check(path, home: home) }

    /// A control about to be pressed or typed into.
    static func control(label: String, secure: Bool, typing: Bool) -> GateVerdict {
        if secure, typing { return .refuse("I never type into password fields") }
        if !typing, ComputerUse.isConsequential(label) { return .park("press \(label)") }
        return .allow
    }

    static func keys(_ combo: String) -> GateVerdict {
        let k = combo.lowercased().replacingOccurrences(of: " ", with: "")
        if k == "cmd+return" || k == "cmd+enter" || k == "⌘↩" || k == "cmd+return" { return .park("send with ⌘↩") }
        return .allow
    }

    /// One entry point per tool call. `paneBusy`/`hasUnsaved` are supplied by the caller (live state, not model text).
    /// Every model-initiated send/relay/spawn/open_url parks with the exact target and full text or URL.
    static func tool(_ name: String, _ input: [String: Any], paneBusy: Bool = false, hasUnsaved: Bool = false, origin: Origin = .model) -> GateVerdict {
        func str(_ k: String) -> String { input[k] as? String ?? "" }
        if input.values.contains(where: { ($0 as? String)?.unicodeScalars.contains { $0.value == 0 } == true }) { return .refuse("bad characters in the request") }
        switch name {
        case "run_shell": return shell(str("command"), cwd: str("cwd"))
        case "read_file": return readableFile(str("path"))
        case "move_to_trash": return .park("move to trash: " + str("path"))
        case "send_to_pane": return origin == .local && !paneBusy ? .allow : .park("\(paneBusy ? "interrupt busy agent " : "send to ")\(str("target")): \(str("text"))")
        case "relay": return .park("relay \(str("from")) → \(str("to"))\(paneBusy ? " (busy)" : "")")
        case "spawn_agent": return .park("start an agent: " + str("text"))
        case "open_url": return origin == .local ? .allow : .park("open URL: " + str("url"))
        case "quit_app", "quit_graceful", "hide_app":
            if isOwnApp(name: str("name")) { return .refuse("I can't quit or hide True itself") }
            return name == "quit_app" ? .park("quit \(str("name"))\(hasUnsaved ? " (may have unsaved changes)" : "")") : .allow
        case "press_keys": return keys(str("keys"))
        case "click_row": return control(label: str("label"), secure: false, typing: false)
        case "type_into_row": return control(label: str("label"), secure: input["secure"] as? Bool ?? false, typing: true)
        default: return .allow
        }
    }
}
