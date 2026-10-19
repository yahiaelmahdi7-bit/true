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

## Your lane: L2 — Analytics warehouse + closed loop (contract §6, §8 row L2)
Build the `analytics/` package so the numbers tell us what to change next, then prove whether the change helped. Cover ALL of:
- **What edits work**: performance by edit features (style pack, hook type, captions, flash, length, cut pace) per campaign/platform.
- **Money per campaign**: earnings from campaign payout terms × tracked views, per post / account / campaign / week.
- **Pipeline health**: stage throughput, dwell time, failure and drop rates per stage (from L1's events — code against the §2
  signatures with a same-signature shim until L1's events.py exists; say so in your report).
- **Audience + strengths**: region, age, content type, platform, account — where we are strong, where we lose.
- **Ranked suggestions**: a ranked list with evidence + expected lift; accepting one writes `perf_weights` that calibrate.py reads
  (the hook in §6), and each applied suggestion gets a before/after measurement so the system learns which changes worked.
  Ranking/choosing is a decision → Jev per the DISCIPLINE block; minimum-sample guards in code (no suggestion from thin data).
- CLIs per §6 with JSON output exactly as the contract states (L3 renders it); add fixtures under `engine/tests/fixtures/contract/`.
Tracker: per-post parsing has never been checked against real data. If a real DB exists locally, copy it read-only to a temp file
(`sqlite3 <db> ".backup <tmp>"`), build an anonymised fixture from it, and test the parser against that. Never write to a real DB.
Proof: run every analysis on the fixture/sandbox DB and paste the outputs (incl. the ranked suggestions) into docs/lanes/L2.md.
