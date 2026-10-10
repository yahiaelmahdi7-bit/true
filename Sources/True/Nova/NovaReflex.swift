import Foundation

/// Nova's **reflex** — the hundred-millisecond read of an utterance that happens BEFORE any slow
/// brain is consulted, and that decides whether a slow brain is needed at all.
///
/// ## Why this exists
///
/// Until now the voice path had exactly two speeds. A handful of deterministic parsers caught the
/// utterances that match a fixed grammar ("launch the crew", "Ben, fix the tests"); everything
/// else — every un-addressed sentence of three words or more, spoken on the canvas — went to the
/// Haiku dispatcher through a shelled `claude -p`, which costs 3–20 seconds and was the ONLY way
/// to learn that a sentence wasn't a command at all. So ordinary dictation waited on a model
/// whose answer was "that's not for me", questions waited on a dispatcher before reaching the
/// answering brain, and "open my browser" — a desk verb the grammar had no line for — took the
/// long way round every single time. The user's ask was exact: *speak all day, and let her know
/// in a hundred milliseconds whether it was a command.*
///
/// Jev (`JevClient`) is a System One model: it returns typed judgments with probabilities, not
/// prose, in ~100ms. That is precisely the shape of this decision. One call, several questions
/// asked at once over the same state (the utterance, who's on the desk, the last few turns):
///
/// - `kind`       — desk control · a task for an agent · a question for Nova · dictation · not
///                  for Nova at all (talking to someone in the room, thinking out loud, the TV).
/// - `addressed`  — was the speaker talking TO Nova/the computer? (the guard the always-on
///                  spotter never had; it only knew her name).
/// - `verb`       — which fixed desk verb, when it's desk control (the executor's own vocabulary).
/// - `seat`       — best-fit crew member for a task (a prior for the dispatcher, never a verdict).
/// - `tier`       — how expensive the job is worth (haiku…fable), same rubric the dispatcher uses.
/// - `complete`   — is the sentence finished, or did the silence stop fire mid-thought?
/// - `interrupt`  — "stop", "shut up", "cancel" — meant to halt Nova, not to be typed.
/// - `needsCode`  — does the task change code (vs. a lookup), a hint for the dispatcher.
///
/// ## What it is NOT
///
/// Jev cannot write. It doesn't compose the enriched prompt a seat receives, it doesn't answer a
/// question, it doesn't fix a misheard word. Those stay with the dispatcher (Haiku) and the
/// answering voice (Hermes) — the reflex just tells the desk which of them to wake, or that
/// neither is needed, and hands them its typed read as a prior so they start from a decision
/// rather than from raw speech. Code keeps every rule: the thresholds below, the verb vocabulary,
/// the extraction of an app or site name from the words around a verb.
///
/// ## Confidence doctrine
///
/// Every threshold is a floor on ACTING, never on thinking: a low-confidence reflex means "fall
/// through to the old chain exactly as before", so the worst the reflex can do is nothing. The
/// one path that never existed before — a command with no wake word, lifted off the always-on
/// spotter — is held to stricter floors and to a short list of REVERSIBLE verbs, because there
/// the price of a false positive is Nova acting on a sentence meant for someone else.
enum NovaReflex {

    // MARK: - Inputs

    /// One routable seat, as the reflex sees it.
    struct Seat: Sendable, Equatable {
        let name: String
        let skills: String
        let live: Bool
        /// The CLI behind the seat ("claude") so "set up a claude session" can name a seat by its
        /// model when the speaker doesn't know its name. Optional so the existing call sites and
        /// fixtures compile unchanged.
        var backend: String? = nil
    }

    /// Everything the reflex is allowed to know. Deliberately SMALL: Jev's documented weakness is
    /// large state unrelated to the decision, so this carries the roster, a few recent turns, and
    /// where the user is looking — not the whole canvas brief.
    struct Context: Sendable {
        var seats: [Seat] = []
        /// The last few exchanges, newest last, as "USER: …" / "NOVA: …" lines.
        var recent: [String] = []
        /// What is actually in front of him, when it is not Axon — "Dia, on the tab \"WhatsApp\"
        /// (web.whatsapp.com)". Supplied by `ScreenContext`, which keeps it current off the hot
        /// path. Nil means Axon is front, or nothing useful could be read.
        var lookingAt: String? = nil
    }

    /// Where the words came from — it changes what the reflex is allowed to trigger.
    enum Source: Sendable {
        /// A finished dictation take (the mic was opened deliberately, or by her name).
        case take
        /// The always-on spotter: no wake word, no take, just words in the room.
        case ambient
    }

    // MARK: - The verdict

    enum Kind: String, CaseIterable, Sendable {
        case deskControl = "desk_control"
        case agentTask = "agent_task"
        case question = "question_for_nova"
        case dictation = "dictation"
        case notForNova = "not_for_nova"
    }

    struct Verdict: Sendable {
        let source: Source
        let transcript: String

        let kind: Kind
        let kindConfidence: Double
        let kindProbabilities: [Kind: Double]
        /// P(the speaker was talking to Nova / the computer).
        let addressed: Double
        /// A desk verb from `verbs`, or nil for "none".
        let verb: String?
        let verbConfidence: Double
        /// A crew seat name (as spoken in the roster) or "everyone"; nil for "none".
        let seat: String?
        let seatConfidence: Double
        let tier: AgentModel?
        let tierConfidence: Double
        /// P(the utterance is a finished instruction).
        let complete: Double
        /// P(the speaker wants Nova to stop / be quiet / cancel).
        let interrupt: Double
        /// P(the task requires writing or changing code).
        let needsCode: Double

