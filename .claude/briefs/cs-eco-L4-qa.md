# Clip Studio ecosystem — lane brief

You are L4 QA on the team (L1 spine, L2 analytics, L3 app are merged) turning Clip Studio into one connected system. Your worktree branches from
`ecosystem/base` (main + autopilot + vibes + 10s-flash + accounts/mail, all gates green: engine 949 pass, swift 111/0).

**Read `docs/ECOSYSTEM.md` in full before writing code.** It is the contract: event log, campaign_id everywhere, the 8 stages,
the conductor, trust/auto-approve, the analytics warehouse + closed loop, the campaign-first app, the CLI JSON contracts and the
lane file-ownership table (§8). Yahia's decisions are in it; do not re-ask them. Where your code and the contract disagree, the
contract wins unless it says "existing".

Gates (foreground, paste the tail into your report):
- engine: `cd engine && PYTHONPATH=$PWD ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q`
- app:    `swift test` (Package.swift is at the repo root)
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

## Your lane: L4 — QA + wiring, ENGINE ONLY (engine/, docs/ECOSYSTEM.md, docs/lanes/L4.md)
A parallel lane (L3b) owns ALL Swift (Sources/, Tests/) and the app-invented fixtures `contracts/analytics-*.json` +
`contracts/suggestions.json` (hyphen names). Do not touch those. The engine's real fixtures are `contracts/analytics_*.json`,
`suggestions_list.json`, `campaign-board.json`, `events.json` — the app is being switched to read exactly these, so keep their
shapes stable; if you must change one, say so loudly in your report.
L1–L3 were built in parallel and merged on `ecosystem/base`. Read docs/lanes/L1.md, L2.md, L3.md first — their "not verified"
and "contract changes" sections are your work list. Must do, in order:
1. **Safety (first commit):** the old `autopilot tick` still posts clips from UNTRUSTED campaigns without approval. Make it obey the
   same rule as `conduct tick` (untrusted → only human-approved clips post; trusted → trust gate), or make it delegate to the
   conductor. Test that an untrusted campaign's unapproved clip can never reach a post via either entry point.
2. **Wire L1 ↔ L2:** the conductor's `_track` and `_analyze` hooks must call L2's tracker/analytics; L2's events
   (`metrics.snapshot`, `audience.snapshot`, `account.*`, `suggestion.*`, `submission.paid`) go through the real `events.py`;
   the conductor must READ the config keys suggestions write (`slot.hours:{cid}`, `length_target:{cid}`, `platform_mix:{cid}`,
   `campaign.focus:{cid}`) so an applied suggestion changes the next tick. Test each.
3. **One fixture dir:** engine fixtures exist in both `engine/tests/fixtures/contract/` and `contracts/`. Keep `contracts/`
   (the ECOSYSTEM.md name), move anything unique, repoint every ENGINE reference (incl. gen_contract_l2.py), delete `contract/`.
4. **Contract test:** run every CLI the app reads (campaign-board, events, analytics *, suggestions list) on the sandbox DB and
   assert its JSON keys AND value types match the engine fixture in `contracts/` (types matter: the app broke on string-vs-number).
5. **`engine/tests/test_ecosystem_e2e.py`:** one sandbox run of the whole loop — campaign → sources → moments → edit → review
   (untrusted stops; trusted with ≥30 labels and precision ≥0.90 auto-approves) → dry-run post → metrics snapshot (fixture) →
   analyze → ranked suggestion → apply → perf_weights + config key → next tick reflects it → measure. Assert the events table
   tells the whole story per campaign.
6. Update docs/ECOSYSTEM.md with every contract change the lanes reported (one line each, marked "changed by L<n>").
Proof: paste both gates and the e2e test's event timeline into docs/lanes/L4.md.
