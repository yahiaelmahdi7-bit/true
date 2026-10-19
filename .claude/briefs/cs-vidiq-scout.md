# cs-vidiq-scout: weekly, budgeted vidIQ trend scout for every joined campaign

Goal: once a week, pull what is beating its account's normal views on Instagram, TikTok and YouTube Shorts for each joined campaign's niche, store it in the existing trend store, show Yahia a one-line digest, and let it influence which moments get cut ONLY if it beats the baseline on unseen clips.

Why vidIQ: the earlier Maxun scout (branch `builder/cs-maxun-trends-20261014-160153`, SCORE-REPORT.md) could not read Instagram or TikTok at all (login walls, correctly not worked around). Yahia has a vidIQ account with an MCP API key, which is authorized access to exactly that data.

## Step 0: start from the Maxun trend work
Branch from main, then `git merge builder/cs-maxun-trends-20261014-160153` (trends.py, trends_eval.py, test_trends.py, conductor + finder hooks, infra/maxun). Resolve conflicts on your side. Make the Maxun reader optional: if its service is down, skip it quietly (logged once), never fail the scout.

## vidIQ access (facts, measured 2026-10-17)
- Endpoint `https://mcp.vidiq.com/mcp`, MCP over HTTP: JSON-RPC POST, reply is SSE (`event: message` / `data: {...}` lines). Sequence: `initialize` -> `notifications/initialized` -> `tools/call`. No Mcp-Session-Id came back (stateless).
- Auth header `Authorization: Bearer <key>`. Key: `security find-generic-password -s app.clipstudio -a vidiq-api-key -w`. NEVER print, log, commit or put it in an event/report. Add a test that the key never appears in logs/events.
- Cloudflare returns 403 to Python's default `Python-urllib` User-Agent. Send `User-Agent: clipstudio/1.0`.
- `tools/list` is free; read each tool's inputSchema there before calling. Every tool result carries `_credits.used`.
- Useful tools: `vidiq_instagram_tiktok_outlier_search`, `vidiq_ig_profile_reels`, `vidiq_ig_accounts_from_outliers`, `vidiq_trending_videos`, `vidiq_outliers`, `vidiq_channel_videos`, `vidiq_get_videos_by_ids`. Free: `vidiq_balance`, `vidiq_user_channels`.
- FORBIDDEN (cost + out of scope): any `vidiq_generate_*`, `vidiq_compose`, `vidiq_motion_graphics`, `vidiq_voiceover_*`, `vidiq_video_watch`, `vidiq_watch_shortform_content`, `vidiq_refine_thumbnail`, bookmarks/competitor writes, `vidiq_video_upload`, `vidiq_edit_media`.

## Credit budget (HARD)
Free plan: 170 credits now (150 renew 2026-10-29, 20 add-on). Per-tool cost is unknown.
- Your whole build may spend at most 70 credits: up to 10 to measure the cost of each tool you plan to use (one call each), up to 60 for the held-out harvest. Check `vidiq_balance` before and after; record credits per call.
- Production: config `trends.vidiq.credits_week` (default 25) and `trends.vidiq.floor` (default 20: never start a run whose estimated cost would leave the balance under it). Check `vidiq_balance` first. When a cap is hit, stop and emit one plain event; never partial-retry in a loop.

## What the weekly scout collects
Joined campaigns today: Solved (cmp_6fe50dcdb4, Mark Manson's Solved podcast; we post IG + YT) and Boxabl (cmp_99d992d149; TT + IG + YT). Derive niche queries from the campaign row/rules (creator, show, topic), not hard-coded ids.
Per campaign: IG + TikTok outlier posts in the niche; reels of clip accounts in that niche (play counts -> account median -> outlier ratio = beating the account's own norm, same target idea as SCORE-REPORT); YT Shorts trending/outliers. Store in the trend tables with reader='vidiq', recency weighting and RETAIN_D as trends.py already does.

## Ranker (influence on cuts)
Add vidIQ-derived topic / hook-type lift features to `trends fit`. Time split, latest slice never used for fitting or tuning. It may switch on (lam > 0) ONLY if, on the unseen slice, the bootstrap 95% CI of Spearman(trend) - Spearman(baseline) has lower bound > 0 AND top-10 hit rate beats baseline. Otherwise lam stays 0 and the scout still runs as data + digest. Report the numbers either way; a CI that straddles 0 is "no evidence".
Keep the ranker the existing ridge model. Do not add an LLM prompt-and-parse step.

## Switches + schedule
- Scout on/off: config `trends.vidiq.on` (default 0). Yahia/the orchestrator flips it after review. Do not rely on the CLIP_TREND env var for the scout (the launchd conductor has no such env); ranker influence keeps its own switch.
- Weekly cadence through the existing conductor hook (DISCOVER_GAP_D = 7). No new LaunchAgent.

## Weekly digest (what Yahia sees)
One plain-English line per campaign in autopilot_events (kind 'trends'), e.g. "Trending for Solved this week: money and status, dating standards (3 standout reels on Instagram)". Human words only, no ids/codes/scores. Plus `clipengine trends digest` to print it.

## Tests + proof
- pytest with a fake vidIQ client: no network, no credits. Cover: SSE parsing, header + UA, budget cap, balance floor, forbidden-tool guard, key never in logs/events, Maxun-down degrade, digest copy. Full suite from the worktree's engine/ (main baseline: 1416 passed / 2 skipped); report passed/skipped/failed.
- Real harvest/eval runs against a tmp CLIPSTUDIO_HOME copy, never the real library.
- docs/proof/vidiq-scout/REPORT.md, plain language: credits per tool, total credits spent + balance left, harvest counts per platform, the held-out table (baseline / +trend / random, Spearman, top-10/top-20 hit, CI), verdict, sample digest lines for Solved and Boxabl, risks.

## Rules
DISCIPLINE (non-negotiable):
- Lane: you work ONLY in your worktree and branch. Do not touch, checkout, or revert any file outside it. No edits to the real library at ~/Library/Application Support/ClipStudio; do not touch the running ClipStudio app or its launch agents; do not change config in the real library.
- Commits: atomic, one logical change per commit, message says what+why. NEVER push, NEVER merge into main, NEVER 'ship'.
- Gates: run tests in the FOREGROUND and wait for them. NO background shells, NO watch modes, NO until-loops. Kill anything you started before finishing.
- Claims: 'done' means you ran the gate and pasted the passing output. Never report a state you didn't verify this session.
- Decisions: no LLM prompt-and-parse, no keyword lists for classify/route/gate steps; the ranker stays the measured ridge model.
- Data access: vidIQ API only for Instagram/TikTok. No logins, cookies, proxies, scraping of IG/TikTok, or evasion.
- If blocked or idle: say BLOCKED/IDLE + one line why. Do not invent extra scope.
