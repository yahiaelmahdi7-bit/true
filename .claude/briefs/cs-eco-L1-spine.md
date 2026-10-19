# Clip Studio ecosystem — lane brief

You are one of three parallel lanes turning Clip Studio into one connected system. Your worktree branches from
`ecosystem/base` (main + autopilot + vibes + 10s-flash + accounts/mail, all gates green: engine 949 pass, swift 111/0).

**Read `docs/ECOSYSTEM.md` in full before writing code.** It is the contract: event log, campaign_id everywhere, the 8 stages,
the conductor, trust/auto-approve, the analytics warehouse + closed loop, the campaign-first app, the CLI JSON contracts and the
lane file-ownership table (§8). Yahia's decisions are in it; do not re-ask them. Where your code and the contract disagree, the
contract wins unless it says "existing".

Gates (foreground, paste the tail into your report):
- engine: `cd engine && PYTHONPATH=$PWD ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q`
- app:    `cd app && swift test`
Tests rewrite `docs/proof/submit/happy.png` and create `happy-watched-run.png` as a side effect: run
`git checkout -- docs/proof/submit/happy.png; rm -f docs/proof/submit/happy-watched-run.png` before every commit; never commit them.

Hard rules: no network in tests (mocks/fixtures). Never flip `post.golive`. Write launchd plists, never load them. Never touch the
live install (`~/Projects/clip-studio.live`) or the main checkout (`~/Projects/clip-studio`) except to run its venv python.
`__main__.py` is shared: append imports/`add(...)` lines at the END of their blocks, no reordering.
Report: write `docs/lanes/<your lane>.md` (NOT result.md): what you built, gate output, what is verified vs. NOT verified, and any
contract change you had to make (with why). Your final message = the same summary.

```
DISCIPLINE (non-negotiable):
- Lane: you work ONLY on the files your lane owns in docs/ECOSYSTEM.md §8 (plus the extras named below). Do not touch,
  checkout, or revert any file outside it — other lanes edit the same repo on sibling branches.
- Commits: atomic, one logical change per commit, message says what+why. NEVER push, NEVER merge,
  NEVER 'ship' — the user pushes, not you. Do not suggest pushing more than once.
- Gates: run lint/tsc/tests in the FOREGROUND and wait for them. NO background shells
  (run_in_background), NO watch modes, NO until-loops. Kill anything you started before finishing.
- Claims: 'done' means you ran the gate and pasted the passing output. Local commit ≠ 'pushed';
  code written ≠ 'working'. Never report a state you didn't verify this session.
- Decisions: if your change adds or touches a classify / route / gate / rank / verify step, make it a Jev
  call through the repo's vendored jev-kit (engine/clipengine/jev.py; see the jev skill): code owns the flow, Jev answers
  narrow typed questions, route on confidence, log the decision. No LLM prompt-and-parse, no keyword lists.
- If blocked or idle: say BLOCKED/IDLE + one line why. Do not invent extra scope.
```

## Your lane: L1 — Spine & conductor (contract §1–5, §8 row L1)
Order:
1. FIRST commit: `events.py` (the emit/query API exactly as §2), the campaign_id migration (§1) in common.py, and the
   contract fixtures for `campaign-board` / `events` CLI JSON under `engine/tests/fixtures/contract/` — L2 and L3 code
   against these shapes in parallel, so keep them exactly as the contract states.
2. Emit events from every existing stage (ingest, moments, edits, approval, slot/post, tracker hand-off) with campaign_id.
3. The conductor (§4): one tick walks every active campaign through the 8 stages, reusing autopilot.py's per-campaign chain
   and caps (3/day/campaign, 9/day global). Idempotent, crash-safe, every step logged as an event. CLI `conduct` (+ `--dry-run`).
4. Trust/auto-approve (§5): trusted campaigns auto-approve only when ≥30 labels and holdout precision ≥0.90; otherwise stop at
   Review. The trust decision is a gate → Jev per the DISCIPLINE block, with the numeric floor in code. CLI `trust`.
5. Write `com.clipstudio.conductor.plist` (NOT loaded). Note in your report: the live slot plist runs from
   ~/Projects/clip-studio.live, not main.
6. Extra (from the accounts review): `inbox.sync` must DROP any mail whose recipient domain is not `in.prismlens.net` — the Resend
   receiving API is team-wide (a real 2026-09-29 mail to an `*.resend.app` address came through). Add a test. You own inbox.py
   for this change only.
Proof: an end-to-end dry run on a sandbox DB (campaign → sources → moments → edit → review/auto-approve → queued post) showing
the events table rows per stage, pasted into docs/lanes/L1.md.
