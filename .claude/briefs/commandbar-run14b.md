You are making **Run 14b — Command bar fixes after the first live run** for True (`/Users/y/Projects/true`,
SwiftPM macOS 26 terminal app). Run 14 (the Command bar) is already merged. Read `SPEC.md` "Hard rules", "Stack" and
**"Run 14 — The Command bar"** items 2–4: commit a105e01 amended them, and that diff (`git show a105e01 -- SPEC.md`)
is your whole job. You are in a git worktree on your own branch; other Claude sessions use the main checkout.

DISCIPLINE (non-negotiable):
- Lane: you work ONLY inside this worktree. Do not touch ~/.claude, ~/.true, ~/.axon, or any file outside the repo.
- Commits: atomic, one logical change per commit, message says what+why. NEVER push, NEVER merge,
  NEVER 'ship' — the user pushes, not you. Do not suggest pushing more than once.
- Gates: run build/tests in the FOREGROUND and wait for them. NO background shells
  (run_in_background), NO watch modes, NO until-loops. Kill anything you started before finishing.
- Claims: 'done' means you ran the gate and pasted the passing output. Code written ≠ 'working'.
  Never report a state you didn't verify this session.
- Decisions: Jev (through `JevClient`) only selects; the policies below are CODE applied after Jev answers.
- Never launch True.app. Never run the JEV_LIVE suite (the orchestrator runs it).
- If blocked or idle: say BLOCKED/IDLE + one line why. Do not invent extra scope.

**FIXED LABELS.** Never edit `Tests/TrueTests/Fixtures/commandbar-labelled.json` (c29 was relabelled on main by
the orchestrator after a decision by Yahia — that is expected). Do not tune wording or floors to make any case pass.

The five changes (all in `Sources/True/CommandBar/`, each with offline tests, no network):
1. **Danger question** — `destructive` noul text becomes exactly the SPEC item 3 string ("Does `text` push commits
   to a remote, delete or wipe data, force-push, deploy, publish, send messages or write to a live third-party
   service?"). Danger-pattern fallback list: plain `git push` (any form) joins it.
2. **Seat policy** — SPEC item 3, applied in code after Jev, in order: (1) a seat named in the text (whole-word,
   case-insensitive, over ALL seats awake or asleep; reuse the CrewDisplay-style lookup) wins and sets the project;
   it must also be in the Jev state's seat candidates even when its project is not the picked/current one;
   (2) `agent_task` never targets an unnamed seat (→ focused_pane if a Claude pane in that project is focused, else
   new_claude_pane); (3) `question_for_claude` in a project other than the focused Claude pane's → an awake seat
   there (Jev's pick among them, else the first), else new_claude_pane. Asleep named seat → wake then deliver
   (existing path). Test the full table.
3. **open_project argument** — project = `ProjectMatcher.rank(query: text minus the verb words)` top hit; Jev's
   `project` slot only when the matcher finds nothing. ("open trading" → TradingAgents while `true` is focused.)
4. **Shell gate** — without a `!`/`$` prefix, a shell `kind` needs the first word to be an executable on `$PATH`,
   a shell builtin, or a path (`./`, `~/`, `/`); otherwise treat `kind` as below 0.5 (two-choice state, nothing
   auto-sent). The PATH/builtin lookup is injected so tests don't depend on the machine.
5. **Live suite input** — `CommandBarLiveTests` reads an absolute path from env `COMMANDBAR_FIXTURE` when set, else
   the default fixture; print the file name in the table header. Same scoring.

Test command (CommandLineTools flags, from SPEC):
```
FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
nice -n 10 swift test -j 4 -Xswiftc -F$FW -Xlinker -F$FW -Xlinker -rpath -Xlinker $FW -Xlinker -rpath -Xlinker $LIB
```

**Done =** `swift build` clean with no new warnings, all tests green (paste the summary), `scripts/package.sh`
produced `True.app`, commits on the branch, `git diff main -- Tests/TrueTests/Fixtures/commandbar-labelled.json`
empty (paste it). App NOT launched; JEV_LIVE NOT run.

Final report: commits (hash + subject), the pasted test summary, the empty fixture diff, deviations with why,
anything not verified.
