import AppKit
import Foundation
import Observation
import os

/// Identity of the executable file: which inode and when it last changed. `scripts/package.sh` replaces
/// the whole .app, so a rebuild changes at least one of the two (or removes the file).
struct BinaryStamp: Equatable, Sendable {
    var inode: UInt64
    var modified: Date

    static func read(_ url: URL) -> BinaryStamp? {
        var st = stat()
        guard stat(url.path, &st) == 0 else { return nil }
        let t = st.st_mtimespec
        return BinaryStamp(inode: UInt64(st.st_ino),
                           modified: Date(timeIntervalSince1970: TimeInterval(t.tv_sec) + TimeInterval(t.tv_nsec) / 1e9))
    }
}

/// Pure decisions for "restart to update".
enum BuildFreshness {
    /// Stale = the file on disk is no longer the one this process started from. `nil` = file is gone.
    static func isStale(launched: BinaryStamp, current: BinaryStamp?) -> Bool { current != launched }

    /// Detached `/bin/sh` that waits for `pid` to exit, then reopens the bundle. pid and path travel as
    /// positional args ($1, $2), never interpolated into the script. No `open -n`: two Trues at once
    /// would race on workspace.json.
    static func relauncherArguments(pid: Int32, bundlePath: String) -> [String] {
        ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$2\"", "sh", String(pid), bundlePath]
    }

    /// Wording of the pre-restart question; nil when nothing is working (restart directly).
    static func workingWarning(_ working: Int) -> String? {
        guard working > 0 else { return nil }
        let who = working == 1 ? "1 agent is" : "\(working) agents are"
        return "\(who) working. Restarting interrupts their current step; sessions resume after."
    }

    /// posix_spawn with POSIX_SPAWN_SETSID: the child gets its own session and process group, so it is
    /// not reaped with True's group and keeps running after True exits. Returns false if the spawn failed.
    static func spawnDetached(_ executable: String, _ args: [String]) -> Bool {
        var attr: posix_spawnattr_t?
        guard posix_spawnattr_init(&attr) == 0 else { return false }
        defer { posix_spawnattr_destroy(&attr) }
        guard posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID)) == 0 else { return false }
        let argv: [UnsafeMutablePointer<CChar>?] = ([executable] + args).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        return posix_spawn(&pid, executable, nil, &attr, argv, environ) == 0
    }
}

/// Watches the running executable; once it changes on disk, `stale` flips true (one-way) and the tab bar
/// offers "Restart to update". Event-driven: one vnode source, cancelled on first detection, plus a single
/// stat when the app becomes active as a backstop. No timers.
@MainActor @Observable
final class BuildFreshnessWatcher {
    static let shared = BuildFreshnessWatcher()

    private(set) var stale = false
    /// Drives the confirmation dialog attached to the pill.
    var confirming = false

    @ObservationIgnored private let log = Logger(subsystem: "True", category: "update")
    @ObservationIgnored private var launched: BinaryStamp?
    @ObservationIgnored private var exeURL: URL?
    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var activeObserver: NSObjectProtocol?

    /// Restart is only offered from a real .app bundle; a bare `swift run` binary just logs.
    var canRestart: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    /// Pill and menu item show/enable on this.
    var offersRestart: Bool { stale && canRestart }

    func start() {
        guard launched == nil, let url = Bundle.main.executableURL, let stamp = BinaryStamp.read(url) else { return }
        launched = stamp; exeURL = url
        let fd = open(url.path, O_EVTONLY)
        if fd >= 0 {
            let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.delete, .rename, .write], queue: .main)
            s.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.markStale() } }
            s.setCancelHandler { close(fd) }
            s.resume()
            source = s
        }
        // Backstop for a swap the vnode watch missed: one stat on activation.
        activeObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recheck() }
        }
    }

    func recheck() {
        guard !stale, let launched, let exeURL else { return }
        if BuildFreshness.isStale(launched: launched, current: BinaryStamp.read(exeURL)) { markStale() }
    }

    private func markStale() {
        guard !stale else { return }
        stale = true
        source?.cancel(); source = nil
        if let o = activeObserver { NotificationCenter.default.removeObserver(o); activeObserver = nil }
        log.notice("binary on disk changed since launch; restart to update")
    }

    /// Working-agent count from the same verdict that holds the Mac awake.
    private func workingCount() -> Int { WorkAwake.liveVerdict(Date()).reasons.count }

    /// Dialog text, nil when nothing is mid-work.
    var warning: String? { BuildFreshness.workingWarning(workingCount()) }

    /// The pill / menu entry point: ask first if agents are mid-work, else go.
    func requestRestart() {
        guard offersRestart else { return }
        if warning != nil { confirming = true } else { restart() }
    }

    /// Spawn the relauncher, THEN terminate normally so applicationShouldTerminate records the sessions.
    func restart() {
        let args = BuildFreshness.relauncherArguments(pid: getpid(), bundlePath: Bundle.main.bundleURL.path)
        guard BuildFreshness.spawnDetached("/bin/sh", args) else {
            log.error("restart: could not spawn relauncher; staying open")
            return
        }
        NSApp.terminate(nil)
    }
}
