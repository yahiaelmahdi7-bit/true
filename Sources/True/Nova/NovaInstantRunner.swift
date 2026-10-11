import AppKit
import Foundation
import CoreGraphics

/// One shared URLSession (HTTP/2 keep-alive) for Anthropic, plus a prewarm so the first addressed word doesn't pay TLS.
enum NovaNet {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.waitsForConnectivity = false; c.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: c)
    }()
    /// Keyless HEAD requests just to open the TLS connections. No key is attached, nothing is logged.
    static func prewarm(hosts: [String] = ["https://api.anthropic.com", "https://api.typesafe.ai"]) {
        for h in hosts {
            guard let u = URL(string: h) else { continue }
            var r = URLRequest(url: u); r.httpMethod = "HEAD"; r.timeoutInterval = 4
            Task.detached { _ = try? await session.data(for: r) }
        }
    }
}

/// Instant-lane tools that are NOT in `NovaToolSchemas` (the brain never sees them). They still go through
/// `NovaHands.run` → `NovaGate.tool` (default allow); quitting is graceful `terminate()` only, never force.
enum NovaInstantTools {
    static let names: Set<String> = ["activate_app", "hide_app", "quit_graceful", "volume_delta", "mute", "scroll", "switch_tab"]

    static func run(_ name: String, _ i: [String: Any]) async -> (String, Bool) {
        let n = i["name"] as? String ?? ""
        switch name {
        case "activate_app":
            return await MainActor.run {
                if let app = running(n) { app.unhide(); app.activate(); return ("activated \(n)", false) }
                return ("not running", false)
            }
        case "hide_app":
            return await MainActor.run {
                if let a = running(n), NovaGate.isOwnApp(a) { return ("I can't hide True itself", true) }
                running(n)?.hide(); return ("hid \(n)", false)
            }
        case "quit_graceful":
            return await MainActor.run {
                guard let app = running(n) else { return ("\(n) isn't running", true) }
                if NovaGate.isOwnApp(app) { return ("I can't quit True itself", true) }
                _ = app.terminate(); return ("asked \(n) to quit", false)
            }
        case "volume_delta":
            let cur = await volume(), d = i["delta"] as? Int ?? 10
            await setVolume(max(0, min(100, cur + d))); return ("volume \(max(0, min(100, cur + d)))", false)
        case "mute":
            await osa("set volume output muted \((i["on"] as? Bool ?? true) ? "true" : "false")"); return ("muted", false)
        case "scroll":
            let up = i["up"] as? Bool ?? false
            for _ in 0..<3 {
                CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: Int32(up ? 8 : -8), wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
            }
            return ("scrolled", false)
        case "switch_tab": return await switchTab(query: i["query"] as? String ?? "", browser: (i["browser"] as? String).flatMap { $0.isEmpty ? nil : $0 })
        default: return ("no such tool", true)
        }
    }

    /// List tabs with a fixed script, match in Swift, focus by number: none of his words reach AppleScript. Runs off-main via `exec`.
    static func switchTab(query: String, browser: String?) async -> (String, Bool) {
        let (front, running) = await MainActor.run { (NSWorkspace.shared.frontmostApplication?.localizedName, NSWorkspace.shared.runningApplications.compactMap(\.localizedName)) }
        guard let b = NovaTabs.resolveBrowser(named: browser, frontmost: front, running: running) else {
            return (browser.map { "\($0) isn't running" } ?? "no browser is running", true)
        }
        guard let list = NovaTabs.listScript(b) else { return ("can't read tabs in \(b)", true) }
        let r = await NovaHands.exec("/usr/bin/osascript", ["-e", list], cwd: nil, timeout: 5, cap: 200_000)
        guard r.status == 0 else { return ("couldn't read \(b) tabs (allow automation for True?)", true) }
        guard let tab = NovaTabs.pick(query, in: NovaTabs.parseList(r.out)), let focus = NovaTabs.focusScript(b, window: tab.window, tab: tab.tab) else {
            guard let site = NovaInstant.sites[query] else { return ("no \(query) tab open in \(b)", true) }
            let o = await NovaHands.exec("/usr/bin/open", ["-a", b, site.url], cwd: nil, timeout: 5, cap: 512)
            return o.status == 0 ? ("opened \(site.name) in \(b)", false) : ("couldn't open \(site.name) in \(b)", true)
        }
        let f = await NovaHands.exec("/usr/bin/osascript", ["-e", focus], cwd: nil, timeout: 5, cap: 512)
        return f.status == 0 ? ("switched to \(tab.title)", false) : ("couldn't switch \(b) to that tab", true)
    }

    /// The single new process of that name that appeared since `before`; nil if none or ambiguous.
    static func newPID(named: String, before: Set<Int32>, now: [(Int32, String)]) -> Int32? {
        let hits = now.filter { !before.contains($0.0) && $0.1.lowercased() == named.lowercased() }
        return hits.count == 1 ? hits[0].0 : nil
    }
    @MainActor static func running(_ name: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.localizedName?.lowercased() == name.lowercased() }
    }
    static func volume() async -> Int {
        let r = await NovaHands.exec("/usr/bin/osascript", ["-e", "output volume of (get volume settings)"], cwd: nil, timeout: 5, cap: 64)
        return Int(r.out) ?? 50
    }
    static func setVolume(_ n: Int) async { await osa("set volume output volume \(n)") }
    static func osa(_ s: String) async { _ = await NovaHands.exec("/usr/bin/osascript", ["-e", s], cwd: nil, timeout: 5, cap: 64) }
}

