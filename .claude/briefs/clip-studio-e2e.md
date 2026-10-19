# Clip Studio: end-to-end operational check — `clipengine e2e` harness + break list (Solved, PB Blake)

First read and follow ~/.claude/skills/dispatch-brief/SKILL.md. Repo: ~/Projects/clip-studio (worktree off main at or after
9461932). No push, no merge, never relaunch the ClipStudio app, never write to the real library. Never post, queue or submit
anything for real. Write result.md EARLY and extend it as you go. Worktrees have no venv: run tests as
`PYTHONPATH=. ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q` from the worktree's engine/.

## Why (Yahia, 2026-10-12: "get the clipping system fully built and operational end to end")
Every stage exists (feeds, join, sources, moments, Edit Room, depth captions, Style Lab, queue/approval, publish, metrics,
signal loop) but nothing has ever run source → posted → submitted → measured. Real library today: 14 campaign sources
(5 Solved cmp_6fe50dcdb4, 9 PB Blake cmp_77539b16a8), 7 clips, 0 posts, 0 accounts rows. Upload-Post profile `default` has
ONLY tiktok:eliteclipperzz1 (Solved needs Instagram + YouTube; PB Blake needs a dedicated TikTok whose name contains "PB Blake").

## Lane discipline (5 builders are editing render.py, editroom.py, overlays.py, effects/quality, campaigns.py/onboarding,
playbook.py, InAppBrowser/CampaignExtras, a new submit.py right now)
Put everything in a NEW module `engine/clipengine/e2e.py` + one `add("e2e", ...)` line in __main__.py + tests. Do NOT fix
breaks in other files: record each one (stage, file:line, symptom, evidence, severity P0-P2, proposed fix in <= 3 lines).

## The harness: `clipengine e2e --campaign <id> [--source <src_id>] [--keep]`
- Tmp home: sqlite backup API from `file:<real>?mode=ro` into a tmp CLIPSTUDIO_HOME; symlink the needed source media read-only.
  No downloads; if media is missing, that is a P0 break. Delete the tmp home unless --keep.
- Stages, each PASS / FAIL / NOT-BUILT with seconds + evidence path, exit code != 0 on any FAIL:
  1 campaign loaded, joined, rules parsed (Solved: submit_within_minutes=30, platforms instagram+youtube, 20-60 s, face 5 s)
  2 source: rights=campaign, on the campaign's allowlist / official channel
  3 transcript + word timings present
  4 moments: candidates generated through the normal path (incl. playbook gates if present on main)
  5 render through the normal path with the campaign's edit_style; ffprobe 1080x1920, measured video bitrate (target 12-16
    Mbps; report the number), duration inside the campaign window; existing QC verdict
  6 campaign compliance check for that clip (the app's own rules check), each rule listed pass/fail
  7 approval: queue the clip, approve it in the tmp home, confirm cap counters (3/day) and spend ceiling counters move
  8 publish DRY RUN: payload platforms == campaign platforms (Solved never TikTok), tags per platform, caption text, which
    Upload-Post profile; then GET-only `publish.linked_platforms("default")` (the ONLY Upload-Post call allowed) → FAIL with
    "connect <platform> in Upload-Post" when a required platform is not connected
  9 submit: if a submit module exists on main, run it against a local fixture; else NOT-BUILT
  10 metrics: metric_snapshots path on a recorded fixture response (no network)
- Paid API spend for the whole build <= $2 (Jev/Anthropic only as the pipeline normally calls them); log the estimate.

## Runs + proof
Run it for Solved (src_fda8b8256f, the 1301 s episode) and PB Blake (shortest PB source). Output
docs/proof/e2e/<campaign>.md (stage table) + 3 stills per rendered clip (first frame, mid, last) via ffmpeg select, labels
via Pillow (ffmpeg has no drawtext). result.md = both stage tables + the full break list sorted by severity.

## Done =
Engine pytest green; tests for the harness itself (tmp-home isolation: a test proves the real library path is never opened
read-write; exit code on a forced FAIL; NOT-BUILT handling). Both campaign runs executed with real tables in result.md.
