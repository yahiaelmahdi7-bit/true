# Clip Studio ecosystem — lane brief

You are L3b, the app-fix lane (L1 spine, L2 analytics, L3 app are merged) turning Clip Studio into one connected system. Your worktree branches from
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

## Your lane: L3b — make the app read the real engine + taste fixes, SWIFT ONLY (Sources/, Tests/, docs/DESIGN.md,
## docs/proof/ecosystem/, docs/lanes/L3b.md, and the app-invented fixtures named below)
A parallel lane (L4) owns everything under engine/ (incl. the engine fixtures) — do not edit engine files.
Read docs/lanes/L2.md, L2-proof.txt and L3.md first.
1. **Real shapes:** L3 invented the analytics JSON and drew the screens from its own fixtures
   `engine/tests/fixtures/contracts/analytics-*.json` + `suggestions.json` (hyphen names). The engine's real CLI output is
   `contracts/analytics_*.json` + `suggestions_list.json` (underscore names; shapes overlap little — audience shares 1 key).
   Rewrite the Swift decoders (Sources/ClipStudioCore/Ecosystem.swift) and views to read the REAL shapes, keep every screen
   showing what it shows now where the engine has the data, show an honest "not enough data / not available" where it doesn't
   (e.g. TikTok audience, hook type without Jev). Tests decode the underscore fixtures; then delete the hyphen fixtures.
   Types matter: the board just broke because the app wanted strings where the engine sends numbers/objects.
2. **Board fits:** the campaign Board (8 stage columns) must show all 8 stages without horizontal scroll at a 1440×900 window
   (and stay usable at 1280). Compact columns / smaller cards / counts-first — your call, but no stage hidden off-screen.
3. **What works is hard to read:** bars and CI lines are drawn offset from each other, labels sit on a different row from their
   marks, each section has its own scale (the 0 line jumps), and the axis says "+0%". Redesign: one shared scale across sections,
   label and mark on the same row, one clear 0% baseline, mark + interval aligned, "0%". Follow the dataviz skill.
4. **Empty / engine-unavailable states** for the campaign page and every analytics tab (Home already has one). And the
   "All queued posts / All published posts" links on Home must look like real controls, not orphaned text.
5. Stills light + dark of every screen you changed + the new states into docs/proof/ecosystem/ (replace old ones), LOOK at each,
   self-critique with the /taste skill, fix, re-shoot. List them in docs/lanes/L3b.md.
