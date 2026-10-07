import Testing
import Foundation
@testable import True

private func ans(_ type: String, choice: String? = nil, _ conf: Double? = 0.9, noul: Double? = nil) -> JevAnswer {
    JevAnswer(type: type, choice: choice, confidence: conf, probabilities: nil, noul: noul, score: nil)
}
private func proj(_ n: String) -> Project { Project(name: n, path: "/p/\(n)", parent: "/p") }
private func reply(_ a: [String: JevAnswer]) -> JevReply { JevReply(answers: a) }

private let allProjects = [proj("true"), proj("TradingAgents"), proj("prism")]
private let allSeats = [
    BarSeat(name: "true-cto", project: "true", awake: true),
    BarSeat(name: "true-security", project: "true", awake: false),
    BarSeat(name: "prism-lead", project: "prism", awake: true),
    BarSeat(name: "prism-qa", project: "prism", awake: false),
]
private func ctx(_ kind: PaneKind, project: String? = "true", seat: String? = nil) -> CommandContext {
    CommandContext(focused: FocusedPane(kind: kind, project: project, seat: seat, cwd: project.map { "/p/\($0)" }),
                   projects: allProjects, seats: allSeats, all: allProjects)
}
private func kindTarget(_ kind: String, _ target: String?, project: String? = nil) -> JevReply {
    var a = ["kind": ans("choice", choice: kind)]
    if let target { a["target"] = ans("choice", choice: target) }
    if let project { a["project"] = ans("choice", choice: project) }
    return reply(a)
}

@Suite struct DangerFixTests {
    @Test func destructiveQuestionIsTheSpecString() {
        let q = CommandRouter.questions(text: "x", context: ctx(.shell), onlyDanger: true)["destructive"]
        let want = "Does `text` push commits to a remote, delete or wipe data, force-push, deploy, publish, send messages or write to a live third-party service?"
        #expect(String(describing: q).contains(want))
    }
    @Test func plainGitPushIsDangerous() {
        for t in ["git push", "git push origin main", "git  push -u origin x", "cd x && git push"] { #expect(CommandRules.isDangerous(t), "\(t)") }
        #expect(!CommandRules.isDangerous("git pull") && !CommandRules.isDangerous("git status"))
    }
}

@Suite struct SeatPolicyTests {
    // (1) a named seat wins
    @Test func namedSeatWinsAndSetsProject() {
        let r = CommandRouter.route(text: "ask prism-lead to fix the build", reply: kindTarget("agent_task", "new_claude_pane"), context: ctx(.claude))
        #expect(r.target == .seat("prism-lead") && r.seat == "prism-lead" && r.project?.name == "prism")
    }
    @Test func namedByDisplayNameCaseInsensitiveAsleepToo() {
        let r = CommandRouter.route(text: "have the QA check it", reply: kindTarget("question_for_claude", "focused_pane"), context: ctx(.claude))
        #expect(r.target == .seat("prism-qa") && r.project?.name == "prism")
        let s = CommandRouter.route(text: "Security should audit it", reply: kindTarget("agent_task", nil), context: ctx(.claude))
        #expect(s.target == .seat("true-security") && s.project == nil)
    }
    @Test func wholeWordOnly() {
        let r = CommandRouter.route(text: "the ctor is wrong", reply: kindTarget("agent_task", nil), context: ctx(.claude))
        #expect(r.target == .focusedPane)
        #expect(!CommandRules.containsWholeWord("octopus", "cto") && CommandRules.containsWholeWord("ask CTO now", "cto"))
    }
    @Test func namedSeatIsInJevStateCandidates() {
        let q = CommandRouter.questions(text: "ask prism-lead", context: ctx(.shell), onlyDanger: false)
        #expect(String(describing: q["target"]).contains("seat_prism-lead"))
    }

