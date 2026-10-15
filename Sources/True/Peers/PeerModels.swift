import Foundation

/// Records the peers engine persists (Run 29). Plain Codable JSON under `~/.true/peers/`, files 0600, dirs 0700.

extension Notification.Name {
    static let peersChanged = Notification.Name("true.peers.changed")
}

/// Sender side: a friend's True we can send to. The token is the one their True handed us at pairing.
struct PeerLink: Codable, Equatable, Sendable {
    var label: String
    var url: String
    var token: String
    var receiverLogin: String
}

/// Receiver side: a job a paired peer handed to this Mac.
struct InboundJob: Codable, Equatable, Sendable, Identifiable {
    var req: PeerJobRequest
    var peerLabel: String
    var deviceId: UUID
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
    var id: String { req.jobId }
}

/// Sender side: a job we handed to a peer. Only the SHA-256 of the reply token is kept.
struct SentJob: Codable, Equatable, Sendable, Identifiable {
    var jobId: String
    var peerLabel: String
    var peerLogin: String
    var title: String
    var repo: String
    var base: String
    var mode: PeerMode
    var fromAgent: String
    var tokenHash: String
    var status: PeerStatus
    var note: String
    var branch: String?
    var sha: String?
    var result: String?
    var created: Date
    var updated: Date
    var id: String { jobId }
}

/// A POST waiting for the network. `owner` is the peer device id (receiver side), so a revoke can drop it.
struct OutboxItem: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case job, event }
    var id: String
    var kind: Kind
    var jobId: String
    var peerLabel: String
    var owner: String?
    var baseURL: String
    var path: String
    var bearer: String
    var body: Data
    var attempt: Int
    var nextAt: Date
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
    func headSHA(worktree: String) -> String?
    func remoteURL(ofRepoAt path: String) -> String?
    func deliverLine(agent: String, line: String)
    func stop(panes: [UUID], builders: [String])
}

/// One POST to a peer's True. `status` 0 = the network failed.
protocol PeerTransport: Sendable {
    func post(baseURL: String, path: String, bearer: String?, body: Data) -> (status: Int, body: Data)
}
