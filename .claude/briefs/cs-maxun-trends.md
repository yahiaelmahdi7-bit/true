# Brief: Maxun for trend scouting + view tracking -> a more accurate Clip score

Yahia (2026-10-14): "Where Maxun does fit: reading public pages — tracking view counts on other people's clips or scouting trending source content. Not posting. Use Maxun for trend search and score to higher accuracy."
Maxun = github getmaxun/maxun, AGPL-3.0, self-hosted via Docker (free). Use it ONLY as a separate local service called over its API; never copy its code into clip-studio.

## Settled constraints (Yahia)
- Trends rotate week to week ("no system stays more than 4 months"): keep it CHEAP, REFRESHABLE (weekly), RECENCY-WEIGHTED; no giant one-off harvest. Ranker stays opt-in (flag CLIP_TREND=1, default off) until it beats the current Clip score on UNSEEN data.
- Public pages only: no logins, no paid proxies, no CAPTCHA solving, no anti-bot evasion, polite rate limits, respect robots.txt/ToS. If a site blocks plain access (TikTok/IG often do), record it as "not available" — don't work around it. Free only (no paid APIs).
- Prefer the simplest reliable reader per source: yt-dlp already reads public YouTube/Shorts view counts — use Maxun where no extractor exists. Report which reader each source uses and why.
- Prior work to reuse: commit c8633fb on the cs-jev-viral builder branch (4 public-clipper harvest scripts, unmerged) and the viral tracker/ranker code already in engine (grep viral, hookscore, livesig).

## Do (in this clip-studio worktree)
1. Install Maxun with Docker (pin the image tag; record it) bound to localhost only. Smoke test one robot on a public page.
2. Robots / readers: (a) TREND SCOUT: recent uploads + view velocity for each joined campaign's source channels (Solved: Mark Manson UC0TnW9acNxqeojxXDMbohcA) and trending topics in that niche; (b) CLIP TRACKER: public short clips cut from the same sources by other clippers (e.g. YouTube Shorts search for the show/guest names), snapshot views at first seen, +24 h, +72 h, +7 d.
3. engine/clipengine/trends.py: store snapshots in the library DB (new tables, additive), compute recency-weighted velocity per topic/guest/hook type; expose features for the scorer.
4. Score accuracy: build a time-split dataset of public clips (features from their transcript/title/length/hook + trend features) -> observed view velocity. Baseline = current Clip score features. Fit the simplest model that works (statistical before ML). Evaluate on the LATEST time slice only (unseen): Spearman + top-k hit rate, baseline vs new. Write SCORE-REPORT.md with the honest numbers, sample size, and caveats. Wire into the finder/gate ONLY behind CLIP_TREND=1.
5. Weekly refresh: one command (`python -m clipengine trends refresh`) + a conductor hook that runs it at most weekly; decay old data.
6. Tests for 3-5 with fakes (no network in tests). `cd engine && env -u CLIP_PIPELINE .venv/bin/python -m pytest -q -p no:cacheprovider` (baseline 1255 passed / 2 skipped). Commit on your branch only; no merge/push; never post/submit. Sandbox data only for experiments (copy /tmp/cs-tune-home), never ~/Library/Application Support/ClipStudio.
Done = Maxun running locally + readers + trends.py + SCORE-REPORT.md with unseen-data numbers + tests green.
