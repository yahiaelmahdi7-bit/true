import Foundation

/// **Hearing your own name.** The one place that knows what "Nova" sounds like after a speech
/// recognizer has had its way with it — and therefore the one place that decides whether an
/// utterance was addressed to her at all.
///
/// Before this, four separate pieces of the app each carried their own private idea of the wake
/// cue: the always-listening spotter (`WakeListener.triggers`), `CrewStore.spokenTokens`,
/// `CrewStore.globalDirective`, and nothing at all in `looseResolve`. They disagreed — the spotter
/// knew the mishears, the parsers only knew the literal spellings, and `looseResolve` didn't strip
/// the address, so "Nova, Ben fix the tests" lost Ben and went to the model. Four lists is four
/// chances to drift; hearing your own name is one behaviour and belongs in one type.
///
/// Pure value logic — Foundation only, no actor, no I/O — so both the real-time spotter (off the
/// main actor, on a recognition callback) and the main-actor parsers can call it, and so it can be
/// exercised standalone.
///
/// ## The two safety tiers
/// A wake name is a security boundary in miniature: match too loosely and ordinary dictation gets
/// typed into a live agent's terminal; match too tightly and she never answers. So variants come in
/// two tiers:
/// * **strong** — spellings no English sentence produces by accident ("novah", "nover", "no va").
///   Safe to match on their own.
/// * **weak** — real English words the recognizer genuinely emits for this sound ("over" is the
///   single most common one). Matched ONLY when a greeting sits immediately in front, because
///   "hey over" is a person calling a name and "move it over" never is.
///
/// ## Where each tier is allowed to fire
/// The weak tier is used by the always-listening spotter and NOWHERE else, because the two callers
/// pay wildly different prices for being wrong. A false wake costs an open microphone — the empty
/// take behind it is already handled, and you notice and move on. A false ADDRESS costs your
/// dictation being typed into a live agent's terminal, which nothing undoes. So `read` — the half
/// that decides where your words LAND — takes only the strong and split tiers, and "Hi Noah, can
/// you send the file" stays the sentence you dictated. Same doctrine already written into
/// `CrewStore.resolveTarget`: what strict matching misses, the dispatcher model still catches;
/// what loose matching costs is unrecoverable.
enum NovaAddress {

    // MARK: - What her name sounds like

    /// Openers that mark what follows as an address rather than a sentence.
    static let greetings: Set<String> = [
        "hey", "hi", "hello", "yo", "ok", "okay", "hiya", "hay", "heya",
    ]

    /// Spellings that are unmistakably the name — none is an English word, so they may match with
    /// no greeting in front. The `nova…` stem is handled separately (see `isStrongName`) because
    /// the recognizer likes to hang a letter off the end ("novas", "novah", "novak").
    ///
    /// The failure modes behind each: the final schwa heard as "-er" (nover), /v/ devoiced to /f/
    /// or stopped to /b/ (nofa, noba), the first vowel lengthened or reduced (noova, nuva, nuhva),
    /// the final vowel fronted (nove), and the initial /n/ misheard as a liquid (lova, rova).
    static let strongNames: Set<String> = [
        "nover", "nofa", "noba", "noova", "nuva", "nuhva", "nove", "novia", "nowa", "knova",
        "novo", "lova", "rova",
    ]

    /// Two-token hearings — the recognizer splits the name when it can't place the sound.
    /// "know va" is the one Apple's on-device model produces most.
    static let splitNames: [[String]] = [
        ["no", "va"], ["know", "va"], ["no", "vah"], ["know", "vah"],
        ["no", "vuh"], ["know", "vuh"], ["nuh", "va"], ["nova", "uh"],
    ]

    /// Real words the recognizer emits for /ˈnoʊvə/. Each one is common enough in ordinary speech
    /// that matching it bare would be a menace, so these fire only directly after a greeting.
    /// "Over" leads the list on measured evidence — it is what this app's own on-device recognizer
    /// wrote for a bare "Nova" often enough to be named in `WakeWord`'s original comment — and
    /// "Noah" is the same sound with the /v/ dropped entirely.
    static let weakNames: Set<String> = [
        "over", "noah", "noa", "hover", "ova", "nope",
    ]

