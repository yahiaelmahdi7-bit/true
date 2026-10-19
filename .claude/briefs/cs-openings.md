# Clip Studio: stronger openings + readable captions + higher moment bar

First read and follow ~/.claude/skills/dispatch-brief/SKILL.md. Repo: ~/Projects/clip-studio, worktree off main at/after 474dfea.
No push, no merge, never relaunch the ClipStudio app, never post/submit, never WRITE the real library
(~/Library/Application Support/ClipStudio/library.sqlite: `?mode=ro` reads only; renders go to a tmp CLIPSTUDIO_HOME copy).
Tests from the worktree's engine/: `PYTHONPATH=. ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q` (baseline: run it first, record).
Write result.md EARLY and extend it. Another session edits submit.py/tracker.py/metrics: do not touch those (lane = render side).

## Why (Yahia, 2026-10-16)
Two Solved clips posted. Clip 1 (mom_e8ac7c07d7, media/clips/mom_e8ac7c07d7.mp4, 42.6 s) frame 0 = BLANK cream wall (caption fading in over
an empty top panel) -> Instagram used it as the cover; then two side profiles stacked, no hook title, abstract opener. IG avg watch 10.3 s
of 42.6 s (24%); YT stalled at ~733 views (pay floor is 1,000). Clip 2 (mom_39a28580a8_chg1792139569_48k.mp4, 28.7 s) is the target look:
Mark face-on from frame 0, hook title, logo. Its top captions are thin white on a cream wall: hard to read; campaign rule = "Big accurate
subtitles for the whole clip", "Mark's face in the first 5 s" (rules face_first_seconds 5, min 20 s / max 60 s).

## Build
1. Frame 0 never empty: the speaker's face visible in frame 0 and in >=90% of frames in 0-2 s; no text fading in from 0 opacity at t=0
   (captions/hook start fully visible). QA gate in qa.py (~l.24) / render.py (~l.672) with a plain reason string; held clips log it.
2. Cover: pick a face-on frame with the hook title visible and pass it as the cover (publish.py ~l.85-94 already sends cover_timestamp /
   cover_image); store the chosen cover_ms.
3. Layout: when one speaker carries the first 5 s, render him full-frame (face-on crop) instead of the stacked 2-shot; stack only when both
   speak in the first 5 s. Don't regress the wideshot face fix (cs-wideshot-faces) or the card layout.
4. Captions: outline/stroke + soft shadow so white text reads on pale backgrounds; size up to "big" (measure: min contrast ratio against the
   local background >= 4.5 on sampled frames of both clips). Keep caption timing/spelling logic untouched.
5. Length: prefer 20-35 s cuts when the moment allows (never below the campaign min, never mid-thought).
6. Moment bar: autopilot/onboard picks need moment score >= config `autopilot.moment_floor` (default 0.55; today 0.48 = onboard.MOMENT_FLOOR
   l.15 and wherever else 0.48 gates picks - find all). If the pool runs short, report it; never lower the bar silently. Report from the real
   library (read-only) how many Solved moments clear 0.55 (about 23 of 531 today).
7. Record render facts in clips.features (additive keys): face_frame0 (bool), hook_title (bool), layout ("full"|"stack"|"card"), logo (bool),
   cover_ms, caption_contrast_min. The data builder reads these into post_facts; keep names exactly.

## Proof (Yahia judges by video, never still grids)
docs/proof/openings/ab.mp4: synced side-by-side old vs new for mom_e8ac7c07d7, mom_39a28580a8 and one more ready Solved moment
(render from a tmp CLIPSTUDIO_HOME copy). Plus frame0.png strip (frame 0 of each, old vs new). REPORT.md: what changed, test counts
before/after, the contrast numbers, the 0.55 pool count, exact commands to re-render the real ready queue AFTER merge (do not run them).
