# Clip Studio Style Lab: trend scout — find trending / high-performing edits and feed them to the learner

First read and follow ~/.claude/skills/dispatch-brief/SKILL.md. Repo: ~/Projects/clip-studio (worktree off main 1f29a5b).
No push/merge, never relaunch the ClipStudio app, real library read-only, tests on fixtures + mocked HTTP (no live
network in tests). Write result.md EARLY and extend it.

## The ask (Yahia)
"every official source and youtube api and a scraper finding trending or high performance edits and learning".
Context: module of the Style Lab. Another builder is making `edit-style-learn <video> --name <slug>` (style.json,
schema 1) and `edit-style-score`; they are NOT on main yet — call them only if present (`shutil.which`/import probe),
otherwise queue the reference as `pending_learn`. Do not edit stylelearn.py / framescan / depth / editroom files.

## Hard line (settled with Yahia — encode in code, test it)
No logins/cookies, no proxies, no antidetect, no fake user agents, no captcha solving, no evasion of any kind.
Honest UA string naming Clip Studio; respect robots.txt for any HTML page; per-host rate limit (>= 2 s between
requests) and a daily cap. Where an official API exists, use it instead of HTML. Downloaded references are third-party:
stored only under ~/Projects/clip-studio-refs/lab/refs/<id>/ for local measurement, never reposted, never rendered
into our clips, never committed. TikTok/Instagram organic videos: no bot scraping — they enter via (a) the drop folder,
(b) `lab-add <url>` with official oEmbed metadata (TikTok oEmbed, Instagram oEmbed if a token is configured, else
metadata empty), (c) the TikTok Creative Center pages only if robots.txt allows — otherwise list it as manual browse.

## Build (`clipengine/trendscout.py`, CLI group `lab-*`)
1. **Store:** additive tables in the library DB (migration pattern used elsewhere): `lab_refs` (id, url, platform,
   channel, title, published_at, duration_s, views, likes, comments, subs, fetched_at, source, local_path, sha256,
   status: new|downloaded|learned|pending_learn|rejected, reject_reason) and `lab_ref_stats` (ref_id, t, views,
   likes, comments) for velocity over time. Never touch existing tables.
2. **Sources (pluggable, each declares access method + ToS note):**
   - `youtube_api`: YouTube Data API v3 via common.py's existing key lookup ("youtube-api"; currently MISSING — the
     command must say exactly how to add it and exit cleanly). Shorts candidates = videos.list chart=mostPopular per
     region + category, and search.list (videoDuration=short, order=viewCount, publishedAfter window) for query
     packs (config file: e.g. "finance", "trading", "business", "podcast clips", "edit"). Quota-aware (track units,
     stop under a floor).
   - `drop_folder`: ~/Projects/clip-studio-refs/lab/inbox/ — any video or .url/.txt with links; Yahia drops refs here.
   - `oembed`: TikTok/Instagram/YouTube link metadata only.
   - `creative_center`: only if robots.txt allows; else a stub that prints the manual-browse URL.
3. **High-performance score:** views/hour since publish (velocity), engagement ratio, and OUTLIER score = views ÷
   the channel's median views over its last 20 uploads (channels.list + playlistItems + videos.list; cache per
   channel 24 h). Rank = blend, documented constants. Persist every snapshot to lab_ref_stats.
4. **Pipeline:** `lab-scout [--sources ...] [--limit N]` → rank → `lab-fetch --top N` downloads top refs with the
   venv yt-dlp (no cookies; best <=1080p mp4; skip > 3 min) → `lab-learn` runs edit-style-learn per downloaded ref when
   available (else pending_learn) → `lab-status` prints a compact table. `lab-add <url|path>` for single refs.
5. **Trend view (first cut):** `lab-trends` groups learned refs by a few style.json features (cut median, words per
   card, caption font class, depth share, music under speech, transitions) and shows which groups dominate the top
   outliers this week vs last. Keep it simple and honest; it will grow in L3.
6. Update ~/.claude/skills/clip-edit/SKILL.md with a short "Style Lab scout" section (read the file first; another
   builder may also add a "Learn a style" section — append, don't rewrite).

## Proof
Mocked-HTTP test suite + one LIVE dry run only if the key exists (it does not today → show the exact
missing-key message). Drop the Kumar ref (~/Projects/clip-studio-refs/ref-style-1/ref.mp4) through `lab-add` and show
it lands in lab_refs (use a TMP copy of the DB, not the real library, for this proof) as pending_learn.

## Done =
Whole engine pytest green + new tests (hard-line guards: no cookie/proxy params ever passed to yt-dlp or requests,
robots.txt respected, rate limit, quota floor, outlier math, additive migration, missing-key path).
result.md: files, commands, how Yahia adds the key, what each source can and cannot do and why.
