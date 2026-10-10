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
    static let names: Set<String> = ["activate_app", "hide_app", "quit_graceful", "volume_delta", "mute", "scroll"]

    static func run(_ name: String, _ i: [String: Any]) async -> (String, Bool) {
        let n = i["name"] as? String ?? ""
        switch name {
        case "activate_app":
            return await MainActor.run {
                if let app = running(n) { app.unhide(); app.activate(); return ("activated \(n)", false) }
                return ("not running", false)
            }
        case "hide_app":
            return await MainActor.run { running(n)?.hide(); return ("hid \(n)", false) }
        case "quit_graceful":
            return await MainActor.run {
                guard let app = running(n) else { return ("\(n) isn't running", true) }
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
        default: return ("no such tool", true)
        }
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

    private func execute(_ step: NovaInstantSession.Step) async {
        switch step.kind {
        case .undo(let id):
            if let u = undos.removeValue(forKey: id) { await u(); onUndo?() }
        case .act(let verb):
            let undo = await captureUndo(verb)
            let started = Date()
            let ms = Int(started.timeIntervalSince(step.completedAt) * 1000)
            let w = wordEnd()
            let wordMs = w.end.map { Int(started.timeIntervalSince(w.streamStart.addingTimeInterval($0)) * 1000) }
            timings.append(.init(clauseToActMs: ms, wordToActMs: wordMs, verb: String(describing: verb).prefix(12).description))
            let (tool, input) = Self.tool(for: verb)
            let r = await hands.run(name: tool, input: input, id: "instant")
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
        }
    }

    /// Snapshot what the act will change so "no" can put it back.
    private func captureUndo(_ v: InstantVerb) async -> (() async -> Void)? {
        let front = NSWorkspace.shared.frontmostApplication
        let restoreFront: () async -> Void = { @MainActor in front?.activate() }
        switch v {
        case .openApp(let n):
            let wasRunning = NovaInstantTools.running(n) != nil
            return { await restoreFront(); if !wasRunning { await MainActor.run { _ = NovaInstantTools.running(n)?.terminate() } } }
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
            return { _ = await h.run(name: "media_control", input: ["action": "play_pause"], id: "undo") }
        case .openSite: return restoreFront
        case .scroll, .screenshot: return nil
        }
    }
}