        let latency: TimeInterval
        let model: String

        // MARK: Derived judgments — the policy lives in code, next to the numbers it reads.

        /// Confident enough that this is ordinary dictation (or not for Nova) to skip the slow
        /// dispatcher and land the words at once. The dispatcher's own "nil → dictation" fallback
        /// is what this replaces, minus the 3–20s wait.
        var isPlainDictation: Bool {
            (kind == .dictation || kind == .notForNova) && kindConfidence >= 0.6 && interrupt < 0.5
        }

        /// A desk verb the executor can run straight away, with enough confidence to act on.
        var isDirectDeskControl: Bool {
            kind == .deskControl && kindConfidence >= 0.5 && addressed >= 0.5
                && verb != nil && verbConfidence >= 0.6
        }

        /// Verbs whose meaning is the verb, whatever `kind` came back: "tell Jeff what Ben found"
        /// reads as a task for Jeff (agent_task) AND as a relay; the relay is what was meant.
        /// Guarded: the verb must be strong, and a relay must be phrased receiver-first ("tell
        /// / give / pass …") — "cruz review what ben just did" also scores as a relay, and there
        /// the verbatim route to Cruz is right and a relay would run backwards.
        var isCrossKindVerb: Bool {
            // `resume_work` joins the list on measured evidence: "carry on with the trading thing"
            // reads 97% resume_work but only 41% desk_control (it LOOKS like work for an agent,
            // and in a sense it is — Nova just has to find out what work first).
            guard let verb, ["relay", "poll_crew", "do_on_screen", "resume_work"].contains(verb),
                  verbConfidence >= 0.8, addressed >= 0.6, !isDirectDeskControl else { return false }
            if verb == "relay" { return NovaReflex.startsWithRelayVerb(transcript) }
            return true
        }

        /// A question for Nova herself — go straight to the answering voice, skipping the
        /// dispatcher's round-trip whose only job would have been to say the same thing.
        var isQuestion: Bool {
            kind == .question && kindConfidence >= 0.65 && addressed >= 0.5
        }

        /// Reads unfinished: the silence stop fired inside a sentence. Only ever used to HOLD the
        /// take and reopen the mic (same doctrine as `SmartTurn`): a wrong "unfinished" costs a
        /// beat, a wrong "finished" truncates the user.
        var isMidThought: Bool { complete < 0.25 }

        /// "Stop." — halt her voice and drop the words rather than type them anywhere.
        var isInterrupt: Bool { interrupt >= 0.85 }

        /// The strict gate for words that arrived with NO wake word and NO take. Two independent
        /// judgments must both be strong (addressed AND a desk verb), and the verb must be one
        /// whose false positive is a window opening, not work being sent or state being lost.
        var isAmbientCommand: Bool {
            guard source == .ambient, kind == .deskControl, kindConfidence >= 0.7,
                  addressed >= 0.8, verbConfidence >= 0.8,
                  let verb, NovaReflex.ambientSafeVerbs.contains(verb) else { return false }
            // The screen loop from across the room: fine for "press play" or "close this tab",
            // never for a goal whose words include send / pay / delete / sign in — the loop
            // would park at the button and ask, but the asking itself is noise nobody wanted.
            if verb == "do_on_screen", ComputerUse.isConsequential(transcript) { return false }
            return true
        }

        /// A task the reflex is sure was ADDRESSED to one named seat (or to everyone): the seat
        /// pick is strong, the kind is strong, and the speaker was talking to the desk. This is
        /// what lets "ben can you refactor the uploader" reach Ben's window verbatim in the time
        /// it takes Jev to answer, instead of after the dispatcher has rewritten it 3–20 s later.
        /// Same doctrine as `CrewStore.looseResolve`: addressed commands stay verbatim by design.
        /// 0.8 on the seat is deliberately the highest floor in this type — a task landing in the
        /// wrong agent's terminal is the one voice mistake nothing undoes.
        var isConfidentSeatTask: Bool {
            kind == .agentTask && kindConfidence >= 0.7 && addressed >= 0.7
                && seat != nil && seatConfidence >= 0.8
        }

        /// The reflex was SURE this was a desk command for her, yet nothing downstream could run
        /// it. Used to speak a miss instead of returning nil — because nil means "dictation", and
        /// dictation types the words into whatever field is focused. "show me jef" pasted into
        /// Ben's terminal is worse than "I couldn't do that, sir."
        var isSureDeskControl: Bool {
            kind == .deskControl && kindConfidence >= 0.8 && addressed >= 0.8
        }

        /// The typed pre-read, phrased as a prior for the dispatcher prompt. Two lines, so it
        /// costs the slow brain almost nothing to read and can't be mistaken for an instruction.
        var hintBlock: String {
            func pct(_ p: Double) -> String { String(Int((p * 100).rounded())) + "%" }
            var l1 = "REFLEX (a fast typed pre-read of this utterance — a prior, not a verdict): "
                + "kind=\(kind.rawValue) (\(pct(kindConfidence))), addressed-to-Nova \(pct(addressed))"
            if let verb { l1 += ", desk verb=\(verb) (\(pct(verbConfidence)))" }
            var l2 = "  best-fit seat=\(seat ?? "none") (\(pct(seatConfidence)))"
            if let tier { l2 += ", tier=\(tier.rawValue) (\(pct(tierConfidence)))" }
            l2 += ", code change \(pct(needsCode))"
            return l1 + "\n" + l2
        }
    }

