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
    private var recorder: AudioRecorder?
    private var recording = false
    private var brainTask: Task<Void, Never>?
    private var approval: CheckedContinuation<Bool, Never>?
    private var announcedNoKey = false
    private var recent: [String] = []
    private lazy var speech = NovaSpeechQueue(onSpeakingChanged: { _ in })
    private lazy var hands = NovaHands(approve: { [weak self] what in await self?.approve(what) ?? false },
                                       cancelled: { Task.isCancelled })
    private var run: [String: Any] = [:]
    private var speechBuf = ""

    func start() {
        guard NovaSettings.enabled, !running else { return }
        running = true
        wake.onWake = { [weak self] in Task { @MainActor in self?.take() } }
        wake.onUtterance = { [weak self] t in Task { @MainActor in self?.ambient(t) } }
        keys.setHotkey(NovaSettings.hotkey)
        keys.onEdge = { [weak self] down in Task { @MainActor in if down { self?.take() } } }
        keys.start()
        startWake()
    }
    func stop() { wake.stop(); keys.stop(); running = false; state = .idle }
    private func startWake() { if NovaSettings.wakeWord, !muted, WakeListener.authorized { wake.start() } }

    // MARK: EARS

    /// A deliberate take: wake word or hotkey. Records until ~1 s of quiet after speech (15 s max), then transcribes.
    func take() {
        guard !recording, !muted else { return }
        wake.standDown(); recording = true; state = .listening; transcript = ""; lines = []; NSSound(named: "Tink")?.play()
        let rec = AudioRecorder(); recorder = rec
        do { try rec.start() } catch { finishTake(error: "mic unavailable"); return }
        Task {
            var spoke = false, quiet = 0.0, total = 0.0
            while recording, total < 15 {
                try? await Task.sleep(for: .milliseconds(50)); total += 0.05
                if rec.currentLevel() > 0.02 { spoke = true; quiet = 0 } else if spoke { quiet += 0.05 }
                if spoke, quiet >= 1.0 { break }
            }
            let out = rec.stop()
            recording = false
            guard spoke, !out.samples.isEmpty else { finishTake(error: nil); return }
            state = .thinking
            let text = (try? await SpeechAnalyzerTranscriber(language: "en-US").transcribe(samples: out.samples, wav: out.wav)) ?? ""
            finishTake(error: nil)
            if !text.trimmingCharacters(in: .whitespaces).isEmpty { await utterance(text, source: .take) } else { state = .idle }
        }
    }
    private func finishTake(error: String?) {
        recording = false; recorder = nil; wake.resume()
        if let error { notice = error; state = .idle }
    }

    /// Words in the room, no wake word: reflex only, never the brain; may only complete `ambientSafeVerbs`.
    private func ambient(_ text: String) {
        if pending != nil, resolveSpoken(text) { return }
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

    func utterance(_ raw: String, source: NovaReflex.Source) async {
        let reading = NovaAddress.read(raw)
        if pending != nil, resolveSpoken(raw) { return }
        if reading.isSummons { say("Yes?"); state = .idle; return }
        let text = reading.rest
        transcript = text; if source == .take { state = .thinking }
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
                await self?.begin(NovaToolSchemas.summary(name, input))
                let r = await h.run(name: name, input: input, id: "reflex")
                await self?.end(name, ok: !r.isError, said: r.text)
            },
            brain: { [weak self] prior in
                guard let self, source == .take, hasKey else { return }
                let b0 = Date()
                let brain = HaikuBrain(effort: NovaSettings.effort)
                let user = [prior, "Agents: \(roster)", "In front: \(focus)", "User said: \(text)"].compactMap { $0 }.joined(separator: "\n")
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
    private func end(_ name: String, ok: Bool, said: String) {
        if let i = lines.lastIndex(where: { $0.ok == nil }) { lines[i].ok = ok }
        say(String(said.split(separator: " ").prefix(8).joined(separator: " ")))
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

    private func record(text: String, path: String, reflexMs: Int, brainMs: Int) {
        let hash = SHA256.hash(data: Data(text.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        Self.log.info("utterance \(hash, privacy: .public) path=\(path, privacy: .public) reflex_ms=\(reflexMs) brain_ms=\(brainMs) tools=\(self.lines.count) gate=\(self.pending == nil ? "clear" : "pending", privacy: .public)")
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".true/nova/runs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let obj: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date()), "transcript_hash": hash, "path": path,
                                  "reflex_ms": reflexMs, "brain_ms": brainMs, "tools": lines.map { ["line": $0.text, "ok": $0.ok as Any? ?? NSNull()] }]
        if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) {
            let f = dir.appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(hash).json")
            FileManager.default.createFile(atPath: f.path, contents: d, attributes: [.posixPermissions: 0o600])
        }
        run = [:]
    }
}
