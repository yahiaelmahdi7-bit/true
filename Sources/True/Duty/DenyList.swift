import Foundation

/// The deny-list (SPEC Run 15 §4): regex over a fix's commands, steps, files and the staged brief. A hit beats every
/// rule, pre-approval and Jev answer: the item is `handOff`. One pure entry point (`hits`) used by investigate AND approve.
/// Text is normalised first (backslash-newline joined, invisible characters stripped, NFKC) and matched case-insensitively.
enum DenyList {
    private static let tools = "vercel|wrangler|stripe|supabase|netlify|firebase"
    private static let toolVerbs = "deploy|publish|login|link|db|secrets|functions|projects|env|dev|pull|push|promote|rollback|migration|branches|storage|charge|customers|payments|webhooks|trigger|listen|--\\w+|-\\w"
    private static let pm = "npm|pnpm|yarn|bun"

    static let rules: [(name: String, regex: String)] = [
        ("git push", #"\bgit\b[^\n;&|]*?\bpush\b"#),
        ("gh write", #"\bgh\s+(pr\s+(create|merge|close|edit|comment|review)|release\b|workflow\s+run|secret\b|repo\s+(delete|create|edit|rename|archive)|issue\s+(comment|create|close|edit|delete)|api\b[^\n]*(-X|--method|--input|\s-f\b|\s-F\b|--field))"#),
        ("git destructive", #"\bgit\b[^\n;&|]*?(\breset\b[^\n;&|]*?--hard|\bclean\b[^\n;&|]*?(-\w*f|--force)|\bbranch\b[^\n;&|]*?-D\b|\bcheckout\b[^\n;&|]*?--\s+\.|\b(checkout|restore)\s+\.(\s|$))"#),
        ("rm recursive", #"\brm\s(?:[^\n;&|]*?\s)?(-\w*[rR]\w*|--recursive)\b"#),
        ("sql destructive", #"\bDROP\s+(TABLE|DATABASE|SCHEMA|INDEX|VIEW)\b|\bDROP\s+COLUMN\b|\bTRUNCATE\b|\bDELETE\s+FROM\b"#),
        ("hosting cli", "(^|[;&|\\n]\\s*|\\bnpx\\s+|\\brun\\s+)(\(tools))\\b|\\b(\(tools))\\s+(\(toolVerbs))\\b|api\\.stripe\\.com"),
        ("package publish", "\\b(\(pm))\\b[^\n;&|]*?\\bpublish\\b|\\bcargo\\s+publish\\b|\\btwine\\s+upload\\b|\\bfly(ctl)?\\s+(deploy|launch|secrets|apps)\\b"),
        ("messaging", #"\bsendmail\b|\bmailx?\s+(-|\S+@)|api\.resend\.com|\bresend\s+api\b|api\.telegram\.org|hooks\.slack\.com|\btelegram\b|\bslack\s+(message|webhook|post)\b"#),
        ("keychain", #"\bsecurity\b[^\n;&|]*?(password|keychain)\b"#),
        ("secret files", #"(?<![\w])\.env(\.[\w-]+)?(?![\w-])|\.(key|pem)(?!\w)|(?<![\w])id_(rsa|ed25519|ecdsa|dsa)\b|\.ssh/|\.aws/credentials|(?<![\w])credentials(\.\w+)?(?!\w)"#),
        ("protected config", #"\.claude/settings(\.local)?\.json|(~|\$HOME|/Users/\w+)/\.axon\b|(^|[\s'"])\.axon/"#),
        ("kill", #"\b(killall|pkill|kill)\b|quit\s+app\s+"True"|osascript[^\n]*quit"#),
        ("builder kill", #"\bbuilder\s+kill\b"#),
        ("pipe to shell", #"\b(curl|wget)\b[^\n]*\|\s*(?:(?:sudo|env)\s+)*(?:[\w./-]*/)?(?:ba|z|da)?sh\b|\b(?:ba|z|da)?sh\s+(?:-\w+\s+)*(?:<\(|\$\()\s*(?:curl|wget)|\b(?:curl|wget)\b[^\n]*\|\s*(?:sudo\s+)?(?:python3?|perl|ruby|node)\b"#),
    ]

    /// Needs two patterns in the same text (settings.json after `cd ~/.claude`).
    private static let combos: [(name: String, a: String, b: String)] = [
        ("protected config", #"\.claude\b"#, #"settings(\.local)?\.json"#),
    ]

    private static let invisible: Set<UInt32> = {
        var s: Set<UInt32> = [0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0xFEFF, 0x00AD, 0x180E, 0x034F, 0x061C, 0x115F, 0x1160,
                              0x17B4, 0x17B5, 0x3164, 0xFFA0]
        for v in 0x202A...0x202E { s.insert(UInt32(v)) }
        for v in 0x2060...0x2069 { s.insert(UInt32(v)) }
        for v in 0xFE00...0xFE0F { s.insert(UInt32(v)) }
        for v in 0xE0000...0xE007F { s.insert(UInt32(v)) }
        for v in 0xE0100...0xE01EF { s.insert(UInt32(v)) }
        return s
    }()

    /// Strip invisible/format characters (Unicode tags, variation selectors, fillers, bidi, soft hyphen…).
    static func stripInvisible(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars where !invisible.contains(u.value) { out.append(u) }
        return String(out)
    }

    /// Join backslash-newlines, strip invisibles, NFKC.
    static func normalize(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\\\r\n", with: "").replacingOccurrences(of: "\\\n", with: "")
        t = stripInvisible(t)
        return t.precomposedStringWithCompatibilityMapping
    }

    private static func matches(_ text: String, _ re: String, caseInsensitive: Bool = true) -> Bool {
        guard let rx = try? NSRegularExpression(pattern: re, options: caseInsensitive ? [.caseInsensitive] : []) else { return true }
        return rx.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    private static func all(_ text: String, _ re: String, caseInsensitive: Bool = true) -> [String] {
        guard let rx = try? NSRegularExpression(pattern: re, options: caseInsensitive ? [.caseInsensitive] : []) else { return [] }
        let ns = text as NSString
        return rx.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    /// A curl/wget segment that can send a body or write remotely, unless every target host is exactly local.
    private static func curlWrites(_ seg: String) -> Bool {
        let methods = all(seg, #"(?:-[A-Za-z]*X|--request|--method)[=\s]*[A-Za-z]+"#)
        let badMethod = methods.contains { m in
            let verb = m.replacingOccurrences(of: #"^.*?(?:X|request|method)[=\s]*"#, with: "", options: [.regularExpression, .caseInsensitive])
            return !["get", "head"].contains(verb.lowercased())
        }
        let body = matches(seg, #"(?<![\w-])-[A-Za-z]*[dFT]"#, caseInsensitive: false)
            || matches(seg, #"--(data\S*|json|post\S*|form\S*|upload-file|body-\S+|input)\b"#)
        guard badMethod || body else { return false }
        return !allHostsLocal(seg)
    }

    private static func allHostsLocal(_ seg: String) -> Bool {
        var hosts: [String] = []
        for tok in seg.split(whereSeparator: { " \t'\"".contains($0) }).map(String.init) where !tok.hasPrefix("-") {
            var rest = tok
            let hasScheme = rest.range(of: "://") != nil
            if let r = rest.range(of: "://") { rest = String(rest[r.upperBound...]) }
            else if !(rest.contains(".") || rest.contains(":") || rest.lowercased() == "localhost") { continue }
            if !hasScheme && rest.hasPrefix("@") { continue }
            var auth = String(rest.prefix { !"/?#".contains($0) })
            if let at = auth.lastIndex(of: "@") { auth = String(auth[auth.index(after: at)...]) }
            if auth.hasPrefix("[") { auth = String(auth.prefix { $0 != "]" }) + "]" }
            else if let c = auth.firstIndex(of: ":") { auth = String(auth[..<c]) }
            hosts.append(auth.lowercased())
        }
        let local: Set<String> = ["localhost", "127.0.0.1", "[::1]", "0.0.0.0"]
        return !hosts.isEmpty && hosts.allSatisfy { local.contains($0) }
    }

    /// Quotes and backslashes removed, so `git 'push'`, `git pu""sh`, `rm -r"f"` read as plain commands.
    static func dequoted(_ s: String) -> String { s.filter { !"'\"\\".contains($0) } }

    /// Names of every rule the text trips (empty = clear). THE entry point: investigate and approve both call this.
    /// Fails closed: oversize text is a hit; a regex that cannot run is a hit. Both the raw and the dequoted view are checked.
    static func hits(_ raw: String) -> [String] {
        if raw.utf8.count > 65_536 { return ["oversize"] }
        let text = normalize(raw)
        var out: [String] = []
        for view in [text, dequoted(text)] {
            for r in rules where matches(view, r.regex) { out.append(r.name) }
            for c in combos where matches(view, c.a) && matches(view, c.b) { out.append(c.name) }
            // Whole line, not split on ; | & (those can sit inside quotes): any curl/wget line that writes remotely.
            for line in view.split(separator: "\n") {
                let s = String(line)
                guard matches(s, #"\b(curl|wget)\b"#) else { continue }
                if curlWrites(s) { out.append("curl write"); break }
            }
        }
        return Array(Set(out)).sorted()
    }

    static func isHit(_ text: String) -> Bool { !hits(text).isEmpty }

    static func hits(commands: [String], steps: [String], files: [String]) -> [String] {
        hits((commands + steps + files).joined(separator: "\n"))
    }
}
