import Foundation

/// Where an agent task goes.
enum CommandTarget: Equatable, Sendable {
    case focusedPane, newClaudePane, backgroundBuilder
    case seat(String)

    var id: String {
        switch self {
        case .focusedPane: "focused_pane"
        case .newClaudePane: "new_claude_pane"
        case .backgroundBuilder: "background_builder"
        case .seat(let n): "seat_\(n)"
        }
    }
    init?(id: String) {
        switch id {
        case "focused_pane": self = .focusedPane
        case "new_claude_pane": self = .newClaudePane
        case "background_builder": self = .backgroundBuilder
        default:
            guard id.hasPrefix("seat_"), id.count > 5 else { return nil }
            self = .seat(String(id.dropFirst(5)))
        }
    }
}

/// What Jev is shown: the focused pane, the candidate projects (already ranked by code) and the seats.
struct CommandContext: Equatable, Sendable {
    var focused: FocusedPane
    var projects: [Project]      // ranked candidates, at most `maxProjects`
    var seats: [BarSeat]
    var all: [Project] = []      // every known project: `open_project` ranks over these, not just the candidates
    static let maxProjects = 8

    /// The project the focused pane is in, when it is one of the known projects.
    var current: Project? {
        guard let n = focused.project else { return nil }
        return projects.first { $0.name == n }
    }
}

/// One slot of the route line, so a chip can carry a "?" when Jev was under the floor.
enum RouteSlot: String, Sendable, CaseIterable { case kind, project, target, action }

/// What the bar shows and what Return runs.
struct Route: Equatable, Sendable {
    var text: String                 // payload (prefix stripped)
    var kind: CommandKind
    var kindConfidence: Double?
    var project: Project?            // nil = the focused pane's own project
    var target: CommandTarget
    var action: CommandAction
    var seat: String?                // wake_seat / sleep_seat subject
    var destructive: Double?         // nil = Jev did not answer
    var model: AgentModel?
    var effort: AgentEffort?
    var uncertain: Set<RouteSlot> = []
    /// kind confidence < 0.5: the bar shows "Run in shell / Send to Claude" instead of a guess.
    var twoChoice = false
    /// Other doors worth Tab, most likely first.
    var alternatives: [CommandKind] = []
    var viaRule = false

    var isDestructive: Bool { (destructive ?? 0) >= CommandRouter.destructiveFloor }
}

enum CommandRouter {
    static let floor = 0.6
    static let kindFloor = 0.5
    static let destructiveFloor = 0.5
    static let timeout: TimeInterval = 3
    static let debounce: Duration = .milliseconds(300)

    // MARK: Questions

    static func projectID(_ i: Int) -> String { "p\(i)" }

    static func state(text: String, context c: CommandContext) -> [String: Any] {
        func opt(_ s: String?) -> Any { s ?? NSNull() }
        var projects: [[String: Any]] = c.projects.enumerated().map { ["id": projectID($0.offset), "name": $0.element.name] }
        if projects.isEmpty { projects = [] }
        return [
            "text": text,
            "focused": ["kind": c.focused.kind.rawValue, "project": opt(c.focused.project), "seat": opt(c.focused.seat)],
            "projects": projects,
            "seats": c.seats.map { ["name": $0.name, "project": $0.project, "awake": $0.awake] },
        ]
    }

    static func questions(text: String, context c: CommandContext, onlyDanger: Bool) -> [String: JevQuestion] {
        let destructive = JevQuestion.noul(
            "Does `text` push commits to a remote, delete or wipe data, force-push, deploy, publish, send messages or write to a live third-party service?")
        if onlyDanger { return ["destructive": destructive] }
        var q: [String: JevQuestion] = ["destructive": destructive]
        q["kind"] = .choice("What does `text` ask for, given the `focused` pane?", [
            (id: "shell_command", what: "a command for the terminal shell, run as typed"),
            (id: "agent_task", what: "an instruction for a Claude agent to do work"),
            (id: "question_for_claude", what: "a question for Claude to answer, changing nothing"),
            (id: "true_action", what: "a verb for the True app itself: open a project, new tab, split, show the hub"),
            (id: "none", what: "none of these"),
        ])
        var proj: [(id: String, what: String)] = c.projects.enumerated().map { (id: projectID($0.offset), what: $0.element.name) }
        if c.focused.project != nil { proj.append((id: "current", what: "the project of the `focused` pane")) }
        proj.append((id: "none", what: "no particular project"))
        q["project"] = .choice("Which project does `text` mean? Candidates are in `projects`.", proj)
        var target: [(id: String, what: String)] = []
        if c.focused.kind != .empty { target.append((id: "focused_pane", what: "the pane the user is looking at, as is")) }
        target.append((id: "new_claude_pane", what: "a fresh Claude pane in the project"))
        for s in c.seats { target.append((id: "seat_\(s.name)", what: "the named seat `\(s.name)` of project \(s.project)")) }
        target.append((id: "background_builder", what: "a long detached build running without a pane"))
        q["target"] = .choice("Where should the work in `text` go?", target)
        q["action"] = .choice("Which True verb is `text`, if it is one?", [
            (id: "open_project", what: "open a project's folder in a pane"),
            (id: "new_tab", what: "open a new tab"),
            (id: "split_right", what: "split the pane to the right"),
            (id: "split_down", what: "split the pane downward"),
            (id: "show_hub", what: "show the Hub of agents"),
            (id: "show_results", what: "show the results sheet"),
            (id: "wake_seat", what: "start a named seat"),
            (id: "sleep_seat", what: "stop a named seat"),
            (id: "fill_displays", what: "fill all displays"),
            (id: "none", what: "not a True verb"),
        ])
        q["model"] = JevFill.modelQuestion(subject: "text")
        q["effort"] = JevFill.effortQuestion(subject: "text")
        return q
    }

