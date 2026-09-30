You are continuing **True** in `~/Projects/true` (you are in a git WORKTREE of it, on your own branch).
Runs 1–3 are DONE and committed — read `SPEC.md` in full (its Hard rules bind), then `git log --oneline`
and the current code before changing anything. This run adds ONE feature: the **Context Cleaner**.

## Why
Yahia's projects carry ~80 context files Claude Code loads into sessions: `CLAUDE.md` files (re-read on
every turn of every session) and `HANDOFF*.md` files (read by the next session). Most were written for
older models and are padded with scaffolding current models don't need — ALL-CAPS emphasis, repeated
warnings, generic good practice, file trees, finished step-by-step logs. That padding is pure context
cost. He wants True to rewrite them with a current model, keeping every real fact and cutting the rest,
across all projects in one pass — and he reviews before anything is written.

## The feature (one name: "Context Cleaner")
1. **Command:** Agents menu → `Context Cleaner…` (no shortcut). Opens a sheet (~920×640, HIG look per
   SPEC: SF Symbols, system fonts, Liquid Glass bars, dark).
2. **Scan** (off the main actor, each time the sheet opens; nothing watches disk). Project roots = the
   SAME list the ⌘O palette uses (`ProjectStore` + `ProjectList.build`), plus `~` itself. In each root:
   `CLAUDE.md`, `.claude/CLAUDE.md`, `.claude/HANDOFF*.md`, `HANDOFF.md`, `studio-docs/HANDOFF*.md`.
   Plus the global `~/.claude/CLAUDE.md` listed FIRST as kind "Global" with the caption "Loaded into
   every session" and UNCHECKED by default. De-dupe by resolved real path. Skip files < 400 bytes.
   Each row: kind badge (Global / CLAUDE.md / Handoff), abbreviated path grouped by project, est.
   tokens (bytes ÷ 4), age, checkbox. Disabled rows with a reason:
   - **live** — a `HANDOFF-<tok>.md` whose owner is running: `~/.claude/state/live-<tok>` exists and its
     first whitespace-separated field is a pid for which `kill(pid, 0) == 0` or errno is `EPERM`
     (same rule as `~/.claude/hooks/handoff-inject.sh`). Never rewrite a live session's handoff.
   - **in use** — modified less than 10 minutes ago (a session may be writing it).
   Default checked: every enabled Handoff and CLAUDE.md row (not Global).
