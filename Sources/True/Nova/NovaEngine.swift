import Foundation
import AppKit
import CryptoKit
import OSLog

/// Wires EARS → REFLEX ∥ BRAIN → HANDS (behind the GATE) → HUD + VOICE. One name per thing; see docs/kb/glossary.md.
@MainActor
final class NovaEngine: ObservableObject {
    static let shared = NovaEngine()
    nonisolated static let setupLine = "security add-generic-password -s net.prismlens.true -a anthropic -U -w"
    private static let log = Logger(subsystem: "net.prismlens.true", category: "nova")

    enum State: String { case idle, listening, thinking, acting, waiting = "waiting for go-ahead", done }
    struct Line: Identifiable { let id = UUID(); var text: String; var ok: Bool? }

    @Published var state: State = .idle
    @Published var transcript = ""
    @Published var lines: [Line] = []
    @Published var pending: String?
    @Published var notice: String?
    @Published var muted = false { didSet { muted ? wake.stop() : startWake() } }
    @Published private(set) var running = false

    private let wake = WakeListener()
    private let keys = HotkeyMonitor()
    // Live stream (Run 26b): turn state. No recorder on the command path — the stream's own final is the transcript.
    private var live = NovaLiveTurn()
    private var turnActive = false
    private var turnStart = Date()
    private var lastCommand = ""
    private var lastChange = Date()
    private var lastTokenCount = 0
    private var hotkeyHeld = false
    private var session: NovaInstantSession?
    private var eager = NovaEagerTurn()
    private var eagerTask: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var endpointing = DynamicEndpointing(seed: 1.0)
    private var speaking = false
    private var lastTurnEnd = Date.distantPast
    private var directDone = Set<String>()
    private lazy var runner: NovaInstantRunner = {
        let r = NovaInstantRunner(hands: hands)
        r.wordEnd = { [weak self] in (self?.lastWordEnd, self?.wake.streamStartedAt ?? Date()) }
        r.onResult = { [weak self] verb, text, bad in self?.instantDone(verb, text, bad) }
        r.onUndo = { [weak self] in self?.lines.append(.init(text: "undone", ok: true)); NSSound(named: "Pop")?.play() }
        return r
    }()
    private var lastWordEnd: TimeInterval?
    private var brainTask: Task<Void, Never>?
    private var approval: CheckedContinuation<Bool, Never>?
    private var announcedNoKey = false
    private var recent: [String] = []
    private lazy var speech = NovaSpeechQueue(onSpeakingChanged: { [weak self] s in self?.speaking = s })
    private lazy var hands = NovaHands(approve: { [weak self] what in await self?.approve(what) ?? false },
                                       cancelled: { Task.isCancelled })
    private var run: [String: Any] = [:]
    private var speechBuf = ""

    func start() {
        guard NovaSettings.enabled, !running else { return }
        running = true
        wake.streamTakes = true
        wake.onWake = { }   // the engine reads the name itself from onPartial (it needs the word index)
        wake.onPartial = { [weak self] t, final, end in Task { @MainActor in self?.partial(t, final: final, wordEnd: end) } }
        wake.onUtterance = { [weak self] t in Task { @MainActor in self?.ambient(t) } }
        keys.setHotkey(NovaSettings.hotkey)
        keys.onEdge = { [weak self] down in Task { @MainActor in self?.hotkey(down) } }
        keys.start()
        startWake()
    }
    func stop() { wake.stop(); keys.stop(); running = false; state = .idle }
    private func startWake() {
        if NovaSettings.wakeWord, !muted, WakeListener.authorized { wake.extraContext = Self.contextNames(); wake.start() }
    }

