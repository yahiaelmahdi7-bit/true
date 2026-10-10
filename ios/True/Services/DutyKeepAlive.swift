import AVFoundation
import Observation

/// "On duty": keeps True running in the background so a pane that needs you reaches the lock screen within one poll.
///
/// How: a silent audio session. `.playback` + `.mixWithOthers` and a running AVAudioEngine that renders zeros, with
/// `UIBackgroundModes: audio`, stops iOS from suspending the app. The normal poll loop (AppModel.startPolling) keeps
/// running and posts the notifications. No sound is ever played and other apps' audio is not interrupted.
///
/// Honest cost: the phone never sleeps True's process, so it uses some battery while on duty (the audio engine is
/// cheap, the 10 s network poll is the bigger part), and it only works while the Mac is reachable on the network.
/// A phone call, Siri or another app taking the audio session pauses it; we resume on the interruption's end.
/// If iOS or the user kills the app it is off until True is opened again (there is no push server to wake it).
@MainActor @Observable
final class DutyKeepAlive {
    static let shared = DutyKeepAlive()

    private(set) var active = false
    private var engine: AVAudioEngine?
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard !active else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch { return }
        guard run() else { return }
        active = true
        let nc = NotificationCenter.default
        observers = [
            nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
                let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let type = raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:))
                MainActor.assumeIsolated { if type == .ended { self?.resume() } }
            },
            nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resume() }
            },
            nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resume() }
            },
            nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.engine = nil; self?.resume() }
            },
        ]
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        engine?.stop(); engine = nil
        active = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func resume() {
        guard active else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        if engine?.isRunning != true { _ = run() }
    }

    /// Build (or rebuild) the engine with a source node that renders silence.
    private func run() -> Bool {
        engine?.stop()
        let e = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let silence = AVAudioSourceNode(format: format) { _, _, _, buffers in
            for b in UnsafeMutableAudioBufferListPointer(buffers) { memset(b.mData, 0, Int(b.mDataByteSize)) }
            return noErr
        }
        e.attach(silence)
        e.connect(silence, to: e.mainMixerNode, format: format)
        do { try e.start() } catch { return false }
        engine = e
        return true
    }
}
