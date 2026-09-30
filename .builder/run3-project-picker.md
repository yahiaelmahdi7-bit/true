You are continuing **True** in `~/Projects/true` (branch `main`). Runs 1–2 are DONE and committed —
read `SPEC.md` in full (its Hard rules still bind), then `git log --oneline` and the current code
before changing anything. This run adds ONE feature: the **Open Project palette**.

## Why
Yahia opens a tab, then types `cd ~/Projects/some-repo` by hand and mistypes it. He wants to pick a
repo by typing a few letters and land in it — optionally with Claude already running.

## The feature (one name: "Open Project")
1. **Command:** File menu, right under "New Tab": `Open Project…` with ⌘O. Toggles the palette.
2. **Palette UI:** a Spotlight-style floating card centered near the top of the terminal area (an
   overlay inside the window, not a new window), Liquid Glass (`.glassEffect`), ~560pt wide. A search
   field focused on open, then a list (max ~9 rows visible, scrolls). HIG look per SPEC (SF Symbols,
   system fonts, dark). Each row: `folder` SF Symbol · project **name** · parent location dimmed
   (`~/Projects`) · trailing dimmed git branch (read `.git/HEAD` directly — NO git process) · a small
   "handoff" capsule when `<repo>/.claude/HANDOFF*.md` exists (unfinished work waiting there).
   Footer hint row: `↩ Open   ⌘↩ Open with Claude   esc Close` and an `Add Folder…` button.
3. **Keys:** ↑/↓ move the highlight (wraps), Return = open the highlighted project in a NEW tab,
   ⌘Return = new tab AND start Claude, Esc or clicking outside = close, click a row = Return.
   After any open the palette closes and focus goes to the new pane's terminal.
4. **New tab:** reuse `WorkspaceModel`'s tab creation with `cwd` = the project folder. No custom name
   (the tab title already falls back to the cwd basename).
5. **Open with Claude:** the pane starts as `$SHELL -l -i -c 'claude; exec "$SHELL" -l'` so the
   user's `claude` alias applies (it is `claude-burn`) AND when Claude exits the pane stays as a normal
   shell in the repo (an agent pane closes instead — this must NOT). This pane is NOT an agent: do not
   use `AgentRegistry.launchSpecs`, no `TRUE_AGENT`, not counted by `isAgentPane`. Add a minimal,
   one-shot "startup command for a pane" (e.g. on `TerminalRegistry` or `WorkspaceModel`, consumed
   once in `EmbeddedTerminal.makeNSView`) — never persisted, so a restored tab is a plain shell.
6. **Project list** (built off the main actor each time the palette opens; nothing watches disk):
   - `roots`: every direct sub-DIRECTORY of each root is a project (git or not).
   - `pinned`: extra single folders.
   - skip hidden folders, names matching the `exclude` globs, and paths that no longer exist.
   - de-dupe by standardized path.
   Stored in `~/.true/projects.json` (Codable, `version` field, same store style as the workspace/
   agents stores: missing file → defaults written on first open; corrupt file → defaults, don't crash,
   don't overwrite the corrupt file silently — rename it to `projects.json.corrupt`). Defaults:
   `roots: ["~/Projects", "~/studio-builds"]`,
   `pinned: ["~/Prism", "~/Prism-landing-lab", "~/Documents/LifeOS", "~/Downloads/studio-shine-main", "~/auth2api"]`,
   `exclude: ["*.builders", "axon-lanes"]`, `recent: []`. Store paths with `~` and expand on read.
   `Add Folder…` = NSOpenPanel (directories only) → appended to `pinned`, list refreshes.
7. **Recents:** every open (both kinds) records `{path, openedAt}` at the front of `recent`
   (de-duped, capped at 50) and saves.
8. **Matching + order** (pure functions in their own file, no UI imports):
   - Empty query: recents first (newest first), then everything else by name, case-insensitive.
   - Query: case-insensitive fuzzy subsequence match against the name, then against the parent path
     as a weaker fallback. Score bonuses: exact name, name prefix, match at a word boundary (after
     `-`, `_`, `.`, space, or a camelCase hump), consecutive runs. Recency breaks ties.
   - **Typo tolerance** (the actual complaint): if the query is 3+ chars and a name has no subsequence
     match, it still matches when the query is within Damerau-Levenshtein distance ≤ 1 (query ≤ 5
     chars) or ≤ 2 (longer) of the name OR of the name's prefix of the same length. Typo matches
     always rank below real matches. `finace` → `finance-desk`, `mezan` → `mizan`, `fnance` → `finance-desk`.

## Tests (TrueTests, pure logic)
Scorer ordering (exact > prefix > boundary > scattered), typo fallback cases above + a query that
must NOT match, empty-query recents-then-alpha order; list building from a temp dir tree (roots,
hidden skipped, exclude globs, pinned, missing paths, de-dupe); recents de-dupe + cap; projects.json
round-trip, missing `version`, corrupt-file fallback; the Claude startup command string; that a
startup command is consumed once.

## DISCIPLINE (non-negotiable)
- Lane: ONLY ~/Projects/true. Never touch ~/.axon, ~/.claude/settings.json, or other repos.
  Do not write to the real ~/.true/projects.json in tests — inject a temp path.
- Commits: atomic, message says what+why. NEVER push, merge, or tag.
- Gates in the FOREGROUND only: no run_in_background, no watch modes, no until-loops.
- 'done' = you ran the gate and pasted passing output. Never report what you didn't verify.
- If blocked: say BLOCKED + one line why. No extra scope (no settings UI for roots, no git status
  counts, no file watching, no fuzzy-finding files inside repos).

## HEAT RULES (hard)
- Build only with `nice -n 10 swift build -j 4`; tests only with the `nice -n 10 swift test -j 4 ...`
  command in SPEC.md. One build/test process at a time. Full test suite at most ~4 times.
- True.app IS RUNNING RIGHT NOW and hosts live sessions (including the one that launched you).
  NEVER launch, open, quit, kill, or signal True/True.app. Do NOT run `scripts/package.sh` — the
  reviewer packages after checking. No `open`, `osascript`, screenshots, no GUI of any kind.

Order: projects store + list builder → scorer → tests for both → startup-command plumbing →
palette view + ⌘O command → wire open/open-with-Claude + recents → full test run. Commit after each
step that builds.

Finish with a short plain-English report: what works, pasted final build + test output, commit list,
what was never exercised because nothing was launched (the palette UI and ⌘↩ are untested live), and
anything risky.
