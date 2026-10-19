# Clip Studio — Analytics back as a top tab + "collected so far" (restored look)

Repo: ~/Projects/clip-studio (Swift app at repo root Sources/ + Tests/; engine = Python in engine/, venv engine/.venv). Work in your worktree branch only. Do NOT merge, push, run scripts/package.sh, or touch the installed ClipStudio.app. Do NOT change config post.golive or autopilot.pause in the real library. Never write to the real library: sandbox copies only.

## Why
The restore-look merge (a568175) brought back the redesign-1 look (top tabs For you / Studio / Sources) but demoted Analytics from a sidebar item to a small text button (EcoShellViews.swift:95 "Analytics" BrandSecondaryButton, and the For you chip row). Yahia reads that as "the analytics and the training data are gone". They are not: engine `analytics` / `suggestions` CLIs work (EcoStore.loadAnalytics), the real library has 0 posts so every performance chart is empty, while training signals ARE being collected (labels keep/reject, events edit.rendered / edit.qc_failed / conductor.*, moments, clips, edits).

## Build
1. **Top tab.** Add `Analytics` as the 4th top tab in the restored shell (Shell.swift / AppModel ShellRoute tabs): For you · Studio · Sources · Analytics, same tab style as the others, ⌘4 if the others have shortcuts. It shows the existing global analytics page (EcoAnalyticsViews: Overview / What works / Audience & platforms / Money / Pipeline health / Suggestions) embedded full width, no "‹ Home" back link inside the tab. Route `analytics[/<section>]` (AppModel.swift:349) lands on the new tab. The For you "Analytics" button either goes to the tab or is removed (no duplicate page). The campaign page Analytics tab stays as is.
2. **Engine: `analytics collected [--campaign X]`** (engine/clipengine/analytics/cli.py + the `choices` list in __main__.py:199). Read-only JSON: labels {keep, reject, last_ts}, moments found, clips rendered, edits, qc_failed {n, top_reasons (from events payload)}, events by kind (last 30d), posts, first_post_ts. Unit tests in engine/tests/test_analytics.py. Full engine suite stays green.
3. **"Collected so far" on Overview.** Always show a compact stat row (same component/style as Home's stat row) with those counts. When posts == 0, the performance charts area shows one plain sentence instead of empty charts: "Performance shows up after your first post. Clip Studio is already learning from your keeps and rejects." Never show fake numbers in the real app; fixtures only in QA.
4. Taste: Brand tokens only, one accent (green), no grey-on-grey selected states, no empty grids, content fills width (max 1400 like the restore-look nits pass).

## Proof (required)
- Extend scripts/shoot-restore.sh (or a new shoot-analytics.sh): stills of the top bar with the new tab, and the Analytics tab Overview in dark + light at 1440x900 and 1280x800 — (a) fixture data, (b) a REAL engine run against a sandbox: CLIPSTUDIO_HOME = dir with a `sqlite3 .backup` copy of ~/Library/Application Support/ClipStudio/library.sqlite. Stills (b) must show the real counts (labels 6: 4 keep / 2 reject at time of writing; verify with sqlite yourself).
- docs/proof/analytics-tab/README.md: verdict first, list of stills, the `analytics collected --json` output vs direct sqlite counts (must match).
- Look at your own stills before claiming done.

## Done =
swift build clean, swift test green, engine pytest green (state the counts), README + stills, short summary of files changed. Commit on your branch. Nothing packaged.

DISCIPLINE (non-negotiable):
- Lane: you work ONLY on your worktree branch (Sources/ClipStudio shell + analytics views, engine/clipengine/analytics + __main__.py analytics choices, tests, scripts/shoot-*, docs/proof/analytics-tab). Two other builders (cs-two-speaker, cs-style-school) edit the same repo in their own worktrees; don't touch render.py / captions.py / stylelearn.
- Commits: atomic, message says what+why. NEVER push, NEVER merge, NEVER package.
- Gates: run swift build / swift test / pytest in the FOREGROUND. No background shells, watch modes or until-loops.
- Claims: 'done' means you ran the gate and pasted the passing output. Never report a state you didn't verify.
- If blocked: say BLOCKED + one line why. Do not invent extra scope.
