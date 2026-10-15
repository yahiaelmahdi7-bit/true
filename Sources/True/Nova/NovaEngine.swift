import Foundation
import AppKit
import OSLog

/// Wires EARS → REFLEX ∥ BRAIN → HANDS (behind the GATE) → HUD + VOICE. One name per thing; see docs/kb/glossary.md.
@MainActor
final class NovaEngine: ObservableObject {
    static let shared = NovaEngine()
    nonisolated static let setupLine = "security add-generic-password -s net.prismlens.true -a anthropic -U -w"
    private static let log = Logger(subsystem: "net.prismlens.true", category: "nova")

    enum State: String { case idle, listening, thinking, acting, waiting = "waiting for go-ahead", done }
    struct Line: Identifiable { let id = UUID(); var text: String; var ok: Bool?; var tool = "" }

    @Published var state: State = .idle
    @Published var transcript = ""
    @Published var lines: [Line] = []
    @Published var pending: String?
    @Published private(set) var pendingID: UUID?
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
    private var tellTurn = NovaTellTurn()
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
    private let approvals = NovaApprovals()
    private var speechEndedAt = Date.distantPast
    /// When Nova's own voice was playing: late-delivered words timestamped inside it are spent (Run 26f).
    private var speechWindows: [(start: Date, end: Date)] = []
    private var tellUndone = false
    private func speech_trim() { if speechWindows.count > 20 { speechWindows.removeFirst(speechWindows.count - 20) } }
    private var eagerHeld = false
    private var announcedNoKey = false
    private var recent: [String] = []
    private lazy var speech = NovaSpeechQueue(onSpeakingChanged: { [weak self] s in
        guard let self else { return }
        if s { self.speechWindows.append((Date(), .distantFuture)) }
        else { self.speechEndedAt = Date(); if let i = self.speechWindows.indices.last { self.speechWindows[i].end = Date() } }
        self.speech_trim()
        self.speaking = s })
    private lazy var hands = NovaHands(approve: { [weak self] what in await self?.approve(what) ?? false },
                                       cancelled: { Task.isCancelled })
    /// Eager (mid-speech) hands: read-only tools only; anything that changes something is held for the final run (M1).
    private lazy var eagerHands = NovaHands(approve: { _ in false }, cancelled: { Task.isCancelled }, eager: true,
                                            onHeld: { [weak self] in Task { @MainActor in self?.eagerHeld = true; self?.eagerTask?.cancel() } })   // live 2026-10-11: held open_url was retried 6-7x
    private var run: [String: Any] = [:]
    private var recordFrom = 0   // `lines` already written to a run record: ambient utterances don't reset `lines`, so a record takes only what's new
    private var speechBuf = ""
    private var utterSeen = false
    private var utterCard: UUID?

