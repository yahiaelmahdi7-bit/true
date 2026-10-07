import Foundation

/// The deny-list (SPEC Run 15 §4): regex over a fix's commands, steps and files. A hit beats every rule,
/// pre-approval and Jev answer: the item is `handOff`. Re-run on the exact staged text at Approve.
enum DenyList {
    private static let tools = "vercel|wrangler|stripe|supabase"
    private static let toolVerbs = "deploy|publish|login|link|db|secrets|functions|projects|env|dev|pull|push|promote|rollback|migration|branches|storage|charge|customers|payments|webhooks|trigger|listen|--\\w+|-\\w"

    static let rules: [(name: String, regex: String)] = [
        ("git push", #"\bgit\s+(-\S+\s+)*push\b"#),
        ("gh pr", #"\bgh\s+pr\s+(create|merge)\b"#),
        ("git destructive", #"\bgit\s+(reset\s+--hard|clean\s+-\w*f|branch\s+-D\b)"#),
        ("rm recursive", #"\brm\s+(-\w*[rR]\w*|--recursive)\b"#),
        ("sql destructive", #"\bDROP\s+(TABLE|DATABASE|SCHEMA|INDEX)\b|\bTRUNCATE\b|\bDELETE\s+FROM\b"#),
        ("hosting cli", "(^|[;&|\\n]\\s*|\\bnpx\\s+|\\brun\\s+)(\(tools))\\b|\\b(\(tools))\\s+(\(toolVerbs))\\b|api\\.stripe\\.com"),
        ("npm publish", #"\bnpm\s+publish\b"#),
        ("messaging", #"\bsendmail\b|\bmailx?\s+-|api\.resend\.com|\bresend\s+api\b|api\.telegram\.org|hooks\.slack\.com|\btelegram\b|\bslack\s+(message|webhook|post)\b"#),
        ("keychain", #"\bsecurity\s+\S*generic-password\b"#),
        ("secret files", #"(^|[\s/'"=~,])\.env(\.[\w-]+)?($|[\s,;:'"])|\.(key|pem)($|[\s,;:'")])|(^|[\s/'"=~,])id_(rsa|ed25519|ecdsa|dsa)\b|~/\.ssh/|/\.ssh/"#),
        ("protected config", #"\.claude/settings(\.local)?\.json|(~|\$HOME|/Users/\w+)/\.axon\b|(^|[\s'"])\.axon/"#),
        ("kill True", #"\b(killall|pkill)\b|quit\s+app\s+"True"|osascript[^\n]*quit"#),
        ("builder kill", #"\bbuilder\s+kill\b"#),
    ]

    private static let mutating = #"(-X\s*(POST|PUT|PATCH|DELETE)\b|--request\s+(POST|PUT|PATCH|DELETE)\b|\s-d\b|\s--data\S*|\s--post\S*|\s-F\b|\s--form\b|--upload-file|\s-T\s)"#
    private static let localHost = #"(localhost|127\.0\.0\.1|\[::1\]|0\.0\.0\.0)"#

    /// Names of every rule the text trips (empty = clear).
    static func hits(_ text: String) -> [String] {
        var out: [String] = []
        for r in rules where text.range(of: r.regex, options: .regularExpression) != nil { out.append(r.name) }
        for seg in text.split(whereSeparator: { ";\n|&".contains($0) }) {
            let s = String(seg)
            guard s.range(of: #"\b(curl|wget)\b"#, options: .regularExpression) != nil else { continue }
            let bodyless = s.range(of: mutating, options: [.regularExpression, .caseInsensitive]) != nil
            if bodyless && s.range(of: localHost, options: .regularExpression) == nil { out.append("curl write"); break }
        }
        return out
    }

    static func isHit(_ text: String) -> Bool { !hits(text).isEmpty }

    static func hits(commands: [String], steps: [String], files: [String]) -> [String] {
        hits((commands + steps + files).joined(separator: "\n"))
    }
}
