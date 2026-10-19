# Clip Studio — vibes-1: style-pack v2 + held-out bench + scout ref shortlist (STOP for Yahia's picks)

Repo ~/Projects/clip-studio, start from main AFTER captions-v3 (quality-fix1) and publish-fix1 are merged. Tests:
`PYTHONPATH=. ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q` from the worktree's engine/. Never touch the real
library at ~/Library/Application Support/ClipStudio except READ-ONLY source media via a tmp home (see /private/tmp/kumar-home:
tmp library.sqlite + `media` symlink). Never relaunch ClipStudio/True.app, never push, never post anything.

## Goal (Yahia, 2026-10-12)
"I need this system to be solid so we can edit and clip up other videos in this quality, and we need different vibes — the
Andrew Tate vibe, the looksmaxing vibe, the wellbeing ones and all." A vibe = a STYLE PACK (Style Lab: learn → pack → render →
score vs refs). Engine rules bind every pack (captions-v3 B1/B3/B4/B5: spoken words only, on time, one home spot, inside the
picture; HD bar 1080x1920 12–16 Mbps, no silent upscale, QC gate). A pack changes LOOK, never those rules.

## Part 1 — style-pack v2 schema
Extend the pack schema (keep `kumar-method` loading) with typed, validated blocks — unknown fields rejected:
- `captions` (from captions-v3 B8; quiet default), `grade` (contrast, saturation, warmth, b&w moments, glow/sharpen),
- `pace` (target shot length, cut-on-beat vs cut-on-phrase), `camera` (punch-in/zoom amount + frequency, slow-mo moments),
- `transitions` (none|fade|flash|whip), `sfx` (none|impacts|whooshes — licence gate applies), `text_density`,
- `music`: none|campaign|licensed|**in_app**. Campaign policy always beats the pack (PB Blake rules).
Anything a pack asks for that the renderer can't do goes in its `unsupported` list (= toolkit backlog), never silently dropped.

## Part 2 — music = in_app (Yahia's decision)
Vibe clips render with NO music bed (speech + licensed SFX only, leave mix headroom). A clip whose pack says `music: in_app`
gets approval status **needs_your_sound**: the slot routine must NOT auto-post it. Instead it prepares a ready-to-post packet
(final mp4 + caption/hashtags from campaign rules + the vibe's suggested sound mood/tempo) and notifies Yahia. After he posts
in the app, the clip is submitted to Content Rewards from either (a) a post URL he pastes into ClipStudio / the engine CLI, or
(b) detecting the new post on the connected account via Upload-Post or an official API — no logins/cookies/scraping. Build (a);
build (b) only if an official read path exists, else document why not. Clips with no music (e.g. PB Blake editorial) keep the
existing auto-post+submit slot routine unchanged. Tests: in_app clip is never picked by the slot routine; paste-URL → submit.

## Part 3 — held-out bench ("solid")
Pick 6–8 source videos from campaign-licensed media already in the library that differ on purpose: podcast two-shot, single
talking head indoors, outdoor/handheld, low light, already-vertical source, fast talker, a clip with lots of b-roll gaps.
Record them in engine/bench/bench.json (source ids + why each is there). `clipengine bench run [--vibe X]` renders every bench
video in every installed pack in a tmp home and writes a scorecard (docs/proof/bench/<date>/scorecard.md + contact sheets):
caption timing (card start vs first-word onset), shown-vs-spoken diff, home-line spread, in-picture bounds, bitrate, QC
sharpness/blockiness, face framing, b-roll relevance verdicts, music/SFX licence. One PASS/FAIL per render + overall.
Wire it as a script the next merges can run; it must FAIL on the old (pre-captions-v3) render behaviour.

## Part 4 — scout reference shortlist, then STOP
For three vibes — `hype` (Andrew Tate-style edits: dark contrast, b&w, hard cuts, punch-ins, bold captions),
`looksmax` (looksmaxing edits: beat-cut, face close-ups/zooms, glow, slow-mo, flash transitions, minimal text),
`wellbeing` (calm talking-head: warm soft grade, slow pace, gentle fades, quiet captions, space) — use the existing scout
(official sources only, YouTube Data API etc.; no logins/cookies/proxies) to find ~12 trending public edits each. For each
candidate: 3 stills + title/channel/views/date/length/url. Output docs/proof/vibes/shortlist-<vibe>.png (numbered contact sheet)
+ shortlist.json. Refs are GRAMMAR ONLY: never commit their media, never reuse their footage.
Then STOP and write result.md: Yahia ticks the refs he wants per vibe; learning the packs (edit-style-learn → pack →
bench render → edit-style-score vs refs) is the next resume, not this run.

## Report (result.md, "vibes-1")
Schema diff, in_app flow + tests, bench list + first scorecard (kumar-method + quiet default), shortlist sheet paths, not-done.