    // MARK: Reply → Route (pure)

    static func defaultKind(_ f: FocusedPane) -> CommandKind {
        f.kind == .claude || f.kind == .seat ? .agentTask : .shellCommand
    }

    static func defaultTarget(_ f: FocusedPane, kind: CommandKind) -> CommandTarget {
        (f.kind == .claude || f.kind == .seat) ? .focusedPane : .newClaudePane
    }

    static func route(text: String, reply: JevReply?, context c: CommandContext, rule: RuleMatch? = nil,
                      isExecutable: (String) -> Bool = { _ in false }) -> Route {
        let payload = rule?.payload ?? text
        var r = Route(text: payload, kind: defaultKind(c.focused), kindConfidence: nil, project: nil,
                      target: .focusedPane, action: .none, seat: nil, destructive: nil, model: nil, effort: nil)
        r.target = defaultTarget(c.focused, kind: r.kind)

        func sure(_ id: String, floor f: Double = floor) -> JevAnswer? {
            guard let a = reply?.answers[id], let conf = a.confidence, conf >= f else { return nil }
            return a
        }

        var jevPickedKind = false
        if let reply {
            r.destructive = reply.answers["destructive"]?.noul
            if let a = reply.answers["kind"], let conf = a.confidence {
                r.kindConfidence = conf
                if let k = a.choice.flatMap(CommandKind.init(rawValue:)), k != .none, conf >= floor { r.kind = k; jevPickedKind = true }
                else {
                    r.uncertain.insert(.kind)
                    if conf < kindFloor { r.twoChoice = true }
                }
                if let probs = a.probabilities {
                    r.alternatives = probs.compactMap { id, p in
                        CommandKind(rawValue: id).flatMap { $0 == .none || $0 == r.kind || p < 0.15 ? nil : ($0, p) }
                    }.sorted { $0.1 > $1.1 }.prefix(3).map(\.0)
                }
            }
            if let a = reply.answers["project"] {
                if let conf = a.confidence, conf >= floor, let id = a.choice {
                    if id.hasPrefix("p"), let i = Int(id.dropFirst()), c.projects.indices.contains(i) {
                        let p = c.projects[i]
                        r.project = p.name == c.focused.project ? nil : p
                    }   // current / none / unknown id → the focused pane's own project
                } else { r.uncertain.insert(.project) }
            }
            if let a = reply.answers["target"] {
                if let conf = a.confidence, conf >= floor, let t = a.choice.flatMap(CommandTarget.init(id:)) {
                    r.target = validated(t, project: r.project?.name ?? c.focused.project, context: c, fallback: r.target)
                } else { r.uncertain.insert(.target) }
            }
            if let a = reply.answers["action"] {
                if let conf = a.confidence, conf >= floor, let act = a.choice.flatMap(CommandAction.init(rawValue:)) { r.action = act }
                else { r.uncertain.insert(.action) }
            }
            if let m = sure("model")?.choice.flatMap(AgentModel.init(rawValue:)) { r.model = m }
            if let s = sure("effort")?.score { r.effort = JevFill.effort(fromScore: s) }
        }
        // A sentence must never be typed into a shell and sent: a shell kind needs a first word that can run.
        if jevPickedKind, r.kind == .shellCommand,
           !CommandRules.looksRunnable(payload, isExecutable: isExecutable) {
            r.kind = defaultKind(c.focused)
            r.uncertain.insert(.kind)
            r.twoChoice = true
        }
        // open_project takes the matcher's top hit for the text minus the verb words; Jev's slot is the fallback.
        if r.action == .openProject {
            let q = CommandRules.stripVerbWords(payload)
            if !q.isEmpty, let hit = ProjectMatcher.rank(c.all.isEmpty ? c.projects : c.all, query: q).first {
                r.project = hit
                r.uncertain.remove(.project)
            }
        }
        // A true_action with no verb is not runnable: fall back to the pane-aware default.
        if r.kind == .trueAction, r.action == .none { r.kind = defaultKind(c.focused) }
        // A seat target needs a seat of the project the work is for; a focused-pane target needs a pane.
        if case .focusedPane = r.target, c.focused.kind == .empty { r.target = .newClaudePane }
        // Agent work aimed at another project cannot land in the focused pane.
        if r.project != nil, r.target == .focusedPane { r.target = .newClaudePane }

        if r.action == .wakeSeat || r.action == .sleepSeat, r.seat == nil {
            r.seat = CommandRules.namedSeat(in: payload, seats: c.seats, preferProject: c.focused.project)?.name
        }
        applySeatPolicy(&r, text: payload, context: c)

        if let rule { apply(rule, to: &r, context: c, jevAnswered: reply != nil) }
        return r
    }

