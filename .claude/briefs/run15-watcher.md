# Brief: True Run 15 — the Watcher (agents that are real)

Source of truth: `SPEC.md` section "## Run 15" (commit 22bf200). Build exactly that; where this brief and the spec differ,
the spec wins. Read `docs/kb/index.md` first for the codebase map.

## Must-haves (from the spec, restated so nothing is missed)
- Duty primitive + `watcher` role, agent home `~/.true/agents/<name>/`, Inbox (append-only events, pure `Inbox.fold`),
  three v1 sources (builders incl. stuck, unpushed >= 24 h, abandoned Overseer failures), injection screen + redaction,
  wake gate / dedupe / done check / permission level as narrow Jev nouls combined in code (questions VERBATIM from the
  spec; the five danger nouls move to one shared `Agents/DangerQuestions.swift` used by Command bar AND Watcher).
- Deny-list in code beats every rule, pre-approval and Jev answer. Jev slow/down/keyless is never more permissive.
- Investigations: `claude -p` read-only argv exactly as §3 (never bypassPermissions, Bash, Edit, Write, WebFetch), with
  `--max-turns`, `--max-budget-usd`, and the agent-burn hook wired in `watcher.settings.json` with env AGENT_BURN_MAIN=1.
  Hook path constant: `/Users/y/Projects/jev-tools/burn/agent-burn.ts` (may not exist yet: skip the entry when missing).
  `mcp.json` -> `/Users/y/Projects/jev-tools/bin/jev-files-mcp` when executable.
- Approve on `askFirst` = deny-list re-check on the exact brief, then `~/.claude/bin/builder start --name fix-<item> ...
  --model sonnet --budget <fixUSD> --worktree` (fixUSD $1). `handOff` = Copy steps only, never a builder.
- Budget + burn defaults from §7 Q1. No timers (events only; stuck check on WorkAwake's existing tick).
- Hub: Watcher card + Inbox under "Your move", item sheet (HIG, monochrome, eye avatar the only colour); `truectl inbox`.
- Labelled dev set: `Tests/TrueTests/Fixtures/watcher-labelled.json` (read it; NEVER edit it). Tests read its schema;
  `WatcherLiveTests` (JEV_LIVE=1, path from env `WATCHER_FRESH`, default = the dev fixture) prints label vs answer +
  probabilities, accuracy per floor, and the handOff gate. Do not run it.

## Done (same bar as Run 14)
`swift build` clean with no new warnings; all tests green (paste the summary); `scripts/package.sh` built True.app;
commits on your branch. App NOT launched. JEV_LIVE NOT run. Never push. Don't edit `~/.claude` or `~/.true` real files
(tests use temp dirs). End with a "Not verified" list.