    /// Greeting and name fused into ONE real word: Apple's on-device model writes "Hey Nova" as "Hangover"
    /// (measured 2026-10-11, every "Hey Nova" in a live test). Being English, it counts only where the recognizer
    /// itself judged a sentence START (capitalised) and no article sits in front: "Hangover, what time is it"
    /// wakes; "I have a hangover" and "watch The Hangover" never do. Spotter + live-stream slicing only, like `weakNames`.
    static let fusedNames: Set<String> = ["hangover"]
    private static let fusedBlockers: Set<String> = ["a", "an", "the", "my", "your", "his", "her", "their", "our", "this", "that", "no"]
    static func isFusedCall(_ words: [String], at i: Int, capitalized: Bool) -> Bool {
        capitalized && fusedNames.contains(words[i]) && (i == 0 || !fusedBlockers.contains(words[i - 1]))
    }

    /// Decoration between a greeting and the name — "hey **there** Nova". Only ever consumed once a
    /// greeting has been seen, so a sentence merely starting with one of these is left alone.
    private static let greetedFillers: Set<String> = ["there", "um", "uh", "so", "yo", "hey"]

    /// Decoration between the name and the actual instruction — "Nova, **please** launch the crew".
    ///
    /// Vocative decoration ONLY. Words like "look", "listen" and "now" read as filler but are real
    /// verbs and real time-words in this app's vocabulary — shedding them turns "Nova, look at
    /// Jeff's window" into "at Jeff's window", which is an instruction with its verb amputated.
    private static let postNameFillers: Set<String> = ["please", "there", "um", "uh", "so", "hey"]

    /// Politeness bridges right after the name. Shedding these is what turns "Nova, could you
    /// launch the crew" into the deterministic `.launchCrew` desk verb instead of a trip to the
    /// dispatcher model — same words, a third of the latency, and an answer that can't vary.
    private static let postNameBridges: [[String]] = [
        ["can", "you"], ["could", "you"], ["would", "you"], ["will", "you"], ["can", "u"],
        ["do", "me", "a", "favor"], ["do", "me", "a", "favour"],
    ]

    /// Follow-ups that add no instruction — she was called, not asked. "Nova, you there?" wants the
    /// same thing "Nova?" wants: an answer and an open mic.
    private static let summonsTails: Set<String> = [
        "", "you there", "are you there", "you up", "you awake", "you with me", "you listening",
        "are you listening", "can you hear me", "could you hear me", "can you hear me now",
        "do you hear me", "come in", "hello", "hi", "hey",
        "wake up", "you busy", "are you busy", "got a second", "you got a second",
    ]

    /// Phrases handed to `SFSpeechRecognitionRequest.contextualStrings` to bias the recognizer
    /// toward the name it exists to hear. Lives here so the bias and the matching can't describe
    /// different words.
    static let contextualStrings = ["Nova", "Hey Nova", "Hi Nova", "OK Nova", "Nova, launch the crew"]

    /// True when a single token is unambiguously the name. The `nova` stem stays suffix-open (the
    /// recognizer writes "novas"/"novah"/"novak" for the same sound) but is length-capped, so
    /// "novel", "novice" and "November" can never come in through the back door.
    ///
    /// Letters only, deliberately: it keeps the POSSESSIVE out. "Nova's design is broken" is a
    /// sentence ABOUT her, not one addressed TO her, and without this guard the six-character
    /// "nova's" walks straight into the stem rule and the subject of the sentence gets eaten.
    static func isStrongName(_ token: String) -> Bool {
        guard !token.isEmpty, token.allSatisfy(\.isLetter) else { return false }
        if strongNames.contains(token) { return true }
        return token.hasPrefix("nova") && token.count <= 6
    }