    /// SPEC Run 14 item 3, in order: a seat named in the text wins; an agent_task never lands on an unnamed seat;
    /// a question outside the focused Claude pane's project goes to an awake seat there, else a new pane.
    private static func applySeatPolicy(_ r: inout Route, text: String, context c: CommandContext) {
        guard r.kind.sendsToClaude else { return }
        let focusedProject = c.focused.project
        if let s = CommandRules.namedSeat(in: text, seats: c.seats, preferProject: r.project?.name ?? focusedProject) {
            r.target = .seat(s.name)
            r.seat = s.name
            r.uncertain.remove(.target)
            if s.project == focusedProject { r.project = nil; r.uncertain.remove(.project) }
            else if let p = (c.projects + c.all).first(where: { $0.name == s.project }) { r.project = p; r.uncertain.remove(.project) }
            return
        }
        if case .backgroundBuilder = r.target { return }
        let project = r.project?.name ?? focusedProject
        let onClaude = c.focused.kind == .claude || c.focused.kind == .seat
        let focusedClaudeHere = onClaude && c.focused.project == project
        switch r.kind {
        case .agentTask:
            if case .seat = r.target { r.target = focusedClaudeHere ? .focusedPane : .newClaudePane }
        case .questionForClaude where !focusedClaudeHere:
            let awake = project.map { p in c.seats.filter { $0.project == p && $0.awake } } ?? []
            if case .seat(let n) = r.target, awake.contains(where: { $0.name == n }) { return }
            if let first = awake.first { r.target = .seat(first.name); r.seat = first.name } else { r.target = .newClaudePane }
        default: break
        }
    }

    /// A seat target only stands when that seat belongs to the project the work is for.
    private static func validated(_ t: CommandTarget, project: String?, context c: CommandContext,
                                  fallback: CommandTarget) -> CommandTarget {
        guard case .seat(let n) = t else { return t }
        guard let s = c.seats.first(where: { $0.name == n }), project == nil || s.project == project else { return fallback }
        return t
    }

    private static func apply(_ rule: RuleMatch, to r: inout Route, context c: CommandContext, jevAnswered: Bool) {
        r.viaRule = true
        if !rule.authoritative {
            // A guess: keep Jev's pick when it was sure, fill in only when it was absent or unsure.
            guard !jevAnswered || r.uncertain.contains(.kind) else { r.viaRule = false; return }
        }
        if let k = rule.kind {
            r.kind = k
            r.twoChoice = false
            r.uncertain.remove(.kind)
        }
        if let p = rule.project { r.project = p.name == c.focused.project ? nil : p; r.uncertain.remove(.project) }
        if let s = rule.seat {
            r.target = .seat(s)
            r.seat = s
            r.uncertain.remove(.target)
            if let seat = c.seats.first(where: { $0.name == s }), seat.project != c.focused.project,
               let p = c.projects.first(where: { $0.name == seat.project }) { r.project = p }
        }
        if rule.action != .none { r.action = rule.action; r.uncertain.remove(.action) }
        if rule.kind == .shellCommand { r.target = .focusedPane; r.model = nil; r.effort = nil }
    }

    /// Tab: swap the door for the runner-up, keeping everything else.
    static func switching(_ r: Route, to k: CommandKind, context c: CommandContext) -> Route {
        var n = r
        n.kind = k
        n.twoChoice = false
        n.uncertain.remove(.kind)
        n.alternatives = ([r.kind] + r.alternatives.filter { $0 != k }).filter { $0 != .none }
        if k.sendsToClaude, case .backgroundBuilder = n.target {} else if k.sendsToClaude {
            n.target = n.project == nil ? defaultTarget(c.focused, kind: k) : .newClaudePane
        }
        return n
    }

    // MARK: The wire

    static func ask(text: String, context c: CommandContext, rule: RuleMatch?, jev: JevClient) async -> JevReply? {
        await jev.ask(state: state(text: rule?.payload ?? text, context: c),
                      questions: questions(text: rule?.payload ?? text, context: c, onlyDanger: rule?.onlyDanger ?? false),
                      timeout: timeout)
    }

    /// Candidate projects for the state: the ranked hits for the whole line, then per word, then recents.
    static func candidates(text: String, projects: [Project], recent: [String]) -> [Project] {
        var out: [Project] = []
        func add(_ ps: [Project]) { for p in ps where !out.contains(p) && out.count < CommandContext.maxProjects { out.append(p) } }
        let q = text.trimmingCharacters(in: .whitespaces)
        add(Array(ProjectMatcher.rank(projects, query: q, recent: recent).prefix(4)))
        for w in q.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" }) where w.count >= 3 {
            add(Array(ProjectMatcher.rank(projects, query: String(w), recent: recent).prefix(2)))
        }
        add(Array(ProjectMatcher.rank(projects, query: "", recent: recent).prefix(4)))
        return out
    }
}
