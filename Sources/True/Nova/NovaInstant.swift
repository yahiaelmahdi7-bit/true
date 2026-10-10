import Foundation

/// INSTANT LANE: a pure, local matcher run on every ADDRESSED partial transcript. No network, no model — the lane
/// decides, the GATE and HANDS still guard (the engine runs every step through `NovaHands`). Ambient speech never
/// reaches it; the engine only feeds it words after the wake name / while the hotkey is held.
///
/// Clause = a piece of the addressed partial split on "and then", "then", "and", "after that", ",". Each clause is
/// dispatched the moment it is complete (or, for the last clause, the moment it fully matches) while later words are
/// still arriving; a dispatched clause never dispatches again as partials revise.

enum InstantVerb: Equatable {
    case openApp(String), hideApp(String), quitApp(String), focusPane(String)
    case volumeUp, volumeDown, mute(Bool), setVolume(Int)
    case media(String)              // play_pause | next | previous
    case scroll(up: Bool), screenshot
    case openSite(name: String, url: String)

    /// Acts that can be taken back with "no / undo". Scroll and screenshot are not undoable.
    var undoable: Bool {
        switch self { case .scroll, .screenshot: return false; default: return true }
    }
    var spoken: String {
        switch self {
        case .openApp(let n): return "opened \(n)"
        case .hideApp(let n): return "hid \(n)"
        case .quitApp(let n): return "quit \(n)"
        case .focusPane(let n): return "focused \(n)"
        case .volumeUp: return "turned the volume up"
        case .volumeDown: return "turned the volume down"
        case .mute(let on): return on ? "muted" : "unmuted"
        case .setVolume(let n): return "set volume to \(n)"
        case .media(let m): return m.replacingOccurrences(of: "_", with: " ")
        case .scroll(let up): return up ? "scrolled up" : "scrolled down"
        case .screenshot: return "took a screenshot"
        case .openSite(let n, _): return "opened \(n)"
        }
    }
}

/// Installed + running app names with aliases. Full-name matches only.
struct AppIndex {
    let names: [String]
    private let byNorm: [String: String]
    static let aliases: [String: String] = [
        "chrome": "Google Chrome", "google chrome": "Google Chrome", "code": "Visual Studio Code", "vs code": "Visual Studio Code",
        "vscode": "Visual Studio Code", "visual studio code": "Visual Studio Code", "settings": "System Settings",
        "system preferences": "System Settings", "preferences": "System Settings", "imessage": "Messages", "word": "Microsoft Word",
        "excel": "Microsoft Excel", "powerpoint": "Microsoft PowerPoint", "term": "Terminal", "activity monitor": "Activity Monitor",
    ]

    init(names: [String]) {
        self.names = names
        var m: [String: String] = [:]
        for n in names { m[Self.norm(n)] = n }
        byNorm = m
    }

    static func norm(_ s: String) -> String {
        String(s.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }).split(separator: " ").joined(separator: " ")
    }

    struct Hit: Equatable { let name: String; let ambiguous: Bool }

    func resolve(_ query: String) -> Hit? {
        let q = Self.norm(query)
        guard !q.isEmpty else { return nil }
        var target = byNorm[q]
        if target == nil, let a = Self.aliases[q], byNorm[Self.norm(a)] != nil { target = a }
        guard let name = target else { return nil }
        let n = Self.norm(name)
        let longer = names.contains { let o = Self.norm($0); return o != n && o.hasPrefix(n + " ") }
        return Hit(name: name, ambiguous: longer)
    }

    /// /Applications, /System/Applications, ~/Applications (one level of subfolders) plus running apps.
    static func scan(running: [String]) -> AppIndex {
        var out = Set(running)
        let fm = FileManager.default
        for root in ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"] {
            for item in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
                if item.hasSuffix(".app") { out.insert(String(item.dropLast(4))); continue }
                for sub in (try? fm.contentsOfDirectory(atPath: root + "/" + item)) ?? [] where sub.hasSuffix(".app") {
                    out.insert(String(sub.dropLast(4)))
                }
            }
        }
        return AppIndex(names: out.sorted())
    }
}