    // MARK: - Vocabulary

    /// Verbs the desk executes without any free text — Jev can pick one outright.
    static let directVerbs: [String: String] = [
        "focus_pane": "bring ONE named agent's or terminal pane to the front in True (\"show me ben\", \"take me to the trading agent\", \"open the build pane\")",
        "read_pane": "read back what a named AGENT's or terminal pane says in True (\"what did Ben say\", \"did the build finish\") — never a message, chat, email or page on the user's own screen, which is do_on_screen",
        "status": "a status report on True's agents (\"how's everyone doing\", \"status\", \"who needs me\")",
        "screenshot_full": "capture the whole screen AS AN IMAGE into True's Shots (\"take a screenshot\") — not for Nova to look at herself",
    ]

    /// Verbs that need a noun phrase from the sentence; code lifts it (`query(for:in:)`).
    static let queryVerbs: [String: String] = [
        "open_app": "open a Mac APPLICATION by name — including \"the browser\" (\"open my browser\", \"open spotify\", \"launch chrome\")",
        "quit_app": "quit a Mac application (\"close spotify\", \"quit chrome\")",
        "relaunch_app": "restart a Mac application (\"restart chrome\")",
        "open_site": "open a WEBSITE or page (\"open youtube\", \"pull up github\", \"go to gmail\")",
        "play_video": "WATCH or LISTEN to something specific (\"play lofi beats\", \"put on the Dune trailer\")",
        "media_control": "control playback or volume: play, pause, next track, volume up/down/mute, set volume (\"pause the music\", \"next song\", \"volume to 30\")",
        "spawn_agent": "START a new agent or terminal in True, or set up a session in a project (\"open Ben in prism\", \"set up a claude session in the trading repo\", \"start an agent on the website\")",
        "do_on_screen": "LOOK AT whatever is on screen right now and act on it, or answer about it — read what it says, click, press, fill in, scroll, follow an instruction the screen itself is showing (\"click the share button\", \"what does this say\", \"fill in my email\")",
        "relay": "hand what ONE agent found over to ANOTHER agent (\"tell Jeff what Ben found\", \"pass Ben's result to Cruz\")",
        "poll_crew": "ask every live agent the same question and report back who said what (\"ask everyone if their tests pass and tell me who said what\")",
    ]

    /// Verbs the desk may run from words heard with NO wake name. Widened on the user's order
    /// ("no constraint, just work"): apps open, quit and relaunch; sites and media play; projects
    /// and seats open and focus; a seat's window is read back; screenshots and status are taken;
    /// and the screen loop runs — but only for a goal with no consequential verb in it
    /// (`isAmbientCommand` checks the words). Still absent: anything that sends work INTO a
    /// live agent (route, broadcast, relay, submit), git push/commit, restarts, clear_desk. Those
    /// wait for her name, because an overheard sentence must never become a prompt in a pane.
    static let ambientSafeVerbs: Set<String> = [
        "focus_pane", "status", "read_pane", "screenshot_full", "open_app", "quit_app", "relaunch_app",
        "open_site", "play_video", "media_control", "do_on_screen",
    ]

    /// Verbs whose extraction is deterministic and whose executor path already exists; the
    /// reflex may run these directly from a take. Query verbs the desk would have to ASK about
    /// (commit messages, hires, relays) stay with the dispatcher, which can phrase the question.
    static var directlyExecutable: Set<String> {
        Set(directVerbs.keys).union(queryVerbs.keys)
    }

    // MARK: - The read

    /// Read `transcript` in one Jev call. `nil` = the reflex didn't fire (no key, timeout, bad
    /// reply) and the caller MUST behave exactly as it did before the reflex existed.
    static func read(_ transcript: String, context: Context, source: Source = .take,
                     timeout: TimeInterval = 0.9) async -> Verdict? {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, NovaJev.isConfigured else { return nil }

        let (state, questions) = request(for: text, context: context)
        guard let reply = await NovaJev.ask(state: state, questions: questions, timeout: timeout),
              let kindAnswer = reply.answers["kind"], let kindRaw = kindAnswer.choice,
              let kind = Kind(rawValue: kindRaw) else { return nil }

        var kindProbabilities: [Kind: Double] = [:]
        for k in Kind.allCases { kindProbabilities[k] = kindAnswer.probability(of: k.rawValue) }

        let verbAnswer = reply.answers["verb"]
        let verb = verbAnswer?.choice.flatMap { $0 == "none" ? nil : $0 }
        let seatAnswer = reply.answers["seat"]
        let seat = seatAnswer?.choice.flatMap { $0 == "none" ? nil : $0 }
        let tierAnswer = reply.answers["tier"]
        let tier = tierAnswer?.choice.flatMap { AgentModel(rawValue: $0) }

        return Verdict(
            source: source,
            transcript: text,
            kind: kind,
            kindConfidence: kindAnswer.confidence ?? 0,
            kindProbabilities: kindProbabilities,
            addressed: reply.answers["addressed"]?.noul ?? 0,
            verb: verb,
            verbConfidence: verbAnswer?.confidence ?? 0,
            seat: seat,
            seatConfidence: seatAnswer?.confidence ?? 0,
            tier: tier,
            tierConfidence: tierAnswer?.confidence ?? 0,
            complete: reply.answers["complete"]?.noul ?? 1,
            interrupt: reply.answers["interrupt"]?.noul ?? 0,
            needsCode: reply.answers["needs_code"]?.noul ?? 0,
            latency: reply.latency,
            model: reply.model)
    }

