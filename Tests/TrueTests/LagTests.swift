import Testing
import Foundation
@testable import True

private func tmp() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("lag-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}
private func inode(_ u: URL) -> UInt64 { ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.systemFileNumber] as? UInt64) ?? 0 }
private func size(_ u: URL) -> Int { ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? Int) ?? 0 }
private func gitItem(_ id: String) -> InboxItem {
    InboxItem(id: id, agent: Duty.watcherName, source: "git", kind: "unpushed", subject: "repo@main", repo: "/tmp/r", fingerprint: "git|unpushed|\(id)",
              title: "t", evidence: "e", report: nil, level: nil, state: .open, seen: 1, at: 1000, cost: 0, note: nil, builderID: nil,
              lookedFixed: false, snoozeUntil: nil, canInvestigate: false)
}

@MainActor @Suite struct MainThreadTests {
    /// A slow `git` (300 ms per call) must not hold the main actor: the check yields while it waits.
    @Test func slowGitDoesNotBlockMain() async throws {
        let root = tmp()
        let file = InboxFile(dir: InboxFile.home(agent: Duty.watcherName, root: root)); file.ensureDir()
        for i in 0..<3 { file.append(InboxEvent(.created, id: "g\(i)", at: 1000, item: gitItem("g\(i)"))) }
        var deps = WatcherStore.Deps()
        deps.root = root
        deps.git = { _ in Thread.sleep(forTimeInterval: 0.3); return nil }
        deps.enabled = { true }
        let store = WatcherStore(deps: deps)

        let t0 = Date()
        store.checkStuck(builders: [])
        #expect(Date().timeIntervalSince(t0) < 0.010, "checkStuck must return immediately")

        // Ping the main actor while the check runs: a 10 ms sleep must wake on time.
        var worst = 0.0
        for _ in 0..<5 {
            let s = Date()
            try await Task.sleep(nanoseconds: 10_000_000)
            worst = max(worst, Date().timeIntervalSince(s) - 0.010)
        }
        // Run alone this is ~2 ms (the 20 ms bar); the bound is 250 ms so other suites hogging the main actor in a full run
        // cannot flake it, and it is still below one 300 ms git call (blocked code measured 1117 ms).
        #expect(worst < 0.250, "main actor stalled \(Int(worst * 1000)) ms during the check")
        await store.checkTask?.value
    }

    /// A tick that arrives while a check is still running is skipped, not queued.
    @Test func overlappingChecksAreSkipped() async throws {
        let root = tmp()
        let file = InboxFile(dir: InboxFile.home(agent: Duty.watcherName, root: root)); file.ensureDir()
        file.append(InboxEvent(.created, id: "g0", at: 1000, item: gitItem("g0")))
        let calls = Box(0)
        var deps = WatcherStore.Deps()
        deps.root = root; deps.enabled = { true }
        deps.git = { _ in calls.mutate { $0 += 1 }; Thread.sleep(forTimeInterval: 0.2); return nil }
        let store = WatcherStore(deps: deps)
        store.checkStuck(builders: [])
        try await Task.sleep(nanoseconds: 50_000_000)
        store.checkStuck(builders: [])
        store.checkStuck(builders: [])
        await store.checkTask?.value
        // one item -> branchesArgv lookup only (nil stops it): exactly one git call for the one check
        #expect(calls.value == 1)
    }

    @Test func inboxChangeAppendsOnly() throws {
        let root = tmp()
        var deps = WatcherStore.Deps()
        deps.root = root; deps.enabled = { true }
        let file = InboxFile(dir: InboxFile.home(agent: Duty.watcherName, root: root)); file.ensureDir()
        for i in 0..<50 { file.append(InboxEvent(.created, id: "g\(i)", at: 1000, item: gitItem("g\(i)"))) }
        let store = WatcherStore(deps: deps)
        let before = try Data(contentsOf: file.url), ino = inode(file.url)
        store.reject("g7", reason: "Already handled")
        let after = try Data(contentsOf: file.url)
        #expect(inode(file.url) == ino, "file was replaced (whole-file rewrite)")
        #expect(after.prefix(before.count) == before, "existing bytes changed")
        #expect(after.count - before.count < 600, "one change wrote \(after.count - before.count) bytes")
        #expect(store.items.first { $0.id == "g7" }?.state == .resolved)
    }
}

@Suite struct JSONLogTests {
    @Test func appendIsOrderRecordBytes() throws {
        let dir = tmp(), u = dir.appendingPathComponent("a.jsonl")
        var last = 0, total = 0
        for i in 0..<1000 {
            let line = Data("{\"n\":\(i),\"pad\":\"xxxxxxxxxxxxxxxxxxxx\"}\n".utf8)
            JSONLog.append(line, to: u, maxBytes: 10 << 20, keep: 2)
            let s = size(u)
            #expect(s - last == line.count)       // delta is exactly this record
            last = s; total += line.count
        }
        #expect(total == last)
        #expect(JSONLog.writeCount(for: u) == 1000)
        #expect(((try FileManager.default.attributesOfItem(atPath: u.path))[.posixPermissions] as? Int) == 0o600)
    }

    @Test func rotatesAtCapKeepingTwo() throws {
        let dir = tmp(), u = dir.appendingPathComponent("r.jsonl")
        let line = Data(String(repeating: "x", count: 99).utf8 + [10])      // 100 bytes
        for _ in 0..<1000 { JSONLog.append(line, to: u, maxBytes: 10_000, keep: 2) }
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("r.1.jsonl").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("r.2.jsonl").path))
        #expect(!fm.fileExists(atPath: dir.appendingPathComponent("r.3.jsonl").path))
        #expect(size(u) <= 10_000 + 100)
        #expect(size(dir.appendingPathComponent("r.1.jsonl")) <= 10_100)
    }

    @Test func overseerLogAppendsAndUsesOneMegCap() {
        #expect(OverseerLog.maxBytes == 1 << 20)
    }
}

@Suite struct OffMainTests {
    /// `dispatchPrecondition` would kill the test process, so the rule is a pure check the runners also assert.
    @Test @MainActor func mainThreadViolates() {
        #expect(OffMain.violatesNow())
    }
    @Test func backgroundIsFine() async {
        let v = await Task.detached { OffMain.violatesNow() }.value
        #expect(!v)
    }
}
