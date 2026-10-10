import Foundation

/// Pure helpers for the live-stream turn (Run 26b). No mic, no AppKit — everything the engine decides about WHICH
/// words are a command lives here so it is testable with recorded partial sequences.
struct NovaLiveTurn {
    /// Tokens at or before this index are spent (a finished turn, or ambient chatter): the wake name must come after.
    private(set) var floor = 0
    /// Hotkey held: the command starts at this token index (no name needed).
    private(set) var hotkeyBase: Int?

    static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }
    /// Lowercased, edge-punctuation-free tokens for name matching.
    static func norm(_ toks: [String]) -> [String] {
        toks.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",.!?;:\"'()…-")) }
    }

    mutating func pressHotkey(wordCount: Int) { hotkeyBase = wordCount }
    mutating func endTurn(wordCount: Int) { floor = wordCount; hotkeyBase = nil }

    /// The addressed command words in this partial, or nil when nothing is addressed to Nova (ambient speech), or
    /// when Nova itself is speaking (self-speech is never a command; only "stop" barges in — see `isBargeIn`).
    mutating func command(in text: String, novaSpeaking: Bool) -> [String]? {
        let toks = Self.tokens(text)
        if toks.count < floor { floor = 0; hotkeyBase = nil }       // the recognition stream restarted
        if novaSpeaking { return nil }
        if let b = hotkeyBase { return Array(toks.dropFirst(min(b, toks.count))) }
        guard let i = NovaAddress.indexAfterLastName(in: Self.norm(toks)), i > floor else { return nil }
        return Array(toks.dropFirst(i))
    }

    /// "stop" in the last two words while Nova is talking.
    static func isBargeIn(_ text: String) -> Bool {
        norm(tokens(text)).suffix(2).contains("stop")
    }
}

/// Eager end-of-turn: when the addressed text has been unchanged for `quiet`, start reflex+brain on the unhandled
/// remainder; new words cancel and restart it (cap `maxRestarts` per turn). Pure so the cap is testable.
struct NovaEagerTurn {
    static let quiet: TimeInterval = 0.25
    static let maxRestarts = 3
    private(set) var restarts = 0
    private(set) var startedFor: String?
    private var lastText = ""
    private var lastChange = Date.distantPast

    enum Action: Equatable { case none, start(String), cancel }

    /// Call on every partial/tick with the current unhandled text.
    mutating func observe(unhandled: String, now: Date) -> Action {
        if unhandled != lastText {
            lastText = unhandled; lastChange = now
            if startedFor != nil {
                startedFor = nil
                restarts += 1
                return .cancel
            }
            return .none
        }
        if startedFor == nil, !unhandled.isEmpty, now.timeIntervalSince(lastChange) >= Self.quiet, restarts <= Self.maxRestarts {
            startedFor = unhandled; return .start(unhandled)
        }
        return .none
    }
}