    /// The exact state + questions sent for `transcript`. Public so the calibration test posts
    /// the SAME payload the app does — a spec that lived in two places would drift.
    static func request(for transcript: String, context: Context) -> (state: [String: Any], questions: [String: Any]) {
        // Skills are user-editable prose and can run long; the reflex needs the gist.
        func short(_ s: String, _ n: Int) -> String {
            s.count <= n ? s : String(s.prefix(n)) + "…"
        }
        let crew: [[String: Any]] = context.seats.map {
            ["name": $0.name, "skills": short($0.skills, 140), "window_open": $0.live]
        }
        var state: [String: Any] = [
            "utterance": transcript,
            "note": "The utterance is speech-recognition output: names and words may be misheard.",
            "agents": crew,
            // What he is looking at, concretely. This used to be the placeholder "another screen
            // or app", which told the model nothing and made every demonstrative ("close this",
            // "what does this say") unanswerable without asking him. Naming the app, the window
            // and the tab is what lets a sentence with no object in it resolve to one.
            "user_is_looking_at": context.lookingAt ?? "another app",
        ]
        if !context.recent.isEmpty {
            state["recent_conversation"] = Array(context.recent.suffix(6))
        }

        var seatOptions: [String: String] = ["none": "no single seat fits, or this isn't a task for an agent",
                                             "everyone": "the whole crew should get it"]
        for s in context.seats { seatOptions[s.name] = short(s.skills, 140) }

        var verbOptions: [String: String] = ["none": "not a desk operation"]
        for (k, v) in directVerbs { verbOptions[k] = v }
        for (k, v) in queryVerbs { verbOptions[k] = v }

        let questions: [String: Any] = [
            "kind": [
                "type": "choice",
                "instructions": [
                    "question": "What is `utterance` to Nova, the voice assistant inside True (a Mac app that runs AI coding agents in terminal panes) (the `agents`)?",
                    "focus": "Judge the speaker's intent, not the grammar. A sentence that names a crew member and gives them work is a task. A request that operates the desk, the Mac, the browser, or asks what a seat said is desk control.",
                ],
                "criteria": [
                    Kind.deskControl.rawValue: [
                        "what": "operate the desk or the Mac: open/close/focus a crew window, launch or clear the crew, status, open an app, a website, a project, set up an agent session in a project, play something, run tests/build, git status/push, restart a seat, read what a seat said, click/press/fill in something in the app on screen",
                        "examples": ["open my browser", "launch the crew", "show me Jeff", "how's everyone doing", "open youtube", "what did Ben say", "open Ben in prism", "click the share button"],
                    ],
                    Kind.agentTask.rawValue: [
                        "what": "work for an AI coding agent: write, fix, refactor, test, investigate, or a message to relay into an agent session",
                        "examples": ["fix the failing auth tests", "write a parser for the config file", "tell everyone to commit", "Ben, add a retry to the uploader"],
                    ],
                    Kind.question.rawValue: [
                        "what": "a question or small talk meant for Nova herself to ANSWER out loud — not work, not a desk operation",
                        "examples": ["who is Jeff", "what time is it", "why did Claude stop working", "thanks Nova"],
                    ],
                    Kind.dictation.rawValue: [
                        "what": "text the speaker wants TYPED where the cursor is: prose, a message, notes, a prompt being composed — spoken to the computer but not an instruction for Nova",
                        "examples": ["dear John, thanks for your email, I'll get back to you tomorrow", "the onboarding copy needs a warmer tone"],
                    ],
                    Kind.notForNova.rawValue: [
                        "what": "not addressed to the computer at all: a person in the room, a phone call, thinking aloud, a TV",
                        "examples": ["yeah I'll grab lunch in ten", "can you pass me the charger", "hmm let me think"],
                    ],
                ],
            ],
            "addressed": [
                "type": "noul",
                "instructions": "Is the speaker of `utterance` talking TO Nova / the computer (rather than to another person, or to themselves)?",
                "criteria": [
                    "true": ["what": "an instruction, request, question, or dictation aimed at the assistant or the machine", "examples": ["open my browser", "Nova, launch the crew", "write this down: buy milk"]],
                    "false": ["what": "talk between people, a phone call, thinking aloud, background media", "examples": ["can you pass me the charger", "I'll be there in five", "what did she say about it"]],
                ],
            ],
            "verb": [
                "type": "choice",
                "instructions": [
                    "question": "If `utterance` operates the desk or the Mac, which ONE operation is it? Otherwise `none`.",
                    "focus": "Agent and terminal panes use focus_pane/read_pane; Mac applications use open_app/quit_app/relaunch_app; websites use open_site; projects/repos (and agent sessions IN a project) use open_project. \"open my browser\" is open_app. Pressing, clicking, filling in or scrolling something in the app currently on screen is do_on_screen. The word \"open\" does NOT decide this: naming something that is already up somewhere — a TAB, a window, an app they were just in — is go_to, whereas a site or app to be brought up fresh is open_site / open_app.",
                ],
                "criteria": verbOptions,
            ],
            "seat": [
                "type": "choice",
                "instructions": [
                    "question": "Which crew member (from `agents`) does `utterance` concern — the seat to open, close, focus, restart or read back, the seat being ADDRESSED with work, or the best fit for the work — or `everyone`? `none` when no seat is involved.",
                    "focus": "A name spoken in the utterance wins even if misheard slightly (\"deke\" ~ \"deek\", \"jeff\" ~ \"jef\"). When the utterance ADDRESSES one seat and merely mentions another (\"cruz, review what ben did\"), the addressed seat — usually the name at the start — is the answer. A seat named by its model (\"a claude session\") is that seat. For work with no name, match the task to the skills and prefer a seat whose window is open.",
                ],
                "criteria": seatOptions,
            ],
            "tier": [
                "type": "choice",
                "instructions": [
                    "question": "If `utterance` is work for an agent, how much model is the JOB worth? Judge the work, not the wording.",
                    "focus": "When in doubt pick the cheaper tier.",
                ],
                "criteria": [
                    "haiku": "a lookup or one-liner: read a file, check status, rename a variable, run a command",
                    "sonnet": "ordinary implementation: a normal feature, a bug fix, tests, a refactor of a file or two — the usual answer",
                    "opus": "genuinely hard: subtle debugging, a design with real trade-offs, changes across many files",
                    "fable": "the largest architectural work, or the user explicitly asked for maximum reasoning (\"think hard\", \"best model\")",
                ],
            ],
            "complete": [
                "type": "noul",
                "instructions": "Is `utterance` a FINISHED sentence or instruction, as opposed to one cut off mid-thought that the speaker was still going to continue?",
                "criteria": [
                    "true": ["what": "reads as complete; the speaker could stop here", "examples": ["open my browser", "fix the auth bug", "who is Jeff"]],
                    "false": ["what": "trails off, ends on a connective or an article, or is an unfinished clause", "examples": ["open the", "and then we should", "tell Ben to"]],
                ],
            ],
            "interrupt": [
                "type": "noul",
                "instructions": "Is `utterance` telling Nova to STOP — stop talking, cancel, be quiet, never mind?",
                "criteria": [
                    "true": ["examples": ["stop", "stop talking", "shut up Nova", "cancel that", "never mind"]],
                    "false": ["what": "anything else, including 'stop the server' or 'cancel the subscription' as work for an agent"],
                ],
            ],
            "needs_code": [
                "type": "noul",
                "instructions": "Would carrying out `utterance` require WRITING or CHANGING code (as opposed to answering, looking something up, or operating the desk)?",
            ],
        ]
        return (state, questions)
    }

