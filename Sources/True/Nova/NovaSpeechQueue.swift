import AVFoundation
import Foundation

/// The single serialization point for everything Nova says.
///
/// One request owns the output path until that path has finished. While it is active, new requests
/// wait in a deliberately tiny queue; once two are waiting, the oldest stale request is discarded.
@MainActor
final class NovaSpeechQueue {
    struct Request: Sendable {
        let line: String
        let elevenEnabled: Bool
        let elevenVoiceID: String?
        let elevenModel: String?
        let voiceboxProfile: String?
    }

    /// One active line plus at most two waiting lines is enough context without becoming narration.
    private static let backlogLimit = 2

    private let onSpeakingChanged: @MainActor @Sendable (Bool) -> Void
    private let elevenLabsOutput = NovaQueuedElevenLabsOutput()
    private let nativeOutput = NovaNativeSpeechOutput()

    private var backlog: [Request] = []
    private var activeID: UUID?
    private var activeTask: Task<Void, Never>?

    private static var personalVoiceRequested = false

    init(onSpeakingChanged: @escaping @MainActor @Sendable (Bool) -> Void) {
        self.onSpeakingChanged = onSpeakingChanged
    }

    func enqueue(_ request: Request) {
        guard activeTask == nil else {
            backlog.append(request)
            if backlog.count > Self.backlogLimit {
                backlog.removeFirst(backlog.count - Self.backlogLimit)
            }
            return
        }

        start(request)
    }

    /// Stop the active output and invalidate its completion before clearing every waiting line.
    func shutUp() {
        backlog.removeAll(keepingCapacity: true)
        activeID = nil

        let task = activeTask
        activeTask = nil
        task?.cancel()

        elevenLabsOutput.stop()
        nativeOutput.stop()
        onSpeakingChanged(false)
    }

    private func start(_ request: Request) {
        let id = UUID()
        activeID = id
        onSpeakingChanged(true)

        activeTask = Task { [weak self] in
            guard let self else { return }
            await self.deliver(request)
            self.finished(id)
        }
    }

    private func finished(_ id: UUID) {
        // `shutUp()` invalidates the ID before resuming/cancelling any in-flight continuation. An
        // old task can therefore never finish a newer line or advance its queue.
        guard activeID == id else { return }
        activeID = nil
        activeTask = nil

        guard !backlog.isEmpty else {
            onSpeakingChanged(false)
            return
        }

        start(backlog.removeFirst())
    }

    /// Keep the established fallback contract exactly ordered: ElevenLabs, Voicebox, native.
    private func deliver(_ request: Request) async {
        if request.elevenEnabled, NovaElevenLabs.isConfigured,
           await elevenLabsOutput.speak(
               request.line,
               voiceID: request.elevenVoiceID,
               model: request.elevenModel
           ) {
            return
        }

        guard !Task.isCancelled else { return }

        guard !Task.isCancelled else { return }
        await speakNative(request.line)
    }

    private func speakNative(_ line: String) async {
        // Preserve the existing lazy Personal Voice prompt: it appears only if the native tier is
        // actually reached, and at most once in this process.
        if !Self.personalVoiceRequested,
           AVSpeechSynthesizer.personalVoiceAuthorizationStatus == .notDetermined {
            Self.personalVoiceRequested = true
            _ = await AVSpeechSynthesizer.requestPersonalVoiceAuthorization()
        }

        guard !Task.isCancelled else { return }

        // Reaching this tier is the moment the user actually HEARS the problem, so it is the
        // honest place to record it — not the moment a request failed somewhere they can't see.
        let health = NovaVoiceHealth.shared
        health.noteReachedSystemVoice()

        // Say WHY, once per launch, folded into the line she was already going to speak. A robot
        // voice with no explanation reads as "the app is broken"; the same voice saying "my voice
        // service has a failed payment" reads as a system that knows its own state. Prepending
        // rather than enqueuing keeps it one utterance — a separate line would be the second half
        // of the pile-up this whole file exists to prevent.
        var spoken = line
        if let notice = health.spokenNotice, health.shouldAnnounceOnce() {
            spoken = notice + " " + line
        }

        let utterance = AVSpeechUtterance(string: spoken)
        utterance.voice = Self.currentNativeVoice()
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.05
        await nativeOutput.speak(utterance)
    }

    /// The best voice available right now: Personal Voice first, then the installed quality ladder.
    private static func currentNativeVoice() -> AVSpeechSynthesisVoice? {
        if AVSpeechSynthesizer.personalVoiceAuthorizationStatus == .authorized,
           let personal = AVSpeechSynthesisVoice.speechVoices().first(where: {
               $0.voiceTraits.contains(.isPersonalVoice) && $0.language.hasPrefix("en")
           }) {
            return personal
        }
        return bestNativeVoice
    }

