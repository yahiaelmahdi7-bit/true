import Foundation
import AVFoundation

/// Nova's human voice.
///
/// The tier below this one — `AVSpeechSynthesizer` — is a 1990s formant synthesiser with a nicer
/// coat of paint. It is *intelligible*, which is a different thing from *listenable*, and an
/// assistant you have to endure is an assistant you stop talking to. ElevenLabs is the top tier of
/// `VoiceEngine.speak`: ElevenLabs → Voicebox (local) → system voice, each falling through to the
/// next the moment it can't deliver, so Nova is never mute.
///
/// **The key never travels through chat, argv, or a plist.** It lives in the Keychain via `Vault`,
/// exactly like every other provider key Axon holds. A one-time handoff file (written by
/// `pbpaste`, mode 0600) is imported and immediately shredded — see `importKeyIfPresent`.
enum NovaElevenLabs {

    // MARK: Configuration

    /// A pleasing alto that reads as a capable colleague rather than a voice actor — chosen by ear
    /// against the rest of the roster. Overridable in Settings → Voice.
    static let defaultVoiceID = "XrExE9yKIg1WjnnlVkGX"   // Matilda — professional, agent, audiobook
    static let defaultVoiceName = "Matilda"

    /// Measured on this account, same voice, same sentence: `eleven_turbo_v2_5` ~0.9 s to a finished
    /// clip, `eleven_v3` ~3.9 s. v3 is the more expressive model, but four seconds is past the point
    /// where a confirmation is still a confirmation — you've already moved on — so turbo is the
    /// default and v3 is one pick away in Settings for anyone who'd rather have the expression.
    ///
    /// The `Cache` below makes the first cost the only cost either way: Nova's lines are a small
    /// recurring set, so each distinct one is synthesized once and instant every time after.
    static let defaultModel = "eleven_turbo_v2_5"

    /// The expressive alternative, offered in Settings.
    static let expressiveModel = "eleven_v3"

    /// Selectable models, fastest first — what Settings → Voice lists.
    static let models: [(id: String, label: String)] = [
        ("eleven_flash_v2_5", "Flash — fastest, flattest"),
        ("eleven_turbo_v2_5", "Turbo — fast, natural (default)"),
        ("eleven_v3",         "v3 — most expressive, ~4s"),
        ("eleven_multilingual_v2", "Multilingual v2 — steady"),
    ]

    private static let vaultAccount = "elevenlabs"

