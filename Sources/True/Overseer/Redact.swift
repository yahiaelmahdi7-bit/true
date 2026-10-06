import Foundation

/// Strips credentials from text before it leaves the process (the Overseer's Jev call and its log file).
/// Pure. Over-redacting is fine; leaking is not.
enum Redact {
    static let mark = "[redacted]"

    private static let patterns: [NSRegularExpression] = [
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?(?:-----END [A-Z ]*PRIVATE KEY-----|$)"#,
        #"\bsk-(?:ant-)?[A-Za-z0-9_\-]{8,}"#,
        #"\b(?:ghp|gho)_[A-Za-z0-9]{8,}"#,
        #"\bgithub_pat_[A-Za-z0-9_]{8,}"#,
        #"\bAKIA[0-9A-Z]{12,}"#,
        #"\bxox[bp]-[A-Za-z0-9\-]{8,}"#,
        #"\bBearer\s+[A-Za-z0-9._~+/=\-]{8,}"#,
        // NAME=value where NAME contains KEY / TOKEN / SECRET / PASSWORD (any case).
        #"\b[A-Za-z0-9_]*(?i:key|token|secret|password)[A-Za-z0-9_]*=\S+"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    static func secrets(_ text: String) -> String {
        var out = text
        for re in patterns {
            out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out),
                                              withTemplate: mark)
        }
        return out
    }
}
