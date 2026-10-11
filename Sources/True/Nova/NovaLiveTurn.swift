import Foundation

/// Pure helpers for the live-stream turn (Run 26b). No mic, no AppKit — everything the engine decides about WHICH
/// words are a command lives here so it is testable with recorded partial sequences.
struct NovaLiveTurn {
    /// Tokens at or before this index are spent (a finished turn, or ambient chatter): the wake name must come after.
    private(set) var floor = 0
    /// Recognition-stream generation (`WakeListener.begin()` bumps it). Only a NEW stream resets the floor: a revision that
    /// merges tokens ("no va" -> "nova") inside one stream must never bring Nova's own spent words back.
    private var gen = 0
    /// Hotkey held: the command starts at this token index (no name needed).
    private(set) var hotkeyBase: Int?

    /// Words the recognizer timestamped inside Nova's own speech (+ tail) are spent even when delivered late.
    mutating func spend(upTo n: Int) {
        if hotkeyBase != nil { hotkeyBase = max(hotkeyBase ?? 0, n) } else { floor = max(floor, n) }
    }
    static func spentCount(segmentStarts: [Date], windows: [(start: Date, end: Date)], tail: TimeInterval) -> Int {
        var n = 0
        for (i, t) in segmentStarts.enumerated() where windows.contains(where: { t >= $0.start && t <= $0.end.addingTimeInterval(tail) }) { n = i + 1 }
        return n
    }
    /// The last partial and when it arrived. On-device recognition STARTS THE TEXT OVER after a pause, with no final and
    /// no new stream (live 2026-10-11: "Hey nova what time is it" … pause … "No", "Open Safari"), so the floor must reset
    /// then too — otherwise every later "Hey Nova" lands at or below it and Nova stays deaf until the stream ends.
    private var prev: [String] = []
    private var prevAt = Date.distantPast
    static let restartGap: TimeInterval = 1.0

    /// A partial after a pause that is much SHORTER than the one before is a fresh transcript. A revision ("no va" ->
    /// "nova", "time is" -> "time's") keeps most of the letters, so it never resets the floor (P1 still holds).
    static func restarted(from old: [String], to new: [String], gap: TimeInterval) -> Bool {
        guard gap >= restartGap, new.count < old.count else { return false }
        let letters = { (t: [String]) in Double(norm(t).joined().count) }
        return letters(new) < 0.6 * letters(old)
    }

    private mutating func sync(_ generation: Int, _ toks: [String], now: Date) {
        if generation != gen { gen = generation; floor = 0; hotkeyBase = nil }   // a new stream restarted the transcript
        else if Self.restarted(from: prev, to: toks, gap: now.timeIntervalSince(prevAt)) {
            floor = 0; if hotkeyBase != nil { hotkeyBase = 0 }   // same stream, text started over: every word is new
        }
        prev = toks; prevAt = now
    }

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
    mutating func command(in text: String, novaSpeaking: Bool, generation: Int = 0, now: Date = Date()) -> [String]? {
        let toks = Self.tokens(text)
        sync(generation, toks, now: now)
        if novaSpeaking { return nil }
        if let b = hotkeyBase { return Array(toks.dropFirst(min(b, toks.count))) }
        guard let i = NovaAddress.indexAfterLastName(in: Self.norm(toks), capitalized: toks.map { $0.first?.isUppercase == true }), i > floor else { return nil }
        return Array(toks.dropFirst(i))
    }

    /// Engine entry point for every partial. `gated` = Nova speaking or in its echo tail.
    mutating func ingest(_ text: String, gated: Bool, novaSpeaking: Bool, generation: Int = 0, now: Date = Date()) -> [String]? {
        let toks = Self.tokens(text)
        sync(generation, toks, now: now)
        if gated {
            // Nova's own words (and the echo tail) are spent: a "nova" in them must never address a later command (P1).
            let n = toks.count
            if hotkeyBase != nil { hotkeyBase = n } else { floor = n }
            return nil
        }
        return command(in: text, novaSpeaking: novaSpeaking, generation: generation, now: now)
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
