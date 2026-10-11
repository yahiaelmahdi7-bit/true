import Foundation
import AVFoundation
import AppKit

/// Why Nova does not currently sound like Nova.
///
/// `VoiceEngine.speak` has always had three tiers — ElevenLabs → Voicebox → the system voice —
/// each falling through to the next "the instant it can't deliver, so Nova is never mute". That
/// design is right, and it hid a real outage for weeks: when the ElevenLabs subscription's payment
/// failed, every line 401'd, fell through twice, and came out of a 1990s formant synthesiser. From
/// the outside there is no difference between *"her voice broke"* and *"her voice was never set
/// up"* — you just hear a robot and assume the app is broken.
///
/// A fallback that is silent about falling back is a fallback that lies. This records WHY the
/// demotion happened, in the user's language, with the one action that fixes it.
enum NovaVoiceTier: String {
    case elevenLabs = "ElevenLabs"
    case voicebox = "Voicebox"
    case system = "system voice"
}

/// The specific reason Nova is off her real voice. Ordered roughly by how actionable it is.
enum NovaVoiceFault: Equatable {
    /// Speaking normally on the top tier.
    case healthy
    /// No ElevenLabs key configured — an install that simply never set the voice up.
    case noKey
    /// The account's payment failed. The single most confusing failure, because the key is valid,
    /// present, and correct — it is the invoice that is broken.
    case paymentIssue(String)
    /// The key was rejected (revoked, wrong account, or missing the text-to-speech permission).
    case unauthorized(String)
    /// Quota or rate limit — usually temporary, and worth distinguishing from a dead key.
    case rateLimited
    /// Couldn't reach the service at all (offline, DNS, timeout).
    case unreachable
    /// The service answered, but not with audio.
    case serviceError(Int)
    /// Reached the bottom tier AND this Mac has no good voice installed, so the bottom tier is as
    /// bad as it gets. Free to fix and most people don't know the download exists.
    case compactSystemVoice
}

/// Live account of which voice Nova is actually using and why.
///
/// Main-actor `ObservableObject` so Settings can render it, deliberately low-frequency: it only
/// publishes when the verdict CHANGES, so a failing tier can't turn a per-sentence failure into a
/// per-sentence view invalidation.
@MainActor
final class NovaVoiceHealth: ObservableObject {
    static let shared = NovaVoiceHealth()

    @Published private(set) var fault: NovaVoiceFault = .healthy
    @Published private(set) var tier: NovaVoiceTier = .elevenLabs
    /// When the current fault was first seen — so the UI can say "since 14:02" rather than implying
    /// it just happened.
    @Published private(set) var since: Date?

    /// Nova announces a degradation ONCE per launch, not once per sentence. Hearing "my voice
    /// service is down" in a robot voice before every single line would be a worse bug than the one
    /// it reports.
    private var spokenThisLaunch = false

    private init() {}

    /// Record the outcome of a speech attempt. Cheap and idempotent — safe to call on every line.
    func record(tier: NovaVoiceTier, fault: NovaVoiceFault) {
        let changed = (self.fault != fault) || (self.tier != tier)
        guard changed else { return }
        if fault != self.fault { since = (fault == .healthy) ? nil : Date() }
        self.fault = fault
        self.tier = tier
        if fault == .healthy { spokenThisLaunch = false }
    }

    /// Nova has fallen all the way to the built-in synthesiser for this line.
    ///
    /// This only CLAIMS the verdict when nothing more actionable already explains the demotion: a
    /// failed invoice or a rejected key restores her real voice when fixed, whereas "install a
    /// better system voice" only makes the fallback less bad. The specific fault wins; the tier is
    /// corrected either way so the readout never claims ElevenLabs while a robot is talking.
    func noteReachedSystemVoice() {
        guard !Self.hasGoodSystemVoice else {
            tier = .system
            return
        }
        if fault == .healthy {
            record(tier: .system, fault: .compactSystemVoice)
        } else {
            tier = .system
        }
    }

    /// True exactly once per distinct degradation, so a caller can say it out loud without nagging.
    func shouldAnnounceOnce() -> Bool {
        guard fault != .healthy, !spokenThisLaunch else { return false }
        spokenThisLaunch = true
        // A missing premium voice is cosmetic and only he can fix it: once EVER, not every relaunch (Settings keeps showing it).
        if fault == .compactSystemVoice {
            if UserDefaults.standard.bool(forKey: "nova.voiceNotice.compactSpoken") { return false }
            UserDefaults.standard.set(true, forKey: "nova.voiceNotice.compactSpoken")
        }
        return true
    }

    var isHealthy: Bool { fault == .healthy }