    func start() {
        guard NovaSettings.enabled, !running else { return }
        running = true
        approvals.onChange = { [weak self] item in
            guard let self else { return }
            pending = item?.what; pendingID = item?.id
            state = item == nil ? .acting : .waiting
        }
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
        guard !muted else { return }
        if WakeListener.authorized {
            if NovaSettings.wakeWord { wake.extraContext = Self.contextNames(); wake.start() }
        } else if WakeListener.undetermined {
            // Speech Recognition is its own TCC prompt (not the mic's) and nothing else asks for it: the Axon port
            // dropped the caller, so the wake word and push-to-talk stayed deaf with no prompt and no log line.
            Self.log.info("speech recognition not yet authorized — requesting")
            wake.requestAuthorization { [weak self] ok in
                Self.log.info("speech recognition \(ok ? "granted" : "declined", privacy: .public)")
                if ok { self?.startWake() }
            }
        } else {
            Self.log.info("speech recognition denied — wake word and push-to-talk are off (System Settings → Privacy → Speech Recognition)")
        }
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
        let gated = NovaApproval.micGated(speaking: speaking, sinceSpeechEnd: Date().timeIntervalSince(speechEndedAt))
        if gated, speaking, NovaLiveTurn.isBargeIn(text) { interrupt() }   // only "stop" gets through while Nova talks
        // gated words are consumed (P1): a "nova" Nova said itself can never address a later command
        live.spend(upTo: NovaLiveTurn.spentCount(segmentStarts: wake.segmentStarts, windows: speechWindows, tail: NovaApproval.micTail))
        guard let words = live.ingest(text, gated: gated, novaSpeaking: speaking, generation: wake.generation) else { return }
        if !turnActive { beginTurn() }
        if !utterSeen { utterSeen = true; utterCard = approvals.current?.id }   // the card showing when this utterance STARTED
        lastWordEnd = wordEnd
        command(words.joined(separator: " "), now: Date(), final: final)
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
        turnActive = true; turnStart = Date(); lastChange = Date(); lastCommand = ""; lastWordEnd = nil; tellTurn.reset(); tellUndone = false
        state = .listening; transcript = ""; lines = []; recordFrom = 0; directDone = []
        eagerHeld = false; hands.resetTurn(); eagerHands.resetTurn()
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
    private func command(_ text: String, now: Date, final: Bool = false) {
        if text != lastCommand { lastCommand = text; lastChange = now }
        transcript = text
        if pending != nil, resolveSpoken(text, addressed: true, final: final) { return }   // command() text is addressed by construction
        guard var s = session else { return }
        let steps = s.feed(text, now: now); session = s
        if !steps.isEmpty { runner.enqueue(steps) }
        if s.tellMatched, !s.handled.isEmpty, !tellUndone { tellUndone = true; runner.undoAll() }   // local acts ran before the tell matched
        steerEager(now)
    }

    private func steerEager(_ now: Date) {
        guard let s = session else { return }
        switch eager.observe(unhandled: s.unhandled, now: now) {
        case .cancel: eagerTask?.cancel(); eagerTask = nil
        case .start(let t):
            if NovaTell.parse(lastCommand, roster: AgentRegistry.shared.crew.map(\.name)) != nil { break }   // a tell only ever fires at the final end of turn
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
        let finalAt = Date()
        if pending != nil, !lastCommand.isEmpty, resolveSpoken(lastCommand, addressed: true, final: true) { utterSeen = false; utterCard = nil }   // end of turn = the final utterance
        turnActive = false; ticker?.cancel(); ticker = nil
        utterSeen = false; utterCard = nil
        let unhandled = session?.unhandled.trimmingCharacters(in: .whitespaces) ?? ""
        let handled = session?.handled ?? []
        live.endTurn(wordCount: lastTokenCount); lastTurnEnd = Date()
        if !NovaSettings.wakeWord, !hotkeyHeld { Task { try? await Task.sleep(for: .seconds(1)); if !turnActive { wake.stop() } } }
        if pending == nil, await verbatimSend(finalAt: finalAt) { eagerTask?.cancel(); eagerTask = nil; return }
        if unhandled.isEmpty { eagerTask?.cancel(); state = handled.isEmpty ? .idle : .done; flushRecord(path: "instant"); return }
        if eager.startedFor == unhandled, !eagerHeld, let t = eagerTask { await t.value }   // eager run already has it
        else { eagerTask?.cancel(); directDone = []; await utterance(unhandled, source: .take, already: handled, eager: false) }   // M1: mismatch/held -> discard, rerun final
        eagerTask = nil
        if state == .done { Task { try? await Task.sleep(for: .seconds(3)); if state == .done, !turnActive { state = .idle } } }
    }

    /// Run 26e: "tell <agent> <his words>" goes straight to the pane, no model, no approval. Final end of turn only.
    private func verbatimSend(finalAt: Date) async -> Bool {
        let gated = NovaApproval.micGated(speaking: speaking, sinceSpeechEnd: Date().timeIntervalSince(speechEndedAt))
        guard let t = tellTurn.finalize(lastCommand, roster: AgentRegistry.shared.crew.map(\.name), addressed: true, gated: gated, final: true) else { return false }
        let live = await MainActor.run { () -> Bool in
            let r = AgentRegistry.shared
            let screen = r.panes[t.target].flatMap { TerminalRegistry.shared.view(for: $0)?.screenText() } ?? ""
            return NovaTell.deliverable(awake: r.isAwake(t.target), status: r.statusOf(t.target), screen: screen)
        }
        guard live else {
            lines.append(.init(text: "\(t.target) isn't running", ok: false, tool: "tell")); state = .done
            say("\(t.target) isn't running"); flushRecord(path: "tell"); return true
        }
        let clauseToActMs = Int(Date().timeIntervalSince(finalAt) * 1000)
        NSSound(named: "Pop")?.play()
        let r = await hands.runUser(name: "send_to_pane", input: ["target": t.target, "text": t.text])
        var line = "→ \(t.target): " + t.text.split(separator: " ").prefix(6).joined(separator: " ")
        if r.isError { line = r.text }
        if NovaSettings.showTimings { line += " · \(clauseToActMs) ms" }
        lines.append(.init(text: line, ok: !r.isError, tool: "tell"))
        state = .done; flushRecord(path: "tell")
        Task { try? await Task.sleep(for: .seconds(3)); if state == .done, !turnActive { state = .idle } }
        return true
    }

    private func instantDone(_ verb: InstantVerb, _ text: String, _ bad: Bool) {
        var line = verb.spoken
        if NovaSettings.showTimings, let t = runner.timings.last { line += " · \(t.clauseToActMs) ms" }
        lines.append(.init(text: line, ok: !bad, tool: "instant")); state = .acting
        if bad { say(text) } else { NSSound(named: "Pop")?.play() }
    }

    /// Words in the room, no wake word: reflex only, never the brain; may only complete `ambientSafeVerbs`.
    private func ambient(_ text: String) {
        if NovaApproval.micGated(speaking: speaking, sinceSpeechEnd: Date().timeIntervalSince(speechEndedAt)) { return }
        if pending != nil {   // ambient speech can only say NO (C1)
            if NovaApproval.decide(text, addressed: false) == .deny { approvals.resolve(false) }
            return
        }
        if turnActive || speaking || Date().timeIntervalSince(lastTurnEnd) < 3 { return }   // never re-read a turn or Nova's own voice
        Task { await utterance(text, source: .ambient) }
    }

    // MARK: GATE approval

    func approve(_ what: String) async -> Bool {
        speech.enqueue(.init(line: "Go ahead?", elevenEnabled: Vault.has("elevenlabs"), elevenVoiceID: nil, elevenModel: nil, voiceboxProfile: nil))
        return await approvals.request(what, seconds: NovaGate.parkSeconds)
    }
    /// HUD click: bound to the id of the card that was shown, so a stale click can't approve a newer action (M2).
    func resolve(_ yes: Bool, id: UUID? = nil) { approvals.resolve(yes, id: id) }
    private func resolveSpoken(_ text: String, addressed: Bool, final: Bool) -> Bool {
        let now = approvals.current?.id
        switch NovaApproval.resolution(text, addressed: addressed, final: final, cardAtStart: utterCard, cardNow: now) {
        case .approve: approvals.resolve(true, id: now); return true
        case .deny: approvals.resolve(false, id: now); return true
        case .none: return false
        }
    }
    func interrupt() { brainTask?.cancel(); speech.shutUp(); resolve(false); state = .idle }

    // MARK: REFLEX ∥ BRAIN

    private var brainVoice = BrainFailureVoice()

    private func say(_ s: String) {
        speech.enqueue(.init(line: s, elevenEnabled: Vault.has("elevenlabs"), elevenVoiceID: nil, elevenModel: nil, voiceboxProfile: nil))
    }

    func utterance(_ raw: String, source: NovaReflex.Source, already: [String] = [], eager: Bool = false) async {
        let reading = NovaAddress.read(raw)
        if reading.isSummons { say("Yes?"); state = .idle; return }
        if !eager, source == .take, let a = Self.localAnswer(reading.rest) {   // time/date: on the Mac, 0 ms, no network
            transcript = reading.rest; say(a); state = .done; record(text: reading.rest, path: "local", reflexMs: 0, brainMs: 0); return
        }
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
        let h = eager ? eagerHands : hands
        let path = await NovaSpeculative.race(
            reflex: { let v = await NovaReflex.read(text, context: ctx, source: source); return v },
            direct: { [weak self] a in
                let (name, input) = Self.tool(for: a)
                let key = name + "|" + input.keys.sorted().map { "\($0)=\(input[$0] ?? "")" }.joined(separator: ",")
                if eager, await h.markHeldIfMutating(name) { return }   // M1: eager never changes anything
                guard await self?.claimDirect(key) == true else { return }
                await self?.begin(NovaToolSchemas.summary(name, input), tool: name)
                let r = await h.run(name: name, input: input, id: "reflex")
                await self?.end(name, ok: !r.isError, said: r.text)
            },
            brain: { [weak self] in
                guard let self, source == .take, hasKey else { return }
                let b0 = Date()
                let heard = Task { @MainActor in   // never dead air: soft cue if no words or act by 0.8 s
                    try? await Task.sleep(for: .milliseconds(800))
                    if !Task.isCancelled, self.speechBuf.isEmpty, !self.speaking { NSSound(named: "Morse")?.play() }
                }
                defer { heard.cancel() }
                let brain = HaikuBrain(effort: NovaSettings.effort)
                let done = already.isEmpty ? nil : "Already done: " + already.joined(separator: ", ")
                let user = [done, "Now: \(Self.clock())", "Agents: \(roster)", "In front: \(focus)", "User said: \(text)"].compactMap { $0 }.joined(separator: "\n")
                await MainActor.run { self.speechBuf = "" }
                let out = await brain.respond(user: user, runner: h) { u in
                    Task { @MainActor in
                        switch u.kind {
                        case .text(let s):
                            heard.cancel()
                            self.speechBuf += s
                            while let r = self.speechBuf.firstIndex(where: { ".!?".contains($0) }) {
                                let sentence = String(self.speechBuf[...r]).trimmingCharacters(in: .whitespacesAndNewlines)
                                self.speechBuf = String(self.speechBuf[self.speechBuf.index(after: r)...]); if !sentence.isEmpty { self.say(sentence) }
                            }
                        case .toolStart(let n, let s): heard.cancel(); self.state = .acting; self.lines.append(.init(text: s, ok: nil, tool: n))
                        case .toolEnd(_, let ok): if let i = self.lines.lastIndex(where: { $0.ok == nil }) { self.lines[i].ok = ok }
                        }
                    }
                }
                await MainActor.run { if !self.speechBuf.trimmingCharacters(in: .whitespaces).isEmpty { self.say(self.speechBuf) }; self.speechBuf = "" }
                if case .failed(let m) = out, m != "cancelled" {
                    await MainActor.run {
                        self.notice = "Brain: \(m)"
                        if let kind = BrainFailureVoice.kind(forFailure: m), self.brainVoice.shouldSpeak(kind, now: Date()) {
                            let line = BrainFailureVoice.line(kind)
                            self.notice = line; self.say(line)
                        }
                    }
                }
                await MainActor.run { self.run["brain_ms"] = Int(Date().timeIntervalSince(b0) * 1000); self.run["brain_outcome"] = out.label }
            })
        _ = verdict; _ = tools
        recent = Array((recent + ["USER: \(text)"]).suffix(6))
        reflexMs = Int(Date().timeIntervalSince(t0) * 1000); brainMs = run["brain_ms"] as? Int ?? 0
        state = .done
        record(text: text, path: "\(path)", reflexMs: reflexMs, brainMs: brainMs)
        try? await Task.sleep(for: .seconds(3)); if state == .done { state = .idle }
    }

    /// Questions the Mac answers itself. Whole-utterance match only, so "what time is the meeting" still goes to the brain.
    nonisolated static func localAnswer(_ text: String, now: Date = Date()) -> String? {
        let t = text.lowercased().filter { $0.isLetter || $0 == " " || $0 == "'" }.split(separator: " ").joined(separator: " ")
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        let time: Set = ["what time is it", "what's the time", "whats the time", "what is the time", "time", "the time", "what time it is"]
        let date: Set = ["what day is it", "what's the date", "whats the date", "what is the date", "what's today", "what is today",
                         "what's today's date", "what is today's date", "date", "what date is it", "what day is today"]
        if time.contains(t) { f.dateFormat = "h:mm a"; return "It's \(f.string(from: now))." }
        if date.contains(t) { f.dateFormat = "EEEE, d MMMM"; return "It's \(f.string(from: now))." }
        return nil
    }

    /// Local time for the brain's user turn: "what time / what day" answers in one round, no `date` tool call.
    nonisolated static func clock(_ d: Date = Date()) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "EEEE d MMMM yyyy, HH:mm zzz"
        return f.string(from: d)
    }

    private func begin(_ summary: String, tool: String = "") {
        state = .acting; lines.append(.init(text: summary, ok: nil, tool: tool))
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

    // MARK: RECORD (no words, no hash of the words, no command text: tool names + timings only)

    private func flushRecord(path: String) { record(path: path, reflexMs: 0, brainMs: 0) }
    private func record(text: String = "", path: String, reflexMs: Int, brainMs: Int) {
        let tools = lines.dropFirst(recordFrom).map { ($0.tool.isEmpty ? "tool" : $0.tool, $0.ok) }
        Self.log.info("utterance path=\(path, privacy: .public) reflex_ms=\(reflexMs) brain_ms=\(brainMs) tools=\(tools.count) gate=\(self.pending == nil ? "clear" : "pending", privacy: .public)")
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".true/nova/runs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let obj = Self.runObject(path: path, reflexMs: reflexMs, brainMs: brainMs, clauseMs: runner.timings.last?.clauseToActMs,
                                 wordMs: runner.timings.last?.wordToActMs, tools: tools,
                                 brainOutcome: run["brain_outcome"] as? String)
        if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) {
            let f = dir.appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).json")
            FileManager.default.createFile(atPath: f.path, contents: d, attributes: [.posixPermissions: 0o600])
        }
        run = [:]; recordFrom = lines.count
    }
    /// The run record: tool names and ok flags only (M3/L4). Static so a test can prove no command text or transcript hash leaks.
    nonisolated static func runObject(path: String, reflexMs: Int, brainMs: Int, clauseMs: Int?, wordMs: Int?, tools: [(String, Bool?)],
                                     brainOutcome: String? = nil) -> [String: Any] {
        ["at": ISO8601DateFormatter().string(from: Date()), "path": path, "reflex_ms": reflexMs, "brain_ms": brainMs,
         "clause_to_act_ms": clauseMs as Any? ?? NSNull(), "word_to_act_ms": wordMs as Any? ?? NSNull(),
         "brain_outcome": brainOutcome as Any? ?? NSNull(),
         "tools": tools.map { ["tool": $0.0, "ok": $0.1 as Any? ?? NSNull()] }]
    }
}
