import Foundation

/// Records the peers engine persists (Run 29). Plain Codable JSON under `~/.true/peers/`, files 0600, dirs 0700.

extension Notification.Name {
    static let peersChanged = Notification.Name("true.peers.changed")
}

/// A paired peer. Their public keys were pinned at pairing (from the invite, or from a valid pair-request) and are
/// the only thing that decides who a message is from. `confirmed` = the pairing handshake finished.
struct PeerLink: Codable, Equatable, Sendable {
    var label: String
    var mailboxId: String
    var keys: PeerKeys
    var confirmed: Bool
    var created: Date
}

/// An invite this Mac handed out. Only the SHA-256 of the secret is kept.
struct PendingInvite: Codable, Equatable, Sendable {
    var secretHash: String
    var expires: Date
    var used: Bool
}

/// Receiver side: a job a paired peer handed to this Mac.
struct InboundJob: Codable, Equatable, Sendable, Identifiable {
    var req: PeerJobRequest
    var peerLabel: String
    var peerMailbox: String
    var status: PeerStatus
    var note: String
    var inboundMode: PeerInboundMode
    var flags: [String]
    var received: Date
    var finished: Date?
    var branch: String
    var sha: String?
    var clone: String?
    var worktree: String?
    var pane: UUID?
    var builder: String?
    /// Run 30: whether follow-ups were allowed when the job was accepted (nil = a Run 29 record).
    var steering: Bool? = nil
    /// Run 35: the desk key `<mailbox>|<project>` once the job is delivered to, or waiting in line for, a desk session.
    var desk: String? = nil
    /// Missions M1 (all optional so older inbound.json loads): the Claude session, desk lane, resume count, pause reason / time.
    var sessionId: String? = nil
    var lane: Int? = nil
    var resumes: Int? = nil
    var pausedReason: String? = nil
    var resumeAt: Date? = nil
    /// The accept check failed; the sender's resume request re-runs it.
    var acceptFailed: Bool? = nil
    var target: PeerTarget { req.target }
    var id: String { req.jobId }
}

/// Sender side: a job we handed to a peer.
struct SentJob: Codable, Equatable, Sendable, Identifiable {
    var jobId: String
    var peerLabel: String
    var peerMailbox: String
    var title: String
    var repo: String
    var base: String
    var mode: PeerMode
    var fromAgent: String
    var status: PeerStatus
    var note: String
    var branch: String?
    var sha: String?
    var result: String?
    var created: Date
    var updated: Date
    /// Run 30 (optional so older sent.json still loads).
    var target: PeerTarget? = nil
    var seq: Int? = nil
    var lastActivity: Date? = nil
    /// Missions M1: the job this one retries; why/when the receiver paused it (the receiver's clock, display only).
    var retryOf: String? = nil
    var pausedReason: String? = nil
    var resumeAt: Date? = nil
    var id: String { jobId }
}

/// Run 34: a repo a peer offered and the owner accepted (or, on the sharer's side, one the peer accepted).
/// `path` is the local clone (empty on the sharer's side when it has none we can find).
struct SharedRepo: Codable, Equatable, Sendable {
    var url: String
    var path: String
    var slug: String
}

enum PeerOfferStatus: String, Codable, Sendable { case pending, cloning, accepted, declined, failed }

/// Run 34: an offer in flight. `incoming` = a peer offered us a repo (a card in the Peers sheet); otherwise we offered it.
struct PeerOffer: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var url: String
    var name: String
    var note: String
    var peerLabel: String
    var peerMailbox: String
    var incoming: Bool
    var status: PeerOfferStatus
    /// Why it was declined / failed (plain words, shown on the card).
    var reason: String
    var created: Date
}

/// A sealed message waiting for the relay. `owner` is the peer mailbox, so a revoke can drop it.
struct OutboxItem: Codable, Equatable, Sendable {
    var id: String
    var jobId: String?
    var to: String
    var blob: Data
    var attempt: Int
    var nextAt: Date
    var owner: String?
    /// `activity` = a droppable progress batch: a busy relay backs it off without holding chat behind it.
    var lane: String?
}

/// What the engine needs from the Mac: finding the clone, making the worktree, opening the work, nudging a lead.
/// A protocol so tests run without git, panes or builders.
protocol PeerLauncher: AnyObject, Sendable {
    func resolveClone(repo: String) -> String?
    /// nil = ready; otherwise a short plain reason.
    func prepareWorktree(clone: String, base: String, branch: String, worktree: String) -> String?
    func launchPane(agentName: String, label: String, cwd: String, flags: [String], rolePath: String, firstPrompt: String) -> UUID?
    /// nil = started; otherwise a short plain reason.
    func launchBackground(agentName: String, parent: String, cwd: String, prompt: String) -> String?
    /// Whether a background builder can run here at all (the builder script is installed).
    var canRunBackground: Bool { get }
    func headSHA(worktree: String) -> String?
    func remoteURL(ofRepoAt path: String) -> String?
    func deliverLine(agent: String, line: String)
    func stop(panes: [UUID], builders: [String])
    /// Run 30: type a follow-up line into a job's pane (submitted). False = no live pane.
    func deliverToPane(_ pane: UUID, line: String) -> Bool
    /// Run 30: the pane is showing a permission dialog right now (a `say` must wait for the owner to answer).
    func atPermissionPrompt(pane: UUID) -> Bool
    /// Run 34: `git clone <url> <path>` with the owner's own credentials. nil = cloned; otherwise a short plain reason.
    func cloneRepo(url: String, into path: String) -> String?
    /// Run 35: the pane's tab is still open (a desk only feeds a pane that is alive).
    func paneAlive(_ pane: UUID) -> Bool
    /// Missions M1: remote URLs of the clones under allowed roots (hashed into the Card) and which tools are installed.
    func cloneRemotes() -> [String]
    /// Missions M1: relaunch under an existing Claude session (`--resume <id>`).
    func launchPane(agentName: String, label: String, cwd: String, flags: [String], rolePath: String, firstPrompt: String, resumeSession: String?) -> UUID?
    func launchBackground(agentName: String, parent: String, cwd: String, prompt: String, resumeSession: String?) -> String?
    /// The Claude session id of a pane (from its resume record), nil when unknown.
    func sessionId(forPane pane: UUID) -> String?
    /// Whether a finished background job can be relaunched under its session.
    var canResumeBackground: Bool { get }
    func installedTools() -> [String: Bool]
}

