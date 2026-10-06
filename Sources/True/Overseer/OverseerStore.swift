import Foundation
import Observation

/// Pane → verdict. Fed from the same event tap as `AgentRegistry` (`TrueApp`). Read-only: it never types into a
/// pane. Event-driven: one Jev call per Stop event, nothing on a timer. Jev down / slow / keyless, or the
/// Settings toggle off → no verdict, everything as before.
@MainActor
@Observable
final class OverseerStore {
    static let shared = OverseerStore()
    static let maxInFlight = 6

    private(set) var verdicts: [UUID: OverseerVerdict] = [:]

    @ObservationIgnored private let jev: JevClient
    @ObservationIgnored private let enabled: () -> Bool
    @ObservationIgnored private let log: OverseerLog
    @ObservationIgnored private let cwdFor: (UUID) -> String?
    @ObservationIgnored private let loadDigest: @Sendable (URL, String?) -> TurnDigest?
    /// Bumped on every Stop and on every new prompt / close: a reply for an older token is dropped.
    @ObservationIgnored private var token: [UUID: Int] = [:]
    @ObservationIgnored private var inFlight: Set<UUID> = []

    init(jev: JevClient = .shared,
         enabled: @escaping () -> Bool = { TerminalSettings.overseer },
         log: OverseerLog = .standard,
         cwdFor: @escaping (UUID) -> String? = { pane in
             WorkspaceModel.shared.state.tabs.compactMap { $0.cwds[pane] }.first
         },
         loadDigest: @escaping @Sendable (URL, String?) -> TurnDigest? = { TurnDigestBuilder.load(url: $0, stopMessage: $1) }) {
        self.jev = jev; self.enabled = enabled; self.log = log; self.cwdFor = cwdFor; self.loadDigest = loadDigest
    }

    /// Number of judgments running right now (tests).
    var judging: Int { inFlight.count }

    func handle(_ e: PaneEvent) {
        switch e.kind {
        case .progress where e.message == "prompt":
            clear(e.pane)
        case .stop:
            guard enabled(), let path = e.transcript, !path.isEmpty else { return }
            judge(e, transcript: path)
        default:   // `.error` ends a turn without completing it: never judged
            break
        }
    }

    func paneClosed(_ pane: UUID) {
        clear(pane)
        token[pane] = nil
    }

    func clearAll() {
        for p in Array(verdicts.keys) + Array(inFlight) { token[p, default: 0] += 1 }
        verdicts = [:]
    }

    private func clear(_ pane: UUID) {
        token[pane, default: 0] += 1
        verdicts[pane] = nil
    }

    private func judge(_ e: PaneEvent, transcript: String) {
        let pane = e.pane
        guard !inFlight.contains(pane) else {
            OverseerLog.logger.info("pane=\(pane.uuidString.prefix(8), privacy: .public) skipped: already judging")
            return
        }
        guard inFlight.count < Self.maxInFlight else {
            OverseerLog.logger.info("pane=\(pane.uuidString.prefix(8), privacy: .public) skipped: \(Self.maxInFlight) judgments in flight")
            return
        }
        token[pane, default: 0] += 1
        let mine = token[pane] ?? 0
        inFlight.insert(pane)
        let load = loadDigest, jev = self.jev, log = self.log
        let session = e.session, cwd = cwdFor(pane), stop = e.message
        Task { @MainActor [weak self] in
            let started = Date()
            let raw = await Task.detached { load(URL(fileURLWithPath: transcript), stop) }.value
            var record: OverseerLog.Record?
            if let digest = raw?.redacted {
                let reply = await OverseerJudge.ask(digest, jev: jev)
                let judgment = OverseerJudge.judge(reply: reply, digest: digest)
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                if reply != nil {
                    record = OverseerLog.Record(at: Date(), pane: pane, session: session, cwd: cwd,
                                                judgment: judgment, latencyMs: ms, digest: digest)
                }
                if let self, self.token[pane] == mine, let kind = judgment.verdict {
                    self.verdicts[pane] = OverseerVerdict(kind: kind, reason: judgment.reason ?? "", at: Date(),
                                                          sessionID: session, cwd: cwd)
                }
            }
            self?.inFlight.remove(pane)
            if let record { await Task.detached { log.append(record) }.value }
        }
    }

    // MARK: Queries (views)

    /// Most urgent first; ties newest first.
    static func ordered(_ verdicts: [UUID: OverseerVerdict]) -> [(pane: UUID, verdict: OverseerVerdict)] {
        verdicts.map { (pane: $0.key, verdict: $0.value) }.sorted { a, b in
            a.verdict.kind.urgency != b.verdict.kind.urgency
                ? a.verdict.kind.urgency < b.verdict.kind.urgency
                : a.verdict.at > b.verdict.at
        }
    }

    /// The verdict for a Claude session id (Other-session rows, seat cards).
    func verdict(forSession id: String?) -> OverseerVerdict? {
        guard let id, !id.isEmpty else { return nil }
        return Self.ordered(verdicts).first { $0.verdict.sessionID == id }?.verdict
    }

    /// The most urgent verdict among a tab's panes.
    func verdict(in tab: TabState) -> OverseerVerdict? {
        let panes = Set(tab.tree.leafIDs)
        return Self.ordered(verdicts).first { panes.contains($0.pane) }?.verdict
    }
}