    private static let bestNativeVoice: AVSpeechSynthesisVoice? = {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        return english.first { $0.quality == .premium }
            ?? english.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }()
}

/// Owns ElevenLabs playback for the queue so completion means the clip actually ended, rather than
/// merely that `AVAudioPlayer.play()` accepted it.
///
/// Only PLAYBACK lives here. Synthesis, the on-disk cache and failure classification stay in
/// ``NovaElevenLabs/clip(_:voiceID:model:)`` — there is one ElevenLabs client in the app, and it is
/// the one that reports to ``NovaVoiceHealth``.
@MainActor
private final class NovaQueuedElevenLabsOutput {
    private let delegate = NovaAudioPlayerDelegate()
    private var player: AVAudioPlayer?

    func speak(_ line: String, voiceID: String?, model: String?) async -> Bool {
        guard let data = await NovaElevenLabs.clip(
            line,
            voiceID: voiceID,
            model: model
        ), !Task.isCancelled,
              let player = try? AVAudioPlayer(data: data) else { return false }

        self.player = player
        player.delegate = delegate
        player.prepareToPlay()

        let id = ObjectIdentifier(player)
        let started = await withCheckedContinuation { continuation in
            delegate.install(continuation, for: id)
            if !player.play() {
                delegate.complete(id, returning: false)
            }
        }

        if self.player === player { self.player = nil }
        return started
    }

    func stop() {
        player?.stop()
        player = nil
        // `AVAudioPlayer.stop()` does not promise a delegate callback. Resume the waiter directly;
        // a later callback is harmless because the delegate atomically removed the continuation.
        delegate.cancel()
    }
}

/// Retained by `NovaQueuedElevenLabsOutput`. The lock is required because AVFoundation owns the
/// callback thread; taking the continuation out under the lock makes finish/cancel exactly-once.
private final class NovaAudioPlayerDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: (id: ObjectIdentifier, continuation: CheckedContinuation<Bool, Never>)?

    func install(_ continuation: CheckedContinuation<Bool, Never>, for id: ObjectIdentifier) {
        lock.lock()
        let displaced = pending?.continuation
        pending = (id, continuation)
        lock.unlock()
        displaced?.resume(returning: true)
    }

    func complete(_ id: ObjectIdentifier, returning result: Bool = true) {
        lock.lock()
        let continuation: CheckedContinuation<Bool, Never>?
        if pending?.id == id {
            continuation = pending?.continuation
            pending = nil
        } else {
            continuation = nil
        }
        lock.unlock()
        continuation?.resume(returning: result)
    }

    func cancel() {
        lock.lock()
        let continuation = pending?.continuation
        pending = nil
        lock.unlock()
        continuation?.resume(returning: true)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        complete(ObjectIdentifier(player))
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        complete(ObjectIdentifier(player))
    }
}

/// Bridges AVSpeechSynthesizer's delegate-only completion API into an awaitable operation.
@MainActor
private final class NovaNativeSpeechOutput {
    private let synthesizer = AVSpeechSynthesizer()
    private let delegate = NovaSpeechSynthesizerDelegate()

    init() {
        synthesizer.delegate = delegate
    }

    func speak(_ utterance: AVSpeechUtterance) async {
        let id = ObjectIdentifier(utterance)
        await withCheckedContinuation { continuation in
            delegate.install(continuation, for: id)
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        _ = synthesizer.stopSpeaking(at: .immediate)
        // `stopSpeaking` may invoke didCancel synchronously, asynchronously, or not at all when the
        // utterance has not started. Both paths meet here; the delegate's take-and-nil wins once.
        delegate.cancel()
    }
}

/// AVFoundation does not guarantee which thread invokes these callbacks. The only shared value is
/// the lock-protected continuation, and both didFinish and didCancel race through the same one-shot.
private final class NovaSpeechSynthesizerDelegate: NSObject,
    AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: (id: ObjectIdentifier, continuation: CheckedContinuation<Void, Never>)?

    func install(_ continuation: CheckedContinuation<Void, Never>, for id: ObjectIdentifier) {
        lock.lock()
        let displaced = pending?.continuation
        pending = (id, continuation)
        lock.unlock()
        displaced?.resume()
    }

    func complete(_ id: ObjectIdentifier) {
        lock.lock()
        let continuation: CheckedContinuation<Void, Never>?
        if pending?.id == id {
            continuation = pending?.continuation
            pending = nil
        } else {
            continuation = nil
        }
        lock.unlock()
        continuation?.resume()
    }

    func cancel() {
        lock.lock()
        let continuation = pending?.continuation
        pending = nil
        lock.unlock()
        continuation?.resume()
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        complete(ObjectIdentifier(utterance))
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        complete(ObjectIdentifier(utterance))
    }
}
