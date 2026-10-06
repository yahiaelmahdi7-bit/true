import Testing
import Foundation
@testable import True

/// Hand-labelled synthetic turns. THE LABELS ARE WRITTEN FIRST (the `expected` column below was fixed before any
/// run); the test only prints label vs verdict + probabilities so the thresholds can be calibrated. Run with
/// JEV_LIVE=1 only (the orchestrator runs it; builders never do).
private struct Case {
    let category: String
    let expected: VerdictKind?          // nil = no verdict
    let asked: String
    let steps: [(tool: String, what: String, result: String, failed: Bool)]
    let edited: Bool
    let answer: String
}

private let ok = "Test run with 42 tests passed after 3.1s"
private let cases: [Case] = [
    // verified — a check ran and passed after the work
    Case(category: "verified", expected: .verified, asked: "Fix the off-by-one in pager.swift and make sure tests pass",
         steps: [("Edit", "Sources/pager.swift", "updated", false), ("Bash", "swift test", ok, false)], edited: true,
         answer: "Fixed the off-by-one in pager.swift; swift test now passes (42 tests)."),
    Case(category: "verified", expected: .verified, asked: "Add a /health endpoint",
         steps: [("Write", "server/health.py", "created", false), ("Bash", "pytest -q", "5 passed in 0.4s", false),
                 ("Bash", "curl -s localhost:8000/health", "{\"ok\":true}", false)], edited: true,
         answer: "Added GET /health returning {ok:true}. Tests pass and curl confirms the endpoint responds."),
    Case(category: "verified", expected: .verified, asked: "Rename Foo to Bar everywhere",
         steps: [("Bash", "sed -i '' s/Foo/Bar/g src/*.ts", "", false), ("Bash", "tsc --noEmit", "", false), ("Bash", "npm test", "12 passed", false)],
         edited: true, answer: "Renamed Foo to Bar in all of src; the type-check and the 12 tests pass."),
    // unverified — says done, nothing checked it
    Case(category: "unverified-no-check", expected: .unverified, asked: "Make the login form validate emails",
         steps: [("Edit", "src/Login.tsx", "updated", false)], edited: true,
         answer: "Done — the login form now validates email addresses."),
    Case(category: "unverified-no-check", expected: .unverified, asked: "Speed up the image loader",
         steps: [("Read", "loader.swift", "…", false), ("Edit", "loader.swift", "updated", false)], edited: true,
         answer: "I cached decoded images, so the loader is now much faster. All finished."),
    Case(category: "unverified-no-check", expected: .unverified, asked: "Update the config to use port 9000",
         steps: [("Write", "config.json", "written", false)], edited: true, answer: "Updated config.json to port 9000. Complete."),
    // unverified — a step failed and the answer doesn't say so
    Case(category: "unverified-contradiction", expected: .unverified, asked: "Fix the failing build",
         steps: [("Edit", "main.swift", "updated", false), ("Bash", "swift build", "error: cannot find 'foo' in scope\nexit 1", true)],
         edited: true, answer: "The build is fixed and everything compiles."),
    Case(category: "unverified-contradiction", expected: .unverified, asked: "Make all tests green",
         steps: [("Bash", "pytest", "3 failed, 20 passed", true)], edited: false, answer: "All tests are green now."),
    Case(category: "unverified-contradiction", expected: .unverified, asked: "Deploy the site",
         steps: [("Bash", "vercel deploy --prod", "Error: build failed\nexit code 1", true)], edited: false,
         answer: "Deployed the site to production. Nothing else to do."),
    // partial — some done, more named as left
    Case(category: "partial", expected: .partial, asked: "Migrate all three tables to the new schema",
         steps: [("Bash", "python migrate.py users", "ok", false)], edited: true,
         answer: "I migrated the users table. The orders and invoices tables are still on the old schema."),
    Case(category: "partial", expected: .partial, asked: "Translate the README into French, Spanish and German",
         steps: [("Write", "README.fr.md", "created", false)], edited: true,
         answer: "French is done. Spanish and German are not yet translated."),
    Case(category: "partial", expected: .partial, asked: "Add tests for every public function in utils",
         steps: [("Write", "tests/test_utils.py", "created", false)], edited: true,
         answer: "I covered 4 of the 9 public functions. The remaining 5 still have no tests."),
    // asks_to_continue — offers the next step of the same task
    Case(category: "asks_to_continue", expected: .asksToContinue, asked: "Refactor the parser module step by step",
         steps: [("Edit", "parser.swift", "updated", false)], edited: true,
         answer: "Step 1 is done: tokenizer extracted. Want me to go ahead with step 2, splitting the AST builder?"),
    Case(category: "asks_to_continue", expected: .asksToContinue, asked: "Clean up the dead code in the repo",
         steps: [("Bash", "grep -rn unused .", "12 matches", false)], edited: false,
         answer: "I found 12 unused functions. Shall I continue and delete them?"),
    Case(category: "asks_to_continue", expected: .asksToContinue, asked: "Build the settings screen",
         steps: [("Write", "Settings.swift", "created", false)], edited: true,
         answer: "The layout is in place. Should I carry on and wire up the toggles next?"),
    // asks_you — needs something only the user can give
    Case(category: "asks_you", expected: .asksYou, asked: "Set up the payment webhook",
         steps: [], edited: false, answer: "I need your Stripe webhook signing secret to continue. Can you provide it?"),
    Case(category: "asks_you", expected: .asksYou, asked: "Pick a database for the new service",
         steps: [], edited: false, answer: "Two options: Postgres (relational, familiar) or DynamoDB (serverless). Which do you want?"),
    Case(category: "asks_you", expected: .asksYou, asked: "Tidy the project",
         steps: [("Bash", "ls", "…", false)], edited: false,
         answer: "To free space I'd have to delete your ~/Downloads folder, which is outside this project. Do you approve?"),
    // blocked — hit an error it couldn't pass
    Case(category: "blocked", expected: .blocked, asked: "Install the dependencies and run the app",
         steps: [("Bash", "npm install", "npm ERR! EACCES permission denied", true)], edited: false,
         answer: "I couldn't install the dependencies: npm fails with EACCES permission denied and I can't get past it."),
    Case(category: "blocked", expected: .blocked, asked: "Push the branch",
         steps: [("Bash", "git push", "fatal: Authentication failed", true)], edited: false,
         answer: "The push failed with an authentication error and I have no way to fix it from here."),
    Case(category: "blocked", expected: .blocked, asked: "Run the migration",
         steps: [("Bash", "alembic upgrade head", "could not connect to server: Connection refused", true)], edited: false,
         answer: "I'm stuck: the database refuses connections, so the migration cannot run."),
    // answered — a question, not work
    Case(category: "answered", expected: nil, asked: "What does the Stop hook do?", steps: [("Read", "AgentHooks.swift", "…", false)], edited: false,
         answer: "The Stop hook fires when Claude finishes a turn; True's forwarder sends it to the events socket."),
    Case(category: "answered", expected: nil, asked: "Is Swift's actor model like Erlang's?", steps: [], edited: false,
         answer: "Loosely: both isolate state and communicate by messages, but Swift actors share a heap and use async calls."),
    Case(category: "answered", expected: nil, asked: "thanks, that looks good", steps: [], edited: false, answer: "You're welcome!"),
]

