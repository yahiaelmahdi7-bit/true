import Foundation
import os
@preconcurrency import AVFoundation
@preconcurrency import Speech

/// "Hey Nova" always-listening wake word (A3). A lightweight ON-DEVICE keyword spotter: an
/// `SFSpeechRecognizer` transcribes a continuous mic stream *locally* (nothing leaves the Mac) and,
/// the instant it hears "nova", fires `onWake` — which starts a real dictation take. It is separate
/// from the whisper/cloud pipeline the command itself uses: this only listens for the TRIGGER, then
/// stands down (releases the mic) so the take's own `AudioRecorder` can have it, and resumes when the
/// take ends. One instance, owned by `VoiceEngine`.
@MainActor
final class WakeListener: ObservableObject {
    /// Fired when the wake phrase is heard. The owner starts a take and calls `resume()` when done.
    var onWake: (() -> Void)?

    /// Fired with the words of an utterance that did NOT contain the wake name, once the speaker
    /// has gone quiet for `UtteranceSplitter.quietGap`. This is the "speak all day" seam: the
    /// on-device stream already hears everything said in the room; before this it threw every
    /// sentence away unless her name was in it. The owner decides what (if anything) to do —
    /// `VoiceEngine` runs it through `NovaReflex`, which is the judgment this spotter lacks.
    /// Recognizer text, not whisper: good enough for a short desk command, never used as dictation.
    var onUtterance: ((String) -> Void)?
    private var splitter = UtteranceSplitter()
    private var quietTimer: DispatchWorkItem?

    @Published private(set) var status: Status = .off
    enum Status: Equatable { case off, listening, denied, unavailable(String) }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    /// A `var`, because the fix for "works once, then never again" is a NEW engine after every
    /// take — see `rebuildEngine()`.
    private var audio = AVAudioEngine()
    /// The live tap's counters (buffers delivered, peak level), read by the watchdog.
    private var sink: TapSink?
    private var watchdog: DispatchWorkItem?
    private var silentChecks = 0
    private var heardWords = false
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var restart: DispatchWorkItem?
    private var wantListening = false          // the user's intent — survives a take's stand-down
    private var listening = false
    /// True while a dictation take owns the mic. `wantListening` stays true across a take, so it
    /// alone can't tell "resume me" from "keep your hands off the mic" — and a retry that fired
    /// mid-take would steal the input device out from under the take's own recorder.
    private var standingDown = false
    private var lastFire = Date.distantPast
    /// Delay before the next re-begin, grown on each consecutive failure and reset on success.
    ///
    /// The old fixed 0.3 s was the second half of the wake-crash: when the machine wakes into an
    /// audio state that can't serve a tap, a constant retry is an unbounded hot loop against
    /// hardware that needs *seconds* to settle. Backing off means a slow wake costs a few quiet
    /// retries instead of hundreds of spins.
    // Named concretely rather than as `Self`: a stored-property initializer can't reference the
    // covariant `Self` of a class type, `final` or not.
    private var backoff: TimeInterval = WakeListener.minBackoff
    private static let minBackoff: TimeInterval = 0.3
    private static let maxBackoff: TimeInterval = 15

    /// AVFAudio's own "the audio hardware changed underneath you" signal — the single most reliable
    /// notice that a wake, a device swap, or a Bluetooth handoff just invalidated the engine. The
    /// engine stops itself when this fires, so listening MUST be rebuilt rather than assumed alive.
    private var configObserver: NSObjectProtocol?

    /// One line per state change and per flushed utterance in the unified log
    /// (`/usr/bin/log stream --level info --predicate 'subsystem == "net.prismlens.axon"'`).
    /// Added because the ambient path failed SILENTLY: a spoken command produced no reflex line
    /// and nothing said whether the spotter was listening, heard words, or dropped them. Note
    /// the full path — in zsh, `log` is a builtin that lists logged-in users, and its silent
    /// "too many arguments" is exactly what made the first look at these logs come back empty.
    private let log = Logger(subsystem: "net.prismlens.axon", category: "wake")

