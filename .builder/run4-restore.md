You are continuing **True** in `~/Projects/true` (branch `main`). Runs 1–3 are DONE and committed —
read `SPEC.md` in full (its Hard rules still bind, except the one amended below), then
`git log --oneline` and the current code before changing anything. This run adds TWO things.

## Why
1. Yahia quits True and comes back to lose his place: tabs and splits return, but every Claude
   conversation that was running is gone (panes come back as bare shells), awake agents come back
   asleep, and each shell's screen is blank. He wants to come back **exactly where he left off**.
2. ⌘O (Open Project) opens the picked repo in a NEW tab. He wants it to open as a **split beside the
   pane he's in, in the same tab** (his pick from the options).

## Part 1 — ⌘O opens as a split in the current tab
- `ProjectPalette.open` → a new `WorkspaceModel` method that inserts a new leaf beside the SELECTED
  tab's focused pane, axis `.horizontal` (same as ⌘D Split Right), cwd = the project path, and focuses
  the new pane. Refactor `splitFocused` so both share one `split(axis:cwd:)` path. Tab count unchanged,
  custom tab name untouched. ⌘↩ registers `PaneStartup` for the NEW pane only.
- Remove the now-unused new-tab `openProject` path if nothing else calls it.
- Footer hint: `↩ Open beside   ⌘↩ Open with Claude   esc Close`.

## Part 2 — Restore exactly where he left off
Today `~/.true/workspace.json` restores tabs, split tree, fractions, per-pane cwd, names, selection.
Add three things, all event-driven (Hard rule: idle ≈ 0% CPU — no timers, no polling):

### 2a. Claude conversations resume in their pane
- **Discovery (the key fact):** every live Claude Code process writes
  `<claudeConfigDir>/sessions/<pid>.json` (`AgentLaunch.claudeConfigDir`, honours `CLAUDE_CONFIG_DIR`),
  e.g. `{"pid":80217,"sessionId":"9176169f-…","cwd":"/Users/y","kind":"interactive",…}`. A pane's
  Claude is a DESCENDANT of the pane's shell (`view.process.shellPid`), often 2–3 levels down (shell →
  `claude-burn` bash loop → claude). Walk descendants (libproc `proc_listchildpids`, depth ≤ 5), and
  take the shallowest descendant whose sessions file exists with `kind == "interactive"`. This works
  for ⌘↩ panes AND for `claude` typed by hand. Put the walk behind an injected
  `children: (pid_t) -> [pid_t]` so it is unit-tested with a fake tree + temp sessions dir.
- **Record:** per pane, persisted in `workspace.json`: `.claude(sessionID, cwd)` or `.agent(name)`
  (see 2b). Put it on `TabState` as an OPTIONAL map (e.g. `resume: [UUID: PaneResume]?`).
  **Back-compat is mandatory:** today's `~/.true/workspace.json` (version 1, no new fields) must still
  decode and pass `isConsistent`. Do NOT bump `version` (a bump makes the current file "corrupt" → fresh
  workspace = exactly the loss we're fixing). Add a test that decodes a v1 fixture without the field.
  `closePane` must drop the pane's record like it drops `cwds[pane]`.
- **When recorded (no timers):**
  1. `AppDelegate.applicationShouldTerminate` (return `.terminateNow`) — runs before any view is torn
     down, so shells are still alive. Keep the existing `applicationWillTerminate` save too.
  2. `NSWindow.willCloseNotification` for the main window (closing the window also quits True, and the
     views may be dismantled before `applicationShouldTerminate`).
  3. A one-shot ~2.5 s after Return in a pane (extend the existing `onCommandSubmitted` one-shot) —
     this is what survives a crash / force-quit.
  4. A `.session` hook event from ANY pane (today `AgentRegistry.handle` only uses it for named agents;
     ⌘↩ panes send it too) — record it directly.
  Snapshot rule: if a pane's view/shell is gone, KEEP its previous record (a late snapshot must not wipe
  a good one). Clear a pane's `.claude` record only when its shell is alive and has no Claude descendant.