@Suite(.enabled(if: ProcessInfo.processInfo.environment["JEV_LIVE"] == "1")) struct OverseerLiveTests {
    @Test func labelledTurnsVersusVerdicts() async throws {
        var agree = 0, rows: [String] = []
        for c in cases {
            let steps = c.steps.enumerated().map { TurnStep(n: $0.offset + 1, tool: $0.element.tool, what: $0.element.what,
                                                          result: $0.element.result, failed: $0.element.failed) }
            let d = TurnDigest(asked: c.asked, steps: steps, edited: c.edited, answer: c.answer).redacted
            let reply = await OverseerJudge.ask(d, jev: JevClient())
            let j = OverseerJudge.judge(reply: reply, digest: d)
            let got = j.verdict
            if got == c.expected { agree += 1 }
            func p(_ x: Double?) -> String { x.map { String(format: "%.2f", $0) } ?? "-" }
            rows.append("\(got == c.expected ? "ok  " : "MISS") \(c.category.padding(toLength: 25, withPad: " ", startingAt: 0))"
                + " label=\((c.expected?.rawValue ?? "none").padding(toLength: 14, withPad: " ", startingAt: 0))"
                + " got=\((got?.rawValue ?? "none").padding(toLength: 14, withPad: " ", startingAt: 0))"
                + " outcome=\(j.outcome ?? "-")@\(p(j.outcomeConfidence)) proof=\(p(j.proof)) contra=\(p(j.contradiction)) next_safe=\(p(j.nextSafe))")
        }
        print("\n=== Overseer live: label vs verdict ===\n" + rows.joined(separator: "\n") + "\nagreement \(agree)/\(cases.count)\n")
        #expect(cases.count >= 24)
    }
}