    static var authorized: Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }

    /// Request Speech Recognition authorization (its own TCC prompt, separate from the microphone).
    /// The completion runs on the main actor, so the owner can touch its state from it directly.
    ///
    /// The handler MUST be `@Sendable`: TCC invokes it on a background queue, and a closure that
    /// inherited this `@MainActor` type's isolation would hard-trap under Swift 6's dynamic
    /// actor-isolation check on macOS 26 (`dispatch_assert_queue_fail`). Nonisolated + an explicit
    /// hop to the main actor is the safe shape.
    func requestAuthorization(_ done: @escaping @MainActor (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { @Sendable status in
            Task { @MainActor in done(status == .authorized) }
        }
    }

    /// Begin (or resume) always-listening. Idempotent; sets a `status` and no-ops if denied/unavailable.
    func start() {
        wantListening = true
        standingDown = false
        backoff = Self.minBackoff
        observeHardwareChanges()
        begin()
    }

    /// The user turned it off — stand down for good.
    func stop() {
        wantListening = false
        standingDown = false
        stopObservingHardwareChanges()
        teardown()
        status = .off
    }

    /// Stand down for the duration of a dictation take (its recorder needs the mic), KEEPING the
    /// user's intent so `resume()` brings listening back afterward.
    func standDown() { standingDown = true; teardown() }

    /// Resume listening after a take, if the user still wants it.
    ///
    /// **Always on a fresh engine.** This is the fix for the wake word working exactly once per
    /// launch. During a take the recorder enables voice processing on ITS engine, which
    /// reconfigures the shared input device (a different unit, often a different rate). This
    /// listener was stood down for the whole take, so the `AVAudioEngineConfigurationChange`
    /// notice that would have told it never reached it — a stopped engine gets none — and its
    /// old engine came back with the format it cached at launch. `installTap` accepted that stale
    /// format, `start()` succeeded, and the render callback then failed silently on every buffer:
    /// a stream that logged "listening" and heard nothing, forever. A new engine reads the
    /// hardware as it is now.
    func resume() {
        standingDown = false
        backoff = Self.minBackoff   // a completed take is evidence the mic works; start patient again
        guard wantListening else { return }
        teardown()
        rebuildEngine()
        begin()
    }

    /// Throw the engine away and make a new one, moving the hardware-change observer with it.
    /// Cheap (an engine with nothing connected), and the only reliable way to forget a cached
    /// input format on macOS — `reset()` alone was observed to keep it.
    private func rebuildEngine() {
        stopObservingHardwareChanges()
        audio = AVAudioEngine()
        observeHardwareChanges()
    }

    /// Rebuild listening from scratch because the audio hardware changed (wake, device swap).
    ///
    /// A plain `begin()` is not enough here: `AVAudioEngine` caches the hardware format it was
    /// configured against, so after a device change the cached format and the live one disagree —
    /// which is precisely the mismatch that raises the uncatchable exception. Tearing down first
    /// forces the next `begin()` to read the format the hardware actually has now.
    func audioHardwareChanged() {
        guard wantListening, !standingDown else { return }
        log.info("wake audio hardware changed — rebuilding")
        teardown()
        rebuildEngine()
        backoff = Self.minBackoff
        scheduleRebegin()
    }

    // MARK: - Recognition lifecycle

    private func begin() {
        guard wantListening, !listening else { return }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: break
        case .denied, .restricted: status = .denied; return
        default: status = .off; return   // not yet asked — the owner requests, then calls start()
        }
        // TRANSIENT, not terminal: `isAvailable` flaps right after login/wake and while the
        // on-device language asset is still downloading, and `supportsOnDeviceRecognition` reads
        // false until that asset lands. Returning WITHOUT a retry here was the "wake word just
        // stops working until relaunch" failure — the one begin() path that went permanently
        // deaf while every other recoverable miss re-begins on the backoff. A genuinely
        // unsupported Mac now costs one no-op probe per backoff cap instead of correctness.
        guard let recognizer, recognizer.isAvailable else {
            status = .unavailable("speech recognizer unavailable")
            log.info("wake unavailable: recognizer not available (retry in \(self.backoff, privacy: .public)s)")
            scheduleRebegin()
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            status = .unavailable("on-device speech isn't available on this Mac")
            log.info("wake unavailable: no on-device recognition (retry in \(self.backoff, privacy: .public)s)")
            scheduleRebegin()
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true    // nothing leaves the Mac
        req.shouldReportPartialResults = true
        // Bias the recognizer toward the name it exists to hear. "Nova" is not English and a
        // one-word utterance gives the language model nothing to lean on — without this hint the
        // ASR routinely writes "over"/"nover"/"no va" and the wake never fires. Contextual
        // strings are the documented seam for exactly this: rare proper nouns the stream should
        // prefer when the acoustics are ambiguous.
        req.contextualStrings = NovaAddress.contextualStrings
        request = req

        // The tap fires on a real-time audio thread; `append` is documented thread-safe. A tiny
        // Sendable box carries the request across (mirrors AudioRecorder's @unchecked-Sendable tap).
        let sink = TapSink(req)
        self.sink = sink
        let input = audio.inputNode
        // THE CRASH GUARD. `outputFormat(forBus:)` reports 0 Hz / 0 channels while the input device
        // is absent or still coming back — and handing that to `installTap` raises an Objective-C
        // exception that Swift cannot catch, aborting the whole app (see AudioSafety.swift; this is
        // the measured 2026-07-25 post-wake crash). An unusable mic must cost us a quiet retry, not
        // the cockpit.
        guard let fmt = input.safeTapFormat() else {
            request = nil
            status = .unavailable("waiting for the microphone to come back")
            log.info("wake unavailable: mic format not ready (retry in \(self.backoff, privacy: .public)s)")
            scheduleRebegin()
            return
        }
        // @Sendable is REQUIRED: the tap fires on AVFAudio's real-time thread; a closure that
        // inherited this @MainActor type's isolation would trap under the macOS 26 dynamic
        // actor-isolation check (exactly what AudioRecorder sidesteps by being @unchecked Sendable
        // rather than @MainActor). `sink` is a Sendable box, so capturing it here is safe.
        input.installTap(onBus: 0, bufferSize: 2048, format: fmt) { @Sendable buffer, _ in
            sink.append(buffer)
        }
        audio.prepare()
        do { try audio.start() } catch {
            // Recoverable, not terminal: the engine can refuse to start for the same transient
            // reasons the format check catches. Tear down and try again on the backoff rather than
            // going permanently deaf until the app is relaunched.
            status = .unavailable("couldn't open the mic for the wake word")
            log.info("wake unavailable: engine start failed \(error.localizedDescription, privacy: .public)")
            teardown()
            scheduleRebegin()
            return
        }

        // The result handler MUST be @Sendable for the same reason as `requestAuthorization` above:
        // Speech delivers it on a background queue, and a main-actor-isolated closure would trap
        // under the macOS 26 dynamic isolation check. Extract only Sendable values, then hop to main.
        task = recognizer.recognitionTask(with: req) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in self?.handle(text: text, isFinal: isFinal, failed: failed) }
        }
        listening = true
        status = .listening
        backoff = Self.minBackoff   // the mic opened — earn back the fast retry
        heardWords = false
        silentChecks = 0
        scheduleWatchdog()
        log.info("wake listening on-device (ambient utterances \(self.onUtterance != nil ? "on" : "off", privacy: .public), \(Int(fmt.sampleRate), privacy: .public) Hz)")
    }

    // MARK: - Watchdog

    /// Every few seconds, ask the tap whether audio is actually arriving. A stream can be
    /// "listening" by every flag this class holds and still be deaf — no buffers, or buffers of
    /// exact zeros (a live microphone in a silent room never produces exact zeros; a broken render
    /// path always does). Either way the cure is the same as a hardware change: a fresh engine.
    /// This is the safety net under `resume()`'s fix, and the line it logs is how the next
    /// silent failure gets named instead of guessed at.
    private static let watchdogInterval: TimeInterval = 4

    private func scheduleWatchdog() {
        watchdog?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.checkStream() }
        watchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.watchdogInterval, execute: work)
    }

    private func checkStream() {
        guard listening, let sink else { return }
        let (buffers, peak) = sink.snapshot()
        var dead: String?
        if buffers == 0 {
            dead = "no audio buffers in \(Int(Self.watchdogInterval))s"
        } else if peak == 0 {
            silentChecks += 1
            if silentChecks >= 2 { dead = "\(buffers) buffers of exact silence for \(Int(Self.watchdogInterval) * silentChecks)s" }
        } else {
            silentChecks = 0
        }
        if let dead {
            // On the BACKOFF, not the floor: a device that stays claimed (the recorder's voice
            // processing unit, before `AudioRecorder.stop` learned to release it) turned a
            // 4-second watchdog into a rebuild every 4 seconds for as long as the app ran.
            log.info("wake stream dead (\(dead, privacy: .public)) — rebuilding the engine in \(self.backoff, privacy: .public)s")
            teardown()
            rebuildEngine()
            scheduleRebegin()
            return
        }
        scheduleWatchdog()
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool) {
        // Debug, not info: partials arrive several times a second while anyone talks.
        if let text, !text.isEmpty, !heardWords {
            // Once per stream, at info: proof the recognizer is producing words on THIS engine.
            heardWords = true
            log.info("wake stream hearing words")
        }
        if failed { log.info("wake stream ended with an error (restarting)") }
        if let text, Self.heardTrigger(in: text) {
            log.info("wake trigger heard")
            quietTimer?.cancel(); quietTimer = nil
            fire()
            return   // standing down for the take — do not restart here
        }
        // The running transcript accumulates for the life of the stream; the splitter hands out
        // only the words not yet delivered, once they've sat unchanged for the quiet gap.
        if let text, onUtterance != nil {
            splitter.observe(text)
            quietTimer?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.flushUtterance(final: false) }
            quietTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + UtteranceSplitter.quietGap, execute: work)
        }
        // A recognition stream ends on final / long silence / error / the ~1-minute cap — restart it
        // so listening continues indefinitely.
        if failed || isFinal {
            flushUtterance(final: true)
            scheduleRestart()
        }
    }

    /// Deliver whatever the splitter has been holding. `final` = the stream is ending, so the
    /// words won't be revised again and any remainder is delivered even if it just changed.
    private func flushUtterance(final: Bool) {
        quietTimer?.cancel(); quietTimer = nil
        guard listening || final, let words = splitter.take(now: Date(), final: final) else { return }
        log.info("wake utterance \(words.split(separator: " ").count, privacy: .public) words (final=\(final, privacy: .public)) → reflex")
        onUtterance?(words)
    }

    /// Whether the wake name was JUST said — delegated to `NovaAddress`, which is the ONE place
    /// that knows what "Nova" sounds like once a recognizer has had its way with it. The spotter
    /// used to carry its own trigger list while the transcript parsers carried three more; they
    /// drifted, so the mic woke on sounds the parsers then failed to recognise as an address.
    static func heardTrigger(in transcript: String) -> Bool {
        NovaAddress.heardWakeName(in: transcript)
    }

    private func fire() {
        guard Date().timeIntervalSince(lastFire) > 2 else { return }   // debounce repeated partials
        lastFire = Date()
        standDown()          // hand the mic to the take's own recorder
        onWake?()
    }

    /// A recognition stream ended normally (final / silence / the ~1-minute cap) — restart it.
    private func scheduleRestart() {
        guard listening else { return }
        teardown()
        scheduleRebegin()
    }

    /// The one path back to `begin()`, on a growing delay.
    ///
    /// Guarded by INTENT (`wantListening`) rather than by current state, because the two callers
    /// that matter most reach it from opposite states: a finished recognition stream (was
    /// listening) and a mic that wasn't ready (never started). `standingDown` is the carve-out that
    /// keeps a retry from grabbing the mic while a dictation take is using it.
    private func scheduleRebegin() {
        guard wantListening, !standingDown else { return }
        restart?.cancel()
        let delay = backoff
        backoff = min(backoff * 2, Self.maxBackoff)
        let work = DispatchWorkItem { [weak self] in self?.begin() }
        restart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func teardown() {
        watchdog?.cancel(); watchdog = nil
        sink = nil
        quietTimer?.cancel(); quietTimer = nil
        splitter.reset()
        restart?.cancel(); restart = nil
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        if audio.isRunning { audio.stop() }
        audio.inputNode.removeTap(onBus: 0)
        listening = false
    }

    // MARK: - Hardware changes

    /// Listen for AVFAudio's configuration-change notice. This is what actually fires when the Mac
    /// wakes, an interface is unplugged, or output moves to headphones — the engine has already
    /// stopped itself by the time it arrives, so without this the wake word goes silently deaf and
    /// only a relaunch brings it back.
    private func observeHardwareChanges() {
        guard configObserver == nil else { return }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: audio, queue: .main
        ) { [weak self] _ in
            // The notification can arrive on any queue despite `queue: .main`; hop explicitly.
            Task { @MainActor in self?.audioHardwareChanged() }
        }
    }

    private func stopObservingHardwareChanges() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
    }
}

