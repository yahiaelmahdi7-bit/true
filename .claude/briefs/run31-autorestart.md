Build True "Run 31 — Restart to update by itself" exactly as specified in SPEC.md (section "## Run 31", the last section). SPEC.md is the source of truth. Read that section, then Sources/True/Model/Updater.swift, Model/UpdateLogic.swift, Model/BuildFreshness.swift, Model/WorkAwake.swift, Views/RestartPill.swift, Views/SettingsView.swift and the existing Update*/Updater* tests under Tests/. Also read CLAUDE.md and docs/kb/index.md.

Scope: ONLY the files above plus new test files named in the spec. Do not touch Sources/True/Peers/ (another builder is working there), Nova, Remote, Capture or the relay. No new timers that run while nothing is staged.

Order: 1) UpdateLogic.restartDecision + interval + tests, 2) Updater arming/cancel/restart path + tests, 3) the toast view + Settings toggle. Commit after each step. Gate = `swift build` then `swift test --filter Update` in the foreground; the last commit must paste both passing. If a SPEC line is unbuildable as written, implement the nearest safe behaviour and write the deviation into a "### Deviations (builder)" block under the Run 31 section of SPEC.md.

Memory rules: SourceKit "cannot find X in scope" diagnostics on this SwiftPM package are false positives, trust `swift build`. Never launch or quit True.app. Never pkill by name.

DISCIPLINE (non-negotiable):
- Lane: you work ONLY on the files above, on your own worktree branch. Do not touch, checkout, or revert any file outside it — other agents have uncommitted work in this tree.
- Commits: atomic, one logical change per commit, message says what+why. NEVER push, NEVER merge, NEVER 'ship' — the user pushes, not you. Do not suggest pushing more than once.
- Gates: run build/tests in the FOREGROUND and wait for them. NO background shells, NO watch modes, NO until-loops. Kill anything you started before finishing.
- Claims: 'done' means you ran the gate and pasted the passing output. Local commit ≠ 'pushed'; code written ≠ 'working'. Never report a state you didn't verify this session.
- Decisions: if your change adds or touches a classify / route / gate / rank / verify step, make it a Jev call through the repo's vendored jev-kit (see the jev skill): code owns the flow, Jev answers narrow typed questions, route on confidence, log the decision. No LLM prompt-and-parse, no keyword lists.
- If blocked or idle: say BLOCKED/IDLE + one line why. Do not invent extra scope.
