import Foundation

/// How long Nova waits in silence before deciding you have finished talking — **learned from how
/// you actually pause**, rather than fixed.
///
/// Ported from LiveKit Agents' `DynamicEndpointing` (Apache-2.0,
/// `livekit-agents/livekit/agents/voice/endpointing.py`), with its `ExpFilter` folded in. Only the
/// algorithm is borrowed; nothing of LiveKit's runtime, WebRTC session, or Python stack is
/// involved. Their insight is the part worth having:
///
/// > `min_delay` is learned from the user's pausing behavior so we don't cut off a user who
/// > pauses mid-turn.
///
/// Nova's endpointer measured the room (an adaptive noise floor — see `VoiceEngine.tickMeter`)
/// but never measured the SPEAKER. The cut-off was `config.silenceSeconds`, one number for
/// everyone, and every complaint about being cut off mid-sentence was that number being wrong for
/// this person on this day. A talker who pauses to think needs a longer wait than one who does
/// not, and neither should have to find a slider.
///
/// **The learning signal, in Nova's terms.** LiveKit runs a continuous VAD stream and learns from
/// the gaps between utterances. Nova works in discrete takes, so the equivalent evidence is a
/// CONTINUATION: a take that auto-stopped, and was then followed by more speech that belonged to
/// the same sentence (`VoiceEngine.endsMidThought` holding the fragment and reopening the mic).
/// That is a pause we cut through — proof the wait was too short — and its true length is the one
/// to learn from. Takes that end cleanly pull the estimate back down, so a single thoughtful
/// sentence cannot permanently slow the mic.
///
/// Bounded on both sides for the same reason LiveKit bounds it: the floor keeps a fast talker
/// responsive, and the ceiling stops a noisy session from learning its way into a mic that never
/// closes.
struct DynamicEndpointing {

    /// Exponential moving average with clamping — LiveKit's `ExpFilter`.
    ///
    /// `alpha` is the weight kept on HISTORY, so a high alpha means slow, stable adaptation. 0.9
    /// is their default and the right instinct here: an endpointer that lurches after one odd
    /// pause would feel broken in a way a slightly-wrong constant does not.
    private struct ExpFilter {
        let alpha: Double
        let minVal: Double
        let maxVal: Double
        private(set) var value: Double

        init(alpha: Double, initial: Double, minVal: Double, maxVal: Double) {
            self.alpha = alpha
            self.minVal = minVal
            self.maxVal = maxVal
            self.value = min(max(initial, minVal), maxVal)
        }

        mutating func apply(sample: Double) {
            let filtered = alpha * value + (1 - alpha) * sample
            value = min(max(filtered, minVal), maxVal)
        }
    }

    /// The floor — never wait less than this, however brisk the speaker.
    let minDelay: Double
    /// The ceiling — never wait longer than this, however rambling. Not learned: there is no
    /// natural upper pause to observe in a session, so it only clamps the learned value.
    let maxDelay: Double

    private var pause: ExpFilter

    /// `seed` is the user's configured `silenceSeconds`, which becomes the starting estimate —
    /// so the first take after an upgrade behaves exactly as it did before, and the learning
    /// moves off a number they already chose rather than a number we invented.
    init(seed: Double, minDelay: Double = 0.6, maxDelay: Double = 3.0, alpha: Double = 0.9) {
        let lo = min(minDelay, maxDelay)
        let hi = max(minDelay, maxDelay)
        self.minDelay = lo
        self.maxDelay = hi
        self.pause = ExpFilter(alpha: alpha, initial: seed, minVal: lo, maxVal: hi)
    }

    /// How long to wait in silence before ending the current take.
    var delay: Double { pause.value }

    /// A pause we CUT THROUGH: the take auto-stopped, and what followed turned out to belong to
    /// the same sentence. `observed` is how long that silence actually ran.
    ///
    /// Learned from the real length plus a small margin rather than from the threshold we used —
    /// learning from our own (too-short) threshold could only ever converge back onto it.
    mutating func noteInterruptedPause(_ observed: Double) {
        pause.apply(sample: observed + 0.25)
    }

    /// A take that ended and was NOT continued: the wait was long enough, and possibly longer than
    /// it needed to be. Pulls gently back toward the floor so one thoughtful sentence does not
    /// leave the mic sluggish for the rest of the session.
    mutating func noteCleanEnd() {
        pause.apply(sample: minDelay)
    }
}
