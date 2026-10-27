import Foundation
import Darwin

/// Owner-side Git transport. All refs are explicit; the owner's checkout and local branches are untouched.
final class MissionGitMergeGate: MissionMergeGate {
    let folder: URL
    private let resolve: (String) -> String?
    private let mutex = NSRecursiveLock()
    private struct Consent: Codable {
        var approved: Set<String> = []
        var pending: [String: String] = [:]
    }
    init(folder: URL, resolveClone: @escaping (String) -> String?) {
        self.folder = folder; resolve = resolveClone
    }
    private var consentURL: URL { folder.appendingPathComponent("merge-consent.json") }
    private func consent() throws -> Consent {
        if !FileManager.default.fileExists(atPath: consentURL.path) { return Consent() }
        return try JSONDecoder().decode(Consent.self, from: Data(contentsOf: consentURL))
    }
    func approve(job: String) throws {
        mutex.lock(); defer { mutex.unlock() }
        var value = try consent()
        guard let peer = value.pending[job] else { throw PeerError.invalid("No merge waiting for approval") }
        value.approved.insert(peer); value.pending.removeValue(forKey: job)
        try JSONEncoder().encode(value).write(to: consentURL, options: .atomic)
    }
    private func ownerFile() throws -> MissionFile {
        let text = try String(contentsOf: folder.appendingPathComponent("mission.md"), encoding: .utf8)
        // Destinations were validated by the runner; recover their labels without trusting job-supplied metadata.
        let labels = text.components(separatedBy: "\n").compactMap { line -> String? in
            let line = line.trimmingCharacters(in: .whitespaces)
            return line.hasPrefix("where:") ? String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces) : nil
        }
        return try MissionFile.parse(text, peers: labels)
    }
    private func git(_ args: [String], _ repo: String) -> (Int32, String) {
        PeerLauncherLive.git(["-c", "core.hooksPath=/dev/null"] + args, in: repo)
    }
    private func withRepo<T>(_ repo: String, _ body: (String) throws -> T) throws -> T {
        guard let clone = resolve(repo) else { throw PeerError.invalid("can't merge: no shared remote") }
        let common = git(["rev-parse", "--path-format=absolute", "--git-common-dir"], clone)
        guard common.0 == 0 else { throw PeerError.invalid("can't merge: no shared remote") }
        let fd = open(common.1 + "/true-mission.lock", O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw PeerError.invalid("Couldn't lock the repo") }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw PeerError.invalid("Couldn't lock the repo") }
        return try body(clone)
    }
    private func validBase(_ base: String, repo: String) -> Bool {
        base != "main" && base != "master" && git(["check-ref-format", "refs/heads/" + base], repo).0 == 0
    }
    /// Publish the initial mission base before any launcher needs origin/<mission branch>.
    func prepare(_ mission: MissionFile, id: String) throws {
        for repo in Set(mission.jobs.map(\.repo)) {
            try withRepo(repo) { clone in
                let base = mission.into ?? "mission/\(id)"
                guard validBase(base, repo: clone) else { throw PeerError.invalid("Choose a mission branch away from main") }
                guard git(["fetch", "origin"], clone).0 == 0 else { throw PeerError.invalid("can't merge: no shared remote") }
                if git(["ls-remote", "--exit-code", "--heads", "origin", "refs/heads/" + base], clone).0 == 0 { return }
                let head = git(["ls-remote", "--symref", "origin", "HEAD"], clone)
                let source = head.1.split(separator: "\n").first(where: { $0.hasPrefix("ref: refs/heads/") })?
                    .split(whereSeparator: { $0 == " " || $0 == "\t" }).dropFirst().first.map(String.init)
                guard let source else { throw PeerError.invalid("can't merge: no shared remote") }
                let startingRef = "refs/remotes/origin/" + source.dropFirst("refs/heads/".count)
                guard git(["push", "origin", startingRef + ":refs/heads/" + base], clone).0 == 0,
                      git(["fetch", "origin"], clone).0 == 0 else { throw PeerError.invalid("can't merge: no shared remote") }
            }
        }
    }
    func merge(_ launch: MissionLaunch, at destination: MissionDestination, check: String?) throws -> MissionMergeAnswer {
        mutex.lock(); defer { mutex.unlock() }
        let mission = try ownerFile()
        guard let check = mission.check, !check.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .inputRequired("Yahia, add check: to the mission")
        }
        let base = mission.into ?? "mission/\(folder.lastPathComponent)"
        do {
            return try withRepo(launch.job.repo) { clone in
                guard validBase(base, repo: clone), launch.base == base,
                      launch.branch.hasPrefix("peer/\(folder.lastPathComponent)/"),
                      git(["check-ref-format", "refs/heads/" + launch.branch], clone).0 == 0 else {
                    return .inputRequired("Choose a mission branch away from main")
                }
                // Fetch exact heads, avoiding stale remote-tracking refs and ambiguous branch/tag names.
                let jobRef = "refs/true-missions/\(folder.lastPathComponent)/job"
                let baseRef = "refs/true-missions/\(folder.lastPathComponent)/base"
                guard git(["fetch", "--no-tags", "origin", "+refs/heads/\(launch.branch):\(jobRef)", "+refs/heads/\(base):\(baseRef)"], clone).0 == 0 else {
                    return .inputRequired("can't merge: no shared remote")
                }
                let sha = git(["rev-parse", jobRef], clone).1
                if git(["merge-base", "--is-ancestor", sha, baseRef], clone).0 == 0 { return .merged }
                if case .peer(let peer) = destination {
                    var value = try consent()
                    if !value.approved.contains(peer) {
                        value.pending[launch.job.title] = peer
                        try JSONEncoder().encode(value).write(to: consentURL, options: .atomic)
                        let stat = git(["diff", "--numstat", baseRef + "..." + sha], clone)
                        guard stat.0 == 0 else { return .inputRequired("Couldn't read the diff") }
                        let rows = stat.1.split(separator: "\n").map { $0.split(separator: "\t") }
                        let added = rows.reduce(0) { $0 + (Int($1.first ?? "") ?? 0) }
                        let removed = rows.reduce(0) { $0 + ($1.count > 1 ? Int($1[1]) ?? 0 : 0) }
                        return .inputRequired("First merge from \(peer): \(rows.count) files, +\(added) -\(removed). Merge?")
                    }
                }
                let worktree = FileManager.default.temporaryDirectory.appendingPathComponent("true-mission-" + UUID().uuidString)
                guard git(["worktree", "add", "--detach", worktree.path, baseRef], clone).0 == 0 else { return .inputRequired("Couldn't make a merge worktree") }
                defer { _ = git(["worktree", "remove", "--force", worktree.path], clone) }
                let merged = git(["-c", "user.name=True", "-c", "user.email=true@localhost", "merge", "--no-edit", "--no-ff", sha], worktree.path)
                guard merged.0 == 0 else {
                    let short = git(["rev-parse", "--short", baseRef], clone).1
                    return .inputRequired("rebase on \(short)")
                }
                let home = FileManager.default.temporaryDirectory.appendingPathComponent("true-check-home-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                defer { try? FileManager.default.removeItem(at: home) }
                let env = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin", "HOME": home.path,
                           "LANG": "en_US.UTF-8", "TMPDIR": FileManager.default.temporaryDirectory.path]
                let result = Subprocess.exec("/bin/sh", ["-c", "cd \"$1\" && " + check, "mission-check", worktree.path],
                                             timeout: nil, mergeStderr: true, env: env)
                guard let result, result.status == 0 else {
                    let output = result.map { String(decoding: $0.out, as: UTF8.self) } ?? "Couldn't run the check"
                    let tail = output.split(separator: "\n").suffix(8).joined(separator: "\n")
                    return .inputRequired(PeerMask.text(tail.isEmpty ? "Check failed" : tail))
                }
                guard git(["push", "origin", "HEAD:refs/heads/" + base], worktree.path).0 == 0 else {
                    return .inputRequired("can't merge: no shared remote")
                }
                return .merged
            }
        } catch PeerError.invalid(let reason) { return .inputRequired(reason) }
    }
}