    /// Recognizer bias: running apps first (recent), then installed, then the True roster. Capped at ~60.
    static func contextNames() -> [String] {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.localizedName)
        let installed = AppIndex.scan(running: []).names
        let roster = AgentRegistry.shared.crew.map(\.name)
        var seen = Set<String>(), out: [String] = []
        for n in running + roster + installed where seen.insert(n).inserted { out.append(n) }
        return Array(out.prefix(60))
    }

    // MARK: EARS

    /// Every partial of the live stream. Ambient speech never fires the lane; Nova's own speech is ignored (only
    /// "stop" barges in); the words AFTER the last wake name (or after the held hotkey) are the command.
    private func partial(_ text: String, final: Bool, wordEnd: TimeInterval?) {
        guard !muted else { return }
        lastTokenCount = NovaLiveTurn.tokens(text).count
        if speaking { if NovaLiveTurn.isBargeIn(text) { interrupt() }; return }
        guard let words = live.command(in: text, novaSpeaking: speaking) else { return }
        if !turnActive { beginTurn() }
        lastWordEnd = wordEnd
        command(words.joined(separator: " "), now: Date())
        if final { Task { await finishTurn() } }
    }

    private func hotkey(_ down: Bool) {
        guard !muted else { return }
        if down {
            hotkeyHeld = true
            if !NovaSettings.wakeWord, WakeListener.authorized { wake.extraContext = Self.contextNames(); wake.start() }
            live.pressHotkey(wordCount: lastTokenCount)
            beginTurn()
        } else {
            hotkeyHeld = false
            if turnActive { Task { await finishTurn() } }   // hotkey release = end of turn immediately
        }
    }

    private func beginTurn() {
        guard !turnActive else { return }
        turnActive = true; turnStart = Date(); lastChange = Date(); lastCommand = ""; lastWordEnd = nil
        state = .listening; transcript = ""; lines = []; directDone = []
        eager = NovaEagerTurn(); eagerTask?.cancel(); eagerTask = nil
        NSSound(named: "Tink")?.play()
        NovaNet.prewarm()
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.localizedName)
        session = NovaInstantSession(apps: AppIndex.scan(running: running), panes: AgentRegistry.shared.crew.map(\.name))
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                await self?.tick()
            }
        }
    }

    /// New addressed words: drive the instant lane, spoken approvals, the HUD, and the eager end-of-turn.
    private func command(_ text: String, now: Date) {
        if text != lastCommand { lastCommand = text; lastChange = now }
        transcript = text
        if pending != nil, resolveSpoken(text) { return }
        guard var s = session else { return }
        let steps = s.feed(text, now: now); session = s
        if !steps.isEmpty { runner.enqueue(steps) }
        steerEager(now)
    }

    private func steerEager(_ now: Date) {
        guard let s = session else { return }
        switch eager.observe(unhandled: s.unhandled, now: now) {
        case .cancel: eagerTask?.cancel(); eagerTask = nil
        case .start(let t):
            let done = s.handled
            eagerTask = Task { [weak self] in await self?.utterance(t, source: .take, already: done, eager: true) }
        case .none: break
        }
    }

    private func tick() async {
        guard turnActive else { return }
        let now = Date()
        if var s = session, !lastCommand.isEmpty {   // prefix-wait: re-feed the same words so a held "Music" can fire
            let steps = s.feed(lastCommand, now: now); session = s
            if !steps.isEmpty { runner.enqueue(steps) }
        }
        steerEager(now)
        let quiet = now.timeIntervalSince(lastChange)
        if hotkeyHeld { return }
        if lastCommand.isEmpty ? now.timeIntervalSince(turnStart) > 6 : quiet >= endpointing.delay { await finishTurn() }
    }

    private func finishTurn() async {
        guard turnActive else { return }
        turnActive = false; ticker?.cancel(); ticker = nil
        let unhandled = session?.unhandled.trimmingCharacters(in: .whitespaces) ?? ""
        let handled = session?.handled ?? []
        live.endTurn(wordCount: lastTokenCount); lastTurnEnd = Date()
        if !NovaSettings.wakeWord, !hotkeyHeld { Task { try? await Task.sleep(for: .seconds(1)); if !turnActive { wake.stop() } } }
        if unhandled.isEmpty { eagerTask?.cancel(); state = handled.isEmpty ? .idle : .done; flushRecord(path: "instant"); return }
        if eager.startedFor == unhandled, let t = eagerTask { await t.value }   // eager run already has it
        else { eagerTask?.cancel(); await utterance(unhandled, source: .take, already: handled, eager: false) }
        eagerTask = nil
        if state == .done { Task { try? await Task.sleep(for: .seconds(3)); if state == .done, !turnActive { state = .idle } } }
    }

    private func instantDone(_ verb: InstantVerb, _ text: String, _ bad: Bool) {
        var line = verb.spoken
        if NovaSettings.showTimings, let t = runner.timings.last { line += " · \(t.clauseToActMs) ms" }
        lines.append(.init(text: line, ok: !bad)); state = .acting
        if bad { say(text) } else { NSSound(named: "Pop")?.play() }
    }

    /// Words in the room, no wake word: reflex only, never the brain; may only complete `ambientSafeVerbs`.
    private func ambient(_ text: String) {
        if pending != nil, resolveSpoken(text) { return }
        if turnActive || speaking || Date().timeIntervalSince(lastTurnEnd) < 3 { return }   // never re-read a turn or Nova's own voice
        Task { await utterance(text, source: .ambient) }
    }

    // MARK: GATE approval

    func approve(_ what: String) async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            approval = c; pending = what; state = .waiting
            speech.enqueue(.init(line: "Go ahead?", elevenEnabled: Vault.has("elevenlabs"), elevenVoiceID: nil, elevenModel: nil, voiceboxProfile: nil))
            Task { try? await Task.sleep(for: .seconds(NovaGate.parkSeconds)); resolve(false) }
        }
    }
    func resolve(_ yes: Bool) {
        guard let c = approval else { return }
        approval = nil; pending = nil; state = .acting; c.resume(returning: yes)
    }
    private func resolveSpoken(_ text: String) -> Bool {
        let t = text.lowercased()
        if t.contains("go ahead") || t.contains("approve") { resolve(true); return true }
        if t.contains("cancel") || t.contains("don't") || t.contains("stop") { resolve(false); return true }
        return false
    }
    func interrupt() { brainTask?.cancel(); speech.shutUp(); resolve(false); state = .idle }

    // MARK: REFLEX ∥ BRAIN

    private func say(_ s: String) {
        speech.enqueue(.init(line: s, elevenEnabled: Vault.has("elevenlabs"), elevenVoiceID: nil, elevenModel: nil, voiceboxProfile: nil))
    }

    func utterance(_ raw: String, source: NovaReflex.Source, already: [String] = [], eager: Bool = false) async {
        let reading = NovaAddress.read(raw)
        if pending != nil, resolveSpoken(raw) { return }
        if reading.isSummons { say("Yes?"); state = .idle; return }
        let text = eager ? raw : reading.rest
        if !eager { transcript = text }; if source == .take { state = .thinking }
        let t0 = Date()
        let seats = AgentRegistry.shared.crew.map { NovaReflex.Seat(name: $0.name, skills: "", live: AgentRegistry.shared.isAwake($0.name)) }
        let ctx = NovaReflex.Context(seats: seats, recent: recent, lookingAt: NSWorkspace.shared.frontmostApplication?.localizedName)
        let hasKey = Vault.has("anthropic", envFallback: ["ANTHROPIC_API_KEY"])
        if source == .take, !hasKey, !announcedNoKey {
            announcedNoKey = true; say("Haiku isn't set up. I can still do quick commands."); notice = Self.setupLine
        }
        var reflexMs = 0, brainMs = 0
        var verdict: NovaReflex.Verdict?
        var tools: [String] = []
        let roster = seats.map { "\($0.name)\($0.live ? "*" : "")" }.joined(separator: ", ")
        let focus = ctx.lookingAt ?? "unknown"
        let h = hands
        let path = await NovaSpeculative.race(
            reflex: { let v = await NovaReflex.read(text, context: ctx, source: source); return v },
            direct: { [weak self] a in
                let (name, input) = Self.tool(for: a)
                let key = name + "|" + input.keys.sorted().map { "\($0)=\(input[$0] ?? "")" }.joined(separator: ",")
                guard await self?.claimDirect(key) == true else { return }
                await self?.begin(NovaToolSchemas.summary(name, input))
                let r = await h.run(name: name, input: input, id: "reflex")
                await self?.end(name, ok: !r.isError, said: r.text)
            },
            brain: { [weak self] in
                guard let self, source == .take, hasKey else { return }
                let b0 = Date()
                let brain = HaikuBrain(effort: NovaSettings.effort)
                let done = already.isEmpty ? nil : "Already done: " + already.joined(separator: ", ")
                let user = [done, "Agents: \(roster)", "In front: \(focus)", "User said: \(text)"].compactMap { $0 }.joined(separator: "\n")
                await MainActor.run { self.speechBuf = "" }
                let out = await brain.respond(user: user, runner: h) { u in
                    Task { @MainActor in
                        switch u.kind {
                        case .text(let s):
                            self.speechBuf += s
                            while let r = self.speechBuf.firstIndex(where: { ".!?".contains($0) }) {
                                let sentence = String(self.speechBuf[...r]).trimmingCharacters(in: .whitespacesAndNewlines)
                                self.speechBuf = String(self.speechBuf[self.speechBuf.index(after: r)...]); if !sentence.isEmpty { self.say(sentence) }
                            }
                        case .toolStart(let n, let s): self.state = .acting; self.lines.append(.init(text: s, ok: nil)); _ = n
                        case .toolEnd(_, let ok): if let i = self.lines.lastIndex(where: { $0.ok == nil }) { self.lines[i].ok = ok }
                        }
                    }
                }
                await MainActor.run { if !self.speechBuf.trimmingCharacters(in: .whitespaces).isEmpty { self.say(self.speechBuf) }; self.speechBuf = "" }
                if case .failed(let m) = out, m != "cancelled" { await MainActor.run { self.notice = "Brain: \(m)" } }
                await MainActor.run { self.run["brain_ms"] = Int(Date().timeIntervalSince(b0) * 1000); self.run["brain_outcome"] = "\(out)" }
            })
        _ = verdict; _ = tools
        recent = Array((recent + ["USER: \(text)"]).suffix(6))
        reflexMs = Int(Date().timeIntervalSince(t0) * 1000); brainMs = run["brain_ms"] as? Int ?? 0
        state = .done
        record(text: text, path: "\(path)", reflexMs: reflexMs, brainMs: brainMs)
        try? await Task.sleep(for: .seconds(3)); if state == .done { state = .idle }
    }

    private func begin(_ summary: String) {
        state = .acting; lines.append(.init(text: summary, ok: nil))
    }
    /// One direct act per tool+input per turn (the eager run and the final run must not both fire it).
    private func claimDirect(_ key: String) -> Bool { directDone.insert(key).inserted }
    /// Feedback never waits: a soft earcon, no spoken confirmation unless the act returned information or failed.
    private func end(_ name: String, ok: Bool, said: String) {
        if let i = lines.lastIndex(where: { $0.ok == nil }) { lines[i].ok = ok }
        if !ok || ["hub_status", "read_pane"].contains(name) { say(String(said.split(separator: " ").prefix(8).joined(separator: " "))) }
        else { NSSound(named: "Pop")?.play() }
    }

    /// Reflex action → the same tool the brain would call (one hand per verb).
    nonisolated static func tool(for a: NovaAction) -> (String, [String: Any]) {
        switch a.action {
        case "focus_pane": return ("focus_pane", ["target": a.agent ?? a.target ?? ""])
        case "read_pane": return ("read_pane", ["target": a.agent ?? a.target ?? "", "lines": 30])
        case "status": return ("hub_status", [:])
        case "screenshot_full": return ("screenshot", [:])
        case "open_app": return ("open_app", ["name": a.query ?? a.target ?? ""])
        case "quit_app": return ("quit_app", ["name": a.query ?? a.target ?? ""])
        default: return ("media_control", ["action": a.query ?? "play_pause"])
        }
    }

    // MARK: RECORD (hash, never the words; no secrets)

    private func flushRecord(path: String) { record(text: lastCommand, path: path, reflexMs: 0, brainMs: 0) }
    private func record(text: String, path: String, reflexMs: Int, brainMs: Int) {
        let hash = SHA256.hash(data: Data(text.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        Self.log.info("utterance \(hash, privacy: .public) path=\(path, privacy: .public) reflex_ms=\(reflexMs) brain_ms=\(brainMs) tools=\(self.lines.count) gate=\(self.pending == nil ? "clear" : "pending", privacy: .public)")
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".true/nova/runs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let obj: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date()), "transcript_hash": hash, "path": path,
                                  "reflex_ms": reflexMs, "brain_ms": brainMs,
                                  "clause_to_act_ms": runner.timings.last?.clauseToActMs as Any? ?? NSNull(),
                                  "word_to_act_ms": runner.timings.last?.wordToActMs as Any? ?? NSNull(), "tools": lines.map { ["line": $0.text, "ok": $0.ok as Any? ?? NSNull()] }]
        if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) {
            let f = dir.appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(hash).json")
            FileManager.default.createFile(atPath: f.path, contents: d, attributes: [.posixPermissions: 0o600])
        }
        run = [:]
    }
}