    /// One plain-English line. No status codes — the code is in `detail` for anyone who wants it.
    var headline: String {
        switch fault {
        case .healthy:            return "Nova is on her real voice."
        case .noKey:              return "Nova has no voice service set up."
        case .paymentIssue:       return "Nova's voice service has a failed payment."
        case .unauthorized:       return "Nova's voice key was rejected."
        case .rateLimited:        return "Nova's voice service is rate-limited."
        case .unreachable:        return "Nova can't reach her voice service."
        case .serviceError:       return "Nova's voice service returned an error."
        case .compactSystemVoice: return "Nova is using this Mac's most basic voice."
        }
    }

    /// What it means, and what it sounds like — written for someone who noticed the SOUND, not the
    /// HTTP status.
    var detail: String {
        switch fault {
        case .healthy:
            return "Speaking through \(tier.rawValue)."
        case .noKey:
            return "Add an ElevenLabs key below to give her a human voice. Until then she speaks "
                 + "through the built-in system voice."
        case .paymentIssue(let message):
            return "ElevenLabs is refusing every request until the latest invoice is settled, so "
                 + "she has dropped to the robotic built-in voice. \(message)"
        case .unauthorized(let message):
            return "The key is present but the service won't accept it for speech — revoked, from "
                 + "another account, or missing text-to-speech permission. \(message)"
        case .rateLimited:
            return "The account is over its limit for now. She'll return to her real voice "
                 + "automatically once it resets."
        case .unreachable:
            return "No answer from the service — usually the network. She'll recover on her own "
                 + "when it comes back."
        case .serviceError(let code):
            return "The service answered with status \(code) instead of audio. If it persists, "
                 + "check the ElevenLabs status page."
        case .compactSystemVoice:
            return "No premium or enhanced English voice is installed, so the fallback is the "
                 + "oldest, most robotic voice macOS ships. The good ones are a free download."
        }
    }

    /// The ONE action that fixes it, or nil when there is nothing the user can do.
    var remedy: String? {
        switch fault {
        case .healthy, .unreachable:
            return nil
        case .noKey, .unauthorized:
            return "Add a working key in Settings → Voice"
        case .paymentIssue:
            return "Settle the invoice at elevenlabs.io"
        case .rateLimited, .serviceError:
            return nil
        case .compactSystemVoice:
            return "Download a premium voice"
        }
    }

    /// Where `remedy` should take them. Opening the right pane beats describing a path through
    /// four levels of System Settings.
    var remedyURL: URL? {
        switch fault {
        case .paymentIssue:
            return URL(string: "https://elevenlabs.io/app/settings/billing")
        case .compactSystemVoice:
            // Spoken Content is where "Manage Voices" lives, and it is genuinely hard to find.
            return URL(string:
                "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent")
        default:
            return nil
        }
    }

    /// The short spoken form, for the one-per-launch announcement. Deliberately not a status
    /// report — it says what she sounds like and why, then stops.
    var spokenNotice: String? {
        switch fault {
        case .healthy, .unreachable, .rateLimited, .serviceError:
            return nil
        case .noKey:
            return "Sir — I have no voice service configured, so this is the built-in voice."
        case .paymentIssue:
            return "Sir — my voice service has a failed payment, so I'm on the built-in voice "
                 + "until it's settled."
        case .unauthorized:
            return "Sir — my voice key is being rejected, so I'm on the built-in voice."
        case .compactSystemVoice:
            return "Sir — this Mac has no premium voice installed, so I sound like this."
        }
    }

    /// Classify an ElevenLabs HTTP response. The body carries the useful part: a 401 alone cannot
    /// tell a revoked key from an unpaid invoice, and those need opposite actions from the user.
    nonisolated static func classify(status: Int, body: Data) -> NovaVoiceFault {
        let detail = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?
            .flatMap { $0["detail"] as? [String: Any] }
        let code = (detail?["status"] as? String) ?? (detail?["code"] as? String) ?? ""
        let message = (detail?["message"] as? String).map { String($0.prefix(160)) }
            ?? ""

        if code.contains("payment") || status == 402 {
            return .paymentIssue(message)
        }
        switch status {
        case 401, 403: return .unauthorized(message)
        case 429:      return .rateLimited
        default:       return .serviceError(status)
        }
    }

    /// Does this Mac have any English voice worth listening to? `false` means the bottom tier is
    /// the compact synthesiser and there is a free download that fixes it.
    ///
    /// Computed once — the installed voice set does not change while the app runs, and
    /// `speechVoices()` is not cheap enough to call per sentence.
    static let hasGoodSystemVoice: Bool = {
        AVSpeechSynthesisVoice.speechVoices().contains {
            $0.language.hasPrefix("en") && ($0.quality == .premium || $0.quality == .enhanced)
        }
    }()
}
