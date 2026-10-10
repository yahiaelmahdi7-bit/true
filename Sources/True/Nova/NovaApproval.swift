import Foundation

/// What a spoken phrase means for a parked action. Pure and static so the rules are testable (C1/H1).
/// Approval needs an ADDRESSED yes (wake name in the same utterance, or the hotkey held); denial works from anywhere.
enum NovaApproval {
    enum Decision: Equatable { case approve, deny, none }
    static let yes: Set<String> = ["go ahead", "approve", "yes", "do it", "confirm"]
    static let no: Set<String> = ["no", "not", "nope", "nah", "never", "cancel", "stop", "dont", "didnt", "wont", "cant", "deny", "denied",
                                  "disapprove", "disapproved", "negative"]
    static let micTail: TimeInterval = 0.4

    static func words(_ text: String) -> [String] {
        let s = text.lowercased().replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "'", with: "")
        return String(s.map { $0.isLetter ? $0 : " " }).split(separator: " ").map(String.init)
    }
    static func decide(_ text: String, addressed: Bool) -> Decision {
        let w = words(text)
        if w.contains(where: no.contains) { return .deny }               // a negation anywhere beats yes
        let named = w.contains("nova")
        let core = w.filter { !["nova", "hey", "please"].contains($0) }
        if core.count > 4 { return .none }
        let phrase = core.joined(separator: " ")
        return (addressed || named) && yes.contains(phrase) ? .approve : .none
    }
    /// The only entry for SPOKEN approval. Approve needs a FINAL utterance and the card that was showing when it started.
    static func resolution(_ text: String, addressed: Bool, final: Bool, cardAtStart: UUID?, cardNow: UUID?) -> Decision {
        let d = decide(text, addressed: addressed)
        if d == .deny { return .deny }                       // a no is safe from anywhere, even mid-sentence
        guard d == .approve, final, let start = cardAtStart, start == cardNow else { return .none }
        return .approve
    }
    /// Nova's own voice (and its echo tail) never counts as input.
    static func micGated(speaking: Bool, sinceSpeechEnd: TimeInterval) -> Bool { speaking || sinceSpeechEnd < micTail }
}

/// One parked action at a time, bound to its own id and timer. A new park denies the old one; a stale resolve is a no-op.
@MainActor
final class NovaApprovals {
    struct Item: Equatable { let id: UUID; let what: String }
    private var cont: CheckedContinuation<Bool, Never>?
    private(set) var current: Item?
    var onChange: ((Item?) -> Void)?

    func request(_ what: String, seconds: TimeInterval) async -> Bool {
        if let old = current { finish(false, old.id) }
        let id = UUID()
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            cont = c; current = Item(id: id, what: what); onChange?(current)
            Task { [weak self] in try? await Task.sleep(for: .seconds(seconds)); self?.resolve(false, id: id) }
        }
    }
    /// `id` nil = whatever is pending (spoken answer); a given id must match (HUD click, timers).
    @discardableResult
    func resolve(_ yes: Bool, id: UUID? = nil) -> Bool {
        guard let cur = current, id == nil || id == cur.id else { return false }
        finish(yes, cur.id); return true
    }
    private func finish(_ yes: Bool, _ id: UUID) {
        let c = cont; cont = nil; current = nil; onChange?(nil); c?.resume(returning: yes)
    }
}
