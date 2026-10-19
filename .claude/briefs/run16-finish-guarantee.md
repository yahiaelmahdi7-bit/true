# Brief: Run 16 — workers finish tasks: a cap is a checkpoint, not a stop

Worktree you are in. Do NOT push, do NOT launch True.app, never read `.claude/heldout/`. Lane: `Sources/True/Duty/`,
`Sources/True/Hub/`, `Tests/` only. Two commits: failing tests first, then the fix.
Gate = docs/kb/conventions.md:5-9 exactly (plain `swift test` fails). Existing 527 tests stay green; weaken none.

Why: Yahia's rule — a worker that stops at a turn/money cap with the task unfinished is a failure. Caps stay (a
runaway backstop) but hitting one must continue the same work, then pause visibly, never silently end incomplete.

## T1 — builders have a new status: `paused`
`~/.claude/bin/builder` is gaining checkpoints: on a money cap it resumes the same session; it writes
`"status": "paused"` (resumable with `builder resume <id>`) when it reaches its absolute ceiling or makes no progress
twice. Today `BuilderState(rawValue:) ?? .failed` (Hub/HubModel.swift:108) would show it as failed and wake the Watcher.
- Add `.paused` to `BuilderState`; handle it in every switch (compiler lists them). Hub label "Paused".
- `BuilderSignals.scan`: a non-acked `.paused` builder -> signal kind `"paused"`, title "Builder <name> paused: needs a
  go-ahead", evidence = result.md (or "The builder paused and left no result.md."). Same shape as failed otherwise.

## T2 — say the real reason an investigation stopped
`Investigation.parse` (Duty/Investigation.swift:127) reports every non-report as "Stopped at its size limit". The
claude `-p --output-format json` object carries `subtype` and `session_id`. New `Outcome` case
`.capped(reason: String, sessionID: String, cost: Double, contextTokens: Int)` when subtype is `error_max_turns`
("Hit its turn limit") or `error_max_budget_usd` ("Hit its money limit") AND session_id is present. Everything else
keeps `.stopped`, and the size-limit wording is only used when no other cause is known.

## T3 — continue on a cap (Yahia chose: continue within the daily budget, then park)
In `WatcherStore.investigate` on `.capped`: ledger the cost (runs: 0), then resume the SAME session while
`dailyUSD - today.usd >= 0.05` and continuations < 4: argv = `Investigation.argv(..., resume: sid)` (adds
`--resume <sid>`, budget `min(perRunUSD, daily left)`, same schema/settings/turns), prompt:
"Checkpoint, not a stop: you hit a limit before returning the report. Continue the investigation from where you
stopped and return the report in the required schema." Stop on `.report` (normal path) or `.stopped`.
- Out of daily budget mid-investigation: emit `.reported` with note "Paused at the daily budget (HH:mm): Investigate
  continues where it stopped", and persist the session id on the item (new optional InboxEvent field
  `resumeSession`, tolerant decode; the item exposes the latest one). The next `investigate(id)` resumes that session
  with the continuation prompt instead of a fresh run; a report clears it.
- Continuations count dollars only: they do not consume `runsPerDay` or the per-repo 3/day.
- A context-size stop (burn hook / `.stopped`) is NOT resumed: the same session would be just as full.

## T4 — fix builders get an absolute ceiling
The builder is gaining `--max-total USD` (absolute ceiling across checkpoints; it pauses there).
`WatcherStore.approve` (WatcherStore.swift:270) passes `--max-total` = `duty.budget.fixMaxUSD` (new DutyBudget field,
default 10, tolerant decode like the others). `--budget fixUSD` stays as the first chunk.

## Tests (each fails before the fix)
parse: turn-cap and money-cap JSON -> `.capped` with the right reason + session id; no-subtype garbage -> `.stopped`.
investigate: capped then report -> one report, second argv contains `--resume <sid>`, runs counted once; capped with
the daily budget exhausted -> note contains "Paused at the daily budget", item keeps the session, next investigate
argv resumes it; continuation stops at 4. `"paused"` meta.json -> `.paused`, scan yields kind "paused"; acked paused
-> no signal. approve argv contains `--max-total 10.00`.

Final report: what changed per T1-T4, gate output pasted (test count), anything you could not do.
