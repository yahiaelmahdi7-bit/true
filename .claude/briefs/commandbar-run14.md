You are building **Run 14 — the Command bar** for True (`/Users/y/Projects/true`, SwiftPM macOS 26 terminal app).
Read `SPEC.md` "Hard rules", "Stack", "Run 6 — Jev in the backend", "Run 12 — The Overseer" (the pattern you copy)
and **"Run 14 — The Command bar"** (the job, already committed on main — do NOT re-append it). You are in a git
worktree on your own branch; other Claude sessions are using the main checkout.

DISCIPLINE (non-negotiable):
- Lane: you work ONLY inside this worktree. Do not touch ~/.claude, ~/.true, ~/.axon, or any file outside the repo.
- Commits: atomic, one logical change per commit, message says what+why. NEVER push, NEVER merge,
  NEVER 'ship' — the user pushes, not you. Do not suggest pushing more than once.
- Gates: run build/tests in the FOREGROUND and wait for them. NO background shells
  (run_in_background), NO watch modes, NO until-loops. Kill anything you started before finishing.
- Claims: 'done' means you ran the gate and pasted the passing output. Code written ≠ 'working'.
  Never report a state you didn't verify this session.
- Decisions: route / classify / gate steps are Jev calls through the repo's `JevClient`
  (`Sources/True/Agents/JevClient.swift`): code owns the flow, Jev only SELECTS from candidates code built,
  thresholds live in code, every read is logged. No LLM prompt-and-parse, no keyword lists for judgments
  (the deterministic prefix rules and the dangerous-pattern list in SPEC item 2/4 are the only exceptions).
- Never launch True.app (SPEC rule). Never run the JEV_LIVE suite (the orchestrator runs it).
- If blocked or idle: say BLOCKED/IDLE + one line why. Do not invent extra scope.

**FIXED LABELS — read twice.** `Tests/TrueTests/Fixtures/commandbar-labelled.json` holds 39 routes hand-labelled
BEFORE any run from Yahia's real prompts. Never edit, add, remove or reorder its cases, its `projects`/`seats`, or
its `_readme`. If a label looks wrong to you, list it in your final report — do not change it, and do not tune
prompts or floors to make a particular case pass. `CommandBarLiveTests` (gated `JEV_LIVE=1`) decodes that file,
runs every case through the real router with the fixture's fixed candidates (still ranked by `ProjectMatcher.rank`)
and the case's `focused` pane, applies the scoring rules in `_readme`, and prints a table (id, text, label vs route
per slot, probabilities, ms) plus per-slot accuracy. No accuracy assertion. An offline test (no network) decodes
the fixture and checks every `!` / `$` / exact-action-name case against `CommandRules` alone.

Two spec points that are easy to miss:
- A matched rule picks the door but never skips the danger gate: Jev is still asked the `destructive` noul alone
  (cases c07, c08 — `supabase db push`, `vercel env add … production` behind a `!`). Jev down → fall back to the
  dangerous-pattern list; when neither can say, shell text is typed, not submitted.
- Executor decisions are a pure `Plan` value (door, argv, autoSubmit, needsSecondReturn) so the whole matrix is
  unit-testable without panes.

Pointers (grep for exact paths): overlay look + Esc handling → `HubOverlay`, `TrueTerminalView` key monitor;
Jev pattern + model/effort questions to extract and share → `Agents/JevFill.swift`, `JevFillTests.swift`;
live-suite pattern → `OverseerLiveTests.swift`; redactor → the Overseer `Redact`; log rotation + 0600/0700 →
`OverseerStore` / verdicts.jsonl code; project ranking → `ProjectMatcher.rank`; seat names → `CrewDisplay`;
delivery → `PaneDelivery.write`, summon/wake path, ⌘O new-pane path, `BuilderSpawn` + `isValidName`; settings
toggles → `Settings/TerminalSettings.swift`. Check ⌘K is unused before binding it.
Also add one line each to `docs/kb/glossary.md` (Command bar, route), `docs/kb/security.md` (routes.jsonl and
commandbar history: 0600, redacted, rotated) and the Jev row of `docs/kb/integrations.md` (+ Command bar routing).

Test command (CommandLineTools flags, from SPEC):
```
FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
nice -n 10 swift test -j 4 -Xswiftc -F$FW -Xlinker -F$FW -Xlinker -rpath -Xlinker $FW -Xlinker -rpath -Xlinker $LIB
```

**Done =** SPEC "Run 14 done": `swift build` clean with no new warnings, all tests green (paste the output),
`scripts/package.sh` produced `True.app`, snapshot PNGs in `docs/design/commandbar/` (v1 passes /taste), commits on
the branch, fixture file byte-identical to main (`git diff main -- Tests/TrueTests/Fixtures/commandbar-labelled.json`
empty — paste it). App NOT launched; JEV_LIVE suite NOT run.

Final report: commits (hash + subject), the pasted test summary, the empty fixture diff, any labels you think are
wrong (with why), anything you deviated from with why, and anything not verified.