    // MARK: - Reading the opening of an utterance

    /// What the front of a transcript turned out to be.
    struct Reading: Equatable {
        /// The utterance with any address consumed — the words that carry the actual instruction,
        /// in their ORIGINAL casing and punctuation (this text gets typed into a live PTY, so it
        /// must never come back lowercased).
        var rest: String
        /// Her name was actually heard — as opposed to a bare greeting being shed.
        var namedNova: Bool
        /// She was called and asked for nothing: "Nova", "Hey Nova", "Nova, you there?".
        var isSummons: Bool
    }

    /// Read the opening of `transcript`: shed a greeting, then her name, then the decoration that
    /// follows it, and report what's left.
    ///
    /// Always returns a `Reading` — an utterance that addresses nobody comes back untouched with
    /// `namedNova == false`, so callers can use this unconditionally instead of branching first.
    static func read(_ transcript: String) -> Reading {
        let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = raw.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
        guard !tokens.isEmpty else { return Reading(rest: "", namedNova: false, isSummons: false) }
        let norm = tokens.map(normalized)

        var i = 0
        var greeted = false
        // 1. Greetings, and the filler that rides along with them ("hey there …").
        while i < tokens.count {
            if greetings.contains(norm[i]) { greeted = true; i += 1; continue }
            if greeted, greetedFillers.contains(norm[i]) { i += 1; continue }
            break
        }

        // 2. The name itself. Split hearings are tried before single tokens because "no va" must be
        //    read as one name, not as the word "no" followed by a task.
        var named = false
        if i + 1 < tokens.count,
           splitNames.contains(where: { $0[0] == norm[i] && $0[1] == norm[i + 1] }) {
            named = true; i += 2
        } else if i < tokens.count, isStrongName(norm[i]) {
            named = true; i += 1
        }
        // No weak tier here, on purpose — see the note at the top of the type. A greeting plus a
        // real English word is not enough evidence to redirect someone's words into a terminal.
        // When it really was her name, the spotter has already woken on it and the take that
        // follows is empty, which `VoiceEngine` reads as the summons it is.

        // 3. Decoration after the name — fillers and politeness bridges, in any order. The index is
        //    remembered first: the summons test below has to see the remainder BOTH ways, because
        //    the bridge stripper eats the very words some summonses are made of ("Nova, can you
        //    hear me?" would otherwise arrive as "hear me" and never match a summons tail).
        let afterName = i
        if named {
            var moved = true
            while moved, i < tokens.count {
                moved = false
                if postNameFillers.contains(norm[i]) { i += 1; moved = true; continue }
                if let len = bridgeLength(at: i, norm) { i += len; moved = true }
            }
        }

        // Nothing recognised: hand the utterance back exactly as it came in. A greeting alone IS
        // shed (`spokenTokens` and `globalDirective` both relied on that before this type existed),
        // but it never counts as naming her.
        guard named || greeted else { return Reading(rest: raw, namedNova: false, isSummons: false) }
        let rest = tokens[i...].joined(separator: " ").trimmingCharacters(in: taskTrim)
        let undecorated = tokens[afterName...].joined(separator: " ").trimmingCharacters(in: taskTrim)
        let calledOnly = named && (summonsTails.contains(normalizedPhrase(rest))
                                   || summonsTails.contains(normalizedPhrase(undecorated)))
        return Reading(rest: rest, namedNova: named, isSummons: calledOnly)
    }

    /// `transcript` with any address to Nova removed — the convenience every parser front-end uses.
    static func withoutAddress(_ transcript: String) -> String { read(transcript).rest }

    /// She was called with nothing to do. The caller answers and reopens the mic instead of typing
    /// the word "Nova" into whatever window happened to be focused.
    static func isSummons(_ transcript: String) -> Bool { read(transcript).isSummons }

    // MARK: - The always-listening spotter