enum NovaInstant {
    static let sites: [String: (name: String, url: String)] = [
        "youtube": ("YouTube", "https://www.youtube.com"), "gmail": ("Gmail", "https://mail.google.com"),
        "github": ("GitHub", "https://github.com"), "google": ("Google", "https://www.google.com"),
        "maps": ("Maps", "https://maps.google.com"), "reddit": ("Reddit", "https://www.reddit.com"),
        "twitter": ("X", "https://x.com"), "claude": ("Claude", "https://claude.ai"),
        "calendar": ("Calendar", "https://calendar.google.com"), "drive": ("Drive", "https://drive.google.com"),
    ]
    static let markers: [[String]] = [["wait", "no"], ["not", "that"], ["i", "mean"], ["no"], ["nope"], ["actually"], ["undo"]]
    static let openVerbs: [[String]] = [["open"], ["launch"], ["start"], ["switch", "to"], ["go", "to"], ["show", "me"], ["show"], ["bring", "up"], ["activate"]]
    static let fillers: Set<String> = ["please", "can", "could", "would", "you", "just", "now", "hey", "okay", "ok", "um", "uh"]

    struct Clause: Equatable {
        var words: [String]
        var markerLen = 0
        var hasMarker: Bool { markerLen > 0 }
    }

    private static func strip(_ t: String) -> String { String(t.lowercased().filter { $0.isLetter || $0.isNumber }) }

    /// Split an addressed partial into clauses. Correction markers start a new clause and stay at its head.
    static func clauses(_ text: String) -> [Clause] {
        let raw = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        var out: [Clause] = []
        var cur: [String] = []
        func flush() { if !cur.isEmpty { out.append(Clause(words: cur, markerLen: markerLen(cur))) }; cur = [] }
        var i = 0
        while i < raw.count {
            let w = strip(raw[i])
            let comma = raw[i].hasSuffix(",") || raw[i].hasSuffix(";")
            if w.isEmpty { i += 1; continue }
            if w == "then" || w == "and" { flush(); i += 1; continue }
            if w == "after", i + 1 < raw.count, strip(raw[i + 1]) == "that" { flush(); i += 2; continue }
            if !cur.isEmpty, let m = markers.first(where: { matches($0, raw, i) }) {
                flush(); cur = m; i += m.count
                if comma || (i > 0 && raw[i - 1].hasSuffix(",")) { /* marker punctuation shed */ }
                continue
            }
            cur.append(w)
            if comma { flush() }
            i += 1
        }
        flush()
        return out
    }
    private static func matches(_ m: [String], _ raw: [String], _ i: Int) -> Bool {
        guard i + m.count <= raw.count else { return false }
        return (0..<m.count).allSatisfy { strip(raw[i + $0]) == m[$0] }
    }
    private static func markerLen(_ w: [String]) -> Int { markers.first(where: { w.count >= $0.count && Array(w.prefix($0.count)) == $0 })?.count ?? 0 }

    enum Match: Equatable { case none, act(InstantVerb, ambiguous: Bool) }

