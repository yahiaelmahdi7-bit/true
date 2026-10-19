# Clip Studio: get paid for every post + capture the data that explains views

First read and follow ~/.claude/skills/dispatch-brief/SKILL.md. Repo: ~/Projects/clip-studio, worktree off main at/after 474dfea.
No push, no merge, never relaunch the ClipStudio app, never post, never SUBMIT for real, never load contentrewards.com, never WRITE the
real library (~/Library/Application Support/ClipStudio/library.sqlite: `?mode=ro` reads only; tests use fixtures / tmp CLIPSTUDIO_HOME).
Tests from the worktree's engine/: `PYTHONPATH=. ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q` (record baseline first).
Write result.md EARLY and extend it. Lane: submit.py, tracker.py, metrics/post_facts, new report module, AutoSubmit.swift. A parallel builder
owns render.py/qa.py/captions/publish.py and adds clips.features keys face_frame0, hook_title, layout, logo, cover_ms, caption_contrast_min
(read them if present, tolerate absence). Read docs/ distribution research (commit 1eec7b7) for the clipping economy context.

## Why (Yahia, 2026-10-16: "make sure we actually get the money for that value we add")
Solved (cmp_6fe50dcdb4) pays $1.25 CPM, per clip min $1.25 (=1,000 views) max $300, views count for 30 days; payout rules: tier1_min_pct 40,
min_engagement_pct 0.2. Content Rewards only accepts a submission within 30 MINUTES of the post going live. Both real posts so far were
submitted BY HAND (campaign_submissions detail). Post 2 (post_2c682aa27d) was marked failed by the tracker (fixed in 474dfea), so the engine
never queued it. Autopilot now posts at NY 12:00/16:30/21:00 = Dubai 20:00/00:30/05:00 while Yahia sleeps. We are blind on viewer country
and on YouTube retention.

## Build
1. Unattended auto-submit: trace the live chain post live -> live_at + URL -> ledger pending -> in-app AutoSubmit submits before deadline, with
   fixtures/fakes. Confirm 474dfea was the only reason post 2 was skipped, or name the other. State exactly what must be true on the Mac at
   05:00 for it to work (app running? CR session alive? screen locked/asleep ok?) and fix what code can fix (e.g. keep the WebView session
   alive, retry, run on wake). Add a deadline-at-risk alert at T-10 min (needs_you + macOS notification). Log every attempt in the ledger.
2. CR status reader: per submission pending/approved/rejected, views, earned, rejection reason, read from the CR "Your submissions" page in the
   in-app browser (parse visible text; a JSON endpoint only if the page already calls one). Additive columns on campaign_submissions
   (cr_state, cr_views, cr_earned, cr_reason, cr_checked_at). Fixture from this real page text: tabs "Approved 0 / Pending 4 / Rejected 0",
   cards "ClipFarm x Solved w/ Mark... CPM Oct 16, 2026 ... 116 views".
3. Money ledger + `clipengine money [--campaign]`: per clip per platform views, over-1k flag, projected $ (views/1000*CPM, min/max per clip),
   CR state, earned. Totals: earned, pending, "views needed to unlock" per clip.
4. YouTube Analytics: installed-app OAuth (token in Keychain, scopes yt-analytics.readonly + youtube.readonly) for the Elite-Clipperzz channel;
   per video averageViewPercentage, averageViewDuration, views by country -> tier1_pct (one TIER1 list in one place; say where CR defines
   it, else US/GB/CA/AU and flag the assumption). Additive post_facts columns. Data lags ~48 h: handle that. Find any existing Google client /
   API key config first; write the one-time steps Yahia must do (plain English, numbered). Instagram: use whatever Upload-Post already returns
   (avg watch, reach, countries?); document gaps, no Facebook app build.
5. Features + cadence: post_facts.features gets hook_type (Jev choice: question / bold claim / story / advice / quote / other, with
   confidence), jev_quality, and the render keys above. Fill views_1h/6h/24h/72h/7d from the nearest snapshot (additive columns as needed).
6. `clipengine report learn --campaign <id> [--md path]`: money section (from 3) + per-feature groups with n, median views_24h, share over 1k,
   avg_view_pct, tier1_pct; any group n<10 says "not enough data yet". No p-value theatre. Weekly LaunchAgent: plist generator dry-run only.

## Proof
REPORT.md: real-library read-only runs of `money` and `report learn` on today's 2 posts (paste output), the auto-submit chain trace with what
the Mac needs overnight, the OAuth steps for Yahia, test counts before/after.