    /// Where `pbpaste` drops the key for a one-time import.
    private static var handoffURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Axon/.elevenlabs.import")
    }

    /// Move a handed-off key into the Keychain and remove the file. Idempotent and cheap, so it can
    /// be called on every access — there is no moment where the key sits in two places for long.
    @discardableResult
    static func importKeyIfPresent() -> Bool {
        let url = handoffURL
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return false }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            // Overwrite before unlinking: removing a file leaves its blocks readable until reused.
            try? Data(repeating: 0, count: max(raw.count, 1)).write(to: url)
            try? FileManager.default.removeItem(at: url)
        }
        guard !key.isEmpty else { return false }
        return Vault.set(vaultAccount, key)
    }

    /// In-process cache of the key.
    ///
    /// Every `SecItemCopyMatching` against a locally-signed binary can raise the "Axon wants to use
    /// your keychain" prompt. `isConfigured` is read from a SwiftUI view body, and view bodies
    /// re-evaluate constantly — so an uncached read meant a Keychain hit (and a possible prompt) on
    /// *every render*. The Keychain is now touched at most once per launch, and again only when the
    /// key is deliberately changed.
    ///
    /// `nil` = not yet read; `""` = read and genuinely absent (a negative result is cached too,
    /// otherwise an install with no key would re-prompt forever).
    /// Lock-guarded rather than actor-isolated: `apiKey` is read both from view bodies (main actor)
    /// and from the detached task that synthesizes speech, and making it `@MainActor` would force
    /// the audio path to hop threads for what is a single string read.
    private nonisolated(unsafe) static var cachedKey: String?
    private static let cacheLock = NSLock()

    static var apiKey: String {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cachedKey { return cachedKey }
        importKeyIfPresent()
        let key = Vault.get(vaultAccount, envFallback: ["ELEVENLABS_API_KEY", "ELEVEN_API_KEY"]) ?? ""
        cachedKey = key
        return key
    }

    /// Is a key available? Answered from the Keychain's *metadata*, so it never prompts and never
    /// needs the value — see ``Vault/exists(_:)``.
    ///
    /// This used to be `!apiKey.isEmpty`, which meant the render-time question "is the voice set
    /// up?" performed a real secret read. The cache below made it once per launch rather than once
    /// per frame, but once per launch is still a password dialog standing between you and the app —
    /// one of three that made a cold start cost three prompts. The value itself is now fetched only
    /// where it's genuinely used: `speak`.
    static var isConfigured: Bool {
        cacheLock.lock()
        let cached = cachedKey
        cacheLock.unlock()
        if let cached { return !cached.isEmpty }   // already read this launch — free and exact
        return Vault.has(vaultAccount, envFallback: ["ELEVENLABS_API_KEY", "ELEVEN_API_KEY"])
    }

    static func setKey(_ key: String) {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        Vault.set(vaultAccount, clean)
        cacheLock.lock()
        cachedKey = clean
        cacheLock.unlock()
    }

    static func clearKey() {
        Vault.delete(vaultAccount)
        cacheLock.lock()
        cachedKey = ""
        cacheLock.unlock()
    }

    /// Read the key once at launch, off the critical path, so the single unavoidable Keychain hit
    /// happens at a predictable moment instead of mid-render or mid-sentence.
    /// Import a handed-off key file if one is waiting. **No longer reads the Keychain.**
    ///
    /// It used to be `_ = apiKey`, deliberately spending one prompt at launch so no later view
    /// render could trigger one. That trade is obsolete now `isConfigured` answers from metadata:
    /// the launch prompt is gone AND renders stay free. The file import stays — it's a plain
    /// filesystem read, and a key waiting to be adopted should still be adopted at a predictable
    /// moment rather than whenever Nova first happens to speak.
    static func warmKeyCache() { importKeyIfPresent() }

    // MARK: Speaking

    /// Synthesize and play `text`. Returns whether ElevenLabs actually spoke it — `false` means the
    /// caller should fall through to the next voice tier rather than leaving Nova silent.
    ///
    /// Deliberately awaits the full MP3 before playing rather than streaming it into an audio queue:
    /// Nova's lines are one or two sentences, the flash model returns them in a few hundred
    /// milliseconds, and a single complete buffer can't produce the mid-word stutter a starved
    /// stream would. Long-form narration would justify real streaming; a confirmation does not.
    /// The finished MP3 for `text`, from cache or from the API — **without playing it**.
    ///
    /// Playback lives in ``NovaSpeechQueue`` so that "this line is done" means the audio actually
    /// ended rather than that `play()` was accepted; synthesis, caching and health classification
    /// stay here so there is exactly ONE ElevenLabs client in the app. `nil` means the caller should
    /// fall through to the next voice tier, and by the time it returns `nil`, ``NovaVoiceHealth``
    /// already knows why.
    static func clip(_ text: String, voiceID: String?, model: String?) async -> Data? {
        let key = apiKey
        guard !key.isEmpty else {
            await NovaVoiceHealth.shared.record(tier: .system, fault: .noKey)
            return nil
        }
        let voice = (voiceID?.isEmpty == false) ? voiceID! : defaultVoiceID
        let modelID = (model?.isEmpty == false) ? model! : defaultModel

        // A line said before is a line already synthesized. This is what makes the slow, good model
        // usable for confirmations.
        if let cached = Cache.read(text: text, voice: voice, model: modelID) {
            await NovaVoiceHealth.shared.record(tier: .elevenLabs, fault: .healthy)
            return cached
        }

        guard let url = URL(string:
            "https://api.elevenlabs.io/v1/text-to-speech/\(voice)?output_format=mp3_44100_128")
        else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Sized for `eleven_v3`, which takes ~4 s for a sentence — an 8 s timeout would have cut off
        // every line on a slow network and silently demoted Nova to the system voice.
        req.timeoutInterval = 20
        // `eleven_v3` treats `stability` as three discrete modes (0.0 creative / 0.5 natural /
        // 1.0 robust) rather than a continuous dial, so 0.5 is deliberate, not a rounded guess.
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "text": text,
            "model_id": modelID,
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75,
                "use_speaker_boost": true,
            ],
        ])

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 500
            guard status < 300, !data.isEmpty else {
                // The body is the only thing that can tell a revoked key from an unpaid invoice,
                // and those need opposite actions from the user — so classify before demoting.
                let fault = NovaVoiceHealth.classify(status: status, body: data)
                await NovaVoiceHealth.shared.record(tier: .system, fault: fault)
                return nil
            }
            Cache.write(data, text: text, voice: voice, model: modelID)
            await NovaVoiceHealth.shared.record(tier: .elevenLabs, fault: .healthy)
            return data
        } catch {
            await NovaVoiceHealth.shared.record(tier: .system, fault: .unreachable)
            return nil
        }
    }

    /// Synthesize a line ahead of time without playing it, so its first real utterance is instant.
    /// Used to warm Nova's stock confirmations after a voice change.
    static func prewarm(_ lines: [String], voiceID: String?, model: String?) async {
        let voice = (voiceID?.isEmpty == false) ? voiceID! : defaultVoiceID
        let modelID = (model?.isEmpty == false) ? model! : defaultModel
        for line in lines where Cache.read(text: line, voice: voice, model: modelID) == nil {
            _ = await synthesizeOnly(line, voice: voice, model: modelID)
        }
    }

    private static func synthesizeOnly(_ text: String, voice: String, model: String) async -> Bool {
        let key = apiKey
        guard !key.isEmpty,
              let url = URL(string:
                "https://api.elevenlabs.io/v1/text-to-speech/\(voice)?output_format=mp3_44100_128")
        else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "text": text, "model_id": model,
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75, "use_speaker_boost": true],
        ])
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              ((resp as? HTTPURLResponse)?.statusCode ?? 500) < 300, !data.isEmpty else { return false }
        Cache.write(data, text: text, voice: voice, model: model)
        return true
    }

    /// Nova's recurring stock lines — the ones worth having ready before you ever hear them.
    static let stockLines = [
        "On it.",
        "Done.",
        "Bringing the whole crew in, sir.",
        "Clearing the desk, sir.",
        "That's with Ben.",
        "I couldn't reach that one.",
        "Nova here. I can hear you, and I'll talk back.",
    ]

    // MARK: Cache

    /// MP3s on disk, keyed by exactly what produced them. Changing the voice or the model changes
    /// the key, so a stale clip in an old voice can never be played back as the new one.
    private enum Cache {
        private static var dir: URL {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            return base.appendingPathComponent("Axon/VoiceCache", isDirectory: true)
        }

        /// Bounded so a session of long spoken answers can't fill the disk.
        private static let maxFiles = 400

        private static func url(text: String, voice: String, model: String) -> URL {
            // A stable, filename-safe digest of the three inputs. FNV-1a rather than CryptoKit:
            // this is a cache key, not a security boundary, and it keeps the file dependency-free.
            var hash: UInt64 = 0xcbf29ce484222325
            for byte in Array("\(model)|\(voice)|\(text)".utf8) {
                hash = (hash ^ UInt64(byte)) &* 0x100000001b3
            }
            return dir.appendingPathComponent(String(format: "%016llx.mp3", hash))
        }

        static func read(text: String, voice: String, model: String) -> Data? {
            try? Data(contentsOf: url(text: text, voice: voice, model: model))
        }

        static func write(_ data: Data, text: String, voice: String, model: String) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: url(text: text, voice: voice, model: model), options: [.atomic])
            prune()
        }

        /// Drop the oldest clips once the directory outgrows `maxFiles`.
        private static func prune() {
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey]),
                  files.count > maxFiles else { return }
            let sorted = files.sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return a < b
            }
            for url in sorted.prefix(files.count - maxFiles) { try? fm.removeItem(at: url) }
        }
    }

    /// Fetch the account's voices for the Settings picker. Returns `[]` on any failure — the picker
    /// then just shows the current selection rather than an error state nobody can act on.
    static func voices() async -> [ElevenVoice] {
        let key = apiKey
        guard !key.isEmpty, let url = URL(string: "https://api.elevenlabs.io/v1/voices") else { return [] }
        var req = URLRequest(url: url)
        req.setValue(key, forHTTPHeaderField: "xi-api-key")
        req.timeoutInterval = 8
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              ((resp as? HTTPURLResponse)?.statusCode ?? 500) < 300,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["voices"] as? [[String: Any]] else { return [] }

        return list.compactMap { v in
            guard let id = v["voice_id"] as? String, let name = v["name"] as? String else { return nil }
            let labels = v["labels"] as? [String: Any] ?? [:]
            let descriptors = ["gender", "accent", "description"]
                .compactMap { labels[$0] as? String }
                .filter { !$0.isEmpty }
            return ElevenVoice(id: id, name: name, descriptor: descriptors.joined(separator: " · "))
        }
    }
}

/// One selectable voice.
struct ElevenVoice: Identifiable, Hashable {
    let id: String
    let name: String
    let descriptor: String

    /// ElevenLabs bakes the character sketch into the name ("Sarah - Mature, Reassuring,
    /// Confident"). Split it so the picker can show a name and a subtitle instead of one long line.
    var shortName: String {
        name.components(separatedBy: " - ").first?.trimmingCharacters(in: .whitespaces) ?? name
    }
    var character: String {
        let parts = name.components(separatedBy: " - ")
        guard parts.count > 1 else { return descriptor }
        return parts.dropFirst().joined(separator: " - ")
    }
}