extension PeerLauncher {
    func launchPane(agentName: String, label: String, cwd: String, flags: [String], rolePath: String, firstPrompt: String, resumeSession: String?) -> UUID? {
        launchPane(agentName: agentName, label: label, cwd: cwd, flags: flags, rolePath: rolePath, firstPrompt: firstPrompt)
    }
    func launchBackground(agentName: String, parent: String, cwd: String, prompt: String, resumeSession: String?) -> String? { "Can't pick a background job back up here" }
    func sessionId(forPane pane: UUID) -> String? { nil }
    var canResumeBackground: Bool { false }
    func atPermissionPrompt(pane: UUID) -> Bool { false }
    func cloneRemotes() -> [String] { [] }
    func installedTools() -> [String: Bool] { [:] }
    func paneAlive(_ pane: UUID) -> Bool { true }
    func cloneRepo(url: String, into path: String) -> String? { "Cloning isn't available here" }
    func deliverToPane(_ pane: UUID, line: String) -> Bool { false }
}

enum PeerRetryReason: String, Equatable, Sendable { case offline, rate, full }

enum PeerSendResult: Equatable, Sendable {
    /// The relay took it.
    case delivered
    /// Not connected, rate-limited or queue full: try again later.
    case retry(PeerRetryReason)
    /// The relay will never take it (too large).
    case refused
}

/// The wire: one message-based pipe to the relay. `send` blocks until the relay answers (call it off the main thread).
/// Inbound messages arrive on `onMessage`; the transport confirms them to the relay once the handler returns.
protocol PeerTransport: AnyObject, Sendable {
    func send(to: String, id: String, blob: Data) -> PeerSendResult
    var onMessage: (@Sendable (_ from: String, _ id: String, _ blob: Data) -> Void)? { get set }
    /// Called with true when the relay connection is ready, false when it drops.
    var onStatus: (@Sendable (Bool) -> Void)? { get set }
    /// Connected only while there is somebody to talk to.
    func setWanted(_ on: Bool)
    var isConnected: Bool { get }
}


// MARK: Run 36a — caps

enum PeerCapsState: Equatable { case yes, no, wait }

/// What a peer's True announced about itself (sealed `caps` payload, persisted per peer in caps.json).
struct PeerCaps: Codable, Equatable {
    var version: String
    var features: [String]
    var home: String
    /// Missions M1 Card fields (all optional on the wire; a 36a-era Card has none).
    var kinds: [String] = []
    var repos: [String] = []
    var lanesTotal: Int? = nil
    var lanesFree: Int? = nil
    var tools: [String: Bool] = [:]
    /// When this Card arrived (local clock); a Card older than `staleAfter` is stale.
    var updated: Date? = nil

    init(version: String, features: [String], home: String) { self.version = version; self.features = features; self.home = home }
    /// A caps.json written before M1 has none of the Card keys.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        version = try c.decode(String.self, forKey: .version); features = try c.decode([String].self, forKey: .features); home = try c.decode(String.self, forKey: .home)
        kinds = try c.decodeIfPresent([String].self, forKey: .kinds) ?? []; repos = try c.decodeIfPresent([String].self, forKey: .repos) ?? []
        lanesTotal = try c.decodeIfPresent(Int.self, forKey: .lanesTotal); lanesFree = try c.decodeIfPresent(Int.self, forKey: .lanesFree)
        tools = try c.decodeIfPresent([String: Bool].self, forKey: .tools) ?? [:]; updated = try c.decodeIfPresent(Date.self, forKey: .updated)
    }

    static let currentVersion = "1.4"
    static let ownFeatures = ["watch", "m1"]
    static let staleAfter: TimeInterval = 600
    func isStale(at now: Date) -> Bool { updated.map { now.timeIntervalSince($0) > Self.staleAfter } ?? true }
    var supportsM1: Bool { features.contains("m1") }
    /// How long a peer that never announced caps is given before we say it needs the update.
    static let unknownGrace: TimeInterval = 60

    static func parse(_ o: [String: Any]) -> PeerCaps? {
        guard let v = o["version"] as? String, v.count <= 32 else { return nil }
        let f = ((o["features"] as? [String]) ?? []).prefix(32).filter { $0.count <= 32 }
        let h = (o["home"] as? String) ?? ""
        guard h.count <= 1024 else { return nil }
        var c = PeerCaps(version: v, features: Array(f), home: h)
        c.kinds = ((o["kinds"] as? [String]) ?? []).prefix(8).filter { $0.count <= 16 }
        c.repos = ((o["repos"] as? [String]) ?? []).prefix(500).filter { $0.count == 64 }
        if let l = o["lanes"] as? [String: Any] { c.lanesTotal = l["total"] as? Int; c.lanesFree = l["free"] as? Int }
        if let t = o["tools"] as? [String: Any] { for (k, v) in t where k.count <= 16 { if let b = v as? Bool { c.tools[k] = b } } }
        return c
    }
}