    static func match(_ wordsIn: [String], apps: AppIndex, panes: [String], repair: InstantVerb? = nil) -> Match {
        var w = wordsIn
        while let f = w.first, fillers.contains(f) { w.removeFirst() }
        while let l = w.last, ["please", "now", "app", "for", "me"].contains(l) { w.removeLast() }
        guard !w.isEmpty, w.count <= 7 else { return .none }
        let core = w.filter { !["the", "a", "it", "my"].contains($0) }
        let c = core.joined(separator: " ")

        switch c {
        case "volume up", "turn up", "turn up volume", "turn volume up", "louder", "raise volume": return .act(.volumeUp, ambiguous: false)
        case "volume down", "turn down", "turn down volume", "turn volume down", "quieter", "lower volume": return .act(.volumeDown, ambiguous: false)
        case "mute": return .act(.mute(true), ambiguous: false)
        case "unmute": return .act(.mute(false), ambiguous: false)
        case "play", "pause", "play pause", "play music", "pause music": return .act(.media("play_pause"), ambiguous: false)
        case "next", "next track", "next song", "skip": return .act(.media("next"), ambiguous: false)
        case "previous", "previous track", "previous song": return .act(.media("previous"), ambiguous: false)
        case "scroll up": return .act(.scroll(up: true), ambiguous: false)
        case "scroll down": return .act(.scroll(up: false), ambiguous: false)
        case "screenshot", "take screenshot", "take screen shot": return .act(.screenshot, ambiguous: false)
        default: break
        }
        if let i = core.firstIndex(of: "volume"), core.count <= 5,
           let n = core.compactMap({ Int($0) }).first, ["set", "volume", "to", "percent"].contains(where: { _ in true }),
           core.filter({ Int($0) == nil }).allSatisfy({ ["set", "volume", "to", "percent"].contains($0) }), i >= 0 {
            return .act(.setVolume(max(0, min(100, n))), ambiguous: false)
        }

        func target(_ q: [String]) -> String { q.filter { $0 != "the" }.joined(separator: " ") }
        if let first = core.first, ["quit", "exit"].contains(first), core.count > 1 {
            if let h = apps.resolve(target(Array(core.dropFirst()))), !NovaGate.isOwnApp(name: h.name) { return .act(.quitApp(h.name), ambiguous: h.ambiguous) }
            return .none
        }
        if core.first == "hide", core.count > 1 {
            if let h = apps.resolve(target(Array(core.dropFirst()))), !NovaGate.isOwnApp(name: h.name) { return .act(.hideApp(h.name), ambiguous: h.ambiguous) }
            return .none
        }
        if core.first == "focus", core.count > 1 {
            if let p = pane(target(Array(core.dropFirst())), panes) { return .act(.focusPane(p), ambiguous: false) }
            return .none
        }
        for v in openVerbs where w.count > v.count && Array(w.prefix(v.count)) == v {
            let q = target(Array(w.dropFirst(v.count)))
            let paneFirst = ["show", "switch", "go", "show me"].contains(v.joined(separator: " ")) || v[0] == "show"
            if paneFirst, let p = pane(q, panes) { return .act(.focusPane(p), ambiguous: false) }
            if let h = apps.resolve(q) { return .act(.openApp(h.name), ambiguous: h.ambiguous) }
            if let p = pane(q, panes) { return .act(.focusPane(p), ambiguous: false) }
            if let s = sites[q] { return .act(.openSite(name: s.name, url: s.url), ambiguous: false) }
            return .none
        }
        // "no, Chrome": a bare name right after taking back an open means "open that instead".
        if let repair, w.count <= 3 {
            let q = target(w)
            switch repair {
            case .openApp, .quitApp, .hideApp:
                if let h = apps.resolve(q) { return .act(.openApp(h.name), ambiguous: h.ambiguous) }
            case .focusPane:
                if let p = pane(q, panes) { return .act(.focusPane(p), ambiguous: false) }
            default: break
            }
        }
        return .none
    }
    private static func pane(_ q: String, _ panes: [String]) -> String? { panes.first { AppIndex.norm($0) == AppIndex.norm(q) } }
}

/// Stateful per-turn driver: feed it the addressed words each time a partial arrives (and again on a timer tick).
struct NovaInstantSession {
    struct Step: Equatable {
        enum Kind: Equatable { case act(InstantVerb), undo(actID: Int) }
        let id: Int
        let clause: Int
        let kind: Kind
        /// When the partial that completed this clause arrived — start of the dispatch-latency clock.
        let completedAt: Date
    }

    static let undoDepth = 3
    static let undoTTL: TimeInterval = 8

    let apps: AppIndex
    let panes: [String]
    let prefixWait: TimeInterval
    private var nextID = 1
    private var dispatched: [Int: (text: String, verb: InstantVerb, actID: Int)] = [:]
    private var markerUndone: [Int: InstantVerb] = [:]
    private var live: [(id: Int, verb: InstantVerb, at: Date)] = []
    private var waiting: (key: String, since: Date)?
    private(set) var unhandled = ""
    var handled: [String] { dispatched.keys.sorted().compactMap { dispatched[$0]?.verb.spoken } }

    init(apps: AppIndex, panes: [String], prefixWait: TimeInterval = 0.25) {
        self.apps = apps; self.panes = panes; self.prefixWait = prefixWait
    }

    private mutating func liveTop(_ now: Date) -> (id: Int, verb: InstantVerb, at: Date)? {
        live = live.filter { now.timeIntervalSince($0.at) <= Self.undoTTL }
        return live.last
    }
    private mutating func takeLive(id: Int, now: Date) -> Bool {
        guard live.contains(where: { $0.id == id }) else { return false }
        live.removeAll { $0.id == id }; return true
    }