    // (2) agent_task never targets an unnamed seat
    @Test func agentTaskUnnamedSeatBecomesFocusedPaneWhenClaudeHere() {
        let r = CommandRouter.route(text: "fix the tests", reply: kindTarget("agent_task", "seat_true-cto"), context: ctx(.claude))
        #expect(r.target == .focusedPane)
        let s = CommandRouter.route(text: "fix the tests", reply: kindTarget("agent_task", "seat_true-cto"), context: ctx(.seat, seat: "true-cto"))
        #expect(s.target == .focusedPane)
    }
    @Test func agentTaskUnnamedSeatBecomesNewPaneOtherwise() {
        let shell = CommandRouter.route(text: "fix the tests", reply: kindTarget("agent_task", "seat_true-cto"), context: ctx(.shell))
        #expect(shell.target == .newClaudePane)
        let empty = CommandRouter.route(text: "fix the tests", reply: kindTarget("agent_task", "seat_true-cto"), context: ctx(.empty, project: nil))
        #expect(empty.target == .newClaudePane)
        // another project picked: the focused Claude pane is not that project's
        let other = CommandRouter.route(text: "fix the tests", reply: kindTarget("agent_task", "seat_prism-lead", project: "p2"), context: ctx(.claude))
        #expect(other.project?.name == "prism" && other.target == .newClaudePane)
    }
    @Test func agentTaskKeepsBackgroundBuilder() {
        let r = CommandRouter.route(text: "long build", reply: kindTarget("agent_task", "background_builder"), context: ctx(.claude))
        #expect(r.target == .backgroundBuilder)
    }

