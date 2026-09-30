# Operations
Owner: cto · Last verified: 2026-09-30

## Run locally
`scripts/package.sh` → `True.app` in repo root (gitignored); Yahia opens it. Agents never launch it. [source: scripts/package.sh]

## Deploy
None. Merges to `main` are Yahia's call; builders never push or merge.

## Environments
Single: the local Mac. State dir `~/.true/` (workspace.json, agents.json, projects.json, hooks/, roles/, scrollback/, sockets). [source: SPEC.md]

## Monitoring & alerts
None beyond the Hub/status pills. Idle CPU is watched by eye (fans). Unknown — see Open questions.

## Recurring jobs
None inside True (no timers by design).

## Recovery runbook
Corrupt workspace/agents file → tolerant decode falls back to defaults [source: git log "corrupt-file fallback"]. Stale TCC prompts after rebuild → ensure "Deck Signing" cert exists. Undo Cleaner via its backup + manifest.

## Vendors
None (Anthropic via user's Claude Code; TypeSafe Jev optional).