    // MARK: - Lifting the noun phrase for a query verb (code, not the model)

    /// Words that, at the FRONT of a spoken command, are the verb and its decoration rather than
    /// the thing being named: "open **up my** browser", "**pull up** github", "**go to** gmail",
    /// "**put on** lofi beats", "**can you open**". Consumed greedily from the left.
    private static let leadingNoise: Set<String> = [
        "open", "opened", "launch", "start", "run", "load", "fire", "boot", "bring", "pull", "put",
        "play", "watch", "listen", "show", "go", "switch", "set", "quit", "close", "restart",
        "relaunch", "kill", "up", "to", "on", "in", "me", "my", "the", "a", "an", "our", "this",
        "that", "it", "them", "please", "can", "could", "would", "will", "you", "u", "just",
        "quickly", "now", "some", "back", "over", "nova", "hey", "ok", "okay",
    ]
    /// Trailing decoration: "open spotify **please**", "open github **for me**".
    private static let trailingNoise: Set<String> = [
        "please", "for", "me", "now", "up", "thanks", "thank", "you", "nova",
    ]

    /// The thing a query verb names, lifted from the sentence around it. Deterministic on
    /// purpose — this is what the model was never asked to generate. `nil` when nothing usable
    /// remains, in which case the caller falls to the dispatcher, which can ask.
    static func query(for verb: String, in transcript: String) -> String? {
        guard queryVerbs[verb] != nil else { return nil }
        let text = NovaAddress.withoutAddress(transcript)
        // The on-screen goal is the WHOLE sentence: "click the share button" loses its verb if
        // the noise shed runs, and the computer-use loop needs the verb to know what to do.
        if verb == "do_on_screen" {
            let goal = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return goal.isEmpty ? nil : goal
        }
        if verb == "poll_crew" { return pollQuestion(in: text) }
        if verb == "relay" { return relayInstruction(in: text) }
        let strip = CharacterSet(charactersIn: ".,!?;:\"'()")
        var words = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map {
            String($0).trimmingCharacters(in: strip)
        }.filter { !$0.isEmpty }
        // Left: shed noise until the first word that carries the name. "browser" is protected
        // from the shed even though it sits in the noise-adjacent vocabulary of `MacControl`.
        while let head = words.first, leadingNoise.contains(head.lowercased()) { words.removeFirst() }
        while let tail = words.last, trailingNoise.contains(tail.lowercased()) { words.removeLast() }
        // "play X on youtube" — the site is the executor's `target`, not part of the query.
        if verb == "play_video", let onIdx = words.lastIndex(where: { $0.lowercased() == "on" }),
           onIdx > 0, onIdx == words.count - 2 {
            words.removeSubrange(onIdx...)
        }
        let q = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? nil : q
    }