/// The pid Nova's own open created (set after the act; read by undo).
final class LaunchedPID: @unchecked Sendable { var pid: Int32? }
/// Undo's terminate, injectable so a test can prove which pid it touches.
nonisolated(unsafe) var novaTerminatePID: (Int32) -> Void = { _ = NSRunningApplication(processIdentifier: $0)?.terminate() }
private func terminate(_ pid: Int32) { novaTerminatePID(pid) }

/// Serial executor for the instant lane's Steps. Captures undo state BEFORE each hand moves, times dispatch.
@MainActor
final class NovaInstantRunner {
    struct Timing { var clauseToActMs: Int; var wordToActMs: Int?; var verb: String }
    private let hands: NovaHands
    private var undos: [Int: () async -> Void] = [:]
    private var chain: Task<Void, Never>?
    private(set) var timings: [Timing] = []
    /// Result per act: (spoken line, isInfo, isError)
    var onResult: ((InstantVerb, String, Bool) -> Void)?
    var onUndo: (() -> Void)?
    /// Seconds-since-stream-start of the last word's end, and when the stream started (for word_to_act_ms).
    var wordEnd: () -> (end: TimeInterval?, streamStart: Date) = { (nil, Date()) }

    init(hands: NovaHands) { self.hands = hands }

    /// Clause N+1 only dispatches after clause N's hand has started: steps are chained.
    func enqueue(_ steps: [NovaInstantSession.Step]) {
        for step in steps {
            let prev = chain
            chain = Task { [weak self] in
                await prev?.value
                await self?.execute(step)
            }
        }
    }
    func cancelAll() { chain?.cancel() }
    /// A tell matched after local acts already ran: undo them the way "no" does.
    func undoAll() {
        let prev = chain
        chain = Task { [weak self] in
            await prev?.value
            guard let self else { return }
            let all = self.undos; self.undos = [:]
            for (_, u) in all { await u(); self.onUndo?() }
        }
    }

    private func execute(_ step: NovaInstantSession.Step) async {
        switch step.kind {
        case .undo(let id):
            if let u = undos.removeValue(forKey: id) { await u(); onUndo?() }
        case .act(let verb):
            let launched = LaunchedPID()
            let beforePIDs = await MainActor.run { Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier)) }
            let undo = await captureUndo(verb, launched: launched)
            let started = Date()
            let ms = Int(started.timeIntervalSince(step.completedAt) * 1000)
            let w = wordEnd()
            let wordMs = w.end.map { Int(started.timeIntervalSince(w.streamStart.addingTimeInterval($0)) * 1000) }
            timings.append(.init(clauseToActMs: ms, wordToActMs: wordMs, verb: String(describing: verb).prefix(12).description))
            let (tool, input) = Self.tool(for: verb)
            let r = await hands.runLocal(name: tool, input: input)
            if case .openApp(let n) = verb {
                launched.pid = await MainActor.run { NovaInstantTools.newPID(named: n, before: beforePIDs, now: NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0.localizedName ?? "") }) }
            }
            if let undo, !r.isError { undos[step.id] = undo }
            onResult?(verb, r.text, r.isError)
        }
    }

    nonisolated static func tool(for v: InstantVerb) -> (String, [String: Any]) {
        switch v {
        case .openApp(let n): return ("activate_app_or_open", ["name": n])
        case .hideApp(let n): return ("hide_app", ["name": n])
        case .quitApp(let n): return ("quit_graceful", ["name": n])
        case .focusPane(let n): return ("focus_pane", ["target": n])
        case .volumeUp: return ("volume_delta", ["delta": 10])
        case .volumeDown: return ("volume_delta", ["delta": -10])
        case .mute(let on): return ("mute", ["on": on])
        case .setVolume(let n): return ("set_volume", ["level": n])
        case .media(let m): return ("media_control", ["action": m])
        case .scroll(let up): return ("scroll", ["up": up])
        case .screenshot: return ("screenshot", [:])
        case .openSite(_, let url): return ("open_url", ["url": url])
        case .switchTab(let q, let b): return ("switch_tab", ["query": q, "browser": b ?? ""])
        }
    }

    /// Snapshot what the act will change so "no" can put it back.
    private func captureUndo(_ v: InstantVerb, launched: LaunchedPID) async -> (() async -> Void)? {
        let front = NSWorkspace.shared.frontmostApplication
        let restoreFront: () async -> Void = { @MainActor in front?.activate() }
        switch v {
        case .openApp(let n):
            let wasRunning = NovaInstantTools.running(n) != nil
            // L6: undo terminates only the pid Nova's own open produced (recorded after the act), never "an app by that name".
            return { await restoreFront(); if !wasRunning { await MainActor.run { if let pid = launched.pid { terminate(pid) } } } }
        case .hideApp(let n): return { () async -> Void in await MainActor.run { _ = NovaInstantTools.running(n)?.unhide() } }
        case .quitApp(let n):
            let url = NovaInstantTools.running(n)?.bundleURL
            return { if let url { await MainActor.run { NSWorkspace.shared.open(url) } } }
        case .focusPane: return restoreFront
        case .volumeUp, .volumeDown, .setVolume, .mute:
            let prior = await NovaInstantTools.volume()
            return { await NovaInstantTools.setVolume(prior) }
        case .media(let m): guard m == "play_pause" else { return nil }
            let h = hands
            return { _ = await h.runLocal(name: "media_control", input: ["action": "play_pause"]) }
        case .openSite: return restoreFront
        case .scroll, .screenshot, .switchTab: return nil
        }
    }
}