    mutating func feed(_ words: String, now: Date) -> [Step] {
        var steps: [Step] = []
        var rest: [String] = []
        let cs = NovaInstant.clauses(words)
        for (i, c) in cs.enumerated() {
            let isLast = i == cs.count - 1
            var w = c.words
            var repair: InstantVerb?
            if c.hasMarker {
                if markerUndone[i] == nil {
                    guard let top = liveTop(now) else { rest.append(w.joined(separator: " ")); continue }  // "no" elsewhere = ordinary words
                    live.removeAll { $0.id == top.id }
                    steps.append(Step(id: nextID, clause: i, kind: .undo(actID: top.id), completedAt: now)); nextID += 1
                    markerUndone[i] = top.verb
                }
                w = Array(c.words.dropFirst(c.markerLen)); repair = markerUndone[i]
            }
            let text = w.joined(separator: " ")
            if text.isEmpty { continue }
            let m = NovaInstant.match(w, apps: apps, panes: panes, repair: repair)
            if let d = dispatched[i] {
                if d.text == text { continue }
                if case .act(let v, _) = m, v == d.verb { dispatched[i]?.text = text; continue }
                // Material revision of a clause we already acted on: take it back, then handle the new text.
                if takeLive(id: d.actID, now: now) {
                    steps.append(Step(id: nextID, clause: i, kind: .undo(actID: d.actID), completedAt: now)); nextID += 1
                }
                dispatched[i] = nil
            }
            guard case .act(let verb, let ambiguous) = m else { rest.append(text); continue }
            if isLast, ambiguous {
                if waiting?.key != text { waiting = (text, now); continue }
                if now.timeIntervalSince(waiting!.since) < prefixWait { continue }
            }
            let id = nextID; nextID += 1
            steps.append(Step(id: id, clause: i, kind: .act(verb), completedAt: now))
            dispatched[i] = (text, verb, id)
            if verb.undoable {
                live.append((id, verb, now))
                if live.count > Self.undoDepth { live.removeFirst(live.count - Self.undoDepth) }
            }
        }
        unhandled = rest.joined(separator: " ")
        return steps
    }
}

/// Run 26e: "tell the CTO to review the PR" -> the rest of HIS utterance goes verbatim to the agent.
enum NovaTell {
    struct Tell: Equatable { let target: String; let text: String }
    static let verbs: Set<String> = ["tell", "ask", "message"]

    /// "tell/ask/message <agent> [to] <rest>": longest agent phrase wins; two agents behind one phrase = ambiguous = nil.
    /// `text` is the rest of the original utterance, tokens joined by single spaces, never rewritten.
    static func parse(_ rawText: String, roster: [String]) -> Tell? {
        let toks = rawText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard toks.count >= 3, verbs.contains(AppIndex.norm(toks[0])) else { return nil }
        var i = 1
        if AppIndex.norm(toks[i]) == "the" { i += 1 }
        var index: [String: Set<String>] = [:]
        for name in roster {
            let n = AppIndex.norm(name)
            index[n, default: []].insert(name)
            if n.hasPrefix("true ") { index[String(n.dropFirst(5)), default: []].insert(name) }
        }
        for k in stride(from: min(4, toks.count - i - 1), through: 1, by: -1) {
            let key = AppIndex.norm(toks[i..<(i + k)].joined(separator: " "))
            guard let hit = index[key] else { continue }
            guard hit.count == 1, let name = hit.first else { return nil }
            var j = i + k
            if j < toks.count, AppIndex.norm(toks[j]) == "to" { j += 1 }
            guard j < toks.count else { return nil }
            return Tell(target: name, text: toks[j...].joined(separator: " "))
        }
        return nil
    }
}

/// One verbatim send per turn, only at the final end of a turn, addressed, and not while Nova is speaking.
struct NovaTellTurn {
    private(set) var sent = false
    mutating func finalize(_ text: String, roster: [String], addressed: Bool, gated: Bool, final: Bool) -> NovaTell.Tell? {
        guard final, addressed, !gated, !sent, let t = NovaTell.parse(text, roster: roster) else { return nil }
        sent = true
        return t
    }
    mutating func reset() { sent = false }
}