    /// For `resume_work`: the project words, if any, after the "continue my work" phrasing is
    /// shed. Empty (nil) means "the project I'm looking at" — the executor uses the active zone.
    /// Deterministic: everything in `resumePhrases` is decoration around a project name.
    private static let resumePhrases: [String] = [
        "continue", "carry on", "carry", "pick up", "pick", "resume", "keep going", "keep", "going",
        "get back to", "get", "back", "where i left off", "where we left off", "i left off", "left off",
        "my work", "the work", "our work", "work", "working", "on", "in", "with", "for", "at", "to",
        "the", "this", "that", "thing", "project", "repo", "please", "can you", "could you", "nova",
        "hey", "up", "from", "here", "there", "again",
    ]
    static func resumeProject(in transcript: String) -> String? {
        var t = " " + NovaAddress.withoutAddress(transcript).lowercased()
            .replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: ".", with: " ") + " "
        // Longest phrases first so "where i left off" goes before "left off" before "off".
        for phrase in resumePhrases.sorted(by: { $0.count > $1.count }) {
            t = t.replacingOccurrences(of: " \(phrase) ", with: " ")
        }
        let words = t.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    /// For `play_video`: the site named after a trailing "on" ("play the game on mkstreams").
    static func playTarget(in transcript: String) -> String? {
        let words = NovaAddress.withoutAddress(transcript).lowercased()
            .split(separator: " ").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?")) }
        guard words.count >= 3, words[words.count - 2] == "on" else { return nil }
        let site = words[words.count - 1]
        return site.isEmpty ? nil : site
    }

    /// The reflex's verdict as the dispatcher's `Action` shape, so a direct desk verb runs through
    /// the executor's existing `.act` path — one execution path however a verb was recognised.
    static func action(for verdict: Verdict, roster: [String] = []) -> NovaAction? {
        guard let verb = verdict.verb, directlyExecutable.contains(verb) else { return nil }
        let seatVerbs: Set<String> = ["focus_pane", "read_pane"]
        // The model's pick first; failing that, a roster name spoken verbatim in the sentence
        // ("what did deke say") — code can read a name off a transcript without a model.
        let spokenName = roster.first { name in
            let n = name.lowercased()
            return verdict.transcript.lowercased()
                .split(whereSeparator: { !$0.isLetter }).contains { $0 == Substring(n) }
        }
        let agent = seatVerbs.contains(verb)
            ? (verdict.seat.flatMap { $0 == "everyone" ? nil : $0 } ?? spokenName) : nil
        if queryVerbs[verb] != nil {
            // "continue my work" names no project on purpose — the active one is meant.
            guard let q = query(for: verb, in: verdict.transcript) else { return nil }
            return NovaAction(action: verb, agent: nil, query: q,
                                    target: verb == "play_video" ? playTarget(in: verdict.transcript) : nil)
        }
        // Seat verbs need a seat; "open" with no seat named is the dispatcher's to clarify.
        if ["focus_pane", "read_pane"].contains(verb), agent == nil { return nil }
        return NovaAction(action: verb, agent: agent, query: nil, target: nil)
    }

    // MARK: - Setting up sessions: seats × projects, lifted by code

    /// Prepositions that put a seat INTO a project: "open Ben **in** prism", "a claude session
    /// **inside** the trading repo". Deliberately not "on" or "for": "open Ben on the desk" and
    /// "open Ben for me" name no project, and a phrase wrongly read as one becomes a project MISS
    /// that then blocks the seat from opening at all (see `actions(for:seats:)`).
    private static let projectPrepositions: Set<String> = ["in", "into", "inside", "within"]

    /// Places on the desk that follow "in" without naming a repo. "Open Ben in the background"
    /// must not go looking for a project called "background".
    private static let notProjects: Set<String> = [
        "desk", "canvas", "office", "terminal", "background", "foreground", "front", "window",
        "here", "there", "parallel", "meantime", "meanwhile", "zone", "corner", "same", "place",
    ]

    /// The project named after an "in": "open Ben in prism" → "prism"; "set up a claude session
    /// in the trading repo" → "trading repo" (the resolver sheds "repo"). `nil` when no such
    /// phrase exists or it names a desk location instead.
    static func projectPhrase(in transcript: String) -> String? {
        let strip = CharacterSet(charactersIn: ".,!?;:\"'()")
        let words = NovaAddress.withoutAddress(transcript)
            .split(whereSeparator: { $0 == " " || $0 == "\n" })
            .map { String($0).trimmingCharacters(in: strip) }.filter { !$0.isEmpty }
        guard let at = words.lastIndex(where: { projectPrepositions.contains($0.lowercased()) }),
              at + 1 < words.count else { return nil }
        var phrase = Array(words[(at + 1)...])
        while let tail = phrase.last, trailingNoise.contains(tail.lowercased()) { phrase.removeLast() }
        while let head = phrase.first, ["the", "my", "our", "a", "an", "this", "that"].contains(head.lowercased()) {
            phrase.removeFirst()
        }
        guard let first = phrase.first, !notProjects.contains(first.lowercased()) else { return nil }
        let q = phrase.joined(separator: " ")
        return q.isEmpty ? nil : q
    }

