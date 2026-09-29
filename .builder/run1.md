You are building **True**, a new lean macOS terminal app, in `~/Projects/true` (git repo, branch
`main`). Read `SPEC.md` in full first. This run is **Run 1 — Terminal core** only. Do not start Run 2.

Project brief: SwiftPM + SwiftUI + SwiftTerm, macOS 26, Swift 6. Axon (`~/Projects/axon`) is the
parked predecessor: it is a READ-ONLY reference you copy and trim proven code from. The owner is a
non-coder who directs builds; the app must feel native (Apple HIG) and sit at ~0% CPU when idle.

DISCIPLINE (non-negotiable):
- Lane: you work ONLY in ~/Projects/true. Never edit, checkout, build, or run anything in
  ~/Projects/axon (read files there only). Never touch ~/.axon or ~/.claude/settings.json.
- Commits: atomic, one logical change per commit, message says what+why. NEVER push, NEVER merge,
  NEVER 'ship' — the user pushes, not you. Do not suggest pushing more than once.
- Gates: run build/tests in the FOREGROUND and wait for them. NO background shells
  (run_in_background), NO watch modes, NO until-loops. Kill anything you started before finishing.
- Claims: 'done' means you ran the gate and pasted the passing output. Local commit ≠ 'pushed';
  code written ≠ 'working'. Never report a state you didn't verify this session.
- If blocked or idle: say BLOCKED/IDLE + one line why. Do not invent extra scope.

HEAT RULES (the owner's laptop overheated today — these are hard limits):
- Build only with `nice -n 10 swift build -j 4`. Tests only with the `nice -n 10 swift test -j 4 ...`
  command in SPEC.md. One build or test process at a time, ever.
- Build at milestones, not after every edit. Run the full test suite at most ~5 times this run.
- NEVER launch True.app, Axon.app or any GUI; no `open`, `osascript`, `cliclick`, screenshots.
- Don't start MCP servers, browsers, simulators, or `swift package` resolves in a loop.

Order of work: Package.swift + app shell → terminal pane (lifted from Axon) → tabs → split tree +
resize-proof layout → window chrome (drag + double-click) → workspace autosave → settings →
tests → `scripts/package.sh`. Commit after each step that builds.

Finish with a short report: what works, the pasted final build + test output, the commit list
(`git log --oneline`), and anything you had to leave out or found risky (e.g. a lifted Axon file that
pulled in unwanted dependencies and how you cut it).
