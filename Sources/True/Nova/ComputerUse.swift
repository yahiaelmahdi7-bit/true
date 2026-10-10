import Foundation

/// Screen-loop seam. Nova's full AX-walk/Jev-step loop (Axon `Nova/ComputerUse.swift`, ~1300 lines) is NOT
/// ported in this run; `do_on_screen` is handed to Haiku's tools instead. What stays here is the one rule the
/// gate and the ambient check share: which labels are consequential.
enum ComputerUse {
    /// Labels that spend money, send words, destroy data, or grant access. Whole-word, case-insensitive.
    /// Conservative on purpose: a false positive costs one "go ahead"; a false negative sends the email.
    nonisolated static let consequentialWords: [String] = [
        "send", "submit", "pay", "purchase", "buy", "delete", "remove", "confirm", "sign in",
        "log in", "login", "install", "allow", "checkout", "check out", "place order", "discard",
        "trash", "unsubscribe", "transfer", "publish", "post", "share now", "accept", "empty trash",
        "erase", "format", "uninstall", "grant", "authorize", "authorise",
    ]

    nonisolated static func isConsequential(_ label: String) -> Bool {
        let words = label.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let joined = " " + words.joined(separator: " ") + " "
        return consequentialWords.contains { joined.contains(" \($0) ") }
    }
}
