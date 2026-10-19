You are making **Run 14c — Command bar danger questions and kind options** for True (`/Users/y/Projects/true`,
SwiftPM macOS 26 terminal app). Runs 14 and 14b are merged. Read `SPEC.md` "Hard rules", "Stack" and "Run 14 — The
Command bar" item 3; the last commit on main (`git show HEAD -- SPEC.md`) is your whole job. You are in a git
worktree on your own branch; other Claude sessions use the main checkout.

DISCIPLINE (non-negotiable):
- Lane: you work ONLY inside this worktree. Do not touch ~/.claude, ~/.true, ~/.axon, or any file outside the repo.
- Commits: atomic, one logical change per commit, message says what+why. NEVER push, NEVER merge,
  NEVER 'ship' — the user pushes, not you. Do not suggest pushing more than once.
- Gates: run build/tests in the FOREGROUND and wait for them. NO background shells
  (run_in_background), NO watch modes, NO until-loops. Kill anything you started before finishing.
- Claims: 'done' means you ran the gate and pasted the passing output. Code written ≠ 'working'.
- Decisions: Jev (through `JevClient`) only selects; code builds the options and applies thresholds.
- Never launch True.app. Never run the JEV_LIVE suite (the orchestrator runs it).
- If blocked or idle: say BLOCKED/IDLE + one line why. Do not invent extra scope.

**FIXED LABELS.** Never edit `Tests/TrueTests/Fixtures/commandbar-labelled.json`. Use the question strings in
SPEC exactly as written — no rewording, no added examples, no floor changes.

The three changes (in `Sources/True/CommandBar/`, offline tests for each, no network):
1. **Five danger nouls** replace the single `destructive` noul everywhere it is asked (full read AND the
   rule-matched `onlyDanger` read): ids `danger_push`, `danger_delete`, `danger_deploy`, `danger_send`,
   `danger_live`, strings verbatim from SPEC. `Route.destructive` = max of the answered ones (nil when none
   answered). `routes.jsonl` keeps all five values; the live table prints which one was highest.
2. **`focused.meaning`** in the Jev state, the fixed sentence per focused kind from SPEC.
3. **Kind options built by code**: `shell_command` is left out of the `kind` choice when there is no `!`/`$`
   prefix and the first word fails the shell gate (reuse the injected PATH/builtin/path check from Run 14b).
   When shell is left out, the 14b post-hoc demotion for that case is no longer needed — remove the dead path,
   keep the two-choice state for a genuinely low `kind` confidence (< 0.5).
Update the question-JSON-shape tests and the executor/route tests that read `destructive`.

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