    /// Whether the wake name was JUST said, judged from a running recognition transcript.
    ///
    /// Different problem from `read`: this scans a stream that accumulates everything heard so far,
    /// with no reliable punctuation and no guarantee the name starts the sentence. So it consults
    /// only the last few words (a mention half a minute ago must not re-fire the moment the
    /// debounce window reopens), turns every non-letter into a word boundary, and requires a LEFT
    /// boundary on the name — which is what keeps "supernova" and "casanova" from waking her while
    /// still allowing the recognizer's habit of hanging a letter off the end ("novas", "novah").
    static func heardWakeName(in transcript: String) -> Bool {
        let cased = String(transcript.map { $0.isLetter ? $0 : " " }).split(separator: " ").map(String.init)
        let words = cased.map { $0.lowercased() }
        guard !words.isEmpty else { return false }
        let tail = Array(words.suffix(8)), caps = cased.suffix(8).map { $0.first?.isUppercase == true }

        for (i, word) in tail.enumerated() {
            // Strong tier — the name on its own is enough.
            if isStrongName(word) { return true }
            // Split tier — "no va", "know va".
            if i + 1 < tail.count,
               splitNames.contains(where: { $0[0] == word && $0[1] == tail[i + 1] }) { return true }
            // Weak tier — a real English word, so it only counts as her name when someone is
            // plainly calling out: the token immediately before it must be a greeting.
            if i > 0, weakNames.contains(word), greetings.contains(tail[i - 1]) { return true }
            if isFusedCall(tail, at: i, capitalized: caps[i]) { return true }
        }
        return false
    }

    /// Run 26b: index just past the LAST wake name in `words` (lowercased letter tokens), or nil. Same three tiers as
    /// `heardWakeName`, but over the whole running transcript so the live stream can slice off the command after it.
    /// `capitalized[i]` = the ORIGINAL token began upper-case (the fused tier needs it); omitted = fused tier off.
    static func indexAfterLastName(in words: [String], capitalized: [Bool] = []) -> Int? {
        var last: Int?
        for (i, word) in words.enumerated() {
            if isStrongName(word) { last = i + 1 }
            else if i + 1 < words.count, splitNames.contains(where: { $0[0] == word && $0[1] == words[i + 1] }) { last = i + 2 }
            else if i > 0, weakNames.contains(word), greetings.contains(words[i - 1]) { last = i + 1 }
            else if i < capitalized.count, isFusedCall(words, at: i, capitalized: capitalized[i]) { last = i + 1 }
        }
        return last
    }

    // MARK: - Token helpers

    private static let edgePunct = CharacterSet(charactersIn: ",.!?;:\"'()…-")
    /// Only the separator that joined the address to the instruction is shed — never the
    /// instruction's OWN sentence punctuation. Same set `CrewCommandParser` uses, and for the same
    /// reason: "Nova, is the build green?" must keep its question mark, because the dispatcher
    /// reads that mark as evidence it was asked a question rather than given a job.
    private static let taskTrim = CharacterSet(charactersIn: " \t\n,;:")

    /// Lowercase a token and shed its EDGE punctuation, so "Nova," and "you." compare cleanly.
    /// Interior punctuation is left alone on purpose — an apostrophe inside a token is the
    /// difference between calling her and talking about her (see `isStrongName`).
    private static func normalized(_ token: String) -> String {
        token.lowercased().trimmingCharacters(in: edgePunct)
    }

    /// The same normalization applied to a whole phrase — used to compare a remainder against the
    /// "she was only called" tails.
    private static func normalizedPhrase(_ phrase: String) -> String {
        phrase.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map { normalized(String($0)) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Length of a politeness bridge starting at `i`, or `nil`.
    private static func bridgeLength(at i: Int, _ norm: [String]) -> Int? {
        for bridge in postNameBridges where i + bridge.count <= norm.count {
            if (0..<bridge.count).allSatisfy({ norm[i + $0] == bridge[$0] }) { return bridge.count }
        }
        return nil
    }
}
