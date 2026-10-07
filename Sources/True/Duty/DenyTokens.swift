import Foundation

/// Word-by-word reading of a command text (single pass, no regex gaps): git behind its global options, and the target of a pipe
/// behind any wrapper chain. Complements the regex rules in `DenyList`; every input is already under the 8 KB cap.
extension DenyList {
    private static let wrappers: Set<String> = ["sudo", "doas", "env", "nohup", "xargs", "command", "exec", "nice", "ionice", "time",
                                                "stdbuf", "timeout", "caffeinate", "arch"]
    /// Wrapper flags that take a separate value word.
    private static let valuedFlags: Set<String> = ["-u", "-g", "-C", "-U", "-h", "-p", "-r", "-t", "-n", "-c", "-I", "-L", "-P", "-s", "-k"]
    private static let interpreters: Set<String> = ["sh", "bash", "zsh", "dash", "ksh", "fish", "csh", "tcsh", "perl", "ruby", "node",
                                                    "osascript", "php"]
    /// git global options whose value is the next word (when not written `--opt=value`).
    private static let gitValued: Set<String> = ["-c", "-C", "--git-dir", "--work-tree", "--namespace", "--super-prefix", "--config-env"]
    private static let gitDangerousKeys = ["alias.", "core.sshcommand", "core.hookspath", "credential.helper", "core.pager", "core.editor",
                                           "core.fsmonitor"]

    private static func isOp(_ t: String) -> Bool { t.first.map { ";&|\n".contains($0) } ?? false }

    /// Words, with `; & | && || |& newline` as their own operator tokens.
    static func tokens(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var op = ""
        func flushWord() {
            let w = cur.trimmingCharacters(in: CharacterSet(charactersIn: "(){}"))
            if !w.isEmpty { out.append(w) }
            cur = ""
        }
        func flushOp() { if !op.isEmpty { out.append(op); op = "" } }
        for ch in s {
            if ";&|".contains(ch) { flushWord(); op.append(ch) }
            else if ch == "\n" { flushWord(); flushOp(); out.append("\n") }
            else if ch == " " || ch == "\t" || ch == "\r" { flushWord(); flushOp() }
            else { flushOp(); cur.append(ch) }
        }
        flushWord(); flushOp()
        return out
    }

    private static func base(_ w: String) -> String { String(w.split(separator: "/").last ?? Substring(w)) }

    static func tokenHits(_ view: String) -> [String] {
        var out: Set<String> = []
        let toks = tokens(view)
        let hasDownload = matches(view, #"\b(curl|wget)\b"#)
        // One flag byte per token so the 200-word scans below compare integers, not strings.
        let kinds: [UInt8] = toks.map { w in
            if w == "--hard" { return 1 }
            if w == "--force" || (w.hasPrefix("-") && !w.hasPrefix("--") && w.utf8.contains(UInt8(ascii: "f"))) { return 2 }
            if w == "-D" { return 4 }
            if w == "." { return 8 }
            if w == "--" { return 16 }
            return 0
        }
        var i = 0
        while i < toks.count {
            let t = toks[i]
            if t.utf8.count < 200, base(t).lowercased() == "git" { gitAt(toks, kinds, i, &out) }
            if hasDownload, t == "|" || t == "|&" { if pipeTarget(toks, i + 1) { out.insert("pipe to shell") } }
            i += 1
        }
        return Array(out)
    }

    /// `git [global options] <subcommand> <rest…>` -> the existing git rules run on the normalised form.
    private static func gitAt(_ toks: [String], _ kinds: [UInt8], _ at: Int, _ out: inout Set<String>) {
        var j = at + 1
        while j < toks.count, !isOp(toks[j]) {
            let w = toks[j]
            guard w.hasPrefix("-") else { break }
            let lw = w.lowercased()
            if gitDangerousKeys.contains(where: { lw.contains($0) }) { out.insert("obfuscated shell") }
            if gitValued.contains(w) {
                j += 1
                if j < toks.count, !isOp(toks[j]), gitDangerousKeys.contains(where: { toks[j].lowercased().contains($0) }) {
                    out.insert("obfuscated shell")
                }
            }
            j += 1
        }
        guard j < toks.count, !isOp(toks[j]) else { return }
        let sub = toks[j].lowercased()
        guard ["push", "reset", "clean", "branch", "checkout", "restore"].contains(sub) else { return }
        var end = j + 1
        while end < toks.count, !isOp(toks[end]), end - j <= 200 { end += 1 }
        func has(_ m: UInt8) -> Bool { (j + 1..<end).contains { kinds[$0] & m != 0 } }
        let first: UInt8 = j + 1 < end ? kinds[j + 1] : 0
        switch sub {
        case "push": out.insert("git push")
        case "reset": if has(1) { out.insert("git destructive") }
        case "clean": if has(2) { out.insert("git destructive") }
        case "branch": if has(4) { out.insert("git destructive") }
        case "checkout":
            if first & 8 != 0 || (j + 1..<max(end - 1, j + 1)).contains(where: { kinds[$0] & 16 != 0 && kinds[$0 + 1] & 8 != 0 }) { out.insert("git destructive") }
        case "restore": if first & 8 != 0 { out.insert("git destructive") }
        default: break
        }
    }

    /// After a pipe: skip wrapper words and their flags/args; is the first real word a shell/interpreter?
    private static func pipeTarget(_ toks: [String], _ from: Int) -> Bool {
        var j = from
        var inWrapper = false
        while j < toks.count, !isOp(toks[j]) {
            let w = toks[j]
            let b = base(w).lowercased()
            if wrappers.contains(b) { inWrapper = true; j += 1; continue }
            if inWrapper {
                if w.hasPrefix("-") {
                    j += 1
                    if !w.contains("="), valuedFlags.contains(w), j < toks.count, !isOp(toks[j]) { j += 1 }
                    continue
                }
                if w.contains("=") || w.range(of: #"^[0-9.]+[smhd]?$"#, options: .regularExpression) != nil { j += 1; continue }
            }
            return interpreters.contains(b) || b.hasPrefix("python")
        }
        return false
    }
}