- **Resume at launch:** for each restored pane with `.claude(id, cwd)` where `id` is a UUID and its
  transcript exists (reuse/refactor `AgentLaunch.resumeID`'s transcript check into one shared helper),
  the pane starts in `cwd` running (via the existing `PaneStartup` one-shot, registered when the
  workspace loads, before any view is made):
  `claude --resume <id> --settings <paneSettingsPath>; exec "${SHELL:-/bin/zsh}" -l`
  (interactive login shell like `PaneStartup.claudeCommand` — `claude` is Yahia's `claude-burn` alias,
  which passes `--resume` through on first launch). No valid transcript → plain shell, record dropped.
  Update `PaneStartup`'s doc comment (it currently says restored tabs are always plain shells).

### 2b. Awake agents come back awake
- **SPEC amendment (Yahia, 2026-09-30):** replace "Agents start ASLEEP on launch … nothing wakes by
  itself" with: "Agents that were awake when True quit are re-woken on launch into the same pane with
  `--resume`; nothing else wakes by itself." Edit SPEC.md accordingly.
- Snapshot records `.agent(name)` for every pane in `AgentRegistry.panes` (and skips 2a/2c for it).
- At launch, BEFORE the first window render (`TrueApp` touches `AgentRegistry.shared` at init, so
  do it in `AgentRegistry.init` or a `restore()` it calls): for each `.agent(name)` pane whose agent
  still exists in agents.json → `AgentHooks.install`, set `launchSpecs[pane]` with
  `AgentLaunch.argv(…, resumeID: AgentLaunch.resumeID(for:))`, `panes[name] = pane`, status `.idle`.
  Same pane id, same tab, same split position — do NOT open a new tab (that's `wake`). Agent gone →
  record dropped, pane is a plain shell.

### 2c. Plain shells get their screen back
- At snapshot (1)/(2) only (quit/close — not the Return one-shot), for each pane that is NOT Claude
  and NOT an agent: serialize the terminal's NORMAL buffer (scrollback + screen; even if the pane is
  in the alt screen, e.g. vim) **with colours**: walk buffer lines/cells, emit SGR only when the
  attribute changes (fg/bg incl. 256 + truecolor, bold/dim/italic/underline/inverse), skip the
  placeholder cell after a wide char, trim trailing blanks per line, `ESC[0m` at line end, join rows
  that are soft-wrapped (`isWrapped`) without CRLF, trim trailing empty lines. Cap: last 5,000 lines
  and 2 MB. Write `~/.true/scrollback/<paneID>.ans` + a small `<paneID>.json` header
  `{cols, rows, savedAt, wasRunning}` — both mode 0600 (terminal output can contain secrets).
  `wasRunning` = `proc_name` of the shell's direct foreground child if any (e.g. `npm`), never re-run.
  Delete files of panes that no longer exist.
- At launch, in `EmbeddedTerminal.makeNSView`, BEFORE `startProcess`: if a snapshot exists (one-shot,
  consumed like `PaneStartup`), resize the SwiftTerm terminal to the saved cols/rows, feed the bytes,
  then feed one dim line `── restored · Tue 30 Sep 14:02 · was running: npm ──` (omit the
  `was running` part when nil), then CRLF; delete the two files. The shell then prints its prompt below.
- Headless SwiftTerm `Terminal` round-trip test: feed coloured text (ANSI 16 + 256 + truecolor, bold,
  a wide char, a soft-wrapped long line) → serialize → feed into a fresh `Terminal` of the same size →
  every cell's char + fg/bg + style match. Plus: cap respected, trailing blanks trimmed.

## Tests (TrueTests, pure logic, temp dirs only — never the real ~/.true or ~/.claude)
Descendant walk + session pick (nested, non-interactive ignored, missing/garbage JSON ignored,
shallowest wins); resume command string (exact, quoting, non-UUID refused); transcript-missing →
no resume; v1 workspace fixture decodes + round-trip with records; closePane prunes the record;
snapshot keeps a record when the view is gone; agent restore builds launchSpecs with `--resume`
and maps `panes`, unknown agent dropped; ⌘O split: same tab count, new leaf beside focused pane in the
selected tab, focused, cwd = project, startup command only on the new pane; scrollback round trip.

## DISCIPLINE (non-negotiable)
- Lane: ONLY ~/Projects/true. Never touch ~/.axon, ~/.claude/settings.json, or other repos.
  Never write the real ~/.true/* or ~/.claude/* in tests — inject temp paths.
- Commits: atomic, message says what+why. NEVER push, merge, or tag.
- Gates in the FOREGROUND only: no run_in_background, no watch modes, no until-loops.
- 'done' = you ran the gate and pasted passing output. Never report what you didn't verify.
- If blocked: say BLOCKED + one line why. No extra scope (don't re-run arbitrary commands on restore,
  no window-frame persistence, no settings UI).

## HEAT RULES (hard)
- Another builder is compiling a worktree of this repo at the same time. Build only with
  `nice -n 10 swift build -j 2`; tests only with SPEC.md's `swift test` command but `-j 2`. One
  build/test process at a time. Full test suite at most ~4 times.
- True.app IS RUNNING RIGHT NOW and hosts live sessions (including the one that launched you).
  NEVER launch, open, quit, kill, or signal True/True.app. Do NOT run `scripts/package.sh` — the
  reviewer packages after checking. No `open`, `osascript`, screenshots, no GUI of any kind.

Order: Part 1 (⌘O split) + its tests → commit. Then 2a (record type + back-compat test → descendant
walk → snapshot hooks → resume at launch) → commit. Then 2b → commit. Then 2c (serializer + round-trip
test first, then snapshot/restore wiring) → commit. SPEC.md amendment + a short "Run 4 — Restore" note
→ commit. Full test run.

Finish with a short plain-English report: what works, pasted final build + test output, commit list,
what was never exercised because nothing was launched (quit→relaunch restore, ⌘O split, and the
quit-time snapshot are untested live), and anything risky.
