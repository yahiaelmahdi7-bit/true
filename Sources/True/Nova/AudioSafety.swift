@preconcurrency import AVFoundation

/// Guards every microphone tap Axon installs against the one thing AVFAudio will not tolerate:
/// a format the hardware can't actually produce.
///
/// This exists because of a measured crash (2026-07-25, PID 28189, `Time Since Wake: 1632`).
/// The Mac slept; ~27 minutes after waking, `WakeListener.scheduleRestart()` re-entered `begin()`
/// and called `installTap(onBus:bufferSize:format:)` with whatever `outputFormat(forBus: 0)`
/// returned. On a machine whose audio input has not finished coming back, that is a **0 Hz,
/// 0-channel** format — and `AVAudioEngineImpl::InstallTapOnNode` responds by raising an
/// Objective-C `NSException`.
///
/// Swift cannot catch an `NSException`. There is no `try` that helps, no `do/catch` that runs: the
/// exception unwinds straight past Swift's error handling into `abort()`, and the entire cockpit
/// dies — desk agents, terminal panes, in-flight chat turns and all. The crash log's last Swift
/// frame was `WakeWord.swift:89`, and the frame above it was the restart timer, which fires every
/// 0.3 s: so once the machine woke into a bad audio state, the app was in a guaranteed abort loop.
///
/// The rule this encodes: **never hand AVFAudio a format you have not checked.** Validation is the
/// only defence available, because the failure mode is an uncatchable exception rather than an
/// error — by the time you could "handle" it, the process is already gone.
extension AVAudioNode {

    /// The tap format for `bus`, or `nil` when the hardware is not in a usable state right now.
    ///
    /// `nil` is a completely normal, expected answer — not an error worth surfacing. It means
    /// "the input device isn't ready yet", which is exactly what a Mac reports in the seconds (or
    /// occasionally minutes) after waking, while switching outputs, when a USB interface is
    /// unplugged, or when Bluetooth headphones are mid-handoff. The caller's job is to back off and
    /// ask again later, never to force it.
    func safeTapFormat(bus: AVAudioNodeBus = 0) -> AVAudioFormat? {
        let format = outputFormat(forBus: bus)
        // Precisely the condition AVFAudio asserts on internally
        // (`IsFormatSampleRateAndChannelCountValid`). Checking it here turns an uncatchable
        // process abort into an ordinary `nil` we can schedule around.
        guard format.sampleRate > 0, format.channelCount > 0 else { return nil }
        return format
    }
}

/// Why a microphone couldn't be opened — a real Swift error, so callers get to `catch` instead of
/// discovering the answer in a crash report.
enum AudioSetupError: LocalizedError {
    /// The input device exists but isn't reporting a usable format yet (the post-wake case).
    case inputNotReady

    var errorDescription: String? {
        switch self {
        case .inputNotReady:
            return "the microphone isn't ready yet — the audio device is still coming back"
        }
    }
}