/// Carries the recognition request into the real-time tap block without tripping Sendable checks —
/// `append(_:)` is thread-safe by design, so a plain box is enough (same posture as `AudioRecorder`).
private final class TapSink: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    private let lock = NSLock()
    private var buffers = 0
    private var peak: Float = 0

    init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }

    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
        // Cheap per-buffer evidence for the watchdog: did audio arrive, and was any of it non-zero?
        var p: Float = 0
        if let ch = buffer.floatChannelData, buffer.frameLength > 0 {
            let n = Int(buffer.frameLength)
            let ptr = ch[0]
            var i = 0
            while i < n { let a = abs(ptr[i]); if a > p { p = a }; i += 16 }   // stride: a sample is enough
        }
        lock.lock()
        buffers += 1
        if p > peak { peak = p }
        lock.unlock()
    }

    /// Buffers delivered and the peak level since the last call, then reset.
    func snapshot() -> (buffers: Int, peak: Float) {
        lock.lock(); defer { lock.unlock() }
        let s = (buffers, peak)
        buffers = 0; peak = 0
        return s
    }
}

/// Turns a RUNNING recognition transcript (one growing string, revised as the recognizer
/// reconsiders earlier words) into discrete utterances: the words added since the last delivery,
/// released once they've stopped changing for `quietGap`. Pure and value-typed so it can be
/// exercised without a microphone.
///
/// Word-counted, not character-counted: on-device recognition rewrites recent words as context
/// arrives ("open my brows" → "open my browser"), so a character offset into the string would
/// split a word in half; dropping the first N already-delivered WORDS survives those rewrites.
struct UtteranceSplitter {
    /// Silence after the last change before the words count as a finished utterance. Shorter
    /// than a take's learned endpoint on purpose: this path only ever triggers reversible desk
    /// verbs, so a premature cut costs nothing but a missed command.
    static let quietGap: TimeInterval = 1.1
    /// Fewer words than this is noise or a fragment, never a command worth a model call.
    static let minWords = 2

    private(set) var latest: [String] = []
    private(set) var delivered = 0
    private(set) var changedAt: Date = .distantPast

    mutating func observe(_ transcript: String, now: Date = Date()) {
        let words = transcript.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        guard words != latest else { return }
        // A stream that got SHORTER restarted underneath us (a new recognition task): nothing
        // already delivered survives in it, so the offset must not either.
        if words.count < delivered { delivered = 0 }
        latest = words
        changedAt = now
    }

    /// The undelivered words, if they're worth delivering: enough of them, and — unless `final`
    /// — unchanged for the quiet gap. Marks them delivered.
    mutating func take(now: Date, final: Bool) -> String? {
        guard latest.count - delivered >= Self.minWords else { return nil }
        guard final || now.timeIntervalSince(changedAt) >= Self.quietGap - 0.05 else { return nil }
        let words = latest[delivered...].joined(separator: " ")
        delivered = latest.count
        return words
    }

    mutating func reset() {
        latest = []; delivered = 0; changedAt = .distantPast
    }
}