    /// Every seat the sentence names — by roster name (exact, or one edit off for the recognizer's
    /// sake), or by its model ("a claude session", "get Ben up"). Roster order, no duplicates.
    static func spokenSeats(in transcript: String, seats: [Seat]) -> [Seat] {
        let tokens = NovaAddress.withoutAddress(transcript).lowercased()
            .split(whereSeparator: { !$0.isLetter }).map(String.init)
        var found: [Seat] = []
        for seat in seats {
            let name = seat.name.lowercased()
            let byName = tokens.contains { t in
                t == name || (t.count >= 3 && name.count >= 3 && editDistance(t, name) <= (name.count <= 4 ? 1 : 2))
            }
            let byBackend = seat.backend.map { b in tokens.contains(b.lowercased()) } ?? false
            // A model word names the FIRST seat running that model, never every twin of it.
            if byName || (byBackend && !found.contains(where: { $0.backend == seat.backend })) {
                found.append(seat)
            }
        }
        return found
    }

    /// The verdict as one or more executor actions. Most verbs are one action (`action(for:)`);
    /// setting up sessions is where code composes: a project named after "in" is opened FIRST
    /// and the seat(s) spawn into it, and two or more spoken names become one `launch_some`.
    /// Ordering matters — the executor skips a seat open when the project before it missed, so
    /// a misheard repo can't spawn Ben into whatever zone happened to be active.
    static func actions(for verdict: Verdict, seats: [Seat]) -> [NovaAction] {
        guard let verb = verdict.verb else { return [] }
        let roster = seats.map(\.name)
        if verb == "relay" {
            guard let (src, dst) = relayEnds(in: verdict.transcript, seats: seats) else { return [] }
            return [NovaAction(action: "relay", agent: src, query: relayInstruction(in: verdict.transcript), target: dst)]
        }
        if verb == "poll_crew" {
            guard let q = pollQuestion(in: verdict.transcript) else { return [] }
            return [NovaAction(action: "poll_crew", agent: nil, query: q, target: nil)]
        }
        return action(for: verdict, roster: roster).map { [$0] } ?? []
    }

    // MARK: - Between seats: relay ends and a crew poll, lifted by code

    /// Verbs after which the FIRST name is the receiver: "tell **Jeff** what Ben found". Without
    /// one, the first name is the source: "**Ben**'s result to Cruz".
    private static let receiverFirstVerbs: Set<String> = ["tell", "ask", "send", "give", "hand", "pass", "show", "brief", "forward"]

    /// The sentence opens with a hand-over verb ("tell Jeff…", "pass Ben's result…") — the
    /// shape that distinguishes a relay from a task that merely mentions two seats.
    static func startsWithRelayVerb(_ transcript: String) -> Bool {
        let tokens = NovaAddress.withoutAddress(transcript).lowercased()
            .split(whereSeparator: { !$0.isLetter }).map(String.init)
        guard let first = tokens.first(where: { !["please", "can", "could", "you", "just", "now"].contains($0) }) else { return false }
        return receiverFirstVerbs.contains(first) || first == "relay"
    }

    /// (source, target) seat names for a relay, or nil unless exactly two different seats are
    /// named — a relay with one end guessed is a prompt in the wrong pane.
    /// "… to <Y>" makes Y the receiver whatever verb opened the sentence ("pass Ben's result
    /// to Cruz"); otherwise a receiver-first verb makes the first name the receiver ("tell
    /// Jeff what Ben found"); otherwise the first name is the source.
    static func relayEnds(in transcript: String, seats: [Seat]) -> (source: String, target: String)? {
        let tokens = NovaAddress.withoutAddress(transcript).lowercased()
            .split(whereSeparator: { !$0.isLetter }).map(String.init)
        var hits: [(pos: Int, name: String)] = []
        for seat in seats {
            let n = seat.name.lowercased()
            if let i = tokens.firstIndex(where: { $0 == n || ($0.count >= 3 && n.count >= 3 && editDistance($0, n) <= (n.count <= 4 ? 1 : 2)) }) {
                hits.append((i, seat.name))
            }
        }
        hits.sort { $0.pos < $1.pos }
        guard hits.count == 2 else { return nil }
        if hits[1].pos > 0, tokens[hits[1].pos - 1] == "to" { return (hits[0].name, hits[1].name) }
        let verbBeforeFirst = tokens[..<hits[0].pos].contains { receiverFirstVerbs.contains($0) }
        return verbBeforeFirst ? (hits[1].name, hits[0].name) : (hits[0].name, hits[1].name)
    }

