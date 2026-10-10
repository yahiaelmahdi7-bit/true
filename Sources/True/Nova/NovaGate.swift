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

    /// Read-only commands that run without asking. `git` is further limited to read subcommands.
    static let shellAllow: Set<String> = ["ls", "cat", "head", "tail", "grep", "rg", "find", "pwd", "which", "wc", "du", "df",
                                          "ps", "echo", "date", "whoami", "uname", "file", "stat", "sort", "uniq", "tree"]
    static let gitRead: Set<String> = ["status", "log", "diff", "branch", "show", "remote", "rev-parse"]
    private static let shellMeta = CharacterSet(charactersIn: ";&><`\n\\")

    static func shell(_ command: String) -> GateVerdict {
        let c = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else { return .refuse("empty command") }
        if DenyList.isHit(c) { return .refuse("blocked by the deny-list: \(DenyList.hits(c).joined(separator: ", "))") }
        if c.unicodeScalars.contains(where: shellMeta.contains) || c.contains("$(") { return .park("shell command") }
        for seg in c.split(separator: "|", omittingEmptySubsequences: false) {
            let words = seg.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let first = words.first else { return .park("shell command") }
            if first == "git" {
                guard words.count > 1, gitRead.contains(words[1]) else { return .park("shell command") }
            } else if !shellAllow.contains(first) { return .park("shell command") }
            if first == "find", words.contains(where: { ["-exec", "-execdir", "-delete", "-ok"].contains($0) }) { return .park("shell command") }
        }
        return .allow
    }

    /// Files Nova must never read, whatever the model asks.
    static func readableFile(_ path: String) -> GateVerdict {
        let p = (path as NSString).expandingTildeInPath
        let std = URL(fileURLWithPath: p).standardizedFileURL.path
        let home = NSHomeDirectory()
        let name = (std as NSString).lastPathComponent
        if std.hasPrefix(home + "/.ssh") || std.hasPrefix(home + "/.true") || std.hasPrefix(home + "/.aws")
            || std.contains("/Library/Keychains") || name == ".env" || name.hasPrefix(".env.")
            || name.hasSuffix(".pem") || name.hasSuffix(".key") || name.hasPrefix("id_rsa") || name.hasPrefix("id_ed25519") {
            return .refuse("that file holds secrets")
        }
        return .allow
    }

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
    static func tool(_ name: String, _ input: [String: Any], paneBusy: Bool = false, hasUnsaved: Bool = false) -> GateVerdict {
        switch name {
        case "run_shell": return shell(input["command"] as? String ?? "")
        case "read_file": return readableFile(input["path"] as? String ?? "")
        case "move_to_trash": return .park("move to trash")
        case "send_to_pane": return paneBusy ? .park("interrupt a busy agent") : .allow
        case "quit_app": return hasUnsaved ? .park("quit with unsaved changes") : .allow
        case "press_keys": return keys(input["keys"] as? String ?? "")
        case "click_row": return control(label: input["label"] as? String ?? "", secure: false, typing: false)
        case "type_into_row": return control(label: input["label"] as? String ?? "", secure: input["secure"] as? Bool ?? false, typing: true)
        case "spawn_agent": return .allow   // the Command bar's own danger confirm is surfaced as a park by the hand
        default: return .allow
        }
    }
}