3. **Rewrite** (button "Rewrite Selected"): one headless Claude run per UNIQUE content (SHA-256 — the
   mizan worktrees hold 4 identical copies; rewrite once, share the result), at most 3 at a time.
   Model picker: Opus (default) / Sonnet / Fable — reuse `AgentModel` raw values for `--model`.
   - Binary: first executable of `$CLAUDE_BIN`, `~/.local/bin/claude`, `~/.claude/local/claude`,
     `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`, skipping anything whose resolved path's
     basename is `claude-burn`. None → a clear error row, no crash. (A GUI app's PATH lacks these.)
   - argv (VERIFIED working on this Mac 2026-09-30 — uses his Max login, loads none of his hooks,
     plugins, MCP servers or CLAUDE.md, ~5 s per small file):
     `claude -p --model <m> --setting-sources project --strict-mcp-config --tools "" --no-session-persistence --system-prompt <PROMPT>`
     with the file content on STDIN and `currentDirectoryURL` = an EMPTY dir `~/.true/cleaner/empty`
     (never the repo — a repo cwd would load its CLAUDE.md/settings). Env = True's env minus `CLAUDECODE`,
     every `CLAUDE_CODE_*` and every `BURN_*`. Timeout 240 s → terminate the process, error row.
     Do NOT use `--bare` (it skips keychain reads, so the Max-plan login fails).
   - `<PROMPT>` is the text in the PROMPT section below, **verbatim**, as one Swift string constant in its
     own file. Do not edit its wording.
   - Row shows progress: Queued → Rewriting… → `5,950 → 2,100 tok (−65%)` / Error (message) / Lean.
4. **Sanitize + checks** (pure functions, tested):
   - Trim; strip ONE wrapping ``` fence if the whole output is fenced; empty → error.
   - First line: the output's first line must equal the original's first line (the handoff board reads
     it as the title). If both are `#` headings and differ, replace the output's with the original's.
     If the original's first line is missing from the output entirely, prepend it.
   - **Lean:** output ≥ 97% of the original's bytes → status "Lean", unchecked for apply.
   - **Dropped facts:** extract from the ORIGINAL every backticked span, URL (`https?://…`), path
     starting `~/`, `/Users/`, `/opt/`, `/private/`, `/Library/`, and hex/UUID ids of 8+ chars; any not
     present verbatim in the output is listed on the row's detail as yellow chips. A row with dropped
     facts is UNCHECKED for apply by default (he decides). Stale ones may be fine to drop — just show them.
5. **Review:** selecting a row shows BEFORE | AFTER side by side (two monospaced, scrollable,
   selectable text panes, read-only), the token delta, and the dropped-fact chips. A per-row "Apply"
   checkbox. Header totals: `Selected: 48 files · 96,400 → 41,200 tok`.
6. **Apply** ("Apply N Changes"): for each checked row: refuse if the file's size+mtime changed since
   the scan read it ("changed since read — rescan"); back up the original to
   `~/.true/cleaner-backups/<yyyyMMdd-HHmmss>/files/<absolute path without leading />`; atomic write
   keeping the file's permissions; write `manifest.json` in that backup dir
   (`[{path, shaBefore, shaAfter}]`). **"Undo Last Apply"** restores every file of the newest manifest
   whose current SHA equals `shaAfter` (skips + reports the others). Nothing is ever written without the
   Apply click. No git operations.
7. Closing the sheet cancels queued jobs and terminates running `claude` processes.
   Idle ≈ 0% CPU: no timers; process completion is callback/async driven.

## PROMPT (verbatim)
You rewrite one context file that Claude Code loads into a coding session. The reader is a current Claude model (Claude 5 family), not a human. The file is either:
- a CLAUDE.md — standing instructions, re-read on every turn of every session in that project, so each line costs context forever; or
- a HANDOFF.md — the state a fresh session needs to resume unfinished work.

Current models follow instructions precisely, read code and git history themselves, and do the sensible thing by default. Many of these files were written for older models and carry scaffolding those models needed. That scaffolding now only costs context, and loud emphasis makes current models over-apply a rule. Your job: keep every fact the reader cannot cheaply get elsewhere, and cut the rest.

KEEP — verbatim wherever exactness matters:
- Exact paths, commands, URLs, ports, hostnames, IDs, env var names, versions, account and service names, file names.
- Decisions already made and the reason; constraints; approaches that were tried and failed, and why.
- Rules that came from an incident, with their one-line reason. The reason is what lets the reader apply the rule correctly, so never drop it.
- Anything that contradicts what a capable engineer would assume by default.
- In a handoff: what is done, what is in progress, what is next, blockers, open questions, and any DO-NOT list.

CUT:
- Emphasis scaffolding: ALL CAPS, "IMPORTANT", "CRITICAL", "YOU MUST", "NEVER EVER", bold on everything, the same warning repeated. State each rule once, in a calm sentence.
- Generic good practice any competent engineer already follows: write tests, handle errors, read before editing, be careful, think step by step, don't hallucinate, ask when unsure, keep code clean.
- Coaching on how to think, how to use tools, or how to format answers, unless it is specific to this project.
- Anything the reader can get from the repo in seconds: file trees, lists of files/functions/components, dependency lists, git history, descriptions of what existing code does.
- Duplicates and restatements (say it once), narrative, pep talk, filler, and meta text like "This document describes…".
- In a handoff: step-by-step logs of work that is finished and verified (collapse each to a one-line outcome), pasted tool or test output, and anything a later section supersedes.

FORMAT:
- The first line of the file stays exactly as it is (tools read it as the title).
- Keep markdown. Keep section headings that name a protocol a tool or person relies on (for example DO-NOT, Next steps, Working set, Blockers), merging or dropping other headings freely.
- Prefer short labelled lines and bullets over prose.
- Add nothing new: no new rules, no advice, no notes about your edits.
- If the file is already lean, return it unchanged.

Output only the rewritten file content — no preamble, no explanation, no code fences.
(end of PROMPT)

## Tests (TrueTests, pure logic, temp dirs only — NEVER invoke the real claude; inject the runner)
Scan from a temp tree (all kinds found, Global first + unchecked, < 400 B skipped, realpath de-dupe,
live-skip using a live file holding `getpid()` vs a dead pid, in-use skip with an injected clock);
binary resolution (temp candidates, `claude-burn` skipped, none → error); exact argv + cwd + env
scrubbing; sanitizer (fence strip, first-line enforce both ways, empty → error); lean gate; dropped-fact
extraction + detection; content-hash de-dupe shares one job; apply → backup + manifest + atomic write;
changed-since-read refusal; undo round trip incl. skip when edited after apply.

## DISCIPLINE (non-negotiable)
- Lane: ONLY your worktree of ~/Projects/true. Never touch ~/.axon, ~/.claude/settings.json, other repos.
  Never read or write the real ~/.true/* or ~/.claude/* in tests — inject temp paths. Never run the
  cleaner against real files (the reviewer does the first real run with Yahia).
- Commits: atomic, message says what+why. NEVER push, merge, or tag.
- Gates in the FOREGROUND only: no run_in_background, no watch modes, no until-loops.
- 'done' = you ran the gate and pasted passing output. Never report what you didn't verify.
- If blocked: say BLOCKED + one line why. No extra scope (no auto-run, no scheduling, no git commits of
  cleaned files, no MEMORY.md cleaning).

## HEAT RULES (hard)
- Another builder is compiling ~/Projects/true at the same time. Build only with
  `nice -n 10 swift build -j 2`; tests only with SPEC.md's `swift test` command but `-j 2`. One
  build/test process at a time. Full test suite at most ~4 times.
- True.app IS RUNNING RIGHT NOW and hosts live sessions (including the one that launched you).
  NEVER launch, open, quit, kill, or signal True/True.app. Do NOT run `scripts/package.sh`.
  No `open`, `osascript`, screenshots, no GUI of any kind.

Order: scan + tests → binary/argv/runner + tests → sanitizer/checks + tests → apply/backup/undo +
tests → model (jobs, concurrency, de-dupe) → sheet UI + menu item → full test run. Commit after each
step that builds.

Finish with a short plain-English report: what works, pasted final build + test output, commit list,
your branch name, what was never exercised because nothing was launched (the sheet and real claude
runs are untested live), and anything risky.
