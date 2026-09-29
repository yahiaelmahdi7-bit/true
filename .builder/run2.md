You are continuing **True** in `~/Projects/true` (branch `main`). Run 1 (terminal core) is DONE and
committed — read `SPEC.md` in full, then `git log --oneline` and the current `Sources/True/` code before
changing anything. This run is **Run 2 — Agents mode** exactly as SPEC.md describes (items 1–8).

What Run 1 established (build on it, don't redo it):
- `WorkspaceModel` (Model/WorkspaceModel.swift) owns tabs + split trees; panes render as a FLAT sibling
  list in `TerminalArea` so a shell's view identity never moves on split/tab switch. An agent's pane
  must be an ordinary pane in this model (tagged with the agent name), not a separate view tree.
- `TrueTerminalView` / `EmbeddedTerminal` are the SwiftTerm bridge. PaneDelivery needs to write into a
  pane and READ its rendered screen — add the minimal accessor there rather than a second terminal path.
- Run 1 deliberately dropped Axon's agent hooks/events, PaneTail and the activity monitor. Run 2 lifts
  what it needs from Axon (read-only reference): `Sources/Axon/Desk/AgentEvents.swift`,
  `AgentHooks.swift`, `NeedsYou.swift`, `NeedsYouTray.swift`, `PaneDelivery.swift`,
  `Sources/Axon/Crew/SeatRoles.swift`, `CrewModels.swift`, and fixtures under
  `~/Projects/axon/Tests/AxonTests/Fixtures/permission-dialog` (copy them into TrueTests).
  Replace every DeskModel / SleepCenter / Nova / crew-store dependency with one small `AgentRegistry`.
- Agents start ASLEEP. Nothing wakes, launches `claude`, or opens the socket for writing on its own
  except the socket listener itself (event-driven, no polling).

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

HEAT RULES (hard limits):
- Build only with `nice -n 10 swift build -j 4`. Tests only with the `nice -n 10 swift test -j 4 ...`
  command in SPEC.md. One build or test process at a time, ever. Build at milestones; full test suite
  at most ~5 times this run.
- NEVER launch True.app, Axon.app, `claude`, or any GUI; no `open`, `osascript`, `cliclick`,
  screenshots. The launch-command builder is tested as a pure function that returns argv — never exec it.

Order of work: Agent model + agents.json store → AgentRegistry → launch-command builder + role files →
hook settings + agent-events socket → wake/sleep wired to WorkspaceModel panes → Agents panel + cards →
character builder sheet → needs-you detector + tray + PaneDelivery → talk-to-lead field → tests →
`scripts/package.sh`. Commit after each step that builds.

Finish with a short report in plain English: what works, the pasted final build + test output, the
commit list, what was never exercised because nothing was launched, and anything risky.
