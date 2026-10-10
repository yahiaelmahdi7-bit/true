import Foundation

/// The speed trick: on a finished utterance the REFLEX (Jev ~0.35 s) and the BRAIN are both in flight. If the reflex
/// clears the acting floor for a direct act, the brain task is cancelled (its URLSession stream is torn down on
/// cancellation) and the hand acts; otherwise the brain's request — held for the reflex's verdict for at most
/// `headStart` — carries the verdict as a prior in its user turn.
enum NovaSpeculative {
    enum Path: Equatable { case reflex(NovaAction), brain(prior: String?), none }
    static let headStart: Duration = .milliseconds(900)

    /// Acting floors, from NOVA-REFLEX.md: kind ≥ 0.7, addressed ≥ 0.7 (take) / ambient rules, verb ≥ 0.8.
    static func decide(_ v: NovaReflex.Verdict?) -> Path {
        guard let v else { return .brain(prior: nil) }
        if v.isInterrupt { return .none }
        if v.source == .ambient { return v.isAmbientCommand ? (NovaReflex.action(for: v).map { .reflex($0) } ?? .none) : .none }
        if v.kind == .deskControl, v.kindConfidence >= 0.7, v.addressed >= 0.7, v.verbConfidence >= 0.8,
           let a = NovaReflex.action(for: v, roster: []), ["focus_pane", "read_pane", "status", "screenshot_full", "open_app", "quit_app", "media_control"].contains(a.action) {
            return .reflex(a)
        }
        return .brain(prior: prior(v))
    }

    static func prior(_ v: NovaReflex.Verdict) -> String {
        "Reflex prior (Jev, advisory): kind=\(v.kind.rawValue) \(Int(v.kindConfidence * 100))%, verb=\(v.verb ?? "none"), seat=\(v.seat ?? "none")."
    }

    /// Runs both at t0. The brain never awaits the reflex (Run 26b: parallel, not sequential); if the reflex clears
    /// the acting floor the brain is cancelled. `brain` must honour cancellation.
    @discardableResult
    static func race(reflex: @escaping @Sendable () async -> NovaReflex.Verdict?,
                     direct: @escaping @Sendable (NovaAction) async -> Void,
                     brain: @escaping @Sendable () async -> Void,
                     haveBrain: Bool = true) async -> Path {
        let brainTask: Task<Void, Never>? = haveBrain ? Task { await brain() } : nil
        let v = await reflex()
        let path = decide(v)
        switch path {
        case .reflex(let a): brainTask?.cancel(); await direct(a)
        case .none: brainTask?.cancel()
        case .brain: await brainTask?.value
        }
        return path
    }
}