    // (3) question_for_claude in another project
    @Test func questionInFocusedClaudeProjectKeepsTarget() {
        let r = CommandRouter.route(text: "why is it slow", reply: kindTarget("question_for_claude", "focused_pane"), context: ctx(.claude))
        #expect(r.target == .focusedPane)
    }
    @Test func questionElsewhereGoesToAwakeSeatThere() {
        let r = CommandRouter.route(text: "why is it slow", reply: kindTarget("question_for_claude", "focused_pane", project: "p2"), context: ctx(.claude))
        #expect(r.project?.name == "prism" && r.target == .seat("prism-lead"))
    }
    @Test func questionElsewherePrefersJevsAwakeSeatElseFirst() {
        let seats = [BarSeat(name: "prism-a", project: "prism", awake: true), BarSeat(name: "prism-b", project: "prism", awake: true),
                     BarSeat(name: "prism-c", project: "prism", awake: false)]
        let c = CommandContext(focused: FocusedPane(kind: .claude, project: "true", seat: nil, cwd: nil),
                               projects: allProjects, seats: seats, all: allProjects)
        let pick = CommandRouter.route(text: "why", reply: kindTarget("question_for_claude", "seat_prism-b", project: "p2"), context: c)
        #expect(pick.target == .seat("prism-b"))
        let asleep = CommandRouter.route(text: "why", reply: kindTarget("question_for_claude", "seat_prism-c", project: "p2"), context: c)
        #expect(asleep.target == .seat("prism-a"))
    }
    @Test func questionElsewhereWithNoAwakeSeatGetsNewPane() {
        let seats = [BarSeat(name: "prism-c", project: "prism", awake: false)]
        let c = CommandContext(focused: FocusedPane(kind: .claude, project: "true", seat: nil, cwd: nil),
                               projects: allProjects, seats: seats, all: allProjects)
        let r = CommandRouter.route(text: "why", reply: kindTarget("question_for_claude", "focused_pane", project: "p2"), context: c)
        #expect(r.target == .newClaudePane)
    }
    @Test func questionFromAShellPaneGoesToAnAwakeSeatInItsProject() {
        let r = CommandRouter.route(text: "why is it slow", reply: kindTarget("question_for_claude", "new_claude_pane"), context: ctx(.shell))
        #expect(r.target == .seat("true-cto"))
    }
    @Test func namedAsleepSeatBeatsAwakePolicy() {
        let r = CommandRouter.route(text: "why did QA skip it", reply: kindTarget("question_for_claude", nil), context: ctx(.claude))
        #expect(r.target == .seat("prism-qa") && !allSeats[3].awake)
        #expect(CommandExecutor.plan(route: r, background: false, context: ctx(.claude)).door == .seat("prism-qa"))
    }
    @Test func shellAndActionKindsAreLeftAlone() {
        let r = CommandRouter.route(text: "ls true-cto", reply: kindTarget("shell_command", nil), context: ctx(.shell), isExecutable: { $0 == "ls" })
        #expect(r.kind == .shellCommand && r.target == .newClaudePane || r.target == .focusedPane)
        #expect(r.seat == nil)
    }
}

@Suite struct OpenProjectTests {
    private func open(_ text: String, jevProject: String? = nil, focused: String = "true") -> Route {
        var a = ["kind": ans("choice", choice: "true_action"), "action": ans("choice", choice: "open_project")]
        if let jevProject { a["project"] = ans("choice", choice: jevProject) }
        return CommandRouter.route(text: text, reply: reply(a), context: ctx(.shell, project: focused))
    }
    @Test func matcherBeatsJevsSlot() {
        let r = open("open trading", jevProject: "current")
        #expect(r.project?.name == "TradingAgents" && r.action == .openProject)
        #expect(CommandExecutor.plan(route: r, background: false, context: ctx(.shell)).argv == ["/p/TradingAgents"])
    }
    @Test func matcherHitOnFocusedProjectStillCarriesThePath() {
        let r = open("open true")
        #expect(r.project?.name == "true")
    }
    @Test func jevSlotIsTheFallbackWhenMatcherFindsNothing() {
        let r = open("open zzzqq", jevProject: "p2")
        #expect(r.project?.name == "prism")
    }
    @Test func verbWordsStripped() {
        #expect(CommandRules.stripVerbWords("open the project Prism") == "Prism")
        #expect(CommandRules.stripVerbWords("go to trading") == "trading")
    }
    @Test func rankedOverAllProjectsNotJustCandidates() {
        let c = CommandContext(focused: FocusedPane(kind: .shell, project: "true", seat: nil, cwd: nil),
                               projects: [proj("true")], seats: [], all: allProjects)
        let a = ["kind": ans("choice", choice: "true_action"), "action": ans("choice", choice: "open_project")]
        #expect(CommandRouter.route(text: "open prism", reply: reply(a), context: c).project?.name == "prism")
    }
}

@Suite struct ShellGateTests {
    private let exe: (String) -> Bool = { ["ls", "git", "npm"].contains($0) }
    private func route(_ text: String, rule: RuleMatch? = nil, focused: PaneKind = .shell) -> Route {
        CommandRouter.route(text: text, reply: kindTarget("shell_command", nil), context: ctx(focused), rule: rule, isExecutable: exe)
    }
    @Test func sentenceIsNotShell() {
        let r = route("commit and push")
        #expect(r.twoChoice && r.uncertain.contains(.kind) && r.kind == .shellCommand)   // shell-pane default, but nothing auto-sent
        let c = route("commit and push", focused: .claude)
        #expect(c.twoChoice && c.kind == .agentTask)
    }
    @Test func executableBuiltinAndPathPass() {
        for t in ["ls -la", "git status", "cd ..", "echo hi", "./run.sh", "~/bin/x", "/usr/bin/env"] {
            let r = route(t)
            #expect(!r.twoChoice && r.kind == .shellCommand, "\(t)")
        }
    }
    @Test func bangPrefixSkipsTheGate() {
        let rule = RuleMatch(kind: .shellCommand, payload: "frobnicate now")
        let r = route("!frobnicate now", rule: rule)
        #expect(!r.twoChoice && r.kind == .shellCommand && r.viaRule)
    }
    @Test func gateOnlyJudgesTheShellKind() {
        let r = CommandRouter.route(text: "commit and push", reply: kindTarget("agent_task", nil), context: ctx(.claude), isExecutable: exe)
        #expect(!r.twoChoice && r.kind == .agentTask)
    }
    @Test func twoChoiceIsNeverAutoRun() async {
        // the store refuses Return while twoChoice; the route itself must carry the flag
        #expect(route("please tidy up").twoChoice)
    }
}

@Suite struct LiveInputTests {
    @Test func envPathWinsWhenAbsoluteElseDefault() {
        #expect(CommandBarFixture.liveURL(env: [:]) == CommandBarFixture.defaultURL)
        #expect(CommandBarFixture.liveURL(env: ["COMMANDBAR_FIXTURE": "relative.json"]) == CommandBarFixture.defaultURL)
        #expect(CommandBarFixture.liveURL(env: ["COMMANDBAR_FIXTURE": "/tmp/x/other.json"]).lastPathComponent == "other.json")
    }
    @Test func loadsFromAGivenFile() throws {
        let fx = try CommandBarFixture.load(from: CommandBarFixture.defaultURL)
        #expect(fx.cases.count == 39)
    }
}