    /// What the receiver should DO with the handoff, if the sentence says ("…to review it").
    static func relayInstruction(in transcript: String) -> String? {
        let text = NovaAddress.withoutAddress(transcript).lowercased()
        for marker in [" and ask them to ", " and tell them to ", " so they can ", " to review", " and have them "] {
            if let r = text.range(of: marker) {
                let tail = text[r.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " .,!?"))
                return marker == " to review" ? "review it" : (tail.isEmpty ? nil : tail)
            }
        }
        return nil
    }

    /// The question to broadcast: the words after "ask everyone / the crew / them", minus a
    /// trailing "and tell me who said what". Nil when nothing would be asked.
    static func pollQuestion(in transcript: String) -> String? {
        var text = NovaAddress.withoutAddress(transcript).trimmingCharacters(in: CharacterSet(charactersIn: " .,!?"))
        let lower = text.lowercased()
        for opener in ["ask everyone", "ask everybody", "ask the crew", "ask the team", "ask them all", "ask them", "poll the crew", "poll everyone", "ask all of them"] {
            if let r = lower.range(of: opener) {
                text = String(text[r.upperBound...]); break
            }
        }
        for closer in ["and tell me who said what", "and tell me what they said", "and report back", "then tell me who said what", "and let me know who said what", "and tell me who says what"] {
            if let r = text.lowercased().range(of: closer) { text = String(text[..<r.lowerBound]) }
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " .,!?:"))
        for lead in ["whether ", "if "] where text.lowercased().hasPrefix(lead) { text = String(text.dropFirst(lead.count)) }
        return text.isEmpty ? nil : text
    }

    // MARK: - Talking to a seat, verbatim

    /// Collective handles a broadcast may start with. Mirrors the desk's own list; only ever used
    /// to SHED a leading address, never to decide who was meant (the reflex decided that).
    /// Longest phrases FIRST: "all of you" must win before "all" eats one word of it and leaves
    /// "of you, run the tests" as the task.
    private static let leadingCollectives: [[String]] = [
        ["all", "of", "you"], ["both", "of", "you"], ["the", "team"], ["the", "crew"],
        ["everyone"], ["everybody"], ["team"], ["guys"], ["crew"], ["all"],
    ]
    private static let leadingGreetings: Set<String> = ["hey", "hi", "hello", "yo", "ok", "okay", "so", "um", "uh", "right"]

    /// The words to land in `seat`'s window: the transcript minus the address to Nova and minus
    /// the leading name (with its comma), nothing else touched. "ben can you refactor the
    /// uploader" → "can you refactor the uploader". A leading name that belongs to a DIFFERENT
    /// roster member is a conflict, and the answer is `nil` — hand it to the dispatcher, which can
    /// read the whole sentence, rather than route Cruz's instruction into Ben's terminal.
    /// `nil` also when nothing would be left to send.
    static func taskWithoutSeat(_ transcript: String, seat: String, roster: [String]) -> String? {
        let text = NovaAddress.withoutAddress(transcript).trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        guard !tokens.isEmpty else { return nil }
        let strip = CharacterSet(charactersIn: ",.!?;:\"'()")
        func norm(_ s: String) -> String { s.lowercased().trimmingCharacters(in: strip) }
        func rest(after n: Int) -> String? {
            var r = tokens[n...].joined(separator: " ")
            while let f = r.first, " ,:-—".contains(f) { r.removeFirst() }
            r = r.trimmingCharacters(in: .whitespacesAndNewlines)
            return r.isEmpty ? nil : r
        }
        // Skip at most two greeting words, but only when a name follows them.
        var i = 0
        while i < min(2, tokens.count), leadingGreetings.contains(norm(tokens[i])) { i += 1 }
        func matches(_ name: String, at start: Int) -> Int? {
            let parts = name.lowercased().split(separator: " ").map(String.init)
            guard start + parts.count <= tokens.count else { return nil }
            let spoken = tokens[start..<(start + parts.count)].map(norm)
            if spoken == parts { return parts.count }
            if parts.count == 1, let t = spoken.first, t.count >= 3, parts[0].count >= 3,
               editDistance(t, parts[0]) <= (parts[0].count <= 4 ? 1 : 2) { return 1 }
            return nil
        }
        if seat == "everyone" {
            for c in leadingCollectives where i + c.count <= tokens.count
                && tokens[i..<(i + c.count)].map(norm) == c {
                return rest(after: i + c.count)
            }
            return i == 0 ? text : rest(after: i)
        }
        if let n = matches(seat, at: i) { return rest(after: i + n) }
        // Another member's name leads the sentence: the seat pick disagrees with the words.
        if roster.contains(where: { $0.lowercased() != seat.lowercased() && matches($0, at: i) != nil }) {
            return nil
        }
        return i == 0 ? text : rest(after: i)
    }

    /// Plain Levenshtein on two short tokens — the one-edit tolerance the recognizer needs.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        var cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                let sub = prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1)
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, sub)
            }
            swap(&prev, &cur)
        }
        return prev[y.count]
    }
}

/// The last terminal read Nova spoke, kept so a follow-up ("what did he mean by that?", "is
/// that the same error as before?") is answered FROM the same screen rather than from memory of
/// having said something. One slot: the conversation has one "that".
@MainActor
enum SeatReadMemory {
    static var last: (seat: String, tail: String, at: Date)?

    /// A block for the answering voice, or empty when nothing was read in the last 10 minutes.
    static var block: String {
        guard let last, Date().timeIntervalSince(last.at) < 600 else { return "" }
        return "\n\nTHE LAST SEAT READ (\(last.seat)'s terminal, verbatim tail — the 'that' in a follow-up):\n\(last.tail)\n"
    }
}
