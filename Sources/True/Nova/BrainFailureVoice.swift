import Foundation

/// Spoken explanation when the Anthropic call fails for a reason the user can fix. At most once per 10 min per kind.
struct BrainFailureVoice {
    enum Kind: Hashable { case credits, key }
    private var last: [Kind: Date] = [:]
    static let interval: TimeInterval = 600

    /// `failed(...)` carries "\(BrainError)", so match the case names.
    static func kind(forFailure m: String) -> Kind? {
        if m.contains("creditsExhausted") { return .credits }
        if m.contains("keyRejected") { return .key }
        return nil
    }

    static func line(_ k: Kind) -> String {
        switch k {
        case .credits: return "I can't think right now: the Anthropic account is out of credits."
        case .key: return "My Anthropic key was rejected. Check it in Settings."
        }
    }

    mutating func shouldSpeak(_ k: Kind, now: Date) -> Bool {
        if let t = last[k], now.timeIntervalSince(t) < Self.interval { return false }
        last[k] = now; return true
    }
}
